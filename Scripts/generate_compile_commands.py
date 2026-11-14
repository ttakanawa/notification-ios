#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.9"
# dependencies = []
# ///

"""Extract a complete Swift compilation database from one XCBuild description.

This deliberately supports the 25-field Task schema observed in Xcode 27.2.
XCBuild's files are internal interfaces: reject unknown shapes instead of emitting
an incomplete database after an Xcode update. Updates use an ordinary build and preserve existing JSON on failure.

Format references (Swift project's primary sources):
https://github.com/swiftlang/swift-build/blob/main/Sources/SWBTaskExecution/Task.swift
https://github.com/swiftlang/swift-build/blob/main/Sources/SWBCore/CommandLineArgument.swift
https://github.com/swiftlang/swift-build/blob/main/Sources/SWBUtil/MsgPack.swift
"""

import collections
import json
import re
import struct
from pathlib import Path


class ExtractionError(ValueError):
    """The build description cannot safely produce a complete database."""


class SWBMessagePack:
    """Bounded decoder for Swift Build's MessagePack dialect.

    SWBUtil reserves 0xe0 followed by one byte for UInt8. It is not the standard
    MessagePack negative fixint -32; treating it as such loses array alignment.
    Map keys can be aggregates, so unused maps are represented as key/value pairs.
    """

    def __init__(self, data):
        self.data = data
        self.offset = 0

    def take(self, count):
        end = self.offset + count
        if count < 0 or end > len(self.data):
            raise ExtractionError("Truncated task store at byte %d" % self.offset)
        value = self.data[self.offset:end]
        self.offset = end
        return value

    def integer(self, width, signed=False):
        return int.from_bytes(self.take(width), "big", signed=signed)

    def value(self, depth=0):
        if depth > 128:
            raise ExtractionError("Task store nesting exceeds 128 levels")
        code = self.integer(1)
        if code == 0xe0:
            return self.integer(1)
        if code < 0x80:
            return code
        if code >= 0xe1:
            return code - 256
        if code == 0xc0:
            return None
        if code in (0xc2, 0xc3):
            return code == 0xc3
        if 0xcc <= code <= 0xcf:
            return self.integer(1 << (code - 0xcc))
        if 0xd0 <= code <= 0xd3:
            return self.integer(1 << (code - 0xd0), signed=True)
        if code in (0xca, 0xcb):
            return struct.unpack(">f" if code == 0xca else ">d", self.take(4 if code == 0xca else 8))[0]
        if 0xa0 <= code <= 0xbf or code in (0xd9, 0xda, 0xdb):
            count = code & 31 if code <= 0xbf else self.integer(1 << (code - 0xd9))
            try:
                return self.take(count).decode("utf-8")
            except UnicodeDecodeError as error:
                raise ExtractionError("Invalid UTF-8 in task store") from error
        if code in (0xc4, 0xc5, 0xc6):
            return self.take(self.integer(1 << (code - 0xc4)))
        if 0x90 <= code <= 0x9f or code in (0xdc, 0xdd):
            count = code & 15 if code <= 0x9f else self.integer(2 if code == 0xdc else 4)
            if count > len(self.data) - self.offset:
                raise ExtractionError("Impossible task-store array length")
            return [self.value(depth + 1) for _ in range(count)]
        if 0x80 <= code <= 0x8f or code in (0xde, 0xdf):
            count = code & 15 if code <= 0x8f else self.integer(2 if code == 0xde else 4)
            if count > (len(self.data) - self.offset) // 2:
                raise ExtractionError("Impossible task-store map length")
            return [(self.value(depth + 1), self.value(depth + 1)) for _ in range(count)]
        raise ExtractionError("Unsupported MessagePack code 0x%02x at byte %d" % (code, self.offset - 1))

    def decode(self):
        result = self.value()
        if self.offset != len(self.data):
            raise ExtractionError("Trailing bytes in task store at byte %d" % self.offset)
        return result


def _path(value, directory, require_file=False):
    if not isinstance(value, str) or not value or "\0" in value:
        raise ExtractionError("Invalid path: %r" % (value,))
    result = Path(value)
    if not result.is_absolute():
        result = directory / result
    try:
        result = result.resolve(strict=True)
    except (OSError, RuntimeError) as error:
        raise ExtractionError("Missing or unreadable path: %s" % result) from error
    if require_file and not result.is_file():
        raise ExtractionError("Expected a regular file: %s" % result)
    return result


def _inside(path, root):
    try:
        path.relative_to(root)
        return True
    except ValueError:
        return False


def _read_text(path):
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        raise ExtractionError("Cannot read UTF-8 file: %s" % path) from error
    if "\0" in text:
        raise ExtractionError("NUL byte in text file: %s" % path)
    return text


def _read_json(path):
    try:
        value = json.loads(_read_text(path))
    except json.JSONDecodeError as error:
        raise ExtractionError("Invalid JSON: %s" % path) from error
    if not isinstance(value, dict):
        raise ExtractionError("Expected a JSON object: %s" % path)
    return value


def response_tokens(contents):
    """SwiftDriver's Darwin response syntax, with malformed input rejected.

    Unlike shlex, either quote toggles quoting, and backslash escapes everywhere.
    A line beginning exactly with // is a comment. Nested @ paths use the original
    compiler cwd. Empty quoted tokens are dropped by SwiftDriver too.
    https://github.com/swiftlang/swift-driver/blob/main/Sources/SwiftDriver/Driver/Driver.swift
    """
    result = []
    for line in contents.split("\n"):
        if line.startswith("//"):
            continue
        token = []
        quoted = False
        escaped = False
        for char in line:
            if char == "\\" and not escaped:
                escaped = True
                continue
            if escaped:
                escaped = False
            elif char in ("'", '"'):
                quoted = not quoted
                continue
            elif char.isspace() and not quoted:
                if token:
                    result.append("".join(token))
                    token = []
                continue
            token.append(char)
        if escaped or quoted:
            raise ExtractionError("Unterminated quoting or escaping in response file")
        if token:
            result.append("".join(token))
    return result


def expand_response_files(arguments, directory, active=()):
    """Expand all Swift response files; missing/cyclic files are fatal."""
    expanded = []
    for argument in arguments:
        if not isinstance(argument, str) or "\0" in argument:
            raise ExtractionError("Invalid compiler argument")
        if not argument.startswith("@"):
            expanded.append(argument)
            continue
        path = _path(argument[1:], directory, require_file=True)
        stat = path.stat()
        identity = (stat.st_dev, stat.st_ino)
        if identity in active or len(active) >= 32:
            raise ExtractionError("Cyclic or deeply nested response file: %s" % path)
        nested = response_tokens(_read_text(path))
        expanded.extend(expand_response_files(nested, directory, active + (identity,)))
    return expanded


def _filelist_paths(value, directory):
    """Frontend -filelist paths are literal LF/CRLF lines, not shell tokens.

    https://github.com/swiftlang/swift/blob/main/lib/Frontend/ArgsToFrontendInputsConverter.cpp
    """
    path = _path(value, directory, require_file=True)
    result = []
    for line in _read_text(path).split("\n"):
        if line.endswith("\r"):
            line = line[:-1]
        if line:
            result.append(line)
    if not result:
        raise ExtractionError("Empty Swift source file list: %s" % path)
    return result


def expand_source_filelists(arguments, directory):
    """Inline direct or -Xfrontend forwarded Swift input file lists."""
    result = []
    index = 0
    while index < len(arguments):
        forwarded = arguments[index:index + 2] in (
            ["-Xfrontend", "-filelist"], ["-Xfrontend", "-primary-filelist"]
        )
        flag = arguments[index + 1] if forwarded else arguments[index]
        if flag not in ("-filelist", "-primary-filelist"):
            result.append(arguments[index])
            index += 1
            continue
        operand_index = index + (3 if forwarded else 1)
        if operand_index >= len(arguments) or (forwarded and arguments[index + 2] != "-Xfrontend"):
            raise ExtractionError("Missing operand for %s" % flag)
        paths = _filelist_paths(arguments[operand_index], directory)
        for path in paths:
            if flag == "-primary-filelist":
                result.extend(["-Xfrontend", "-primary-file", "-Xfrontend", path] if forwarded else ["-primary-file", path])
            else:
                result.append(path)
        index = operand_index + 1
    return result


def _command_argument(value):
    if not isinstance(value, list) or len(value) != 2:
        raise ExtractionError("Unknown XCBuild command argument shape")
    tag, body = value
    if type(tag) is not int:
        raise ExtractionError("Unknown XCBuild command argument tag")
    if tag == 0 and isinstance(body, bytes):
        try:
            return body.decode("utf-8")
        except UnicodeDecodeError as error:
            raise ExtractionError("Invalid UTF-8 compiler argument") from error
    if tag in (1, 2) and isinstance(body, str):
        return body if tag == 1 else str(Path(body).parent)
    raise ExtractionError("Unknown XCBuild command argument tag/type: %r" % (value,))


# These options' operands may themselves end in .swift without being source files.
_NON_SOURCE_OPERAND_OPTIONS = {
    "-I", "-F", "-Fsystem", "-Isystem", "-sdk", "-target", "-module-name",
    "-working-directory", "-o", "-output-file-map", "-emit-module-path",
    "-emit-module-interface-path", "-emit-private-module-interface-path",
    "-emit-objc-header-path", "-emit-dependencies-path", "-serialize-diagnostics-path",
    "-dependency-scan-serialize-diagnostics-path", "-emit-const-values-path",
    "-const-gather-protocols-list", "-import-objc-header", "-module-cache-path",
    "-clang-scanner-module-cache-path", "-sdk-module-cache-path", "-index-store-path",
    "-index-unit-output-path", "-clang-build-session-file", "-plugin-path",
    "-external-plugin-path", "-load-plugin-library", "-load-plugin-executable",
    "-vfsoverlay", "-Xcc", "-Xlinker", "-D", "-swift-version", "-package-name",
    "-enable-experimental-feature", "-enable-upcoming-feature", "-num-threads", "-j",
}


def _source_arguments(arguments, directory):
    sources = []
    index = 1  # Skip the absolute swiftc executable.
    while index < len(arguments):
        argument = arguments[index]
        if argument == "-Xfrontend":
            if index + 1 >= len(arguments):
                raise ExtractionError("Missing -Xfrontend operand")
            # Primary source operands must be counted even when forwarded.
            if arguments[index + 1] == "-primary-file":
                if arguments[index + 2:index + 3] != ["-Xfrontend"] or index + 3 >= len(arguments):
                    raise ExtractionError("Malformed forwarded -primary-file")
                sources.append(str(_path(arguments[index + 3], directory, require_file=True)))
                index += 4
            else:
                index += 2
            continue
        if argument in _NON_SOURCE_OPERAND_OPTIONS:
            if index + 1 >= len(arguments):
                raise ExtractionError("Missing operand for %s" % argument)
            index += 2
            continue
        if argument == "-primary-file":
            if index + 1 >= len(arguments):
                raise ExtractionError("Missing -primary-file operand")
            sources.append(str(_path(arguments[index + 1], directory, require_file=True)))
            index += 2
            continue
        if not argument.startswith("-") and argument.endswith(".swift"):
            sources.append(str(_path(argument, directory, require_file=True)))
        index += 1
    return sources


def _swift_sources(inputs, directory):
    if not isinstance(inputs, list) or not all(isinstance(value, str) for value in inputs):
        raise ExtractionError("Invalid Swift compilation input list")
    return [str(_path(value, directory, require_file=True)) for value in inputs if value.endswith(".swift")]


def _option_value(arguments, option):
    positions = [i for i, value in enumerate(arguments) if value == option]
    if len(positions) != 1 or positions[0] + 1 >= len(arguments):
        raise ExtractionError("Expected exactly one %s operand" % option)
    return arguments[positions[0] + 1]


def extract_compilation_database(description_dir, worktree_root, architecture="arm64"):
    """Return all entries for one architecture from one successful build's plan.

    Caller owns build-success checks, selecting the exact description, and atomic
    output replacement. All targets are validated against the full manifest even
    if an architecture is not selected. Same-file entries in different modules
    are retained and sorted by module name; SourceKit-LSP chooses its first entry.
    """
    root = Path(worktree_root).resolve(strict=True)
    description = Path(description_dir).resolve(strict=True)
    request = _read_json(description / "build-request.json")
    container = _path(request.get("containerPath"), root)
    if container.parent != root or container.suffix not in (".xcodeproj", ".xcworkspace"):
        raise ExtractionError("Build description belongs to another worktree: %s" % container)
    if request.get("enableIndexBuildArena") is not False:
        raise ExtractionError("Expected normal Xcode build products, not the indexing build arena")
    manifest = _read_json(description / "manifest.json")
    commands = manifest.get("commands")
    if not isinstance(commands, dict):
        raise ExtractionError("Invalid XCBuild manifest commands")
    expected = collections.Counter()
    for command in commands.values():
        if not isinstance(command, dict):
            raise ExtractionError("Invalid XCBuild manifest command")
        if command.get("tool") == "swift-driver-compilation":
            label = command.get("description")
            if not isinstance(label, str):
                raise ExtractionError("Missing Swift manifest command description")
            sources = _swift_sources(command.get("inputs"), root)
            expected[(label, tuple(sorted(sources)))] += 1
    if not expected:
        raise ExtractionError("No Swift compilation commands in XCBuild manifest")
    try:
        tasks = SWBMessagePack((description / "task-store.msgpack").read_bytes()).decode()
    except OSError as error:
        raise ExtractionError("Cannot read XCBuild task store") from error
    if not isinstance(tasks, list) or not tasks:
        raise ExtractionError("Empty or unsupported XCBuild task store")
    actual = collections.Counter()
    entries = []
    selected_commands = 0
    for task in tasks:
        if not isinstance(task, list) or len(task) != 25:
            raise ExtractionError("Unsupported XCBuild Task schema; expected 25 fields")
        rule = task[4]
        if not isinstance(rule, list) or not all(isinstance(value, str) for value in rule):
            raise ExtractionError("Invalid XCBuild Task ruleInfo")
        if not rule or rule[0] != "SwiftDriver Compilation":
            continue
        if len(rule) != 5:
            raise ExtractionError("Unsupported Swift compilation rule shape")
        directory = _path(task[9], root)
        if not directory.is_dir() or not _inside(directory, root):
            raise ExtractionError("Compiler working directory belongs to another worktree: %s" % directory)
        if not isinstance(task[6], list):
            raise ExtractionError("Invalid XCBuild commandLine")
        argv = [_command_argument(value) for value in task[6]]
        if len(argv) < 3 or argv[:2] != ["builtin-Swift-Compilation", "--"] or Path(argv[2]).name != "swiftc":
            raise ExtractionError("Unsupported Swift compilation wrapper: %r" % (argv[:3],))
        if not Path(argv[2]).is_absolute():
            raise ExtractionError("Expected absolute Swift compiler path")
        _path(argv[2], directory, require_file=True)
        sources = _swift_sources(task[17], directory)
        if not sources:
            raise ExtractionError("Swift compilation has no source files")
        actual[(" ".join(rule), tuple(sorted(sources)))] += 1
        if rule[3] != architecture:
            continue
        arguments = expand_source_filelists(expand_response_files(argv[2:], directory), directory)
        module = _option_value(arguments, "-module-name")
        triple = _option_value(arguments, "-target")
        if module != rule[1] or not triple.startswith(architecture + "-"):
            raise ExtractionError("Swift command does not match its target/architecture rule")
        if collections.Counter(_source_arguments(arguments, directory)) != collections.Counter(sources):
            raise ExtractionError("Swift command sources differ from authoritative XCBuild inputs for %s" % module)
        selected_commands += 1
        for source in sources:
            entries.append({"directory": str(directory), "file": source, "arguments": arguments})
    if actual != expected:
        raise ExtractionError("Task-store Swift commands do not cover the complete XCBuild manifest")
    if not selected_commands or not entries:
        raise ExtractionError("No Swift compilation commands for architecture %s" % architecture)
    entries.sort(key=lambda entry: (entry["file"], _option_value(entry["arguments"], "-module-name"), tuple(entry["arguments"])))
    return entries


def build_database(root, arguments, arch, action='build'):
    """Use the ordinary arena and the description actually used by this successful build."""
    import subprocess

    root = Path(root).resolve(strict=True)
    settings_command = ['xcodebuild', '-showBuildSettings', '-json', *arguments]
    settings = json.loads(subprocess.check_output(settings_command, cwd=root, text=True))
    if not isinstance(settings, list) or not settings:
        raise ExtractionError('Xcode returned no build settings')
    arenas = set()
    configurations = set()
    platforms = set()
    for target in settings:
        values = target['buildSettings']
        if Path(values['SRCROOT']).resolve() != root:
            raise ExtractionError('Build settings refer to another worktree')
        arenas.add(Path(values['OBJROOT']).resolve() / 'XCBuildData')
        configurations.add(values['CONFIGURATION'])
        platforms.add(values['PLATFORM_NAME'])
    if len(arenas) != 1 or len(configurations) != 1 or len(platforms) != 1:
        raise ExtractionError('Expected one build arena, configuration and platform')
    arena = arenas.pop()
    description_path = run_build(root, ['xcodebuild', action, *arguments])
    # Updated for cache hits too; an mtime scan can accidentally select an obsolete plan.
    description_id = (arena / 'prior-build-descriptions.txt').read_text(encoding='utf-8').splitlines()[-1].strip()
    if not re.fullmatch(r'[0-9a-f]{32}', description_id):
        raise ExtractionError('Unsupported Xcode build-description record')
    description = arena / (description_id + '.xcbuilddata')
    if description_path is not None and description_path.resolve() != description.resolve():
        raise ExtractionError('Build-description record does not match the successful build')
    request = json.loads((description / 'build-request.json').read_text(encoding='utf-8'))
    container = Path(request['containerPath']).resolve()
    if container.parent != root:
        raise ExtractionError('Build description belongs to another worktree')
    parameters = request['parameters']
    if parameters['configurationName'] not in configurations:
        raise ExtractionError('Build description has a different configuration')
    if parameters['activeRunDestination']['platform'] not in platforms:
        raise ExtractionError('Build description has a different destination platform')
    if request.get('enableIndexBuildArena') or request.get('useDryRun'):
        raise ExtractionError('Expected a normal completed build, not an index or dry-run build')
    return extract_compilation_database(description, root, arch)


def run_build(root, command):
    """Stream normal build output, retaining only the description path if printed."""
    import subprocess
    import sys

    description = None
    conflicting_descriptions = False
    with subprocess.Popen(command, cwd=root, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, text=True) as process:
        for line in process.stdout:
            sys.stdout.write(line)
            prefix = 'Build description path: '
            if line.startswith(prefix):
                candidate = Path(line[len(prefix):].strip())
                if description is not None and description != candidate:
                    conflicting_descriptions = True
                description = candidate
        if process.wait() != 0:
            raise subprocess.CalledProcessError(process.returncode, command)
    # Keep draining stdout before rejecting output, so a producer cannot block
    # on a full pipe while Popen's context manager waits for it to exit.
    if conflicting_descriptions:
        raise ExtractionError('Multiple build descriptions in one build')
    return description


def atomic_write_database(path, entries):
    import os
    import tempfile

    data = json.dumps(entries, ensure_ascii=False, indent=2) + '\n'
    # Serialize before opening anything and replace only once the entire file is written.
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=path.parent,
                                         prefix='.compile_commands.', suffix='.tmp', delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def main(argv=None):
    import argparse
    import platform
    import subprocess
    import sys

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--arch', default=platform.machine(), help='Architecture to select from the ordinary build plan')
    parser.add_argument('--action', choices=['build', 'build-for-testing'], default='build')
    parser.add_argument('xcodebuild_arguments', nargs=argparse.REMAINDER,
                        help='After --, pass the same project, scheme, configuration, destination and settings as a normal build')
    args = parser.parse_args(argv)
    arguments = args.xcodebuild_arguments
    if arguments[:1] == ['--']:
        arguments = arguments[1:]
    if not arguments:
        parser.error('Pass Xcode build options after -- (or use make sourcekit)')
    root = Path(__file__).resolve().parent.parent
    try:
        entries = build_database(root, arguments, args.arch, args.action)
        atomic_write_database(root / 'compile_commands.json', entries)
    except (OSError, ValueError, KeyError, IndexError, TypeError, subprocess.CalledProcessError) as error:
        print(f'Compilation database update failed; existing JSON preserved: {error}', file=sys.stderr)
        return 1
    print(f'Updated {root / "compile_commands.json"}: {len(entries)} Swift file commands for {args.arch}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
