# Swift Support Plan

## Current Proof

Nyxian now has a narrow Swift proof-of-concept path:

- Swift project config keys:
  - `LDESwiftCompilerPath`
  - `LDESwiftCompilerFlags`
  - `LDESwiftModuleName`
  - `LDESwiftBridgingHeader`
- Builder support for one `.swift` file:
  - compile Swift source to one object file
  - emit a `.swiftmodule`
  - pass the object into the existing linker flow
- A Swift utility template with one `Main.swift`.
- A `NYXIAN_SWIFT_TEST=1` launch mode that skips normal UI and tests the embedded Swift frontend path on device.
- `LLVM-On-iOS/CoreCompiler` embeds Swift frontend support and exposes it through `CCKSwiftCompiler`.
- The device proof compiles a tiny stdlib-free Swift source into an object file through CoreCompiler.

## Device Test Harness

When `NYXIAN_SWIFT_TEST=1` is present in the app environment, Nyxian:

1. Runs bootstrap and waits for the SDK/toolchain files to be available.
2. Writes a tiny Swift source file into a temp folder.
3. Calls `CCKSwiftCompiler.execute(withArguments:output:)`.
4. Uses `swift::performFrontend` in-process instead of spawning `swiftc`.
5. Writes compiler caches and the object output under a writable temp directory.
6. Shows the result on screen and logs to `NSTemporaryDirectory()/nyxian-swift-test.log`.

Status as of 2026-04-21:

- Passing on the connected iPhone with `NYXIAN_SWIFT_TEST=1`.
- Verified output: `SwiftProbe.o exists=true`, diagnostics empty.
- The proof source uses `-parse-stdlib` and avoids `import Foundation`.
- Full stdlib/Foundation imports are not done yet because the bundled Swift resource tree lacks matching iOS Swift `.swiftmodule` files.

## LLVM-On-iOS Work

`LLVM-On-iOS` now has a first CoreCompiler-based Swift frontend integration:

- builds against Swift 6.3 sources/libs from `~/SwiftProject`
- links Swift frontend/static compiler libraries into `CoreCompiler.framework/CoreCompiler`
- bundles `lib_CompilerSwift*.dylib` next to the framework binary
- exposes a C API and Objective-C wrapper:
  - `CCSwiftCompilerExecute`
  - `CCKSwiftCompiler.executeWithArguments:output:`

Nyxian signs the nested Swift compiler dylibs after Xcode embeds `CoreCompiler.framework`.

Swift support no longer tries to run `swiftc` on iOS. iOS disallows that subprocess model, and it does not match Nyxian/CoreCompiler architecture.

The toolchain should be staged in one of these layouts:

```text
Toolchains/Swift/usr/bin/swiftc
Toolchains/Swift/usr/bin/swift-frontend
Toolchains/Swift/usr/lib/swift/...
```

or bundled in the app for test builds:

```text
Shared/SwiftToolchain/usr/bin/swiftc
Shared/SwiftToolchain/usr/bin/swift-frontend
Shared/SwiftToolchain/usr/lib/swift/...
```

## Implementation Phases

1. Create a dedicated branch in `LLVM-On-iOS`.
2. Add Apple Swift compiler sources or a pinned Swift source submodule.
3. Add a host-build stage for any Swift build tools needed during cross-compilation.
4. Add an iOS arm64 cross-build stage for `swiftc`/`swift-frontend`.
5. Install the output into `SwiftToolchain-iphoneos`.
6. Add a packaging target that emits `SwiftToolchain.zip`.
7. Copy or unzip that toolchain into Nyxian bootstrap under `Toolchains/Swift`.
8. Run `NYXIAN_SWIFT_TEST=1` on a real device.
9. Expand the Nyxian builder from one Swift file to module-level Swift compilation.
10. Add diagnostics parsing, bridging header support, and Swift runtime embedding/signing.

## Updated Implementation Status

1. Dedicated branches: done.
2. Pinned Swift 6.3 source/build path: done locally through `~/SwiftProject`.
3. iOS-native Swift frontend libraries: done enough for CoreCompiler proof.
4. In-process CoreCompiler Swift API: done.
5. Nyxian single-file Swift object proof: done.
6. Device deployment with `NYXIAN_SWIFT_TEST=1`: passing for stdlib-free Swift.
7. Foundation/std/SKD module import support: next.
8. Multi-file Swift module compilation: pending.
9. Link/run Swift code in produced apps: pending.
10. Diagnostics and project UI polish: pending.

## Risks

- Swift compiler is not part of LLVM/Clang; it requires Swift compiler sources and a compatible build graph.
- Cross-building Swift usually needs host tools first, so the build cannot be a simple `LLVM_ENABLE_PROJECTS` extension.
- iOS must use CoreCompiler/in-process APIs, not `swiftc` or subprocess execution.
- Resource-dir and SDK/module compatibility must match the Swift compiler version.
- Runtime libraries may need packaging into built apps depending on target iOS version and symbols used.
- Foundation support requires matching Swift stdlib modules and Clang/Foundation module cache paths that are writable in the app sandbox.
