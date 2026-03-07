import Foundation
import Subprocess

/// The captured output from running an external command.
struct CommandResult: Sendable {
    /// The standard output captured from the command.
    let stdout: String
    /// The standard error captured from the command.
    let stderr: String
}

/// A protocol for types that can run external commands and return their output.
///
/// Conforming types execute shell commands asynchronously and return a ``CommandResult``
/// on success, or throw a ``SwiftInterfaceGeneratorError/commandFailed(command:status:stdout:stderr:)``
/// on failure.
protocol CommandRunning: Sendable {
    /// Runs an external command.
    ///
    /// - Parameters:
    ///   - executable: The name or path of the executable to run.
    ///   - arguments: The arguments to pass to the executable.
    ///   - stdin: Optional string to pipe to the command's standard input.
    /// - Returns: A ``CommandResult`` containing the captured stdout and stderr.
    /// - Throws: ``SwiftInterfaceGeneratorError/commandFailed(command:status:stdout:stderr:)``
    ///   if the command exits with a non-zero status.
    func run(
        executable: String,
        arguments: [String],
        stdin: String?
    ) async throws -> CommandResult
}

/// A command runner backed by the `Subprocess` library.
///
/// This is the default runner used by ``SwiftInterfaceGenerator`` in production.
/// It launches processes using `Subprocess.run`, captures up to 8 MB of stdout/stderr,
/// and throws ``SwiftInterfaceGeneratorError/commandFailed(command:status:stdout:stderr:)``
/// on non-zero exit.
struct SubprocessCommandRunner: CommandRunning {
    /// Runs an external command using `Subprocess`.
    ///
    /// - Parameters:
    ///   - executable: The name or path of the executable to run (resolved via `PATH`).
    ///   - arguments: The arguments to pass to the executable.
    ///   - stdin: Optional string to pipe to the command's standard input.
    /// - Returns: A ``CommandResult`` containing the captured stdout and stderr.
    /// - Throws: ``SwiftInterfaceGeneratorError/commandFailed(command:status:stdout:stderr:)``
    ///   if the command exits with a non-zero status.
    func run(
        executable: String,
        arguments: [String],
        stdin: String? = nil
    ) async throws -> CommandResult {
        let result: CollectedResult<StringOutput<UTF8>, StringOutput<UTF8>>

        if let stdin {
            result = try await Subprocess.run(
                .name(executable),
                arguments: Arguments(arguments),
                input: .string(stdin),
                output: .string(limit: 8_388_608),
                error: .string(limit: 8_388_608)
            )
        } else {
            result = try await Subprocess.run(
                .name(executable),
                arguments: Arguments(arguments),
                output: .string(limit: 8_388_608),
                error: .string(limit: 8_388_608)
            )
        }

        let stdout = result.standardOutput ?? ""
        let stderr = result.standardError ?? ""

        if case .exited(let code) = result.terminationStatus, code == 0 {
            return CommandResult(stdout: stdout, stderr: stderr)
        }

        throw SwiftInterfaceGeneratorError.commandFailed(
            command: ([executable] + arguments).joined(separator: " "),
            status: String(describing: result.terminationStatus),
            stdout: stdout,
            stderr: stderr
        )
    }
}
