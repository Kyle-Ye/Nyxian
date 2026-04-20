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

@objc class SwiftToolchainTestRunner: NSObject {
    private static func shellOutput(_ arguments: [String], environment: [String] = []) -> (Int32, String) {
        var output: NSString?
        let status = shell(arguments, 0, environment, &output)
        return (status, (output as String?) ?? "")
    }
    
    private static func swiftCompilerCandidates() -> [String] {
        let environment = ProcessInfo.processInfo.environment
        return [
            environment["NYXIAN_SWIFT_COMPILER"],
            "\(Bootstrap.shared.bootstrapPath("/"))/Toolchains/Swift/usr/bin/swiftc",
            "\(Bundle.main.bundlePath)/Shared/SwiftToolchain/usr/bin/swiftc"
        ].compactMap { $0 }
    }

    private static func installBundledSwiftToolchainIfNeeded() throws {
        let fileManager = FileManager.default
        let bundledToolchain = "\(Bundle.main.bundlePath)/Shared/SwiftToolchain"
        let installedToolchain = Bootstrap.shared.bootstrapPath("/Toolchains/Swift")
        let installedSwiftc = "\(installedToolchain)/usr/bin/swiftc"

        guard fileManager.fileExists(atPath: "\(bundledToolchain)/usr/bin/swiftc") else {
            if fileManager.fileExists(atPath: installedSwiftc) {
                try fixExecutablePermissions(in: installedToolchain)
            }
            return
        }

        if fileManager.fileExists(atPath: installedToolchain) {
            try fileManager.removeItem(atPath: installedToolchain)
        }
        try fileManager.createDirectory(
            atPath: (installedToolchain as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        try fileManager.copyItem(atPath: bundledToolchain, toPath: installedToolchain)
        try fixExecutablePermissions(in: installedToolchain)
    }

    private static func fixExecutablePermissions(in toolchainPath: String) throws {
        let binPath = "\(toolchainPath)/usr/bin"
        let fileManager = FileManager.default

        try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: toolchainPath)
        try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: "\(toolchainPath)/usr")
        try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binPath)

        guard let enumerator = fileManager.enumerator(atPath: binPath) else {
            return
        }

        for case let relativePath as String in enumerator {
            let path = "\(binPath)/\(relativePath)"
            var isDirectory = ObjCBool(false)
            guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
                continue
            }
            try? fileManager.setAttributes([.posixPermissions: isDirectory.boolValue ? 0o755 : 0o755], ofItemAtPath: path)
        }
    }

    private static func existingSwiftCompilerPath() -> String? {
        let fileManager = FileManager.default
        let candidates = swiftCompilerCandidates()
        return candidates.first {
            var isDirectory = ObjCBool(false)
            return fileManager.fileExists(atPath: $0, isDirectory: &isDirectory) && !isDirectory.boolValue
        }
    }

    private static func candidateDiagnostics() -> String {
        let fileManager = FileManager.default
        return swiftCompilerCandidates().map { path in
            var isDirectory = ObjCBool(false)
            let exists = fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
            let executable = fileManager.isExecutableFile(atPath: path)
            let readable = fileManager.isReadableFile(atPath: path)
            let accessExecutable = access(path, X_OK) == 0
            let attributes = (try? fileManager.attributesOfItem(atPath: path)) ?? [:]
            let permissions = (attributes[.posixPermissions] as? NSNumber)?.uint16Value
            let size = attributes[.size] as? NSNumber
            let permissionsText = permissions.map { String(format: "%04o", $0) } ?? "n/a"
            let sizeText = size.map { "\($0)" } ?? "n/a"
            return "- \(path)\n  exists=\(exists) directory=\(isDirectory.boolValue) readable=\(readable) executable=\(executable) accessX=\(accessExecutable) mode=\(permissionsText) size=\(sizeText)"
        }.joined(separator: "\n")
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

        do {
            try installBundledSwiftToolchainIfNeeded()
        } catch {
            let message = "NYXIAN_SWIFT_TEST failed installing bundled Swift toolchain: \(error.localizedDescription)"
            writeLog(message)
            return message
        }
        
        guard let swiftcPath = existingSwiftCompilerPath() else {
            let message = """
            NYXIAN_SWIFT_TEST missing iOS-native swiftc.
            Checked:
            \(candidateDiagnostics())
            Override with NYXIAN_SWIFT_COMPILER.
            """
            writeLog(message)
            return message
        }

        _ = chmod(swiftcPath, 0o755)
        
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
