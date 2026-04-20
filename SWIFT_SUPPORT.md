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
- A `NYXIAN_SWIFT_TEST=1` launch mode that skips normal UI and tests the iOS-native Swift compiler path on device.

The harness currently reports `NYXIAN_SWIFT_TEST missing iOS-native swiftc` because there is no `swiftc` bundled in Nyxian or produced by `LLVM-On-iOS`.

## Device Test Harness

When `NYXIAN_SWIFT_TEST=1` is present in the app environment, Nyxian:

1. Runs bootstrap and waits for the SDK/toolchain files to be available.
2. Writes a tiny Swift source file into a temp folder.
3. Searches for `swiftc` in:
   - `NYXIAN_SWIFT_COMPILER`
   - `$(BSROOT)/Toolchains/Swift/usr/bin/swiftc`
   - `Bundle/Shared/SwiftToolchain/usr/bin/swiftc`
   - `Bundle/SwiftToolchain/usr/bin/swiftc`
   - `Bundle/swiftc`
4. Runs `swiftc -version`.
5. Runs `swiftc` with `-emit-object` and `-emit-module`.
6. Shows the result on screen and logs to `NSTemporaryDirectory()/nyxian-swift-test.log`.

## LLVM-On-iOS Work

`LLVM-On-iOS` currently builds LLVM/Clang/LLD/CoreCompiler, not Swift. Its Makefile enables:

```text
LLVM_ENABLE_PROJECTS="clang;lld"
```

Swift support needs a separate iOS-native Swift compiler toolchain. The first target should be the smallest useful compiler bundle:

- `swiftc`
- `swift-frontend`
- Swift resource directory
- Swift standard library/module files needed for iOS compilation
- Any runtime libraries required by compiled apps

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

## Risks

- Swift compiler is not part of LLVM/Clang; it requires Swift compiler sources and a compatible build graph.
- Cross-building Swift usually needs host tools first, so the build cannot be a simple `LLVM_ENABLE_PROJECTS` extension.
- iOS execution of compiler binaries may require signing/entitlements and writable temp/cache paths.
- Resource-dir and SDK/module compatibility must match the Swift compiler version.
- Runtime libraries may need packaging into built apps depending on target iOS version and symbols used.
