import Testing
@testable import SwiftInterfaceGenerator

@Test
func commandFailedDescriptionIncludesNonEmptyStreams() {
    let error = SwiftInterfaceGeneratorError.commandFailed(
        command: "swift-demangle --compact",
        status: "exited(1)",
        stdout: "stdout text\n",
        stderr: "stderr text\n"
    )

    #expect(
        error.errorDescription
            == """
            Command failed: swift-demangle --compact

            Status: exited(1)

            stdout:
            stdout text

            stderr:
            stderr text
            """
    )
}

@Test
func unexpectedOutputDescriptionIsMessage() {
    #expect(
        SwiftInterfaceGeneratorError.unexpectedOutput("broken symbols").errorDescription
            == "broken symbols"
    )
}
