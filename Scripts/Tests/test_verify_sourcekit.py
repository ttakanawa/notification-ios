import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import verify_sourcekit as module


class VerificationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='sourcekit verification ')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.source = self.root / 'NotificationManager/App/NotificationApplicationDelegate.swift'
        self.caller = self.source.with_name('AppBootstrapper.swift')
        self.test = self.root / 'NotificationManagerTests/NotificationApplicationDelegateTests.swift'
        self.source.parent.mkdir(parents=True)
        self.test.parent.mkdir()
        self.source.write_text(
            'final class NotificationApplicationDelegate {\n'
            '    typealias Lookup = ReminderSnapshot\n'
            '    func install() {}\n'
            '    func userNotificationCenter() {}\n'
            '}\n', encoding='utf-8')
        self.caller.write_text('func bootstrap() {\n    notificationDelegate.install()\n}\n', encoding='utf-8')
        self.test.write_text('func testCallback() {\n    delegate.userNotificationCenter()\n}\n', encoding='utf-8')
        products = self.root / 'Build/Products/Debug-iphonesimulator'
        (products / 'NotificationManagerDomain.swiftmodule').mkdir(parents=True)
        self.index_store = self.root / 'Index.noindex/DataStore'
        self.index_store.mkdir(parents=True)
        self.arguments = [
            'swiftc', '-module-name', 'NotificationManager', '-sdk', '/SDK/iPhoneSimulator.sdk',
            '-target', 'arm64-apple-ios18.0-simulator', '-I', str(products),
            '-index-store-path', str(self.index_store), str(self.source), str(self.caller),
        ]
        self.database = [
            {'file': str(self.source), 'directory': str(self.root), 'arguments': self.arguments},
            {'file': str(self.test), 'directory': str(self.root), 'arguments': [
                'swiftc', '-module-name', 'NotificationManagerTests',
                '-index-store-path', str(self.index_store), str(self.test),
            ]},
        ]
        self.app_references = [self.location(self.caller, 1)]
        self.test_references = [self.location(self.test, 1)]
        self.references_provider = True
        self.client = mock.Mock()
        self.client.request.side_effect = self.respond
        patcher = mock.patch.object(module, 'LSPClient', return_value=self.client)
        patcher.start()
        self.addCleanup(patcher.stop)

    def location(self, path, line):
        return {'uri': path.as_uri(), 'range': {'start': {'line': line, 'character': 4}}}

    def respond(self, method, params):
        if method == 'initialize':
            return {'capabilities': {'referencesProvider': self.references_provider}}
        if method == 'workspace/_sourceKitOptions':
            return {'compilerArguments': self.arguments[1:], 'workingDirectory': str(self.root), 'kind': 'normal'}
        if method == 'textDocument/diagnostic':
            return {'kind': 'full', 'items': []}
        if method == 'textDocument/hover':
            return {'contents': 'struct ReminderSnapshot'}
        if method == 'textDocument/symbolInfo':
            return [{'name': 'ReminderSnapshot', 'usr': 's:25NotificationManagerDomain16ReminderSnapshotV'}]
        if method == 'workspace/synchronize':
            self.assertEqual(params, {'index': True})
            return {}
        if method == 'textDocument/references':
            self.assertEqual(params['context'], {'includeDeclaration': False})
            return self.app_references if params['position']['line'] == 2 else self.test_references
        self.fail(f'Unexpected request: {method}')

    def verify(self):
        (self.root / 'compile_commands.json').write_text(json.dumps(self.database), encoding='utf-8')
        return module.verify(self.root, 10)

    def test_requires_app_and_test_references_after_index_synchronization(self):
        report = self.verify()
        self.assertEqual(report['references']['app']['count'], 1)
        self.assertEqual(report['references']['testCallback']['count'], 1)
        self.assertEqual(report['indexStore'], str(self.index_store))
        methods = [call.args[0] for call in self.client.request.call_args_list]
        self.assertLess(methods.index('workspace/synchronize'), methods.index('textDocument/references'))
        self.client.close.assert_called_once()

    def test_missing_app_index_flag_is_rejected_before_starting_server(self):
        index = self.arguments.index('-index-store-path')
        del self.arguments[index:index + 2]
        with self.assertRaisesRegex(RuntimeError, 'App command lacks -index-store-path'):
            self.verify()
        self.client.request.assert_not_called()

    def test_reference_provider_options_object_is_accepted(self):
        self.references_provider = {}
        self.verify()

    def test_absent_reference_provider_is_rejected(self):
        self.references_provider = False
        with self.assertRaisesRegex(RuntimeError, 'does not provide reference lookup'):
            self.verify()

    def test_app_only_database_is_rejected_even_if_old_test_index_exists(self):
        self.database.pop()
        with self.assertRaisesRegex(RuntimeError, 'Compilation database lacks the test caller'):
            self.verify()

    def test_empty_references_fail_despite_successful_hover_and_symbol_info(self):
        self.app_references = []
        with self.assertRaisesRegex(RuntimeError, 'Index did not resolve install'):
            self.verify()
        self.client.close.assert_called_once()

    def test_references_in_other_files_do_not_mask_missing_app_index(self):
        self.app_references = [self.location(self.test, 1)]
        with self.assertRaisesRegex(RuntimeError, 'Index did not resolve install'):
            self.verify()

    def test_stale_reference_on_wrong_line_is_rejected(self):
        self.app_references = [self.location(self.caller, 0)]
        with self.assertRaisesRegex(RuntimeError, 'Index did not resolve install'):
            self.verify()

    def test_missing_callback_reference_is_rejected(self):
        self.test_references = []
        with self.assertRaisesRegex(RuntimeError, 'Index did not resolve userNotificationCenter'):
            self.verify()

    def test_test_index_in_a_different_store_is_rejected(self):
        self.database[1]['arguments'][4] = str(self.root / 'OtherIndex')
        with self.assertRaisesRegex(RuntimeError, 'Test caller does not use the app index store'):
            self.verify()


if __name__ == '__main__':
    unittest.main()
