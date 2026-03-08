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
/// It launches processes using `Subprocess.run`, captures full stdout/stderr,
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
        let executable = await Self.preferredExecutablePath(for: executable)
        let result = try await Self.execute(
            executable: executable,
            arguments: arguments,
            stdin: stdin
        )
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

    static func preferredExecutablePath(
        for executable: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isExecutableFile: (String) -> Bool = FileManager.default.isExecutableFile(atPath:),
        xcrunLookup: @escaping @Sendable (String) async -> String? = Self.lookupExecutableInActiveXcode
    ) async -> String {
        guard executable == "swift-demangle", !executable.contains("/") else {
            return executable
        }

        if let toolchainDirectory = environment["TOOLCHAIN_DIR"] {
            let toolchainExecutable = URL(fileURLWithPath: toolchainDirectory, isDirectory: true)
                .appendingPathComponent("usr/bin/\(executable)")
                .path
            if isExecutableFile(toolchainExecutable) {
                return toolchainExecutable
            }
        }

        if let resolvedExecutable = await xcrunLookup(executable),
           isExecutableFile(resolvedExecutable) {
            return resolvedExecutable
        }

        return executable
    }

    private static func lookupExecutableInActiveXcode(_ executable: String) async -> String? {
        let xcrunPath = "/usr/bin/xcrun"
        guard FileManager.default.isExecutableFile(atPath: xcrunPath) else {
            return nil
        }

        do {
            let result = try await execute(
                executable: xcrunPath,
                arguments: ["--find", executable],
                stdin: nil
            )
            return result.standardOutput?
                .split(whereSeparator: \.isNewline)
                .map(String.init)
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    private static func execute(
        executable: String,
        arguments: [String],
        stdin: String?
    ) async throws -> CollectedResult<StringOutput<UTF8>, StringOutput<UTF8>> {
        let result: CollectedResult<StringOutput<UTF8>, StringOutput<UTF8>>

        if let stdin {
            result = try await Subprocess.run(
                .name(executable),
                arguments: Arguments(arguments),
                input: .string(stdin),
                output: .string(limit: .max),
                error: .string(limit: .max)
            )
        } else {
            result = try await Subprocess.run(
                .name(executable),
                arguments: Arguments(arguments),
                output: .string(limit: .max),
                error: .string(limit: .max)
            )
        }
        return result
    }
}
