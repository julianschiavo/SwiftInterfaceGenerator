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

@Test
func generateInfersModuleNameFromDemangledSymbolsWhenBinaryNameDiffers() async throws {
    let temporaryDirectory = try TemporaryDirectory(prefix: "SwiftInterfaceGeneratorTBD")
    let frameworkURL = temporaryDirectory.url
        .appendingPathComponent("SwiftUICore.framework", isDirectory: true)
        .appendingPathComponent("SwiftUICore.tbd")
    let commandRunner = MockCommandRunner(
        responses: [
            .success(CommandResult(stdout: "raw nm output", stderr: "")),
            .success(
                CommandResult(
                    stdout: [
                        "nominal type descriptor for SwiftUI.EdgeInsets",
                        "property descriptor for SwiftUI.EdgeInsets.top : Swift.Int",
                    ].joined(separator: "\n"),
                    stderr: ""
                )
            ),
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

    #expect(generatedInterface.interfaceURL.path.contains("/SwiftUI.swiftmodule/"))
    #expect(
        normalizedInterface(interfaceContents)
            == normalizedInterface(
                """
            // swift-interface-format-version: 1.0
            // swift-compiler-version: Test Swift
            // swift-module-flags: -target arm64-apple-macosx15.0 -enable-library-evolution -module-name SwiftUI
            import Swift

            public struct EdgeInsets {
              public var top: Swift.Int { get }
            }
            """
            )
    )
}

@Test
func generateRecoversProtocolExtensionOpaquePropertyConstraintsForTBDInputs() async throws {
    let temporaryDirectory = try TemporaryDirectory(prefix: "SwiftInterfaceGeneratorOpaqueTBD")
    let frameworkURL = temporaryDirectory.url
        .appendingPathComponent("Fixture.framework", isDirectory: true)
        .appendingPathComponent("Fixture.tbd")
    try FileManager.default.createDirectory(
        at: frameworkURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try """
        --- !tapi-tbd
        tbd-version: 5
        targets: [ arm64-macos ]
        install-name: /System/Library/Frameworks/Fixture.framework/Fixture
        exports:
          - targets: [ arm64-macos ]
            symbols: [ ]
        ...
        """
        .write(to: frameworkURL, atomically: true, encoding: .utf8)

    let commandRunner = MockCommandRunner(
        responses: [
            .success(CommandResult(stdout: "raw nm output", stderr: "")),
            .success(
                CommandResult(
                    stdout: [
                        "protocol descriptor for Fixture.Marker",
                        "protocol descriptor for Fixture.ViewLike",
                        "associated type descriptor for Fixture.ViewLike.Body",
                        "associated conformance descriptor for Fixture.ViewLike.Fixture.ViewLike.Body: Fixture.Marker",
                        "method descriptor for Fixture.ViewLike.body.getter : A.Body",
                        "protocol descriptor for Fixture.StyleableView",
                        "base conformance descriptor for Fixture.StyleableView: Fixture.ViewLike",
                        "property descriptor for (extension in Fixture):Fixture.StyleableView.body : some",
                        "(extension in Fixture):Fixture.StyleableView.body.getter : some",
                    ].joined(separator: "\n"),
                    stderr: ""
                )
            ),
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
    let normalized = normalizedInterface(interfaceContents)

    #expect(normalized.contains("public protocol ViewLike {"))
    #expect(normalized.contains("associatedtype Body: Marker"))
    #expect(normalized.contains("extension StyleableView {"))
    #expect(normalized.contains("public var body: some Marker { get }"))
    #expect(!normalized.contains("public var body: some { get }"))
}

@Test
func generateValidatesDiscoveredExternalModules() async throws {
    let temporaryDirectory = try TemporaryDirectory(prefix: "SwiftInterfaceGeneratorImports")
    let frameworkURL = temporaryDirectory.url
        .appendingPathComponent("Fixture.framework", isDirectory: true)
        .appendingPathComponent("Fixture")
    let rawSymbols = "raw nm output"
    let demangledSymbols = [
        "nominal type descriptor for Fixture.Manager",
        "property descriptor for Fixture.Manager.createdAt : Foundation.Date",
    ].joined(separator: "\n")
    let commandRunner = MockCommandRunner(
        responses: [
            .success(CommandResult(stdout: rawSymbols, stderr: "")),
            .success(CommandResult(stdout: demangledSymbols, stderr: "")),
            // swiftc -typecheck for module validation (Foundation is valid)
            .success(CommandResult(stdout: "", stderr: "")),
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
            import Foundation

            public struct Manager {
              public var createdAt: Foundation.Date { get }
            }
            """
            )
    )
    let invocations = await commandRunner.recordedInvocations()
    #expect(invocations.count == 3)
    #expect(invocations[0] == .init(
        executable: "nm",
        arguments: ["-gU", frameworkURL.standardizedFileURL.path],
        stdin: nil
    ))
    #expect(invocations[1] == .init(
        executable: "swift-demangle",
        arguments: ["--compact"],
        stdin: rawSymbols
    ))
    #expect(invocations[2].executable == "swiftc")
    #expect(invocations[2].arguments.contains("-typecheck"))
    #expect(invocations[2].arguments.contains("-target"))
}

@Test
func generateFiltersAllUnavailableModulesIteratively() async throws {
    let temporaryDirectory = try TemporaryDirectory(prefix: "SwiftInterfaceGeneratorMultiImport")
    let frameworkURL = temporaryDirectory.url
        .appendingPathComponent("Fixture.framework", isDirectory: true)
        .appendingPathComponent("Fixture")
    let rawSymbols = "raw nm output"
    // Symbols reference types from two unavailable modules: ModuleA and ModuleB
    let demangledSymbols = [
        "nominal type descriptor for Fixture.Widget",
        "property descriptor for Fixture.Widget.name : Swift.String",
        "property descriptor for Fixture.Widget.tokenA : ModuleA.Token",
        "property descriptor for Fixture.Widget.tokenB : ModuleB.Token",
    ].joined(separator: "\n")
    let commandRunner = MockCommandRunner(
        responses: [
            .success(CommandResult(stdout: rawSymbols, stderr: "")),
            .success(CommandResult(stdout: demangledSymbols, stderr: "")),
            // First swiftc -typecheck: compiler reports only ModuleA as missing
            .failure(.commandFailed(
                command: "swiftc -typecheck ...",
                status: "exited(1)",
                stdout: "",
                stderr: "error: no such module 'ModuleA'"
            )),
            // Second swiftc -typecheck (after removing ModuleA): reports ModuleB
            .failure(.commandFailed(
                command: "swiftc -typecheck ...",
                status: "exited(1)",
                stdout: "",
                stderr: "error: no such module 'ModuleB'"
            )),
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
    let normalized = normalizedInterface(interfaceContents)

    // Neither ModuleA nor ModuleB should appear in the output
    #expect(!normalized.contains("ModuleA"))
    #expect(!normalized.contains("ModuleB"))
    // Widget should still exist with its non-external member
    #expect(normalized.contains("public struct Widget"))
    #expect(normalized.contains("name"))
}
