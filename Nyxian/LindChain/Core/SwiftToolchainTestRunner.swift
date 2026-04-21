/*
 SPDX-License-Identifier: AGPL-3.0-or-later

 Copyright (C) 2025 - 2026 Kyle-Ye

 This file is part of Nyxian.

 Nyxian is free software: you can redistribute it and/or modify
 it under the terms of the GNU Affero General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Nyxian is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 GNU Affero General Public License for more details.

 You should have received a copy of the GNU Affero General Public License
 along with Nyxian. If not, see <https://www.gnu.org/licenses/>.
*/

import Foundation
import Darwin
import CoreCompiler

@objc class SwiftToolchainTestRunner: NSObject {
    private static func writeLog(_ message: String) {
        let logPath = "\(NSTemporaryDirectory())/nyxian-swift-test.log"
        try? message.write(toFile: logPath, atomically: true, encoding: .utf8)
        NSLog("%@", message)
    }
    
    @objc static func runSynchronously() -> String {
        Bootstrap.shared.bootstrap()
        Bootstrap.shared.waitTillDone()
        
        let fileManager = FileManager.default
        let workDirectory = Bootstrap.shared.bootstrapPath("/Cache/nyxian-swift-test")
        let sourcePath = "\(workDirectory)/main.swift"
        let objectPath = "\(workDirectory)/SwiftProbe.o"
        let executablePath = "\(workDirectory)/SwiftProbe"
        let moduleCachePath = "\(workDirectory)/ModuleCache"
        let sdkPath = Bootstrap.shared.sdkPath
        let resourceDirectory = "\(Bundle.main.bundlePath)/Shared/SwiftToolchain/usr/lib/swift"
        let sdkSwiftLibraryPath = "\(sdkPath)/usr/lib/swift"
        let sdkFrameworkPath = "\(sdkPath)/System/Library/Frameworks"
        let sdkSubFrameworkPath = "\(sdkPath)/System/Library/SubFrameworks"
        
        do {
            try? fileManager.removeItem(atPath: workDirectory)
            try fileManager.createDirectory(atPath: workDirectory, withIntermediateDirectories: true)
            try """
            import Foundation
            import UIKit

            print("hello Nyxian build from \\(UIDevice.current.systemName) \\(UIDevice.current.systemVersion)")
            """.write(toFile: sourcePath, atomically: true, encoding: .utf8)
        } catch {
            let message = "NYXIAN_SWIFT_TEST failed preparing source: \(error.localizedDescription)"
            writeLog(message)
            return message
        }
        
        guard fileManager.fileExists(atPath: sdkPath) else {
            let message = "NYXIAN_SWIFT_TEST missing SDK at \(sdkPath)"
            writeLog(message)
            return message
        }

        guard fileManager.fileExists(atPath: resourceDirectory) else {
            let message = "NYXIAN_SWIFT_TEST missing Swift resource directory at \(resourceDirectory)"
            writeLog(message)
            return message
        }
        
        let compileArguments = [
            "-c",
            "-primary-file",
            sourcePath,
            "-target",
            "arm64e-apple-ios17.0",
            "-Xllvm",
            "-aarch64-use-tbi",
            "-enable-objc-interop",
            "-sdk",
            sdkPath,
            "-resource-dir",
            resourceDirectory,
            "-module-cache-path",
            moduleCachePath,
            "-no-color-diagnostics",
            "-Xcc",
            "-fno-color-diagnostics",
            "-swift-version",
            "5",
            "-module-name",
            "SwiftProbe",
            "-o",
            objectPath
        ]
        
        var output: NSString?
        guard CCKSwiftCompiler.execute(withArguments: compileArguments, output: &output) else {
            let message = "NYXIAN_SWIFT_TEST CoreCompiler Swift compile failed:\n\((output as String?) ?? "")"
            writeLog(message)
            return message
        }

        guard let linkDriver = CCKDriver(arguments: [
            "-target",
            "arm64e-apple-ios17.0",
            "-isysroot",
            sdkPath,
            objectPath,
            "-o",
            executablePath,
            "-framework",
            "Foundation",
            "-framework",
            "UIKit",
            "-F\(sdkFrameworkPath)",
            "-F\(sdkSubFrameworkPath)",
            "-L\(sdkSwiftLibraryPath)",
            "-L\(resourceDirectory)/iphoneos",
            "-rpath",
            "/usr/lib/swift"
        ]) else {
            let message = "NYXIAN_SWIFT_TEST failed to create linker driver."
            writeLog(message)
            return message
        }
        let linkerJobs = linkDriver.generateJobs().filter { $0.type == .linker }
        guard let linkerJob = linkerJobs.first else {
            let message = "NYXIAN_SWIFT_TEST failed to create linker job."
            writeLog(message)
            return message
        }

        var linkDiagnostics: NSArray?
        guard linkerJob.execute(withOutDiagnostics: &linkDiagnostics) else {
            let message = """
            NYXIAN_SWIFT_TEST link failed:
            args:
            \(linkerJob.arguments.joined(separator: "\n"))
            diagnostics:
            \(formatDiagnostics(linkDiagnostics))
            """
            writeLog(message)
            return message
        }

        guard signGeneratedExecutable(at: executablePath) else {
            let message = "NYXIAN_SWIFT_TEST failed signing executable at \(executablePath)"
            writeLog(message)
            return message
        }

        let runOutput = runPatchedExecutable(at: executablePath)
        
        let objectExists = fileManager.fileExists(atPath: objectPath)
        let executableExists = fileManager.fileExists(atPath: executablePath)
        let message = """
        NYXIAN_SWIFT_TEST passed.
        compiler: CoreCompiler Swift frontend
        object: \(objectPath) exists=\(objectExists)
        executable: \(executablePath) exists=\(executableExists)
        sdk swift libs: \(sdkSwiftLibraryPath) exists=\(fileManager.fileExists(atPath: sdkSwiftLibraryPath))
        run exit: \(runOutput.exitCode)
        run stdout:
        \(runOutput.stdout)
        link diagnostics:
        \(linkDiagnostics ?? [])
        diagnostics:
        \((output as String?) ?? "")
        """
        writeLog(message)
        return message
    }

    private static func formatDiagnostics(_ diagnostics: NSArray?) -> String {
        guard let diagnostics else {
            return ""
        }

        return diagnostics.compactMap { diagnostic in
            if let coreDiagnostic = diagnostic as? CCKDiagnostic {
                return coreDiagnostic.message
            }
            return String(describing: diagnostic)
        }.joined(separator: "\n")
    }

    private static func signGeneratedExecutable(at executablePath: String) -> Bool {
        let entitlements = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>get-task-allow</key>
            <true/>
        </dict>
        </plist>
        """
        let entitlementData = entitlements.data(using: .utf8) ?? Data()
        let bundleID = Bundle.main.bundleIdentifier ?? "com.cr4zy.nyxian.swiftprobe"
        guard ZSigner.adhocSignMachO(atPath: executablePath, bundleId: bundleID, entitlementData: entitlementData) else {
            return false
        }
        let userApplicationEntitlements = PEEntitlement(rawValue:
            (1 << 0) | (1 << 3) | (1 << 5) | (1 << 7) | (1 << 14) | (1 << 18) | (1 << 19)
        )
        return macho_after_sign(executablePath, userApplicationEntitlements) == 0
    }

    private static func runPatchedExecutable(at executablePath: String) -> (exitCode: Int, stdout: String) {
        let outputPipe = Pipe()
        let inputPipe = Pipe()
        let mapObject = FDMapObject.emptyMap()
        mapObject?.appendFileDescriptor(inputPipe.fileHandleForReading.fileDescriptor, withMappingToLoc: STDIN_FILENO)
        mapObject?.appendFileDescriptor(outputPipe.fileHandleForWriting.fileDescriptor, withMappingToLoc: STDOUT_FILENO)
        mapObject?.appendFileDescriptor(outputPipe.fileHandleForWriting.fileDescriptor, withMappingToLoc: STDERR_FILENO)

        let workingDirectory = (executablePath as NSString).deletingLastPathComponent
        let items: [String: Any] = [
            "PEExecutablePath": executablePath,
            "PEArguments": [executablePath],
            "PEEnvironment": [
                "HOME": workingDirectory,
                "CFFIXED_USER_HOME": workingDirectory,
                "TMPDIR": workingDirectory
            ],
            "PEWorkingDirectory": workingDirectory,
            "PEMapObject": mapObject as Any
        ]

        let pid = PEProcessManager.shared().spawnProcess(withItems: items, withKernelSurfaceProcess: NXKernelProcessForSwift())
        guard pid >= 0,
              let process = PEProcessManager.shared().process(forProcessIdentifier: pid) else {
            return (-1, "PEProcessManager failed to spawn \(executablePath)")
        }

        let semaphore = DispatchSemaphore(value: 0)
        process.exitingCallback = {
            semaphore.signal()
        }

        let didExit = semaphore.wait(timeout: .now() + 15) == .success
        if !didExit {
            process.terminate()
        }

        outputPipe.fileHandleForWriting.closeFile()
        inputPipe.fileHandleForWriting.closeFile()
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: data, encoding: .utf8) ?? ""
        return (didExit ? 0 : -1, stdout)
    }
}
