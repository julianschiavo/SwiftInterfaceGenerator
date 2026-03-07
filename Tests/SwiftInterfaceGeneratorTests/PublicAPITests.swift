import Foundation
import Testing
@testable import SwiftInterfaceGenerator

@Test
func generateWritesInterfaceAndLogsCommandInputs() async throws {
    let temporaryDirectory = try TemporaryDirectory(prefix: "SwiftInterfaceGeneratorPublic")
    let frameworkURL = temporaryDirectory.url
        .appendingPathComponent("Fixture.framework", isDirectory: true)
        .appendingPathComponent("Fixture")
    let rawSymbols = "raw nm output"
    let demangledSymbols = [
        "0000000000000000 T nominal type descriptor for Fixture.State",
        "0000000000000001 T enum case for Fixture.State.idle(Fixture.State) -> Fixture.State",
        "0000000000000002 T enum case for Fixture.State.named(Fixture.State) -> (Swift.String) -> Fixture.State",
    ].joined(separator: "\n")
    let commandRunner = MockCommandRunner(
        responses: [
            .success(CommandResult(stdout: rawSymbols, stderr: "")),
            .success(CommandResult(stdout: demangledSymbols, stderr: "")),
        ]
    )
    let generator = SwiftInterfaceGenerator(
        commandRunner: commandRunner,
        compilerVersionProvider: { "Test Swift" }
    )

    let generatedInterface = try await generator.generate(
        frameworkBinaryURL: frameworkURL,
        repositoryRootURL: temporaryDirectory.url,
        targetTriple: "arm64-apple-macosx15.0"
    )

    let interfaceContents = try String(contentsOf: generatedInterface.interfaceURL, encoding: .utf8)

    #expect(
        normalizedInterface(interfaceContents)
            == normalizedInterface(
                """
            // swift-interface-format-version: 1.0
            // swift-compiler-version: Test Swift
            // swift-module-flags: -target arm64-apple-macosx15.0 -enable-library-evolution -module-name Fixture
            import Swift

            public enum State {
              case idle
              case named(Swift.String)
            }
            """
            )
    )
    #expect(
        generatedInterface.log
            == "Generated \(generatedInterface.interfaceURL.path) from \(frameworkURL.standardizedFileURL.path)"
    )
    #expect(
        await commandRunner.recordedInvocations()
            == [
                .init(
                    executable: "nm",
                    arguments: ["-gU", frameworkURL.standardizedFileURL.path],
                    stdin: nil
                ),
                .init(
                    executable: "swift-demangle",
                    arguments: ["--compact"],
                    stdin: rawSymbols
                ),
            ]
    )
}

@Test
func generateReplacesExistingModuleDirectory() async throws {
    let temporaryDirectory = try TemporaryDirectory(prefix: "SwiftInterfaceGeneratorStale")
    let frameworkURL = temporaryDirectory.url
        .appendingPathComponent("Fixture.framework", isDirectory: true)
        .appendingPathComponent("Fixture")
    let moduleDirectoryURL = temporaryDirectory.url
        .appendingPathComponent("tmp_module", isDirectory: true)
        .appendingPathComponent("Fixture.swiftmodule", isDirectory: true)
    let staleFileURL = moduleDirectoryURL.appendingPathComponent("stale.txt")
    try FileManager.default.createDirectory(at: moduleDirectoryURL, withIntermediateDirectories: true)
    try "stale".write(to: staleFileURL, atomically: true, encoding: .utf8)

    let commandRunner = MockCommandRunner(
        responses: [
            .success(CommandResult(stdout: "", stderr: "")),
            .success(CommandResult(stdout: "nominal type descriptor for Fixture.Token", stderr: "")),
        ]
    )
    let generator = SwiftInterfaceGenerator(
        commandRunner: commandRunner,
        compilerVersionProvider: { "Test Swift" }
    )

    let generatedInterface = try await generator.generate(
        frameworkBinaryURL: frameworkURL,
        repositoryRootURL: temporaryDirectory.url,
        targetTriple: "arm64-apple-macosx15.0"
    )

    #expect(!FileManager.default.fileExists(atPath: staleFileURL.path))
    #expect(FileManager.default.fileExists(atPath: generatedInterface.interfaceURL.path))
}

@Test
func loadDemangledSymbolsStripsAddressMetadataAndBlankLines() async throws {
    let commandRunner = MockCommandRunner(
        responses: [
            .success(CommandResult(stdout: "raw", stderr: "")),
            .success(
                CommandResult(
                    stdout: """
                    0000000000000000 T nominal type descriptor for Fixture.Flag

                    0000000000000001 T enum case for Fixture.Flag.on(Fixture.Flag) -> Fixture.Flag
                    plain line
                    """,
                    stderr: ""
                )
            ),
        ]
    )
    let generator = SwiftInterfaceGenerator(
        commandRunner: commandRunner,
        compilerVersionProvider: { "Test Swift" }
    )

    let demangledSymbols = try await generator.loadDemangledSymbols(
        frameworkBinaryURL: URL(fileURLWithPath: "/tmp/Fixture.framework/Fixture")
    )

    #expect(
        demangledSymbols
            == [
                "nominal type descriptor for Fixture.Flag",
                "enum case for Fixture.Flag.on(Fixture.Flag) -> Fixture.Flag",
                "plain line",
            ]
    )
}

@Test
func generateUsesDetectedCompilerVersionWhenNoOverrideIsProvided() async throws {
    let commandRunner = MockCommandRunner(
        responses: [
            .success(CommandResult(stdout: "raw", stderr: "")),
            .success(CommandResult(stdout: "nominal type descriptor for Fixture.Token", stderr: "")),
            .success(CommandResult(stdout: "Apple Swift version 6.2.4 effective-5.10\nTarget: arm64-apple-macosx14.0", stderr: "")),
        ]
    )
    let generator = SwiftInterfaceGenerator(commandRunner: commandRunner)

    let temporaryDirectory = try TemporaryDirectory(prefix: "SwiftInterfaceGeneratorVersion")
    let frameworkURL = temporaryDirectory.url
        .appendingPathComponent("Fixture.framework", isDirectory: true)
        .appendingPathComponent("Fixture")
    let generatedInterface = try await generator.generate(
        frameworkBinaryURL: frameworkURL,
        repositoryRootURL: temporaryDirectory.url,
        targetTriple: "arm64-apple-macosx15.0"
    )
    let interfaceContents = try String(contentsOf: generatedInterface.interfaceURL, encoding: .utf8)

    #expect(
        normalizedInterface(interfaceContents).contains("// swift-compiler-version: Apple Swift version 6.2.4 effective-5.10")
    )
    #expect(
        await commandRunner.recordedInvocations()
            == [
                .init(executable: "nm", arguments: ["-gU", frameworkURL.standardizedFileURL.path], stdin: nil),
                .init(executable: "swift-demangle", arguments: ["--compact"], stdin: "raw"),
                .init(executable: "swiftc", arguments: ["-version"], stdin: nil),
            ]
    )
}

@Test
func generatePropagatesCommandFailures() async throws {
    let commandRunner = MockCommandRunner(
        responses: [
            .failure(
                .commandFailed(
                    command: "nm -gU /tmp/Fixture.framework/Fixture",
                    status: "exited(1)",
                    stdout: "",
                    stderr: "boom"
                )
            ),
        ]
    )
    let generator = SwiftInterfaceGenerator(
        commandRunner: commandRunner,
        compilerVersionProvider: { "Test Swift" }
    )

    do {
        _ = try await generator.generate(
            frameworkBinaryURL: URL(fileURLWithPath: "/tmp/Fixture.framework/Fixture"),
            repositoryRootURL: URL(fileURLWithPath: "/tmp", isDirectory: true),
            targetTriple: "arm64-apple-macosx15.0"
        )
        #expect(Bool(false))
    } catch let error as SwiftInterfaceGeneratorError {
        guard case .commandFailed(let command, let status, _, let stderr) = error else {
            #expect(Bool(false))
            return
        }

        #expect(command == "nm -gU /tmp/Fixture.framework/Fixture")
        #expect(status == "exited(1)")
        #expect(stderr == "boom")
    }
}
