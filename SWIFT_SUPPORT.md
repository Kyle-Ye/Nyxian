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
- A Swift utility template with one `main.swift`.
- A `NYXIAN_SWIFT_TEST=1` launch mode that skips normal UI and tests the embedded Swift frontend path on device.
- `LLVM-On-iOS/CoreCompiler` embeds Swift frontend support and exposes it through `CCKSwiftCompiler`.
- The device proof compiles a tiny Swift source into an object file through CoreCompiler.

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
- The stdlib-free proof passed with `-parse-stdlib`.
- A follow-up probe also passed with `import Foundation` by bundling Xcode's iPhoneOS prebuilt `Swift.swiftmodule` and `Foundation.swiftmodule`, then targeting `arm64e-apple-ios17.0`.
- The Foundation route is still experimental because Xcode module resources are version-specific and increase app signing/install work.

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
7. Foundation/stdlib/SDK module import proof: passing experimentally with Xcode iPhoneOS prebuilt modules.
8. Swift executable proof with `main.swift`, `Foundation`, and `UIKit`: done.
9. Real Swift utility project build/run in Nyxian: done with project `BB`.
10. Multi-file Swift module compilation: pending.
11. SwiftUI app lifecycle template: next.
12. Link/run Swift code in produced apps: pending.
13. Diagnostics and project UI polish: pending.

## 2026-04-21 Findings

- Running `swiftc` or `swift-frontend` as an iOS subprocess is not viable. The Swift compiler path must stay inside CoreCompiler and be invoked through Swift compiler APIs.
- `LCUtils.signMachO(at:)` is not suitable for generated proof executables without the user certificate password path; it crashed in zsign password handling. The test harness now uses ad-hoc Mach-O signing plus `macho_after_sign`.
- A Swift executable cannot be loaded with `dlopen` because it is `MH_EXECUTE`. It needs to be launched through Nyxian's process environment.
- Swift cannot import the `kernel_proc_` macro directly because it expands through structure access. A tiny C bridge helper exposes that value to Swift for PEProcess launching.
- The generated executable must be created under a PE-readable/bootstrap path, not an arbitrary temporary path.
- The real Swift project builder is still behind the device proof path. It currently emits duplicate/default Swift flags and inherits C/Kate linker defaults that are wrong for Swift, including `-use-ld=lld`, `-platform_version`, and `-lclang_rt.ios`.
- For real Swift projects, the builder needs the same proven pieces as the harness: `arm64e-apple-ios...`, SDK framework search paths, SDK Swift library path, bundled Swift resource path, and an executable-oriented link path.
- `BB`, a newly created Swift utility project, now builds and runs inside Nyxian with `main.swift`, `Foundation`, and `UIKit`.
- Swift-only linker job generation needed a placeholder object path before `CCKDriver.generateJobs()`. Without it, the linker job could omit the Swift object because `compileSwift()` had not produced it yet, causing `undefined symbol: main`.
- New Swift projects use lowercase `main.swift`; existing single-file projects with different casing are normalized through a cache-side `main.swift` copy during compilation.

## Foundation Support Options

1. Bundle Xcode's iPhoneOS prebuilt modules.
   - Copy `usr/lib/swift/iphoneos/prebuilt-modules/<sdk-version>` into Nyxian's Swift resource dir.
   - Compile device Swift as `arm64e-apple-ios...` so the frontend can load the available `.swiftmodule` files instead of SDK `.swiftinterface` files.
   - This is the fastest working path, but it is Xcode-version-specific and currently increases codesign/install time.
2. Bundle only the dependency closure needed by common imports.
   - Start with `Swift`, `Foundation`, `Darwin`, `CoreFoundation`, `ObjectiveC`, `_Concurrency`, and discovered transitive modules.
   - This should preserve the working behavior while reducing bundle size and codesign cost.
   - The current `import Foundation` probe passes with only `Swift.swiftmodule` and `Foundation.swiftmodule` from Xcode's `iphoneos/prebuilt-modules/26.0`.
3. Package Swift modules as an archive and unpack after install.
   - Store a zip/tar payload as one app resource and extract into `Documents/Toolchains/Swift` during bootstrap.
   - This reduces app-bundle codesign overhead because thousands of module files are not individually sealed in the app signature.
4. Build matching iOS Swift modules from the same Swift source revision.
   - This is cleaner architecturally but significantly more work because stdlib/overlay/Foundation support needs the Swift build graph, SDK overlays, and runtime packaging aligned.
5. Use SDK `.swiftinterface` files directly.
   - This is not preferred. The device failed when the compiler tried the SDK interface because the SDK interface version did not match the embedded Swift compiler build.

## Risks

- Swift compiler is not part of LLVM/Clang; it requires Swift compiler sources and a compatible build graph.
- Cross-building Swift usually needs host tools first, so the build cannot be a simple `LLVM_ENABLE_PROJECTS` extension.
- iOS must use CoreCompiler/in-process APIs, not `swiftc` or subprocess execution.
- Resource-dir and SDK/module compatibility must match the Swift compiler version.
- Runtime libraries may need packaging into built apps depending on target iOS version and symbols used.
- Foundation support requires matching Swift stdlib modules and Clang/Foundation module cache paths that are writable in the app sandbox.
