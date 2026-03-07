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
    private let builder = SwiftInterfaceBuilder()

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
        let moduleName = builder.normalizedModuleName(for: frameworkBinaryURL)
        let outputRootURL = repositoryRootURL
            .standardizedFileURL
            .appendingPathComponent("tmp_module", isDirectory: true)
        let normalizedFrameworkBinaryURL = frameworkBinaryURL.standardizedFileURL
        let moduleDirectoryURL = outputRootURL
            .appendingPathComponent("\(moduleName).swiftmodule", isDirectory: true)
        let interfaceURL = moduleDirectoryURL
            .appendingPathComponent(builder.swiftinterfaceFilename(for: targetTriple))

        try? FileManager.default.removeItem(at: moduleDirectoryURL)
        try FileManager.default.createDirectory(at: moduleDirectoryURL, withIntermediateDirectories: true)

        let demangledSymbols = try await loadDemangledSymbols(frameworkBinaryURL: normalizedFrameworkBinaryURL)
        let compilerVersion = try await loadCompilerVersion()
        let interface = builder.makeInterface(
            demangledSymbols: demangledSymbols,
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

        return demangled.stdout
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map(Self.normalizedSymbolLine)
            .filter { !$0.isEmpty }
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
}
