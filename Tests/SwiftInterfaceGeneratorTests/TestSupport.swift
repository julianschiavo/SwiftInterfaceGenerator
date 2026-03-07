import Foundation
@testable import SwiftInterfaceGenerator

final class TemporaryDirectory {
    let url: URL

    init(prefix: String) throws {
        self.url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

struct MockCommandRunner: CommandRunning {
    struct Invocation: Equatable, Sendable {
        let executable: String
        let arguments: [String]
        let stdin: String?
    }

    enum QueuedResponse: Sendable {
        case success(CommandResult)
        case failure(SwiftInterfaceGeneratorError)
    }

    private actor State {
        var responses: [QueuedResponse]
        var invocations: [Invocation] = []

        init(responses: [QueuedResponse]) {
            self.responses = responses
        }

        func next(for invocation: Invocation) throws -> CommandResult {
            invocations.append(invocation)
            guard !responses.isEmpty else {
                throw SwiftInterfaceGeneratorError.unexpectedOutput("Missing mock response for \(invocation.executable)")
            }

            switch responses.removeFirst() {
            case .success(let result):
                return result
            case .failure(let error):
                throw error
            }
        }

        func snapshotInvocations() -> [Invocation] {
            invocations
        }
    }

    private let state: State

    init(responses: [QueuedResponse]) {
        self.state = State(responses: responses)
    }

    func run(
        executable: String,
        arguments: [String],
        stdin: String?
    ) async throws -> CommandResult {
        try await state.next(
            for: Invocation(
                executable: executable,
                arguments: arguments,
                stdin: stdin
            )
        )
    }

    func recordedInvocations() async -> [Invocation] {
        await state.snapshotInvocations()
    }
}

func normalizedInterface(_ contents: String) -> String {
    contents.trimmingCharacters(in: .whitespacesAndNewlines)
}
