import copy
import contextlib
import io
import json
import os
import struct
import tempfile
import unittest
import sys
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import generate_compile_commands as module

from generate_compile_commands import (
    ExtractionError, SWBMessagePack, extract_compilation_database,
    response_tokens, expand_response_files, expand_source_filelists,
)


def pack(value):
    """Small fixture writer, not production serialization code."""
    if value is None:
        return b"\xc0"
    if type(value) is bool:
        return b"\xc3" if value else b"\xc2"
    if type(value) is int:
        return b"\xd3" + struct.pack(">q", value)
    if isinstance(value, bytes):
        return b"\xc6" + struct.pack(">I", len(value)) + value
    if isinstance(value, str):
        data = value.encode("utf-8")
        return b"\xdb" + struct.pack(">I", len(data)) + data
    if isinstance(value, list):
        return b"\xdd" + struct.pack(">I", len(value)) + b"".join(pack(item) for item in value)
    raise TypeError(value)


class MessagePackTests(unittest.TestCase):
    def test_native_uint8_marker_does_not_break_aggregate_alignment(self):
        self.assertEqual(SWBMessagePack(b"\x92\xe0\x00\xc4\x01x").decode(), [0, b"x"])

    def test_scalar_and_map_variants(self):
        data = b"\x96\xff\xcc\x80\xcd\x01\x00\xce\x00\x01\x00\x00\xca" + struct.pack(">f", 1.5) + b"\x81\x91\x01\xa1v"
        self.assertEqual(SWBMessagePack(data).decode(), [-1, 128, 256, 65536, 1.5, [([1], "v")]])

    def test_invalid_or_truncated_data_is_rejected(self):
        for data in (b"", b"\xe0", b"\x92\xc0", b"\xdb\x00\x00\x00\x05abc", b"\xc1", b"\xa1\xff", b"\xc0\xc0", b"\xdd\xff\xff\xff\xff"):
            with self.subTest(data=data), self.assertRaises(ExtractionError):
                SWBMessagePack(data).decode()

    def test_excessive_nesting_is_rejected(self):
        with self.assertRaises(ExtractionError):
            SWBMessagePack(b"\x91" * 130 + b"\xc0").decode()


class ExtractionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="sourcekit extraction ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve() / "Work tree"
        self.root.mkdir()
        (self.root / "App.xcodeproj").mkdir()
        (self.root / "Sources").mkdir()
        self.compiler = self.root / "Xcode Toolchain" / "swiftc"
        self.compiler.parent.mkdir()
        self.compiler.write_text("fixture")
        self.a = self.root / "Sources" / "A first.swift"
        self.b = self.root / "Sources" / "B.swift"
        self.shared = self.root / "Sources" / "Shared.swift"
        for source in (self.a, self.b, self.shared):
            source.write_text("struct Fixture {}\n")
        self.description = Path(self.temp.name).resolve() / "Derived data" / "plan.xcbuilddata"
        self.description.mkdir(parents=True)
        self.request = {"containerPath": str(self.root / "App.xcodeproj"), "enableIndexBuildArena": False}
        self.tasks = [self.task("ZApp", "arm64", [self.a, self.shared]), self.task("ADomain", "arm64", [self.b, self.shared]), self.task("ZApp", "x86_64", [self.a, self.shared])]
        self.manifest = {"commands": {str(index): self.manifest_command(task) for index, task in enumerate(self.tasks)}}
        self.save()

    def task(self, module, architecture, sources, source_arguments=None):
        arguments = [str(self.compiler), "-module-name", module, "-target", architecture + "-apple-ios18.0-simulator", "-I", str(self.root / "Products with spaces"), "-c"]
        arguments.extend([str(source) for source in sources] if source_arguments is None else source_arguments)
        task = [None] * 25
        task[4] = ["SwiftDriver Compilation", module, "normal", architecture, "com.apple.xcode.tools.swift.compiler"]
        task[6] = [[0, value.encode("utf-8")] for value in ["builtin-Swift-Compilation", "--"] + arguments]
        task[9] = str(self.root)
        task[17] = [str(source) for source in sources]
        return task

    def manifest_command(self, task):
        return {"tool": "swift-driver-compilation", "description": " ".join(task[4]), "inputs": task[17] + [str(self.root / "OutputFileMap.json")]}

    def save(self):
        (self.description / "build-request.json").write_text(json.dumps(self.request))
        (self.description / "manifest.json").write_text(json.dumps(self.manifest))
        (self.description / "task-store.msgpack").write_bytes(pack(self.tasks))

    def extract(self, architecture="arm64"):
        self.save()
        return extract_compilation_database(self.description, self.root, architecture)

    def test_all_targets_and_shared_sources_survive_no_op_build_plan(self):
        entries = self.extract()
        self.assertEqual(len(entries), 4)
        self.assertEqual({entry["file"] for entry in entries}, {str(self.a), str(self.b), str(self.shared)})
        shared = [entry for entry in entries if entry["file"] == str(self.shared)]
        modules = [entry["arguments"][entry["arguments"].index("-module-name") + 1] for entry in shared]
        self.assertEqual(modules, ["ADomain", "ZApp"])
        self.assertTrue(all("arm64-apple-ios18.0-simulator" in entry["arguments"] for entry in entries))
        self.tasks.reverse()
        self.assertEqual(entries, self.extract())
        self.assertEqual(len(self.extract("x86_64")), 2)

    def test_nested_response_files_and_spaces_are_inlined(self):
        (self.root / "Responses").mkdir()
        (self.root / "Sources.rsp").write_text('// ignored\n"Sources/A first.swift" Sources/Shared.swift\n')
        (self.root / "Responses" / "Outer.rsp").write_text('@Sources.rsp\n')
        self.tasks[0] = self.task("ZApp", "arm64", [self.a, self.shared], ["@Responses/Outer.rsp"])
        entries = self.extract()
        args = next(entry["arguments"] for entry in entries if entry["file"] == str(self.a))
        self.assertIn("Sources/A first.swift", args)
        self.assertFalse(any(argument.startswith("@") for argument in args))

    def test_raw_filelist_preserves_unquoted_spaces_and_crlf(self):
        (self.root / "Sources.list").write_bytes(b"Sources/A first.swift\r\nSources/Shared.swift\r\n\r\n")
        self.tasks[0] = self.task("ZApp", "arm64", [self.a, self.shared], ["-filelist", "Sources.list"])
        entries = self.extract()
        self.assertIn("Sources/A first.swift", entries[0]["arguments"])
        self.assertFalse(any("-filelist" in entry["arguments"] for entry in entries))

    def test_forwarded_filelist_and_primary_filelist(self):
        (self.root / "Sources.list").write_text("Sources/A first.swift\nSources/Shared.swift\n")
        args = expand_source_filelists(["swiftc", "-Xfrontend", "-filelist", "-Xfrontend", "Sources.list"], self.root)
        self.assertEqual(args, ["swiftc", "Sources/A first.swift", "Sources/Shared.swift"])
        primary = expand_source_filelists(["-primary-filelist", "Sources.list"], self.root)
        self.assertEqual(primary, ["-primary-file", "Sources/A first.swift", "-primary-file", "Sources/Shared.swift"])
        with self.assertRaises(ExtractionError):
            expand_source_filelists(["-Xfrontend", "-filelist", "bad"], self.root)

    def test_generated_sources_outside_repo_are_supported(self):
        generated = self.description.parent / "Generated symbols.swift"
        generated.write_text("let generated = 1\n")
        self.tasks[0] = self.task("ZApp", "arm64", [self.a, self.shared, generated])
        self.manifest["commands"]["0"] = self.manifest_command(self.tasks[0])
        self.assertEqual(len(self.extract()), 5)

    def test_tagged_path_and_parent_path_arguments(self):
        for task in self.tasks:
            task[6][4] = [1, task[6][4][1].decode()]  # module-name argument becomes path-tagged string.
            task[6].extend([[0, b"-I"], [2, str(self.root / "include" / "dummy")]])
        args = self.extract()[0]["arguments"]
        self.assertIn(str(self.root / "include"), args)

    def test_compiler_option_operand_ending_swift_is_not_source(self):
        self.tasks[0][6].extend([[0, b"-emit-module-path"], [0, str(self.root / "Output.swift").encode()]])
        self.assertEqual(len(self.extract()), 4)

    def test_partial_or_empty_plan_is_rejected(self):
        self.tasks.pop()
        with self.assertRaisesRegex(ExtractionError, "complete XCBuild manifest"):
            self.extract()
        self.tasks = []
        with self.assertRaises(ExtractionError):
            self.extract()
        self.manifest = {"commands": {}}
        with self.assertRaises(ExtractionError):
            self.extract()

    def test_source_added_or_removed_from_args_is_rejected(self):
        for extra in ([], [[0, str(self.b).encode()]]):
            self.tasks[0] = self.task("ZApp", "arm64", [self.a, self.shared])
            if extra:
                self.tasks[0][6].extend(extra)
            else:
                self.tasks[0][6].pop()
            with self.subTest(extra=extra), self.assertRaisesRegex(ExtractionError, "authoritative XCBuild inputs"):
                self.extract()

    def test_foreign_worktree_and_index_arena_are_rejected(self):
        self.request["containerPath"] = str(self.description)
        with self.assertRaisesRegex(ExtractionError, "another worktree"):
            self.extract()
        self.request["containerPath"] = str(self.root / "App.xcodeproj")
        self.request["enableIndexBuildArena"] = True
        with self.assertRaisesRegex(ExtractionError, "indexing build arena"):
            self.extract()
        self.request["enableIndexBuildArena"] = False
        self.tasks[0][9] = str(self.description)
        with self.assertRaisesRegex(ExtractionError, "another worktree"):
            self.extract()

    def test_unknown_task_or_argument_schema_is_rejected(self):
        original = copy.deepcopy(self.tasks)
        for mutation in (lambda: self.tasks[0].append(None), lambda: self.tasks[0][6].append([99, "unknown"])):
            self.tasks = copy.deepcopy(original)
            mutation()
            with self.assertRaises(ExtractionError):
                self.extract()

    def test_wrong_architecture_or_module_is_rejected(self):
        with self.assertRaisesRegex(ExtractionError, "architecture riscv64"):
            self.extract("riscv64")
        self.tasks[0][6][4] = [0, b"WrongModule"]
        with self.assertRaises(ExtractionError):
            self.extract()

    def test_missing_source_and_response_are_rejected(self):
        self.tasks[0] = self.task("ZApp", "arm64", [self.a, self.shared], ["@missing.rsp"])
        with self.assertRaisesRegex(ExtractionError, "Missing or unreadable"):
            self.extract()
        self.a.unlink()
        with self.assertRaises(ExtractionError):
            self.extract()

    def test_invalid_json_and_truncated_task_store_are_rejected(self):
        (self.description / "manifest.json").write_text("{")
        with self.assertRaises(ExtractionError):
            extract_compilation_database(self.description, self.root)
        self.save()
        data = (self.description / "task-store.msgpack").read_bytes()
        (self.description / "task-store.msgpack").write_bytes(data[:-1])
        with self.assertRaises(ExtractionError):
            extract_compilation_database(self.description, self.root)

    def test_response_recursion_and_hardlink_cycles_are_rejected(self):
        (self.root / "a.rsp").write_text("@b.rsp")
        os.link(self.root / "a.rsp", self.root / "b.rsp")
        with self.assertRaisesRegex(ExtractionError, "Cyclic"):
            expand_response_files(["@a.rsp"], self.root)


class ResponseSyntaxTests(unittest.TestCase):
    def test_swift_response_syntax_is_not_posix_shlex(self):
        contents = '// comment\n"A first.swift" B\\ second.swift \'C\\ third.swift\' #literal\n"D\\\"quote.swift"\n'
        self.assertEqual(response_tokens(contents), ["A first.swift", "B second.swift", "C third.swift", "#literal", 'D"quote.swift'])

    def test_unterminated_input_is_rejected(self):
        for value in ('"unclosed', "path\\"):
            with self.subTest(value=value), self.assertRaises(ExtractionError):
                response_tokens(value)


class OrchestrationTests(unittest.TestCase):
    def test_main_does_not_replace_database_when_build_or_extraction_fails(self):
        import subprocess
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            database = root / 'compile_commands.json'
            database.write_text('[{"sentinel":true}]\n')
            for error in (ExtractionError('incomplete plan'),
                          subprocess.CalledProcessError(65, ['xcodebuild'])):
                with self.subTest(error=error), \
                     mock.patch.object(module, '__file__', str(root / 'Scripts' / 'generate.py')), \
                     mock.patch.object(module, 'build_database', side_effect=error), \
                     mock.patch.object(module, 'atomic_write_database') as write, \
                     contextlib.redirect_stderr(io.StringIO()):
                    self.assertEqual(module.main(['--', '-project', 'App.xcodeproj']), 1)
                write.assert_not_called()
                self.assertEqual(database.read_text(), '[{"sentinel":true}]\n')

    def test_streamed_build_path_and_exit_status(self):
        import subprocess
        with tempfile.TemporaryDirectory() as directory, contextlib.redirect_stdout(io.StringIO()) as output:
            path = Path(directory) / 'Derived data' / 'plan.xcbuilddata'
            command = [sys.executable, '-c', 'print(' + repr('Build description path: ' + str(path)) + ')']
            self.assertEqual(module.run_build(Path(directory), command), path)
            with self.assertRaises(subprocess.CalledProcessError):
                module.run_build(Path(directory), [sys.executable, '-c', 'import sys; sys.exit(65)'])
            self.assertIn(str(path), output.getvalue())

    def test_conflicting_build_paths_are_rejected_after_draining_output(self):
        with tempfile.TemporaryDirectory() as directory, contextlib.redirect_stdout(io.StringIO()):
            command = [sys.executable, '-c',
                       "print('Build description path: /first'); "
                       "print('Build description path: /second'); print('x' * 200000)"]
            with self.assertRaisesRegex(ExtractionError, 'Multiple build descriptions'):
                module.run_build(Path(directory), command)

    def test_build_failure_keeps_existing_database(self):
        import subprocess
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            database = root / 'compile_commands.json'
            database.write_text('[{"sentinel":true}]\n')
            settings = [{'buildSettings': {'SRCROOT': str(root), 'OBJROOT': str(root/'DerivedData'),
                                         'CONFIGURATION': 'Debug', 'PLATFORM_NAME': 'iphonesimulator'}}]
            with mock.patch.object(subprocess, 'check_output', return_value=json.dumps(settings)), \
                 mock.patch.object(module, 'run_build', side_effect=subprocess.CalledProcessError(65, ['xcodebuild'])):
                with self.assertRaises(subprocess.CalledProcessError):
                    module.build_database(root, ['-project', 'App.xcodeproj'], 'arm64')
            self.assertEqual(database.read_text(), '[{"sentinel":true}]\n')

    def test_atomic_replace_failure_preserves_existing_database_and_removes_temp_file(self):
        import os
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            database = root / 'compile_commands.json'
            database.write_text('[{"sentinel":true}]\n')
            with mock.patch.object(os, 'replace', side_effect=OSError('simulated replace error')):
                with self.assertRaises(OSError):
                    module.atomic_write_database(database, [{'new': True}])
            self.assertEqual(database.read_text(), '[{"sentinel":true}]\n')
            self.assertEqual(list(root.glob('.compile_commands.*.tmp')), [])

    def test_noop_build_uses_last_recorded_description_not_newest_timestamp(self):
        import os
        import subprocess
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            arena = root / 'DerivedData' / 'XCBuildData'
            arena.mkdir(parents=True)
            correct = arena / ('a' * 32 + '.xcbuilddata')
            newer_but_unused = arena / ('b' * 32 + '.xcbuilddata')
            correct.mkdir()
            newer_but_unused.mkdir()
            request = {'containerPath': str(root / 'App.xcodeproj'),
                       'parameters': {'configurationName': 'Debug',
                                      'activeRunDestination': {'platform': 'iphonesimulator'}}}
            (correct / 'build-request.json').write_text(json.dumps(request))
            (arena / 'prior-build-descriptions.txt').write_text('b'*32+'\n'+'a'*32+'\n')
            settings = [{'buildSettings': {'SRCROOT': str(root), 'OBJROOT': str(arena.parent),
                                         'CONFIGURATION': 'Debug', 'PLATFORM_NAME': 'iphonesimulator'}}]
            with mock.patch.object(subprocess, 'check_output', return_value=json.dumps(settings)), \
                 mock.patch.object(module, 'run_build', return_value=None), \
                 mock.patch.object(module, 'extract_compilation_database', return_value=[{'selected': True}]) as extract:
                entries = module.build_database(root, ['-project', 'App.xcodeproj'], 'arm64')
            self.assertEqual(entries, [{'selected': True}])
            extract.assert_called_once_with(correct, root, 'arm64')


if __name__ == "__main__":
    unittest.main()
