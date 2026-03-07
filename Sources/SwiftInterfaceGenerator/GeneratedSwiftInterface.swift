import Foundation

/// The result of generating a `.swiftinterface` file from a compiled framework binary.
///
/// A `GeneratedSwiftInterface` contains the location of the generated interface file,
/// the module search root for passing to the Swift compiler, and a human-readable log
/// message describing the operation.
///
/// ## Usage
///
/// You obtain a `GeneratedSwiftInterface` by calling
/// ``SwiftInterfaceGenerator/generate(frameworkBinaryURL:repositoryRootURL:targetTriple:)``:
///
/// ```swift
/// let generator = SwiftInterfaceGenerator()
/// let result = try await generator.generate(
///     frameworkBinaryURL: binaryURL,
///     repositoryRootURL: repoURL,
///     targetTriple: "arm64-apple-macosx15.0"
/// )
/// print(result.interfaceURL.path)
/// ```
public struct GeneratedSwiftInterface: Sendable {
    /// The file URL of the generated `.swiftinterface` file.
    ///
    /// The file is written inside a `<ModuleName>.swiftmodule` directory under the
    /// ``moduleSearchRootURL``, with a filename derived from the target triple
    /// (for example, `arm64-apple-macosx.swiftinterface`).
    public let interfaceURL: URL

    /// The root directory containing the generated module artifacts.
    ///
    /// Pass this URL as a module search path (e.g. `-I` flag) when invoking the Swift
    /// compiler so it can locate the generated `.swiftinterface`.
    public let moduleSearchRootURL: URL

    /// A human-readable log message describing the generation that was performed.
    ///
    /// Typically includes the output path and the source binary path, for example:
    /// `"Generated /path/to/Module.swiftinterface from /path/to/Module.framework/Module"`.
    public let log: String

    /// Creates a new generated interface result.
    ///
    /// - Parameters:
    ///   - interfaceURL: The file URL of the generated `.swiftinterface` file.
    ///   - moduleSearchRootURL: The root directory containing the generated module artifacts.
    ///   - log: A human-readable log message describing the generation.
    public init(interfaceURL: URL, moduleSearchRootURL: URL, log: String) {
        self.interfaceURL = interfaceURL
        self.moduleSearchRootURL = moduleSearchRootURL
        self.log = log
    }
}
