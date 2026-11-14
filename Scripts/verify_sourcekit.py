#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.9"
# dependencies = []
# ///

"""Verify the app's compilation database using the selected Xcode SourceKit-LSP."""

import argparse
import json
import pathlib
import queue
import subprocess
import sys
import tempfile
import threading
import time


class LSPClient:
    def __init__(self, root, timeout):
        self.timeout = timeout
        self.next_id = 0
        self.notifications = []
        self.incoming = queue.Queue()
        self.stderr = tempfile.TemporaryFile()
        self.process = subprocess.Popen(
            ['xcrun', 'sourcekit-lsp', '--experimental-feature', 'sourcekit-options-request'],
            cwd=root, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=self.stderr,
        )
        self.reader = threading.Thread(target=self._read_messages, daemon=True)
        self.reader.start()

    def _read_messages(self):
        try:
            while True:
                headers = {}
                while True:
                    line = self.process.stdout.readline()
                    if not line:
                        raise EOFError('SourceKit-LSP closed stdout')
                    if line in (b'\r\n', b'\n'):
                        break
                    key, value = line.decode('ascii').split(':', 1)
                    headers[key.lower()] = value.strip()
                length = int(headers['content-length'])
                body = self.process.stdout.read(length)
                if len(body) != length:
                    raise EOFError('SourceKit-LSP returned a truncated message')
                self.incoming.put(json.loads(body))
        except BaseException as error:
            self.incoming.put(error)

    def send(self, message):
        body = json.dumps({'jsonrpc': '2.0', **message}).encode('utf-8')
        self.process.stdin.write(b'Content-Length: ' + str(len(body)).encode('ascii') + b'\r\n\r\n' + body)
        self.process.stdin.flush()

    def notify(self, method, params):
        self.send({'method': method, 'params': params})

    def request(self, method, params):
        self.next_id += 1
        request_id = self.next_id
        self.send({'id': request_id, 'method': method, 'params': params})
        deadline = time.monotonic() + self.timeout
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError(f'Timed out waiting for {method}')
            try:
                message = self.incoming.get(timeout=remaining)
            except queue.Empty as error:
                raise TimeoutError(f'Timed out waiting for {method}') from error
            if isinstance(message, BaseException):
                raise message
            if message.get('id') == request_id and 'method' not in message:
                if 'error' in message:
                    raise RuntimeError(f'{method}: {message["error"]}')
                return message.get('result')
            if 'method' in message and 'id' in message:
                if message['method'] == 'workspace/configuration':
                    result = [None for _ in message.get('params', {}).get('items', [])]
                else:
                    result = None
                self.send({'id': message['id'], 'result': result})
            else:
                self.notifications.append(message)

    def close(self):
        try:
            if self.process.poll() is None:
                self.timeout = min(self.timeout, 5)
                self.request('shutdown', None)
                self.notify('exit', None)
                self.process.wait(timeout=5)
        except (OSError, EOFError, RuntimeError, TimeoutError, subprocess.TimeoutExpired):
            # Cleanup must not hide the actual verification failure.
            pass
        finally:
            if self.process.poll() is None:
                self.process.kill()
                self.process.wait(timeout=5)
            self.process.stdin.close()
            self.process.stdout.close()
            self.stderr.close()


def option_values(arguments, flag):
    return [arguments[i + 1] for i, value in enumerate(arguments[:-1]) if value == flag]


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def verify_reference(client, source, text, declaration, symbol, caller, call):
    line_number, line = next((i, line) for i, line in enumerate(text.splitlines()) if declaration in line)
    caller_line = next(i for i, line in enumerate(caller.read_text(encoding='utf-8').splitlines()) if call in line)
    references = client.request('textDocument/references', {
        'textDocument': {'uri': source.as_uri()},
        'position': {'line': line_number, 'character': line.index(symbol) + 1},
        'context': {'includeDeclaration': False},
    })
    require(isinstance(references, list) and any(
        item.get('uri') == caller.as_uri()
        and item.get('range', {}).get('start', {}).get('line') == caller_line
        for item in references),
        f'Index did not resolve {symbol} to {caller.name}:{caller_line + 1}; '
        'run make sourcekit to rebuild the app and test indexes')
    return {
        'symbol': symbol,
        'count': len(references),
        'expectedCaller': {'uri': caller.as_uri(), 'line': caller_line + 1},
    }


def verify(root, timeout):
    source = root / 'NotificationManager/App/NotificationApplicationDelegate.swift'
    test_source = root / 'NotificationManagerTests/NotificationApplicationDelegateTests.swift'
    database = json.loads((root / 'compile_commands.json').read_text(encoding='utf-8'))
    matching = [entry for entry in database if pathlib.Path(entry['file']) == source]
    require(bool(matching), 'Compilation database does not contain the app delegate')
    test_matching = [entry for entry in database if pathlib.Path(entry['file']) == test_source]
    require(bool(test_matching), 'Compilation database lacks the test caller; run make sourcekit '
            'with SOURCEKIT_ACTION=build-for-testing (the default)')
    expected_entry = matching[0]
    expected = expected_entry['arguments'][1:]
    expected_sources = {arg for arg in expected if arg.endswith('.swift')}
    require(len(expected_sources) > 1, 'Database command lacks the complete target source list')
    require(option_values(expected, '-module-name') == ['NotificationManager'], 'Unexpected app module name')
    expected_sdk = option_values(expected, '-sdk')
    require(bool(expected_sdk) and 'iPhoneSimulator' in expected_sdk[-1], 'Expected an iOS Simulator SDK')
    expected_target = option_values(expected, '-target')
    require(bool(expected_target) and expected_target[-1].endswith('-simulator'), 'Expected a simulator target')
    products = [path for path in option_values(expected, '-I') if '/Build/Products/' in path]
    require(bool(products), 'Database command lacks ordinary Xcode build products')
    require(any((pathlib.Path(path) / 'NotificationManagerDomain.swiftmodule').exists() for path in products),
            'NotificationManagerDomain.swiftmodule is missing; run the ordinary build first')
    index_stores = option_values(expected, '-index-store-path')
    require(bool(index_stores), 'App command lacks -index-store-path; run make sourcekit with indexing enabled')
    index_store = pathlib.Path(index_stores[-1])
    if not index_store.is_absolute():
        index_store = pathlib.Path(expected_entry['directory']) / index_store
    require(index_store.is_dir(), 'Index store is missing; run make sourcekit first')
    require(option_values(test_matching[0]['arguments'], '-index-store-path') == index_stores,
            'Test caller does not use the app index store; run make sourcekit with indexing enabled')

    client = LSPClient(root, timeout)
    try:
        initialized = client.request('initialize', {
            'processId': None,
            'clientInfo': {'name': 'nomad-sourcekit-verification'},
            'rootUri': root.as_uri(),
            'workspaceFolders': [{'uri': root.as_uri(), 'name': root.name}],
            'capabilities': {
                'textDocument': {
                    'hover': {'contentFormat': ['markdown', 'plaintext']},
                    'diagnostic': {'dynamicRegistration': False, 'relatedDocumentSupport': True},
                },
            },
        })
        references_provider = initialized.get('capabilities', {}).get('referencesProvider')
        require(references_provider is True or isinstance(references_provider, dict),
                'SourceKit-LSP does not provide reference lookup')
        client.notify('initialized', {})
        options = client.request('workspace/_sourceKitOptions', {
            'textDocument': {'uri': source.as_uri()},
            'prepareTarget': False,
            'allowFallbackSettings': False,
        })
        require(options is not None, 'SourceKit-LSP returned no compiler settings')
        arguments = options['compilerArguments']
        require(option_values(arguments, '-module-name') == ['NotificationManager'],
                'SourceKit-LSP did not load the app module settings')
        require(option_values(arguments, '-sdk') == expected_sdk, 'SourceKit-LSP selected a different SDK')
        require(option_values(arguments, '-target') == expected_target, 'SourceKit-LSP selected a different target')
        require(set(products).issubset(option_values(arguments, '-I')), 'SourceKit-LSP lost the Xcode products search path')
        require(expected_sources.issubset(arguments), 'SourceKit-LSP lost target sources')
        require(options.get('workingDirectory') == expected_entry['directory'], 'SourceKit-LSP selected another working directory')
        text = source.read_text(encoding='utf-8')
        client.notify('textDocument/didOpen', {'textDocument': {
            'uri': source.as_uri(), 'languageId': 'swift', 'version': 1, 'text': text,
        }})
        diagnostics = client.request('textDocument/diagnostic', {'textDocument': {'uri': source.as_uri()}})
        require(isinstance(diagnostics, dict) and diagnostics.get('kind') == 'full'
                and isinstance(diagnostics.get('items'), list),
                f'Expected a full diagnostic report: {diagnostics}')
        items = diagnostics['items']
        errors = [item for item in items if item.get('severity') == 1]
        require(not errors, f'SourceKit-LSP returned error diagnostics: {errors}')
        symbol = 'ReminderSnapshot'
        line_number, line = next((i, line) for i, line in enumerate(text.splitlines()) if symbol in line)
        hover = client.request('textDocument/hover', {
            'textDocument': {'uri': source.as_uri()},
            'position': {'line': line_number, 'character': line.index(symbol) + 1},
        })
        require(hover is not None and 'struct ReminderSnapshot' in json.dumps(hover),
                f'SourceKit-LSP did not resolve the Domain symbol: {hover}')
        symbol_info = client.request('textDocument/symbolInfo', {
            'textDocument': {'uri': source.as_uri()},
            'position': {'line': line_number, 'character': line.index(symbol) + 1},
        })
        require(isinstance(symbol_info, list) and any(
            item.get('name') == symbol and 'NotificationManagerDomain' in item.get('usr', '')
            for item in symbol_info), f'Symbol was not resolved in the Domain module: {symbol_info}')
        # Loading index units is asynchronous. Wait for ingestion before querying
        # references, even when background compilation is unavailable for a compdb.
        client.request('workspace/synchronize', {'index': True})
        references = {
            'app': verify_reference(
                client, source, text, 'func install()', 'install',
                root / 'NotificationManager/App/AppBootstrapper.swift', 'notificationDelegate.install()'),
            'testCallback': verify_reference(
                client, source, text, 'func userNotificationCenter(', 'userNotificationCenter',
                test_source, 'delegate.userNotificationCenter('),
        }
        report = {
            'root': str(root),
            'source': str(source),
            'discovery': 'default (no --default-workspace-type or extra search paths)',
            'settingsKind': options.get('kind'),
            'module': option_values(arguments, '-module-name')[-1],
            'sdk': expected_sdk[-1],
            'target': expected_target[-1],
            'products': products,
            'targetSources': len(expected_sources),
            'diagnostics': diagnostics,
            'hover': hover,
            'symbolInfo': symbol_info,
            'indexStore': str(index_store),
            'references': references,
            'diagnosticProvider': initialized.get('capabilities', {}).get('diagnosticProvider'),
        }
        return report
    finally:
        client.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=pathlib.Path, nargs='?', default=pathlib.Path(__file__).resolve().parent.parent)
    parser.add_argument('--timeout', type=float, default=60)
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error('--timeout must be positive')
    try:
        report = verify(args.root.resolve(), args.timeout)
    except (OSError, ValueError, RuntimeError, TimeoutError, EOFError, subprocess.TimeoutExpired) as error:
        print(f'Verification failed: {error}', file=sys.stderr)
        return 1
    print(json.dumps(report, indent=2, ensure_ascii=False))
    return 0


if __name__ == '__main__':
    sys.exit(main())
