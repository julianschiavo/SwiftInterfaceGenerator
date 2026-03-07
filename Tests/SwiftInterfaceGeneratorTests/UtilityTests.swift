import Foundation
import Testing
@testable import SwiftInterfaceGenerator

private let utilityBuilder = SwiftInterfaceBuilder()

@Test
func splitTopLevelKeepsNestedCommasTogether() throws {
    let parts = try utilityBuilder.splitTopLevel(
        "value: Swift.Result<(Swift.Int, Swift.String), Swift.Error>, callback: ((Swift.Int, Swift.String)) -> Swift.Void, options: [Swift.String]"
    )

    #expect(
        parts
            == [
                "value: Swift.Result<(Swift.Int, Swift.String), Swift.Error>",
                "callback: ((Swift.Int, Swift.String)) -> Swift.Void",
                "options: [Swift.String]",
            ]
    )
}

@Test
func splitTopLevelRejectsUnbalancedInput() throws {
    do {
        _ = try utilityBuilder.splitTopLevel("value: Swift.Array<Swift.String")
        #expect(Bool(false))
    } catch let error as SwiftInterfaceGeneratorError {
        guard case .unexpectedOutput(let message) = error else {
            #expect(Bool(false))
            return
        }

        #expect(message == "Unbalanced argument list: value: Swift.Array<Swift.String")
    }
}

@Test
func renderedArgumentListPreservesClosureAndTupleTypes() throws {
    let rendered = try utilityBuilder.renderedArgumentList(
        "value: (Swift.Int, Swift.String), callback: ((Swift.Int) -> Swift.String)",
        protocolNames: [],
        moduleName: "Fixture"
    )

    #expect(
        rendered
            == "value: (Swift.Int, Swift.String), callback: ((Swift.Int) -> Swift.String)"
    )
}

@Test
func renderedArgumentListTreatsNestedTupleLabelsAsPartOfUnlabeledClosureParameter() throws {
    let rendered = try utilityBuilder.renderedArgumentList(
        "(Demo.Element, [Demo.Element], (element: Demo.Element, content: Demo.Window)?) -> ()",
        protocolNames: [],
        moduleName: "Demo"
    )

    #expect(
        rendered
            == "_: (Element, [Element], (element: Element, content: Window)?) -> ()"
    )
}

@Test
func cleanedTypeNameRewritesModulePrefixesAndCBridges() {
    #expect(
        utilityBuilder.cleanedTypeName("__owned Fixture.Token<__C.CGRect>", moduleName: "Fixture")
            == "Token<CoreGraphics.CGRect>"
    )
    #expect(
        utilityBuilder.cleanedTypeName("__C.audit_token_t")
            == "Darwin.audit_token_t"
    )
    #expect(
        utilityBuilder.cleanedTypeName("_StringProcessing.Regex<(Swift.String)>")
            == "_StringProcessing.Regex<(Swift.String)>"
    )
    #expect(
        utilityBuilder.cleanedTypeName("Swift.Actor")
            == "_Concurrency.Actor"
    )
    #expect(
        utilityBuilder.cleanedTypeName("Swift.AsyncIteratorProtocol")
            == "_Concurrency.AsyncIteratorProtocol"
    )
    #expect(
        utilityBuilder.cleanedTypeName("Swift.AsyncSequence")
            == "_Concurrency.AsyncSequence"
    )
}

@Test
func renderedTypeNameUsesExistentialsForProtocolsAndOptionalProtocols() {
    #expect(
        utilityBuilder.renderedTypeName("Fixture.Greeter", protocolNames: ["Greeter"], moduleName: "Fixture")
            == "any Greeter"
    )
    #expect(
        utilityBuilder.renderedTypeName("Fixture.Greeter?", protocolNames: ["Greeter"], moduleName: "Fixture")
            == "(any Greeter)?"
    )
}

@Test
func escapedIdentifierEscapesSwiftKeywords() {
    #expect(utilityBuilder.escapedIdentifier("class") == "`class`")
    #expect(utilityBuilder.escapedIdentifier("Protocol") == "`Protocol`")
    #expect(utilityBuilder.escapedIdentifier("value") == "value")
}

@Test
func swiftinterfaceFilenameNormalizesPlatformVersions() {
    #expect(
        utilityBuilder.swiftinterfaceFilename(for: "arm64-apple-ios18.2-simulator")
            == "arm64-apple-ios-simulator.swiftinterface"
    )
    #expect(
        utilityBuilder.swiftinterfaceFilename(for: "x86_64-apple-macosx15.0")
            == "x86_64-apple-macosx.swiftinterface"
    )
}

@Test
func normalizedModuleNameUsesFilenameWithoutExtensionWhenAvailable() {
    #expect(
        utilityBuilder.normalizedModuleName(for: URL(fileURLWithPath: "/tmp/Fancy.framework/Fancy"))
            == "Fancy"
    )
    #expect(
        utilityBuilder.normalizedModuleName(for: URL(fileURLWithPath: "/tmp/Fancy.dylib"))
            == "Fancy"
    )
}

@Test
func subprocessCommandRunnerPrefersSwiftDemangleFromToolchainDirectory() async {
    let resolvedExecutable = await SubprocessCommandRunner.preferredExecutablePath(
        for: "swift-demangle",
        environment: ["TOOLCHAIN_DIR": "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain"],
        isExecutableFile: { path in
            path == "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-demangle"
        },
        xcrunLookup: { _ in nil }
    )

    #expect(
        resolvedExecutable
            == "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-demangle"
    )
}

@Test
func subprocessCommandRunnerFallsBackToXcrunForSwiftDemangle() async {
    let resolvedExecutable = await SubprocessCommandRunner.preferredExecutablePath(
        for: "swift-demangle",
        environment: [:],
        isExecutableFile: { path in
            path == "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-demangle"
        },
        xcrunLookup: { _ in
            "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-demangle"
        }
    )

    #expect(
        resolvedExecutable
            == "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-demangle"
    )
}

@Test
func subprocessCommandRunnerLeavesOtherExecutablesUnchanged() async {
    let resolvedExecutable = await SubprocessCommandRunner.preferredExecutablePath(
        for: "nm",
        environment: ["TOOLCHAIN_DIR": "/tmp/toolchain"],
        isExecutableFile: { _ in true },
        xcrunLookup: { _ in "/tmp/toolchain/usr/bin/nm" }
    )

    #expect(resolvedExecutable == "nm")
}
