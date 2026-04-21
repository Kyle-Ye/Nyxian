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
        let workDirectory = "\(NSTemporaryDirectory())/nyxian-swift-test"
        let sourcePath = "\(workDirectory)/main.swift"
        let objectPath = "\(workDirectory)/SwiftProbe.o"
        let moduleCachePath = "\(workDirectory)/ModuleCache"
        let sdkPath = Bootstrap.shared.sdkPath
        let resourceDirectory = "\(Bundle.main.bundlePath)/Shared/SwiftToolchain/usr/lib/swift"
        
        do {
            try? fileManager.removeItem(atPath: workDirectory)
            try fileManager.createDirectory(atPath: workDirectory, withIntermediateDirectories: true)
            try """
            public func nyxian_swift_device_proof() {}
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
            "arm64-apple-ios17.0",
            "-Xllvm",
            "-aarch64-use-tbi",
            "-enable-objc-interop",
            "-sdk",
            sdkPath,
            "-resource-dir",
            resourceDirectory,
            "-module-cache-path",
            moduleCachePath,
            "-parse-stdlib",
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
        
        let objectExists = fileManager.fileExists(atPath: objectPath)
        let message = """
        NYXIAN_SWIFT_TEST passed.
        compiler: CoreCompiler Swift frontend
        object: \(objectPath) exists=\(objectExists)
        diagnostics:
        \((output as String?) ?? "")
        """
        writeLog(message)
        return message
    }
}
