# SourceKit-LSP with Xcode build settings

Use the selected Xcode's SourceKit-LSP with this worktree's ordinary build products. Install the project tools with `mise install`; [mise.toml](../mise.toml) pins uv. Use uv to run the Python scripts and their tests; no direct Python command or Xcode-provided interpreter is required. The scripts declare Python 3.9 or later and an empty dependency list in inline metadata, so uv selects a compatible interpreter and downloads one if needed. No build server or third-party Python packages are required.

## First use

From the worktree root, run with mise activated in your shell:

  ```sh
  mise install
  make sourcekit
  make verify-sourcekit
  ```

Without shell activation, use `mise exec -- make sourcekit` and `mise exec -- make verify-sourcekit` after installing the tools.

`make sourcekit` runs an ordinary Debug iOS Simulator build-for-testing, then generates [compile_commands.json](../compile_commands.json). It builds the app, widget, package dependencies and Xcode test targets without executing tests. It uses Xcode's normal DerivedData location, SDK, architectures and compiler settings, with no separate analysis build directory. The build may need the same simulator platform and signing setup as an ordinary Xcode build.

The [project](../NotificationManager.xcodeproj/project.pbxproj) enables compiler index storage and includes local definitions and references in both build configurations. Ordinary builds therefore keep app and test indexes current even when compiling with optimization. Including local symbols also triggers the initial recompilation of existing objects: [Swift Build deliberately excludes index-store path changes from task signatures](https://github.com/swiftlang/swift-build/blob/main/Sources/SWBCore/SpecImplementations/Tools/SwiftCompiler.swift#L869-L915), so enabling storage alone would not backfill missing indexes. These settings do not change the Swift optimization level.

Open Neovim with this worktree root as the LSP workspace and use `xcrun sourcekit-lsp`. SourceKit-LSP discovers the root compilation database automatically. Restart the SourceKit-LSP client after generating or updating the database; for nvim-lspconfig this is typically `:LspRestart`. No repository LSP configuration, global Neovim configuration, or Orca worktree inclusion settings need to change. A nested Swift package opened as its own workspace can select SwiftPM instead of the root database.

The generated database contains absolute paths and is ignored by Git. Generate it independently inside every worktree. Do not copy or symlink a database from another checkout, even when the branches contain the same sources.

## Daily development and updates

Edit and build normally in Xcode or through the existing [Makefile](../Makefile). There is no requirement to save build logs, regenerate the database on every build, or run a clean build.

Run `make sourcekit` again after adding, removing, moving or changing target membership of sources; changing package dependencies, build settings, configuration, SDK, architecture or Xcode toolchain; moving the checkout; or deleting DerivedData. Then restart the LSP client. Source-content-only edits do not normally require regeneration. Rebuild normally when dependency module contents change: the database supplies settings, while the compiled modules still come from Xcode.

A refresh always runs the normal incremental build first. It works even if no Swift compiler task executes. It reads the complete persisted build plan rather than merging partial build logs, so unchanged targets remain present and removed sources do not accumulate. A build failure, missing response file, incomplete extraction or unsupported format leaves the previous database intact and exits unsuccessfully. That retained database can be stale; fix the reported problem and refresh successfully before relying on its settings.

Use the same options and DerivedData location as your usual build when they differ from the defaults. For example:

  ```sh
  make sourcekit SOURCEKIT_CONFIGURATION=Release
  make sourcekit SOURCEKIT_DESTINATION='platform=iOS Simulator,name=iPhone 17e,OS=latest'
  make sourcekit SOURCEKIT_BUILD_ARGS="-derivedDataPath '/path with spaces/Normal DerivedData'"
  make sourcekit SOURCEKIT_ARCH=x86_64
  ```

`SOURCEKIT_ARCH` selects commands already present in the build plan; it does not add an architecture to the build. The default is the host architecture. The default action includes Xcode test targets so references from tests are available, including the explicit calls to the notification delegate callbacks. For an app-only database:

  ```sh
  make sourcekit SOURCEKIT_ACTION=build
  ```

The app-only action excludes test callers and does not satisfy the full reference verifier. The generator CLI still defaults to the app-only action. To forward other ordinary Xcode options without Make's quoting layer, invoke [generate_compile_commands.py](../Scripts/generate_compile_commands.py) directly, specifying the same action as the default Make target:

  ```sh
  uv run --no-project Scripts/generate_compile_commands.py --arch arm64 --action build-for-testing -- \
    -project NotificationManager.xcodeproj -scheme NotificationManager \
    -configuration Debug -destination 'generic/platform=iOS Simulator'
  ```

Do not run concurrent builds against the same DerivedData while refreshing. Different worktrees should use their own normal Xcode build locations.

## Extraction and limits

[generate_compile_commands.py](../Scripts/generate_compile_commands.py) obtains the normal build arena with `xcodebuild -showBuildSettings -json`, requires a successful ordinary build, and reads the last-used build-description ID recorded by Xcode. When Xcode prints a build-description path, it must agree with that record. Selecting the newest cache directory by timestamp would be incorrect when switching back to a cached plan.

The script checks that the build request and compiler working directories belong to this worktree, validates the complete Swift compilation task set against the manifest, selects one architecture, and expands response files and Swift source lists into argument arrays. Paths containing spaces remain individual arguments. It checks the expanded source list against Xcode's authoritative inputs for every selected target before replacing the JSON atomically.

All targets in the selected build plan are retained. If one source belongs to several modules, the database retains each command in deterministic module-name order. SourceKit-LSP currently chooses the first command for the same file/compiler; this format cannot provide interactive scheme, target or architecture switching. Regenerate for a different configuration or architecture. Files excluded from the selected build action have no entry.

This is a Swift-only extractor for the internal 25-field XCBuild task format observed in Xcode 27.2. It rejects unknown formats instead of publishing partial data. Xcode updates may require changes to the decoder or wrapper checks. It supports Darwin Swift response quoting and nested response files, and direct or forwarded source file lists. Missing files, cycles and malformed quoting are errors. It does not execute response-file contents.

The format and selection behavior are grounded in the primary implementations: [Swift Build task serialization](https://github.com/swiftlang/swift-build/blob/main/Sources/SWBTaskExecution/Task.swift), [Swift Build MessagePack](https://github.com/swiftlang/swift-build/blob/main/Sources/SWBUtil/MsgPack.swift), [Swift driver response parsing](https://github.com/swiftlang/swift-driver/blob/main/Sources/SwiftDriver/Driver/Driver.swift), and [SourceKit-LSP compilation database support](https://github.com/swiftlang/sourcekit-lsp/blob/swift-6.4.0-RELEASE/Sources/BuildServerIntegration/JSONCompilationDatabaseBuildServer.swift).

## Verification

  ```sh
  make test-sourcekit
  make verify-sourcekit
  ```

[test_generate_compile_commands.py](../Scripts/Tests/test_generate_compile_commands.py) covers full plans with multiple targets and architectures, shared/generated sources, paths with spaces, nested response files, source-list formats, corrupt or incomplete plans, foreign worktrees, and failed builds or output replacement. [test_verify_sourcekit.py](../Scripts/Tests/test_verify_sourcekit.py) covers missing app index settings or test commands, empty or unrelated references despite successful type resolution, stale reference locations, mismatched index stores, and synchronization before reference lookup.

[verify_sourcekit.py](../Scripts/verify_sourcekit.py) runs through uv and starts the selected `xcrun sourcekit-lsp` with its default workspace discovery. Here xcrun selects the Xcode language server; uv selects the script interpreter. For [NotificationApplicationDelegate.swift](../NotificationManager/App/NotificationApplicationDelegate.swift), it verifies the module name, simulator SDK and target triple, ordinary Products search path, full target source list, and working directory returned by the server. It requires a full diagnostic report without errors, a typed hover, and symbol information identifying the Domain module.

It also requires app and test compiler commands sharing an existing index store, then waits for index ingestion using [workspace synchronization](https://github.com/swiftlang/sourcekit-lsp/blob/swift-6.4.0-RELEASE/Contributor%20Documentation/LSP%20Extensions.md). Two reference requests must return the actual call locations: [install](../NotificationManager/App/NotificationApplicationDelegate.swift#L100) from [AppBootstrapper.swift](../NotificationManager/App/AppBootstrapper.swift#L107), and [userNotificationCenter](../NotificationManager/App/NotificationApplicationDelegate.swift#L276-L285) from [NotificationApplicationDelegateTests.swift](../NotificationManagerTests/NotificationApplicationDelegateTests.swift#L1009-L1013). Declarations, package-only indexes and test-only indexes cannot satisfy these checks. This verifier is specifically for the app's iOS Simulator configuration with test targets included. The compiler-options and synchronization requests are SourceKit-LSP extensions and can change with the toolchain.

Verified on 2026-11-15 with Xcode 27.2 (27B52), Apple Swift 6.4.2 and its bundled SourceKit-LSP:

- 37 generator and verifier regression tests passed using uv-managed Python 3.12.
- The default build-for-testing produced 207 file commands across nine modules, including the three Xcode test targets. This compiled the tests; it did not execute them.
- Enabling project indexing backfilled existing app and widget objects without cleaning. Repeating the default build ran no Swift compilation tasks and produced byte-identical JSON.
- An intentionally unavailable architecture caused extraction to fail while preserving the prior JSON byte for byte.
- A build with an intentionally invalid Swift version failed and likewise preserved the prior JSON byte for byte.
- The app delegate's full diagnostic report contained no errors. Typed hover resolved the Domain type, and symbol information returned USR `s:25NotificationManagerDomain16ReminderSnapshotV`.
- Reference lookup returned the app bootstrapper's call and the test's notification callback call. Successful type resolution alone had previously hidden missing app index units.

The development workflow does not require opening Neovim during generation; direct LSP verification does not establish Neovim UI behavior.
