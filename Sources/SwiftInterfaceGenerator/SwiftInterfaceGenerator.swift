import Foundation

/// Generates `.swiftinterface` files from compiled framework binaries.
///
/// `SwiftInterfaceGenerator` analyzes a compiled framework binary and reconstructs a
/// `.swiftinterface` file describing the module's public API surface.
///
/// ## Overview
///
/// Use this type when you need a `.swiftinterface` for a framework that was built
/// without library evolution enabled, or when you need to regenerate one from a binary
/// artifact.
///
/// ```swift
/// let generator = SwiftInterfaceGenerator()
/// let result = try await generator.generate(
///     frameworkBinaryURL: URL(fileURLWithPath: "/path/to/MyFramework.framework/MyFramework"),
///     repositoryRootURL: URL(fileURLWithPath: "/path/to/output"),
///     targetTriple: "arm64-apple-macosx15.0"
/// )
/// ```
///
/// ## Compiler Version
///
/// The generator automatically detects your Swift compiler version. You can override it
/// by setting the `SWIFT_INTERFACE_COMPILER_VERSION` environment variable.
///
/// ## Topics
///
/// ### Creating a Generator
///
/// - ``init()``
///
/// ### Generating Interfaces
///
/// - ``generate(frameworkBinaryURL:repositoryRootURL:targetTriple:)``
///
/// ### Results
///
/// - ``GeneratedSwiftInterface``
///
/// ### Errors
///
/// - ``SwiftInterfaceGeneratorError``
public struct SwiftInterfaceGenerator: Sendable {
    private let commandRunner: any CommandRunning
    private let compilerVersionProvider: (@Sendable () async throws -> String)?
    private let utilityBuilder = SwiftInterfaceBuilder()

    /// Creates a new generator with the default configuration.
    public init() {
        self.init(commandRunner: SubprocessCommandRunner())
    }

    /// Creates a generator with a custom command runner and optional compiler version provider.
    ///
    /// This initializer is used internally and by tests to inject mock dependencies.
    ///
    /// - Parameters:
    ///   - commandRunner: The runner used to execute `nm`, `swift-demangle`, and `swiftc`.
    ///   - compilerVersionProvider: An optional closure that returns the Swift compiler version
    ///     string. When `nil`, the version is detected automatically.
    init(
        commandRunner: some CommandRunning,
        compilerVersionProvider: (@Sendable () async throws -> String)? = nil
    ) {
        self.commandRunner = commandRunner
        self.compilerVersionProvider = compilerVersionProvider
    }

    /// Generates a `.swiftinterface` file for the given framework binary.
    ///
    /// Analyzes the binary's exported symbols to reconstruct the module's public API,
    /// then writes a `.swiftinterface` file under `repositoryRootURL`.
    ///
    /// - Parameters:
    ///   - frameworkBinaryURL: The URL of the compiled framework binary
    ///     (e.g. `MyFramework.framework/MyFramework`).
    ///   - repositoryRootURL: The root directory where the generated module
    ///     directory will be created.
    ///   - targetTriple: The target triple for the interface header
    ///     (e.g. `"arm64-apple-macosx15.0"`).
    ///
    /// - Returns: A ``GeneratedSwiftInterface`` containing the output file location
    ///   and metadata.
    ///
    /// - Throws: ``SwiftInterfaceGeneratorError`` if generation fails.
    public func generate(
        frameworkBinaryURL: URL,
        repositoryRootURL: URL,
        targetTriple: String
    ) async throws -> GeneratedSwiftInterface {
        let preferredModuleName = utilityBuilder.normalizedModuleName(for: frameworkBinaryURL)
        let outputRootURL = repositoryRootURL
            .standardizedFileURL
            .appendingPathComponent("tmp_module", isDirectory: true)
        let normalizedFrameworkBinaryURL = frameworkBinaryURL.standardizedFileURL

        async let demangledSymbolsTask = loadDemangledSymbols(frameworkBinaryURL: normalizedFrameworkBinaryURL)
        async let compilerVersionTask = loadCompilerVersion()
        let demangledSymbols = try await demangledSymbolsTask
        let compilerVersion = try await compilerVersionTask
        var moduleName = preferredModuleName
        var declarations = utilityBuilder.discoverDeclarations(from: demangledSymbols, moduleName: moduleName)
        if declarations.isEmpty,
           let inferredModuleName = utilityBuilder.inferredModuleName(
               from: demangledSymbols,
               preferredModuleName: preferredModuleName
           ) {
            moduleName = inferredModuleName
            declarations = utilityBuilder.discoverDeclarations(from: demangledSymbols, moduleName: moduleName)
        }

        let moduleDirectoryURL = outputRootURL
            .appendingPathComponent("\(moduleName).swiftmodule", isDirectory: true)
        let interfaceURL = moduleDirectoryURL
            .appendingPathComponent(utilityBuilder.swiftinterfaceFilename(for: targetTriple))

        try? FileManager.default.removeItem(at: moduleDirectoryURL)
        try FileManager.default.createDirectory(at: moduleDirectoryURL, withIntermediateDirectories: true)

        let renderableExternalModules = try await loadRenderableExternalModules(
            declarations: declarations,
            moduleName: moduleName,
            targetTriple: targetTriple
        )
        let renderingBuilder = SwiftInterfaceBuilder(renderableExternalModules: renderableExternalModules)
        let interface = renderingBuilder.renderInterface(
            declarations: declarations,
            targetTriple: targetTriple,
            moduleName: moduleName,
            compilerVersion: compilerVersion
        )
        try interface.write(to: interfaceURL, atomically: true, encoding: .utf8)

        return GeneratedSwiftInterface(
            interfaceURL: interfaceURL,
            moduleSearchRootURL: outputRootURL,
            log: "Generated \(interfaceURL.path) from \(normalizedFrameworkBinaryURL.path)"
        )
    }

    /// Extracts and demangles exported symbols from a framework binary.
    ///
    /// Runs `nm -gU` to list globally-defined symbols, then pipes the output through
    /// `swift-demangle --compact` to produce human-readable symbol names. Address metadata
    /// and blank lines are stripped from the result.
    ///
    /// - Parameter frameworkBinaryURL: The URL of the compiled Mach-O binary.
    /// - Returns: An array of demangled symbol strings, one per exported symbol.
    /// - Throws: ``SwiftInterfaceGeneratorError/commandFailed(command:status:stdout:stderr:)``
    ///   if either `nm` or `swift-demangle` fails.
    func loadDemangledSymbols(frameworkBinaryURL: URL) async throws -> [String] {
        let rawSymbols = try await commandRunner.run(
            executable: "nm",
            arguments: ["-gU", frameworkBinaryURL.path],
            stdin: nil
        )
        let demangled = try await commandRunner.run(
            executable: "swift-demangle",
            arguments: ["--compact"],
            stdin: rawSymbols.stdout
        )

        return Array(
            demangled.stdout
                .split(whereSeparator: \.isNewline)
                .lazy
                .map { Self.normalizedSymbolLine(String($0)) }
                .filter { !$0.isEmpty }
        )
    }

    /// Strips the address and type-code prefix from a demangled symbol line.
    ///
    /// Lines from `swift-demangle` typically have the format `0000000000000000 T symbol name`.
    /// This method returns just the symbol name portion. If the line does not match the
    /// expected three-field format, it is returned unchanged.
    ///
    /// - Parameter line: A single line of demangled output.
    /// - Returns: The symbol name with address metadata removed.
    static func normalizedSymbolLine(_ line: String) -> String {
        let fields = line.split(maxSplits: 2, whereSeparator: \.isWhitespace)
        guard
            fields.count == 3,
            fields[0].allSatisfy(\.isHexDigit),
            fields[1].count == 1
        else {
            return line
        }

        return String(fields[2])
    }

    /// Resolves the Swift compiler version string to embed in the interface header.
    ///
    /// The resolution order is:
    /// 1. The injected `compilerVersionProvider` closure (used in tests).
    /// 2. The `SWIFT_INTERFACE_COMPILER_VERSION` environment variable.
    /// 3. The first non-empty line from `swiftc -version`.
    /// 4. Falls back to `"Apple Swift"` if all else fails.
    private func loadCompilerVersion() async throws -> String {
        if let compilerVersionProvider {
            return try await compilerVersionProvider()
        }

        if let override = ProcessInfo.processInfo.environment["SWIFT_INTERFACE_COMPILER_VERSION"] {
            return override
        }

        do {
            let result = try await commandRunner.run(
                executable: "swiftc",
                arguments: ["-version"],
                stdin: nil
            )
            if let firstLine = result.stdout
                .split(whereSeparator: \.isNewline)
                .map(String.init)
                .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                return firstLine
            }
        } catch {
            // Fall through to default
        }

        return "Apple Swift"
    }

    private func loadRenderableExternalModules(
        declarations: [String: SwiftInterfaceBuilder.Declaration],
        moduleName: String,
        targetTriple: String
    ) async throws -> Set<String> {
        let candidateModules = utilityBuilder.discoveredExternalModules(
            from: declarations,
            moduleName: moduleName
        )

        guard !candidateModules.isEmpty else {
            return []
        }

        guard let sdkIdentifier = sdkIdentifier(for: targetTriple) else {
            return Set(candidateModules)
        }

        return try await withThrowingTaskGroup(of: (String, Bool).self) { group in
            for module in candidateModules {
                group.addTask {
                    let result = try await self.canImport(
                        module: module,
                        sdkIdentifier: sdkIdentifier,
                        targetTriple: targetTriple
                    )
                    return (module, result)
                }
            }

            var renderableModules: Set<String> = []
            for try await (module, canImport) in group {
                if canImport {
                    renderableModules.insert(module)
                }
            }
            return renderableModules
        }
    }

    private func canImport(
        module: String,
        sdkIdentifier: String,
        targetTriple: String
    ) async throws -> Bool {
        let probeRootURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("SwiftInterfaceGeneratorModuleProbe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: probeRootURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: probeRootURL)
        }

        let sourceURL = probeRootURL.appendingPathComponent("Probe.swift")
        let moduleCacheURL = probeRootURL.appendingPathComponent("ModuleCache", isDirectory: true)
        try FileManager.default.createDirectory(at: moduleCacheURL, withIntermediateDirectories: true)
        try "import \(module)\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        do {
            _ = try await commandRunner.run(
                executable: "xcrun",
                arguments: [
                    "--sdk", sdkIdentifier,
                    "swiftc",
                    "-swift-version", "6",
                    "-typecheck",
                    "-target", targetTriple,
                    "-module-cache-path", moduleCacheURL.path,
                    sourceURL.path,
                ],
                stdin: nil
            )
            return true
        } catch {
            return false
        }
    }

    private func sdkIdentifier(for targetTriple: String) -> String? {
        if targetTriple.contains("macosx") {
            return "macosx"
        }
        if targetTriple.contains("ios"), targetTriple.contains("simulator") {
            return "iphonesimulator"
        }
        if targetTriple.contains("ios") {
            return "iphoneos"
        }
        if targetTriple.contains("tvos"), targetTriple.contains("simulator") {
            return "appletvsimulator"
        }
        if targetTriple.contains("tvos") {
            return "appletvos"
        }
        if targetTriple.contains("watchos"), targetTriple.contains("simulator") {
            return "watchsimulator"
        }
        if targetTriple.contains("watchos") {
            return "watchos"
        }
        if targetTriple.contains("xros"), targetTriple.contains("simulator") {
            return "xrsimulator"
        }
        if targetTriple.contains("xros") {
            return "xros"
        }
        return nil
    }
}
