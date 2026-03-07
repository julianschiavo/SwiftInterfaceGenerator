import Foundation

/// Errors that can occur during Swift interface generation.
///
/// These errors cover failures in the external tool pipeline (`nm`, `swift-demangle`)
/// as well as problems encountered while parsing demangled symbol output.
public enum SwiftInterfaceGeneratorError: Error, LocalizedError {
    /// A required ABI symbol was not found in the demangled output.
    ///
    /// - Parameter symbol: The name of the missing symbol.
    case missingRequiredSymbol(String)

    /// An external command exited with a non-zero status.
    ///
    /// - Parameters:
    ///   - command: The full command string that was executed.
    ///   - status: A string representation of the termination status.
    ///   - stdout: The standard output captured from the command.
    ///   - stderr: The standard error captured from the command.
    case commandFailed(command: String, status: String, stdout: String, stderr: String)

    /// The demangled symbol output could not be parsed as expected.
    ///
    /// - Parameter message: A description of what went wrong.
    case unexpectedOutput(String)

    public var errorDescription: String? {
        switch self {
        case .missingRequiredSymbol(let symbol):
            return "Missing required ABI symbol: \(symbol)"
        case .commandFailed(let command, let status, let stdout, let stderr):
            var parts = ["Command failed: \(command)", "Status: \(status)"]
            let trimmedStdout = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedStderr = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedStdout.isEmpty {
                parts.append("stdout:\n\(trimmedStdout)")
            }
            if !trimmedStderr.isEmpty {
                parts.append("stderr:\n\(trimmedStderr)")
            }
            return parts.joined(separator: "\n\n")
        case .unexpectedOutput(let message):
            return message
        }
    }
}
