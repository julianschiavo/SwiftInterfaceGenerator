import Foundation
@testable import SwiftInterfaceGenerator

enum IntegrationTestError: Error, CustomStringConvertible {
    case commandFailed(command: String, stderr: String, status: Int32)

    var description: String {
        switch self {
        case .commandFailed(let command, let stderr, let status):
            return "Command failed (\(status)): \(command)\n\(stderr)"
        }
    }
}

struct CompiledFrameworkFixture {
    let temporaryDirectory: TemporaryDirectory
    let binaryURL: URL
    let targetTriple: String

    var repositoryRootURL: URL {
        temporaryDirectory.url
    }
}

struct IntegrationTestCompiler {
    private static let cachedSDKPath: String = {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["--sdk", "macosx", "--show-sdk-path"]
        process.standardOutput = pipe
        try! process.run()
        process.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }()

    private static let cachedTargetTriple: String = {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["--sdk", "macosx", "swiftc", "-print-target-info"]
        process.standardOutput = pipe
        try! process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!
        struct TargetInfo: Decodable {
            struct Target: Decodable { let triple: String }
            let target: Target
        }
        return try! JSONDecoder().decode(TargetInfo.self, from: Data(output.utf8)).target.triple
    }()

    func compileFramework(
        moduleName: String,
        sources: [String: String]
    ) throws -> CompiledFrameworkFixture {
        let temporaryDirectory = try TemporaryDirectory(prefix: "SwiftInterfaceGeneratorIntegration")
        let sourcesDirectoryURL = temporaryDirectory.url.appendingPathComponent("Sources", isDirectory: true)
        let frameworkDirectoryURL = temporaryDirectory.url
            .appendingPathComponent("\(moduleName).framework", isDirectory: true)
        let binaryURL = frameworkDirectoryURL.appendingPathComponent(moduleName)
        let moduleDirectoryURL = frameworkDirectoryURL
            .appendingPathComponent("Modules", isDirectory: true)
            .appendingPathComponent("\(moduleName).swiftmodule", isDirectory: true)

        try FileManager.default.createDirectory(at: sourcesDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: moduleDirectoryURL, withIntermediateDirectories: true)

        let sourceURLs = try sources.map { name, contents in
            let sourceURL = sourcesDirectoryURL.appendingPathComponent(name)
            try contents.write(to: sourceURL, atomically: true, encoding: .utf8)
            return sourceURL
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }

        let sdkPath = Self.cachedSDKPath
        let targetTriple = Self.cachedTargetTriple
        let moduleOutputURL = moduleDirectoryURL.appendingPathComponent("\(moduleName).swiftmodule")

        _ = try run(
            "/usr/bin/xcrun",
            arguments: [
                "--sdk", "macosx",
                "swiftc",
                "-parse-as-library",
                "-emit-library",
                "-emit-module",
                "-enable-library-evolution",
                "-module-name", moduleName,
                "-sdk", sdkPath,
                "-emit-module-path", moduleOutputURL.path,
                "-o", binaryURL.path,
            ] + sourceURLs.map(\.path)
        )

        return CompiledFrameworkFixture(
            temporaryDirectory: temporaryDirectory,
            binaryURL: binaryURL,
            targetTriple: targetTriple
        )
    }

    func makeGenerator() -> SwiftInterfaceGenerator {
        SwiftInterfaceGenerator(
            commandRunner: SubprocessCommandRunner(),
            compilerVersionProvider: { "Integration Test Swift" }
        )
    }

    private func run(
        _ executable: String,
        arguments: [String]
    ) throws -> (stdout: String, stderr: String) {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw IntegrationTestError.commandFailed(
                command: "\(executable) \(arguments.joined(separator: " "))",
                stderr: stderr,
                status: process.terminationStatus
            )
        }

        return (stdout, stderr)
    }
}

let integrationCompiler = IntegrationTestCompiler()
