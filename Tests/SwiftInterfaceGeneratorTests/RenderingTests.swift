import Testing
@testable import SwiftInterfaceGenerator

private let renderingBuilder = SwiftInterfaceBuilder()

// MARK: - Full Interface Rendering

@Suite("makeInterface rendering")
struct MakeInterfaceTests {
    @Test
    func fullInterfaceWithNestedTypesImportsAndConformances() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "protocol descriptor for Demo.Greeter",
                "associated type descriptor for Demo.Greeter.Output",
                "method descriptor for Demo.Greeter.describe() -> Swift.String",
                "nominal type descriptor for Demo.Box",
                "protocol conformance descriptor for Demo.Box : Swift.Sendable in Demo",
                "property descriptor for Demo.Box.value : T",
                "Demo.Box.value.getter : T",
                "Demo.Box.init(value: T) -> Demo.Box<T>",
                "Demo.Box.map(transform: (T) -> U) -> Demo.Box<U>",
                "static Demo.Box.makeDefault() -> Demo.Box<T>",
                "nominal type descriptor for Demo.Message",
                "protocol conformance descriptor for Demo.Message : Swift.Encodable in Demo",
                "protocol conformance descriptor for Demo.Message : Swift.Decodable in Demo",
                "protocol conformance descriptor for Demo.Message : Swift.Hashable in Demo",
                "protocol conformance descriptor for Demo.Message : Swift.Equatable in Demo",
                "enum case for Demo.Message.text(Demo.Message) -> (Foundation.Date) -> Demo.Message",
                "enum case for Demo.Message.none(Demo.Message) -> Demo.Message",
                "nominal type descriptor for Demo.Manager",
                "metaclass for Demo.Manager",
                "property descriptor for static Demo.Manager.shared : Demo.Manager",
                "static Demo.Manager.shared.getter : Demo.Manager",
                "property descriptor for Demo.Manager.createdAt : Foundation.Date",
                "Demo.Manager.createdAt.getter : Foundation.Date",
                "Demo.Manager.createdAt.setter : (Foundation.Date) -> ()",
                "property descriptor for Demo.Manager.region : CoreGraphics.Region",
                "Demo.Manager.region.getter : CoreGraphics.Region",
                "Demo.Manager.init() -> Demo.Manager",
                "Demo.Manager.accept(greeter: Demo.Greeter) -> ()",
                "Demo.Manager.use(queue: Dispatch.DispatchQueue) -> Foundation.Date",
                "nominal type descriptor for Demo.Namespace",
                "nominal type descriptor for Demo.Namespace.Inner",
                "property descriptor for Demo.Namespace.Inner.token : Darwin.audit_token_t",
                "Demo.Namespace.Inner.token.getter : Darwin.audit_token_t",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Demo",
            compilerVersion: "Test Swift"
        )

        #expect(
            normalizedInterface(interface)
                == normalizedInterface(
                    """
                // swift-interface-format-version: 1.0
                // swift-compiler-version: Test Swift
                // swift-module-flags: -target arm64-apple-macosx15.0 -enable-library-evolution -module-name Demo
                import Swift
                import Foundation
                import Dispatch
                import CoreGraphics
                import Darwin

                public protocol Greeter {
                  associatedtype Output
                  func describe() -> Swift.String
                }

                public struct Box<T>: Swift.Sendable {
                  public var value: T { get }
                  public init(value: T)
                  public func map(transform: (T) -> U) -> Box<U>
                  public static func makeDefault() -> Box<T>
                }

                public enum Message: Swift.Codable, Swift.Hashable {
                  case text(Foundation.Date)
                  case none
                }

                public final class Manager {
                  public static var shared: Manager { get }
                  public var createdAt: Foundation.Date { get set }
                  public var region: CoreGraphics.Region { get }
                  public init()
                  public func accept(greeter: any Greeter)
                  public func use(queue: Dispatch.DispatchQueue) -> Foundation.Date
                }

                public struct Namespace {
                  public struct Inner {
                    public var token: Darwin.audit_token_t { get }
                  }
                }
                """
                )
        )
    }

    @Test
    func emptyStruct() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Empty",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        #expect(
            normalizedInterface(interface)
                == normalizedInterface(
                    """
                // swift-interface-format-version: 1.0
                // swift-compiler-version: Test
                // swift-module-flags: -target arm64-apple-macosx15.0 -enable-library-evolution -module-name Mod
                import Swift

                public struct Empty {
                }
                """
                )
        )
    }

    @Test
    func protocolWithMultipleAssociatedTypesAndMethods() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "protocol descriptor for Mod.DataSource",
                "associated type descriptor for Mod.DataSource.Item",
                "associated type descriptor for Mod.DataSource.Section",
                "method descriptor for Mod.DataSource.numberOfSections() -> Swift.Int",
                "method descriptor for Mod.DataSource.item(at: Swift.Int) -> Mod.DataSource.Item",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        #expect(
            normalizedInterface(interface)
                == normalizedInterface(
                    """
                // swift-interface-format-version: 1.0
                // swift-compiler-version: Test
                // swift-module-flags: -target arm64-apple-macosx15.0 -enable-library-evolution -module-name Mod
                import Swift

                public protocol DataSource {
                  associatedtype Item
                  associatedtype Section
                  func numberOfSections() -> Swift.Int
                  func item(at: Swift.Int) -> DataSource.Item
                }
                """
                )
        )
    }

    @Test
    func protocolInheritanceFromBaseConformanceDescriptors() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "protocol descriptor for Mod.Named",
                "base conformance descriptor for Mod.Named: Swift.Sendable",
                "base conformance descriptor for Mod.Named: Foundation.Identifiable",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        #expect(
            normalizedInterface(interface)
                == normalizedInterface(
                    """
                // swift-interface-format-version: 1.0
                // swift-compiler-version: Test
                // swift-module-flags: -target arm64-apple-macosx15.0 -enable-library-evolution -module-name Mod
                import Swift
                import Foundation

                public protocol Named: Swift.Sendable, Foundation.Identifiable {
                }
                """
                )
        )
    }

    @Test
    func protocolPropertyRequirementsFromMethodDescriptors() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "protocol descriptor for Mod.Described",
                "method descriptor for Mod.Described.title.getter : Swift.String",
                "method descriptor for static Mod.Described.version.getter : Swift.Int",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        #expect(
            normalizedInterface(interface)
                == normalizedInterface(
                    """
                // swift-interface-format-version: 1.0
                // swift-compiler-version: Test
                // swift-module-flags: -target arm64-apple-macosx15.0 -enable-library-evolution -module-name Mod
                import Swift

                public protocol Described {
                  var title: Swift.String { get }
                  static var version: Swift.Int { get }
                }
                """
                )
        )
    }

    @Test
    func associatedTypeConstraintsFromAssociatedConformanceDescriptors() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "protocol descriptor for Mod.Displayable",
                "protocol descriptor for Mod.Tool",
                "associated type descriptor for Mod.Tool.Output",
                "associated conformance descriptor for Mod.Tool.Mod.Tool.Output: Mod.Displayable",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        #expect(
            normalizedInterface(interface)
                == normalizedInterface(
                    """
                // swift-interface-format-version: 1.0
                // swift-compiler-version: Test
                // swift-module-flags: -target arm64-apple-macosx15.0 -enable-library-evolution -module-name Mod
                import Swift

                public protocol Displayable {
                }

                public protocol Tool {
                  associatedtype Output: Displayable
                }
                """
                )
        )
    }

    @Test
    func enumWithMixedCases() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Result",
                "enum case for Mod.Result.success(Mod.Result) -> (Swift.String) -> Mod.Result",
                "enum case for Mod.Result.failure(Mod.Result) -> (Swift.Error) -> Mod.Result",
                "enum case for Mod.Result.pending(Mod.Result) -> Mod.Result",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        #expect(
            normalizedInterface(interface)
                == normalizedInterface(
                    """
                // swift-interface-format-version: 1.0
                // swift-compiler-version: Test
                // swift-module-flags: -target arm64-apple-macosx15.0 -enable-library-evolution -module-name Mod
                import Swift

                public enum Result {
                  case success(Swift.String)
                  case failure(Swift.Error)
                  case pending
                }
                """
                )
        )
    }

    @Test
    func classDetectedViaMetaclass() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Controller",
                "metaclass for Mod.Controller",
                "Mod.Controller.init() -> Mod.Controller",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        #expect(normalizedInterface(interface).contains("public final class Controller"))
    }

    @Test
    func classDetectedViaMetadataBaseOffset() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Controller",
                "class metadata base offset for Mod.Controller",
                "Mod.Controller.init() -> Mod.Controller",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        #expect(normalizedInterface(interface).contains("public final class Controller"))
    }

    @Test
    func rendersSubscriptsFromPropertyDescriptors() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Buffer",
                "Mod.Buffer.subscript.getter : (Swift.Int) -> Swift.String",
                "property descriptor for Mod.Buffer.subscript(Swift.Int) -> Swift.String",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        #expect(
            normalizedInterface(interface)
                == normalizedInterface(
                    """
                // swift-interface-format-version: 1.0
                // swift-compiler-version: Test
                // swift-module-flags: -target arm64-apple-macosx15.0 -enable-library-evolution -module-name Mod
                import Swift

                public struct Buffer {
                  public subscript(_: Swift.Int) -> Swift.String { get }
                }
                """
                )
        )
    }

    @Test
    func codableMerging() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Config",
                "protocol conformance descriptor for Mod.Config : Swift.Encodable in Mod",
                "protocol conformance descriptor for Mod.Config : Swift.Decodable in Mod",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        #expect(normalizedInterface(interface).contains("Swift.Codable"))
        #expect(!normalizedInterface(interface).contains("Swift.Encodable"))
        #expect(!normalizedInterface(interface).contains("Swift.Decodable"))
    }

    @Test
    func hashableAbsorbsEquatable() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Token",
                "protocol conformance descriptor for Mod.Token : Swift.Hashable in Mod",
                "protocol conformance descriptor for Mod.Token : Swift.Equatable in Mod",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        #expect(normalizedInterface(interface).contains("Swift.Hashable"))
        #expect(!normalizedInterface(interface).contains("Swift.Equatable"))
    }

    @Test
    func unsupportedConformancesFiltered() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.MyKey",
                "protocol conformance descriptor for Mod.MyKey : Foundation.AttributedStringKey in Mod",
                "protocol conformance descriptor for Mod.MyKey : Swift.Sendable in Mod",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        #expect(!normalizedInterface(interface).contains("AttributedStringKey"))
        #expect(normalizedInterface(interface).contains("Swift.Sendable"))
    }

    @Test
    func failableInitRendersQuestionMark() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Parser",
                "Mod.Parser.init(data: Foundation.Data) -> Mod.Parser?",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        #expect(normalizedInterface(interface).contains("public init?(data: Foundation.Data)"))
    }

    @Test
    func voidReturnOmitsReturnClause() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Service",
                "Mod.Service.reset() -> ()",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        let norm = normalizedInterface(interface)
        #expect(norm.contains("public func reset()"))
        #expect(!norm.contains("-> ()"))
    }

    @Test
    func methodWithThrowsEffect() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Loader",
                "Mod.Loader.load() throws -> Swift.String",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        #expect(normalizedInterface(interface).contains("public func load() throws -> Swift.String"))
    }

    @Test
    func methodWithAsyncEffect() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Fetcher",
                "Mod.Fetcher.fetch() async -> Swift.String",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        #expect(normalizedInterface(interface).contains("public func fetch() async -> Swift.String"))
    }

    @Test
    func methodWithAsyncThrowsEffects() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.API",
                "Mod.API.request(url: Swift.String) async throws -> Foundation.Data",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        #expect(normalizedInterface(interface).contains("public func request(url: Swift.String) async throws -> Foundation.Data"))
    }

    @Test
    func staticPropertyRenderedAsGetOnly() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Registry",
                "property descriptor for static Mod.Registry.shared : Mod.Registry",
                "static Mod.Registry.shared.getter : Mod.Registry",
                "Mod.Registry.shared.setter : (Mod.Registry) -> ()",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        #expect(normalizedInterface(interface).contains("public static var shared: Registry { get }"))
    }

    @Test
    func protocolParameterGetsAnyPrefix() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "protocol descriptor for Mod.Handler",
                "method descriptor for Mod.Handler.handle() -> ()",
                "nominal type descriptor for Mod.Router",
                "Mod.Router.add(handler: Mod.Handler) -> ()",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        #expect(normalizedInterface(interface).contains("public func add(handler: any Handler)"))
    }

    @Test
    func optionalProtocolParameterGetsWrapped() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "protocol descriptor for Mod.Delegate",
                "method descriptor for Mod.Delegate.notify() -> ()",
                "nominal type descriptor for Mod.View",
                "property descriptor for Mod.View.delegate : Mod.Delegate?",
                "Mod.View.delegate.getter : Mod.Delegate?",
                "Mod.View.delegate.setter : (Mod.Delegate?) -> ()",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        #expect(normalizedInterface(interface).contains("public var delegate: (any Delegate)? { get set }"))
    }

    @Test
    func allocatingInitFilteredOut() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Thing",
                "Mod.Thing.__allocating_init() -> Mod.Thing",
                "Mod.Thing.init() -> Mod.Thing",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        let norm = normalizedInterface(interface)
        #expect(norm.contains("public init()"))
        #expect(!norm.contains("__allocating_init"))
    }

    @Test
    func classWithOnlyAllocatingInitStillRendersInitializer() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Session",
                "metaclass for Mod.Session",
                "Mod.Session.__allocating_init(model: Mod.Model) -> Mod.Session",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        let norm = normalizedInterface(interface)
        #expect(norm.contains("public final class Session"))
        #expect(norm.contains("public init(model: Model)"))
        #expect(!norm.contains("__allocating_init"))
    }

    @Test
    func deinitFilteredOut() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Resource",
                "metaclass for Mod.Resource",
                "Mod.Resource.__deallocating_deinit",
                "Mod.Resource.deinit",
                "Mod.Resource.init() -> Mod.Resource",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        let norm = normalizedInterface(interface)
        #expect(!norm.contains("deinit"))
        #expect(!norm.contains("deallocating"))
        #expect(norm.contains("public init()"))
    }

    @Test
    func operatorsFilteredOut() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Vector",
                "property descriptor for Mod.Vector.x : Swift.Double",
                "Mod.Vector.x.getter : Swift.Double",
                "static Mod.Vector.+ infix(Mod.Vector, Mod.Vector) -> Mod.Vector",
                "static Mod.Vector.prefix -(Mod.Vector) -> Mod.Vector",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        let norm = normalizedInterface(interface)
        #expect(!norm.contains("infix"))
        #expect(!norm.contains("prefix"))
        #expect(norm.contains("public var x: Swift.Double { get }"))
    }

    @Test
    func multipleDeclarationsPreserveSymbolOrder() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Alpha",
                "nominal type descriptor for Mod.Beta",
                "nominal type descriptor for Mod.Gamma",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        let norm = normalizedInterface(interface)
        let alphaRange = norm.range(of: "Alpha")!
        let betaRange = norm.range(of: "Beta")!
        let gammaRange = norm.range(of: "Gamma")!
        #expect(alphaRange.lowerBound < betaRange.lowerBound)
        #expect(betaRange.lowerBound < gammaRange.lowerBound)
    }

    @Test
    func duplicateConformancesDeduped() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Dupe",
                "protocol conformance descriptor for Mod.Dupe : Swift.Sendable in Mod",
                "protocol conformance descriptor for Mod.Dupe : Swift.Sendable in Mod",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        let norm = normalizedInterface(interface)
        let count = norm.components(separatedBy: "Sendable").count - 1
        #expect(count == 1)
    }

    @Test
    func duplicatePropertiesDeduped() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Config",
                "property descriptor for Mod.Config.name : Swift.String",
                "Mod.Config.name.getter : Swift.String",
                "property descriptor for Mod.Config.name : Swift.String",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        let norm = normalizedInterface(interface)
        let count = norm.components(separatedBy: "var name").count - 1
        #expect(count == 1)
    }

    @Test
    func duplicateMethodsDeduped() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Service",
                "Mod.Service.run() -> ()",
                "Mod.Service.run() -> ()",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        let norm = normalizedInterface(interface)
        let count = norm.components(separatedBy: "func run").count - 1
        #expect(count == 1)
    }

    @Test
    func duplicateEnumCasesDeduped() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.State",
                "enum case for Mod.State.idle(Mod.State) -> Mod.State",
                "enum case for Mod.State.idle(Mod.State) -> Mod.State",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        let norm = normalizedInterface(interface)
        let count = norm.components(separatedBy: "case idle").count - 1
        #expect(count == 1)
    }

    @Test
    func keywordPropertyNameEscaped() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Rule",
                "property descriptor for Mod.Rule.default : Swift.String",
                "Mod.Rule.default.getter : Swift.String",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        #expect(normalizedInterface(interface).contains("var `default`: Swift.String"))
    }

    @Test
    func keywordMethodNameEscaped() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Builder",
                "Mod.Builder.return() -> Swift.String",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        #expect(normalizedInterface(interface).contains("func `return`() -> Swift.String"))
    }

    @Test
    func keywordEnumCaseNameEscaped() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Token",
                "enum case for Mod.Token.class(Mod.Token) -> Mod.Token",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        #expect(normalizedInterface(interface).contains("case `class`"))
    }

    @Test
    func genericWhereClauseWithParenthesizedTypeInInit() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Store",
                "Mod.Store.init<A, B where A: Swift.Sequence, B: Mod.Convertible, A.Element == (Swift.String, Mod.Convertible)>(properties: A, uniquingKeysWith: (Mod.Store, Mod.Store) throws -> B) throws -> Mod.Store",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        let norm = normalizedInterface(interface)
        #expect(norm.contains("public init<A, B>(properties: A, uniquingKeysWith: (Store, Store) throws -> B) throws where A : Swift.Sequence, B : Convertible, A.Element == (Swift.String, Convertible)"))
    }
}

// MARK: - Import Discovery

@Suite("Import discovery")
struct ImportDiscoveryTests {
    @Test
    func foundationImport() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Svc",
                "property descriptor for Mod.Svc.date : Foundation.Date",
                "Mod.Svc.date.getter : Foundation.Date",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )
        #expect(normalizedInterface(interface).contains("import Foundation"))
    }

    @Test
    func dispatchImport() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Svc",
                "Mod.Svc.run(queue: Dispatch.DispatchQueue) -> ()",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )
        #expect(normalizedInterface(interface).contains("import Dispatch"))
    }

    @Test
    func coreGraphicsImportViaCGType() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Widget",
                "property descriptor for Mod.Widget.frame : __C.CGRect",
                "Mod.Widget.frame.getter : __C.CGRect",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )
        #expect(normalizedInterface(interface).contains("import CoreGraphics"))
    }

    @Test
    func quartzCoreImport() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Renderer",
                "property descriptor for Mod.Renderer.transform : __C.CATransform3D",
                "Mod.Renderer.transform.getter : __C.CATransform3D",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )
        #expect(normalizedInterface(interface).contains("import QuartzCore"))
    }

    @Test
    func darwinImportViaAuditToken() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Conn",
                "property descriptor for Mod.Conn.token : __C.audit_token_t",
                "Mod.Conn.token.getter : __C.audit_token_t",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )
        #expect(normalizedInterface(interface).contains("import Darwin"))
    }

    @Test
    func noExtraImportsForSwiftOnlyTypes() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Simple",
                "property descriptor for Mod.Simple.value : Swift.Int",
                "Mod.Simple.value.getter : Swift.Int",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )
        let norm = normalizedInterface(interface)
        #expect(norm.contains("import Swift"))
        #expect(!norm.contains("import Foundation"))
        #expect(!norm.contains("import Dispatch"))
    }

    @Test
    func foundationImportViaObjCType() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Compat",
                "Mod.Compat.init(coder: __C.NSCoder) -> Mod.Compat?",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )
        #expect(normalizedInterface(interface).contains("import Foundation"))
    }

    @Test
    func genericPlaceholdersAndBuiltinsDoNotBecomeImports() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "protocol descriptor for Mod.PreferenceKey",
                "associated type descriptor for Mod.PreferenceKey.Value",
                "nominal type descriptor for Mod.Container",
                "Mod.Container.typeErased(_: Any.Type) -> Swift.Int",
                "Mod.Container.preferenceValue<A>(_: A1.Type) -> A1.Value where A1 : Mod.PreferenceKey",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        let norm = normalizedInterface(interface)
        #expect(norm.contains("import Swift"))
        #expect(!norm.contains("import Any"))
        #expect(!norm.contains("import A1"))
    }
}

// MARK: - Generic Type Inference

@Suite("Generic type inference")
struct GenericInferenceTests {
    @Test
    func singleGenericParameter() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Wrapper",
                "property descriptor for Mod.Wrapper.value : T",
                "Mod.Wrapper.value.getter : T",
                "Mod.Wrapper.init(value: T) -> Mod.Wrapper<T>",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )
        #expect(normalizedInterface(interface).contains("public struct Wrapper<T>"))
    }

    @Test
    func multipleGenericParameters() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Pair",
                "property descriptor for Mod.Pair.first : A",
                "Mod.Pair.first.getter : A",
                "property descriptor for Mod.Pair.second : B",
                "Mod.Pair.second.getter : B",
                "Mod.Pair.init(first: A, second: B) -> Mod.Pair<A, B>",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )
        #expect(normalizedInterface(interface).contains("public struct Pair<A, B>"))
    }

    @Test
    func genericParameterNotInferredFromModuleNames() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Response",
                "property descriptor for Mod.Response.ok : Swift.Bool",
                "Mod.Response.ok.getter : Swift.Bool",
                "property descriptor for Mod.Response.transcriptEntries : Swift.ArraySlice<Mod.Transcript.Entry>",
                "Mod.Response.transcriptEntries.getter : Swift.ArraySlice<Mod.Transcript.Entry>",
                "property descriptor for Mod.Response.content : A",
                "Mod.Response.content.getter : A",
                "Mod.Response.init(content: A) -> Mod.Response<A>",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        let norm = normalizedInterface(interface)
        #expect(norm.contains("public struct Response<A>"))
        #expect(!norm.contains("Response<Swift>"))
    }

    @Test
    func genericParameterNotInferredFromMethodName() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Stream",
                "Mod.Stream.makeIterator() -> Mod.Stream<A>.Iterator",
                "Mod.Stream.collect() async throws -> Mod.Response<A>",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        let norm = normalizedInterface(interface)
        // Generic parameter should be inferred as A (from usage), not makeIterator/collect
        #expect(norm.contains("public struct Stream<A>"))
        #expect(!norm.contains("Stream<makeIterator>"))
        #expect(!norm.contains("Stream<collect>"))
    }

    @Test
    func noGenericParametersForConcreteType() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Concrete",
                "property descriptor for Mod.Concrete.name : Swift.String",
                "Mod.Concrete.name.getter : Swift.String",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )
        #expect(normalizedInterface(interface).contains("public struct Concrete {"))
    }
}

// MARK: - ObjC Type Remapping

@Suite("ObjC type remapping in rendering")
struct ObjCRemappingTests {
    @Test
    func cgRectRemapped() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.View",
                "property descriptor for Mod.View.frame : __C.CGRect",
                "Mod.View.frame.getter : __C.CGRect",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )
        #expect(normalizedInterface(interface).contains("CoreGraphics.CGRect"))
        #expect(!normalizedInterface(interface).contains("__C.CGRect"))
    }

    @Test
    func nsCoderRemapped() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Widget",
                "metaclass for Mod.Widget",
                "Mod.Widget.init(coder: __C.NSCoder) -> Mod.Widget?",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )
        #expect(normalizedInterface(interface).contains("Foundation.NSCoder"))
        #expect(!normalizedInterface(interface).contains("__C.NSCoder"))
    }

    @Test
    func caTransform3DRemapped() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Layer",
                "property descriptor for Mod.Layer.transform : __C.CATransform3D",
                "Mod.Layer.transform.getter : __C.CATransform3D",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )
        #expect(normalizedInterface(interface).contains("QuartzCore.CATransform3D"))
    }

    @Test
    func auditTokenRemapped() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Conn",
                "property descriptor for Mod.Conn.token : __C.audit_token_t",
                "Mod.Conn.token.getter : __C.audit_token_t",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )
        #expect(normalizedInterface(interface).contains("Darwin.audit_token_t"))
    }
}

// MARK: - Complex Scenarios

@Suite("Complex rendering scenarios")
struct ComplexRenderingTests {
    @Test
    func structWithInitPropertiesAndMethods() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.User",
                "protocol conformance descriptor for Mod.User : Swift.Sendable in Mod",
                "property descriptor for Mod.User.name : Swift.String",
                "Mod.User.name.getter : Swift.String",
                "Mod.User.name.setter : (Swift.String) -> ()",
                "property descriptor for Mod.User.age : Swift.Int",
                "Mod.User.age.getter : Swift.Int",
                "Mod.User.init(name: Swift.String, age: Swift.Int) -> Mod.User",
                "Mod.User.greet() -> Swift.String",
                "static Mod.User.anonymous() -> Mod.User",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        #expect(
            normalizedInterface(interface)
                == normalizedInterface(
                    """
                // swift-interface-format-version: 1.0
                // swift-compiler-version: Test
                // swift-module-flags: -target arm64-apple-macosx15.0 -enable-library-evolution -module-name Mod
                import Swift

                public struct User: Swift.Sendable {
                  public var name: Swift.String { get set }
                  public var age: Swift.Int { get }
                  public init(name: Swift.String, age: Swift.Int)
                  public func greet() -> Swift.String
                  public static func anonymous() -> User
                }
                """
                )
        )
    }

    @Test
    func deeplyNestedTypes() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.A",
                "nominal type descriptor for Mod.A.B",
                "nominal type descriptor for Mod.A.B.C",
                "property descriptor for Mod.A.B.C.value : Swift.Int",
                "Mod.A.B.C.value.getter : Swift.Int",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        let norm = normalizedInterface(interface)
        #expect(norm.contains("public struct A {"))
        #expect(norm.contains("  public struct B {"))
        #expect(norm.contains("    public struct C {"))
        #expect(norm.contains("      public var value: Swift.Int { get }"))
    }

    @Test
    func multipleConformancesRendered() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Item",
                "protocol conformance descriptor for Mod.Item : Swift.Codable in Mod",
                "protocol conformance descriptor for Mod.Item : Swift.Hashable in Mod",
                "protocol conformance descriptor for Mod.Item : Swift.Sendable in Mod",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        #expect(normalizedInterface(interface).contains(": Swift.Codable, Swift.Hashable, Swift.Sendable"))
    }

    @Test
    func methodWithGenericReturnType() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Container",
                "property descriptor for Mod.Container.value : T",
                "Mod.Container.value.getter : T",
                "Mod.Container.init(value: T) -> Mod.Container<T>",
                "Mod.Container.map(transform: (T) -> U) -> Mod.Container<U>",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        let norm = normalizedInterface(interface)
        #expect(norm.contains("public struct Container<T>"))
        #expect(norm.contains("public func map(transform: (T) -> U) -> Container<U>"))
    }

    @Test
    func protocolInitRequirementRenderedAsInit() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "protocol descriptor for Mod.Convertible",
                "method descriptor for Mod.Convertible.init(value: Swift.String) -> A",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        let norm = normalizedInterface(interface)
        #expect(norm.contains("  init(value: Swift.String)"))
        #expect(!norm.contains("func `init`"))
    }

    @Test
    func protocolMembersWithoutPublicPrefix() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "protocol descriptor for Mod.Configurable",
                "associated type descriptor for Mod.Configurable.Config",
                "method descriptor for Mod.Configurable.configure(with: Mod.Configurable.Config) -> ()",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        let norm = normalizedInterface(interface)
        #expect(norm.contains("  associatedtype Config"))
        #expect(norm.contains("  func configure(with: Configurable.Config)"))
        #expect(!norm.contains("public func configure"))
        #expect(!norm.contains("public associatedtype"))
    }

    @Test
    func enumWithMultiplePayloadTypes() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Value",
                "enum case for Mod.Value.integer(Mod.Value) -> (Swift.Int) -> Mod.Value",
                "enum case for Mod.Value.string(Mod.Value) -> (Swift.String) -> Mod.Value",
                "enum case for Mod.Value.pair(Mod.Value) -> (Swift.Int, Swift.String) -> Mod.Value",
                "enum case for Mod.Value.null(Mod.Value) -> Mod.Value",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        #expect(
            normalizedInterface(interface)
                == normalizedInterface(
                    """
                // swift-interface-format-version: 1.0
                // swift-compiler-version: Test
                // swift-module-flags: -target arm64-apple-macosx15.0 -enable-library-evolution -module-name Mod
                import Swift

                public enum Value {
                  case integer(Swift.Int)
                  case string(Swift.String)
                  case pair(Swift.Int, Swift.String)
                  case null
                }
                """
                )
        )
    }

    @Test
    func regionPropertyAndInitializerRendered() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.View",
                "property descriptor for Mod.View.name : Swift.String",
                "Mod.View.name.getter : Swift.String",
                "property descriptor for Mod.View.visibleRegion : CoreGraphics.Region?",
                "Mod.View.visibleRegion.getter : CoreGraphics.Region?",
                "Mod.View.visibleRegion.setter : CoreGraphics.Region?",
                "Mod.View.init(visibleRegion: CoreGraphics.Region?) -> Mod.View",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        let norm = normalizedInterface(interface)
        #expect(norm.contains("var name"))
        #expect(norm.contains("public var visibleRegion: CoreGraphics.Region? { get set }"))
        #expect(norm.contains("public init(visibleRegion: CoreGraphics.Region?)"))
    }

    @Test
    func constrainedMethodFilteredOut() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Box",
                "property descriptor for Mod.Box.value : T",
                "Mod.Box.value.getter : T",
                "Mod.Box.init(value: T) -> Mod.Box<T>",
                "Mod.Box.unwrap() -> T where Mod.Box.T == Swift.Optional<U>",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        let norm = normalizedInterface(interface)
        #expect(!norm.contains("unwrap"))
    }

    @Test
    func genericMethodRenderedWithWhereClause() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Session",
                "metaclass for Mod.Session",
                "Mod.Session.respond<A where A: Mod.Generable>(to: Swift.String, generating: A.Type) async throws -> Mod.Session.Response<A>",
                "Mod.Session.init<A where A: Mod.Generable>(format: A.Type) -> Mod.Session",
                "static Mod.Session.maximumCount<A where A == [A1]>(Swift.Int) -> Mod.Guide<[A1]>",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        let norm = normalizedInterface(interface)
        #expect(norm.contains("public func respond<A>(to: Swift.String, generating: A.Type) async throws -> Session.Response<A> where A : Generable"))
        #expect(norm.contains("public init<A>(format: A.Type) where A : Generable"))
        #expect(norm.contains("public static func maximumCount<A1>(_: Swift.Int) -> Guide<[A1]> where A == [A1]"))
    }

    @Test
    func genericMethodDoesNotCreateSpuriousDeclarations() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Session",
                "Mod.Session.respond<A where A: Mod.Generable>(to: Swift.String) async throws -> Mod.Session.Response<A>",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        let norm = normalizedInterface(interface)
        // Should only have one struct declaration — Session — not a spurious "respond<A where A: Mod" type
        let structCount = norm.components(separatedBy: "public struct").count - 1
        + norm.components(separatedBy: "public final class").count - 1
        #expect(structCount <= 1)
    }

    @Test
    func methodWithClosureParameterAndImplicitVoidReturn() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Task",
                "Mod.Task.configure(handler: () -> ())",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        let norm = normalizedInterface(interface)
        #expect(norm.contains("public func configure(handler: () -> ())"))
        #expect(!norm.contains("public func configure(handler: () -> ()) -> "))
    }

    @Test
    func ownedParameterAnnotationStripped() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Store",
                "property descriptor for Mod.Store.item : __owned Swift.String",
                "Mod.Store.item.getter : __owned Swift.String",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        let norm = normalizedInterface(interface)
        #expect(norm.contains("var item: Swift.String"))
        #expect(!norm.contains("__owned"))
    }

    @Test
    func protocolMethodsUsesSelfForAssociatedTypes() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "protocol descriptor for Mod.Tool",
                "associated type descriptor for Mod.Tool.Arguments",
                "associated type descriptor for Mod.Tool.Output",
                "method descriptor for Mod.Tool.call(arguments: A.Arguments) async throws -> A.Output",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        let norm = normalizedInterface(interface)
        #expect(norm.contains("func call(arguments: Self.Arguments) async throws -> Self.Output"))
        #expect(!norm.contains("Tool.Arguments"))
        #expect(!norm.contains("Tool.Output"))
    }

    @Test
    func genericMethodOnGenericTypeDeclaresCorrectParams() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Guide",
                "static Mod.Guide.maximumCount<A where A == [A1]>(Swift.Int) -> Mod.Guide<[A1]>",
                "static Mod.Guide.element<A where A == [A1]>(Mod.Guide<A1>) -> Mod.Guide<[A1]>",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        let norm = normalizedInterface(interface)
        // A1 should be declared as the method generic param, not A
        #expect(norm.contains("static func maximumCount<A1>"))
        #expect(norm.contains("static func element<A1>"))
        // The where clause should still reference A (parent) and A1 (method)
        #expect(norm.contains("where A == [A1]"))
    }

    @Test
    func sameModuleConstrainedExtensionMethodsRenderOnConcreteType() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.GenerationGuide",
                "static (extension in Mod):Mod.GenerationGuide<A where A == Swift.String>.anyOf([Swift.String]) -> Mod.GenerationGuide<Swift.String>",
                "static (extension in Mod):Mod.GenerationGuide<A where A == Swift.Int>.minimum(Swift.Int) -> Mod.GenerationGuide<Swift.Int>",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        let norm = normalizedInterface(interface)
        #expect(norm.contains("public struct GenerationGuide<A>"))
        #expect(norm.contains("public static func anyOf(_: [Swift.String]) -> GenerationGuide<Swift.String> where A == Swift.String"))
        #expect(norm.contains("public static func minimum(_: Swift.Int) -> GenerationGuide<Swift.Int> where A == Swift.Int"))
    }

    @Test
    func missingModuleImportsDetected() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.MyModel",
                "protocol conformance descriptor for Mod.MyModel : Observation.Observable in Mod",
                "nominal type descriptor for Mod.Adapter",
                "Mod.Adapter.init(fileURL: Foundation.URL) -> Mod.Adapter",
                "static Mod.Adapter.isCompatible(BackgroundAssets.AssetPack) -> Swift.Bool",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        let norm = normalizedInterface(interface)
        #expect(norm.contains("import Observation"))
        #expect(norm.contains("import BackgroundAssets"))
    }

    @Test
    func underscoreStringProcessingRegexUsesStringProcessingImport() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Schema",
                "Mod.Schema.init<A>(pattern: _StringProcessing.Regex<A>) -> Mod.Schema",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        let norm = normalizedInterface(interface)
        #expect(norm.contains("import _StringProcessing"))
        #expect(norm.contains("_StringProcessing.Regex<A>"))
        #expect(!norm.contains("Swift.Regex"))
    }

    @Test
    func packExpansionUsesEachInArgumentsAndConstraints() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "protocol descriptor for Mod.Fragment",
                "nominal type descriptor for Mod.Builder",
                "Mod.Builder.init<each A where A: Mod.Fragment>(repeat A) -> Mod.Builder",
                "Mod.Builder.append<each A where A: Mod.Fragment>(repeat A) -> Mod.Builder",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        let norm = normalizedInterface(interface)
        #expect(norm.contains("public init<each A>(_: repeat each A) where repeat each A : Fragment"))
        #expect(
            norm.contains(
                "public func append<each A>(_: repeat each A) -> Builder where repeat each A : Fragment"
            )
        )
    }

    @Test
    func asyncConformancesAttachToNestedTypesAndImportConcurrency() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Stream",
                "nominal type descriptor for Mod.Stream.AsyncIterator",
                "protocol conformance descriptor for Mod.Stream<A>.AsyncIterator : Swift.AsyncIteratorProtocol in Mod",
                "protocol conformance descriptor for Mod.Stream<A> : Swift.AsyncSequence in Mod",
                "static Mod.Stream.make() -> Mod.Stream<A>",
                "Mod.Stream.AsyncIterator.next(isolation: isolated Swift.Actor?) async throws -> Swift.Int?",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        let norm = normalizedInterface(interface)
        #expect(norm.contains("import _Concurrency"))
        #expect(norm.contains("public struct Stream<A>: _Concurrency.AsyncSequence {"))
        #expect(norm.contains("public struct AsyncIterator: _Concurrency.AsyncIteratorProtocol {"))
        #expect(norm.contains("public func next(isolation: isolated _Concurrency.Actor?) async throws -> Swift.Int?"))
        #expect(!norm.contains("Swift.AsyncSequence"))
        #expect(!norm.contains("Swift.AsyncIteratorProtocol"))
        #expect(!norm.contains("Swift.Actor"))
    }

    @Test
    func keywordNamedNestedTypesAreEscapedInDeclarationsAndTypeReferences() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Server",
                "nominal type descriptor for Mod.Server.Protocol",
                "property descriptor for static Mod.Server.Protocol.shared : Mod.Server.Protocol",
                "static Mod.Server.Protocol.shared.getter : Mod.Server.Protocol",
                "Mod.Server.init(protocol: Mod.Server.Protocol) -> Mod.Server",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        let norm = normalizedInterface(interface)
        #expect(norm.contains("public struct `Protocol` {"))
        #expect(norm.contains("public static var shared: Server.`Protocol` { get }"))
        #expect(norm.contains("public init(`protocol`: Server.`Protocol`)"))
    }

    @Test
    func unsupportedExternalModuleMembersAreFilteredOut() {
        let filteringBuilder = SwiftInterfaceBuilder(renderableExternalModules: [])
        let interface = filteringBuilder.makeInterface(
            demangledSymbols: [
                "nominal type descriptor for Mod.Schema",
                "Mod.Schema.init(schema: HiddenFramework.Node, source: Swift.String) -> Mod.Schema",
                "Mod.Schema.node() -> HiddenFramework.Node",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        let norm = normalizedInterface(interface)
        #expect(!norm.contains("HiddenFramework"))
        #expect(!norm.contains("init(schema:"))
        #expect(!norm.contains("func node"))
    }

    @Test
    func unresolvedAssociatedTypeMembersAreFilteredOut() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "protocol descriptor for Mod.Transformable",
                "associated type descriptor for Mod.Transformable.Part",
                "nominal type descriptor for Mod.Stream",
                "nominal type descriptor for Mod.Stream.Snapshot",
                "property descriptor for Mod.Stream.Snapshot.value : T.Part",
                "Mod.Stream.Snapshot.value.getter : T.Part",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        let norm = normalizedInterface(interface)
        #expect(!norm.contains("var value"))
    }

    @Test
    func generableStyleConformersGetSelfPartiallyGeneratedTypealias() {
        let interface = renderingBuilder.makeInterface(
            demangledSymbols: [
                "protocol descriptor for Mod.Generable",
                "associated type descriptor for Mod.Generable.PartiallyGenerated",
                "nominal type descriptor for Mod.Payload",
                "protocol conformance descriptor for Mod.Payload : Mod.Generable in Mod",
            ],
            targetTriple: "arm64-apple-macosx15.0",
            moduleName: "Mod",
            compilerVersion: "Test"
        )

        let norm = normalizedInterface(interface)
        #expect(norm.contains("associatedtype PartiallyGenerated"))
        #expect(norm.contains("public typealias PartiallyGenerated = Self"))
    }
}
