/*
 SPDX-License-Identifier: AGPL-3.0-or-later

 Copyright (C) 2025 - 2026 cr4zyengineer

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

@objc class SwiftToolchainTestRunner: NSObject {
    private static func shellOutput(_ arguments: [String], environment: [String] = []) -> (Int32, String) {
        var output: NSString?
        let status = shell(arguments, 0, environment, &output)
        return (status, (output as String?) ?? "")
    }
    
    private static func existingSwiftCompilerPath() -> String? {
        let environment = ProcessInfo.processInfo.environment
        let candidates = [
            environment["NYXIAN_SWIFT_COMPILER"],
            "\(Bootstrap.shared.bootstrapPath("/"))/Toolchains/Swift/usr/bin/swiftc",
            "\(Bundle.main.bundlePath)/Shared/SwiftToolchain/usr/bin/swiftc",
            "\(Bundle.main.bundlePath)/SwiftToolchain/usr/bin/swiftc",
            "\(Bundle.main.bundlePath)/swiftc"
        ].compactMap { $0 }
        
        return candidates.first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }
    
    private static func writeLog(_ message: String) {
        let logPath = "\(NSTemporaryDirectory())/nyxian-swift-test.log"
        try? message.write(toFile: logPath, atomically: true, encoding: .utf8)
        NSLog("%@", message)
    }
    
    @objc static func runSynchronously() -> String {
        Bootstrap.shared.bootstrap()
        Bootstrap.shared.waitTillDone()
        
        let fileManager = FileManager.default
        let workDirectory = "\(NSTemporaryDirectory())/nyxian-swift-test"
        let sourcePath = "\(workDirectory)/main.swift"
        let objectPath = "\(workDirectory)/SwiftProbe.o"
        let modulePath = "\(workDirectory)/SwiftProbe.swiftmodule"
        let sdkPath = Bootstrap.shared.sdkPath
        let bootstrapRoot = Bootstrap.shared.bootstrapPath("/")
        
        do {
            try? fileManager.removeItem(atPath: workDirectory)
            try fileManager.createDirectory(atPath: workDirectory, withIntermediateDirectories: true)
            try """
            import Foundation

            print("Nyxian Swift device proof")
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
        
        guard let swiftcPath = existingSwiftCompilerPath() else {
            let message = """
            NYXIAN_SWIFT_TEST missing iOS-native swiftc.
            Checked:
            - \(bootstrapRoot)/Toolchains/Swift/usr/bin/swiftc
            - \(Bundle.main.bundlePath)/Shared/SwiftToolchain/usr/bin/swiftc
            - \(Bundle.main.bundlePath)/SwiftToolchain/usr/bin/swiftc
            - \(Bundle.main.bundlePath)/swiftc
            Override with NYXIAN_SWIFT_COMPILER.
            """
            writeLog(message)
            return message
        }
        
        let environment = [
            "SDKROOT=\(sdkPath)",
            "BSROOT=\(bootstrapRoot)",
            "CACHEROOT=\(workDirectory)",
            "SRCROOT=\(workDirectory)",
            "HOME=\(NSHomeDirectory())",
            "TMPDIR=\(NSTemporaryDirectory())"
        ]
        
        let versionResult = shellOutput([swiftcPath, "-version"], environment: environment)
        guard versionResult.0 == 0 else {
            let message = "NYXIAN_SWIFT_TEST swiftc -version failed (\(versionResult.0)):\n\(versionResult.1)"
            writeLog(message)
            return message
        }
        
        let compileArguments = [
            swiftcPath,
            sourcePath,
            "-target",
            "arm64-apple-ios17.0",
            "-sdk",
            sdkPath,
            "-swift-version",
            "5",
            "-module-name",
            "SwiftProbe",
            "-emit-object",
            "-emit-module",
            "-emit-module-path",
            modulePath,
            "-o",
            objectPath
        ]
        
        let compileResult = shellOutput(compileArguments, environment: environment)
        guard compileResult.0 == 0 else {
            let message = "NYXIAN_SWIFT_TEST compile failed (\(compileResult.0)):\n\(compileResult.1)"
            writeLog(message)
            return message
        }
        
        let objectExists = fileManager.fileExists(atPath: objectPath)
        let moduleExists = fileManager.fileExists(atPath: modulePath)
        let message = """
        NYXIAN_SWIFT_TEST passed.
        swiftc: \(swiftcPath)
        version:
        \(versionResult.1)
        object: \(objectPath) exists=\(objectExists)
        module: \(modulePath) exists=\(moduleExists)
        output:
        \(compileResult.1)
        """
        writeLog(message)
        return message
    }
}
