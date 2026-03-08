import Foundation
import Testing
@testable import SwiftInterfaceGenerator

@Suite("Integration Tests")
struct IntegrationTests {

    // MARK: - Structs

    @Test
    func simpleStructWithMutableProperties() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "StructFixture",
            sources: [
                "StructFixture.swift": """
                public struct Point {
                    public var x: Double
                    public var y: Double

                    public init(x: Double, y: Double) {
                        self.x = x
                        self.y = y
                    }
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)

        #expect(
            normalizedInterface(contents)
                == normalizedInterface(
                    """
                // swift-interface-format-version: 1.0
                // swift-compiler-version: Integration Test Swift
                // swift-module-flags: -target \(fixture.targetTriple) -enable-library-evolution -module-name StructFixture
                import Swift

                public struct Point {
                  public var x: Swift.Double { get set }
                  public var y: Swift.Double { get set }
                  public init(x: Swift.Double, y: Swift.Double)
                }
                """
                )
        )
    }

    @Test
    func structWithGetOnlyProperties() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "GetOnlyFixture",
            sources: [
                "GetOnlyFixture.swift": """
                public struct Config {
                    public let name: String
                    public let count: Int

                    public init(name: String, count: Int) {
                        self.name = name
                        self.count = count
                    }
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)

        #expect(
            normalizedInterface(contents)
                == normalizedInterface(
                    """
                // swift-interface-format-version: 1.0
                // swift-compiler-version: Integration Test Swift
                // swift-module-flags: -target \(fixture.targetTriple) -enable-library-evolution -module-name GetOnlyFixture
                import Swift

                public struct Config {
                  public var name: Swift.String { get }
                  public var count: Swift.Int { get }
                  public init(name: Swift.String, count: Swift.Int)
                }
                """
                )
        )
    }

    @Test
    func emptyStruct() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "EmptyFixture",
            sources: [
                "EmptyFixture.swift": """
                public struct Empty {}
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)

        #expect(
            normalizedInterface(contents)
                == normalizedInterface(
                    """
                // swift-interface-format-version: 1.0
                // swift-compiler-version: Integration Test Swift
                // swift-module-flags: -target \(fixture.targetTriple) -enable-library-evolution -module-name EmptyFixture
                import Swift

                public struct Empty {
                }
                """
                )
        )
    }

    @Test
    func structWithStaticAndInstanceMembers() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "StaticFixture",
            sources: [
                "StaticFixture.swift": """
                public struct Factory {
                    public let name: String

                    public static func make(name: String) -> Factory {
                        Factory(name: name)
                    }

                    public init(name: String) {
                        self.name = name
                    }
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)

        #expect(
            normalizedInterface(contents)
                == normalizedInterface(
                    """
                // swift-interface-format-version: 1.0
                // swift-compiler-version: Integration Test Swift
                // swift-module-flags: -target \(fixture.targetTriple) -enable-library-evolution -module-name StaticFixture
                import Swift

                public struct Factory {
                  public var name: Swift.String { get }
                  public init(name: Swift.String)
                  public static func make(name: Swift.String) -> Factory
                }
                """
                )
        )
    }

    // MARK: - Enums

    @Test
    func simpleEnum() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "EnumFixture",
            sources: [
                "EnumFixture.swift": """
                public enum TrafficLight {
                    case red
                    case yellow
                    case green
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)

        #expect(
            normalizedInterface(contents)
                == normalizedInterface(
                    """
                // swift-interface-format-version: 1.0
                // swift-compiler-version: Integration Test Swift
                // swift-module-flags: -target \(fixture.targetTriple) -enable-library-evolution -module-name EnumFixture
                import Swift

                public enum TrafficLight: Swift.Hashable {
                  case red
                  case green
                  case yellow
                  public var hashValue: Swift.Int { get }
                  public func hash(into: inout Swift.Hasher)
                }
                """
                )
        )
    }

    @Test
    func enumWithAssociatedValues() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "AssocEnumFixture",
            sources: [
                "AssocEnumFixture.swift": """
                public enum Outcome {
                    case success(String)
                    case failure(Int, String)
                    case pending
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)

        #expect(
            normalizedInterface(contents)
                == normalizedInterface(
                    """
                // swift-interface-format-version: 1.0
                // swift-compiler-version: Integration Test Swift
                // swift-module-flags: -target \(fixture.targetTriple) -enable-library-evolution -module-name AssocEnumFixture
                import Swift

                public enum Outcome {
                  case failure(Swift.Int, Swift.String)
                  case pending
                  case success(Swift.String)
                }
                """
                )
        )
    }

    @Test
    func enumWithMethod() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "EnumMethodFixture",
            sources: [
                "EnumMethodFixture.swift": """
                public enum Direction {
                    case north
                    case south

                    public func opposite() -> Direction {
                        switch self {
                        case .north: return .south
                        case .south: return .north
                        }
                    }
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)

        #expect(
            normalizedInterface(contents)
                == normalizedInterface(
                    """
                // swift-interface-format-version: 1.0
                // swift-compiler-version: Integration Test Swift
                // swift-module-flags: -target \(fixture.targetTriple) -enable-library-evolution -module-name EnumMethodFixture
                import Swift

                public enum Direction: Swift.Hashable {
                  case north
                  case south
                  public var hashValue: Swift.Int { get }
                  public func hash(into: inout Swift.Hasher)
                  public func opposite() -> Direction
                }
                """
                )
        )
    }

    // MARK: - Classes

    @Test
    func finalClass() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "ClassFixture",
            sources: [
                "ClassFixture.swift": """
                public final class Controller {
                    public var title: String

                    public init(title: String) {
                        self.title = title
                    }

                    public func render() -> String {
                        return title
                    }
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)

        #expect(
            normalizedInterface(contents)
                == normalizedInterface(
                    """
                // swift-interface-format-version: 1.0
                // swift-compiler-version: Integration Test Swift
                // swift-module-flags: -target \(fixture.targetTriple) -enable-library-evolution -module-name ClassFixture
                import Swift

                public final class Controller {
                  public var title: Swift.String { get set }
                  public init(title: Swift.String)
                  public func render() -> Swift.String
                }
                """
                )
        )
    }

    @Test
    func classWithStaticSharedInstance() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "SingletonFixture",
            sources: [
                "SingletonFixture.swift": """
                public final class Manager {
                    public static let shared = Manager()

                    public init() {}

                    public func reset() {}
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)

        #expect(
            normalizedInterface(contents)
                == normalizedInterface(
                    """
                // swift-interface-format-version: 1.0
                // swift-compiler-version: Integration Test Swift
                // swift-module-flags: -target \(fixture.targetTriple) -enable-library-evolution -module-name SingletonFixture
                import Swift

                public final class Manager {
                  public static var shared: Manager { get }
                  public init()
                  public func reset()
                }
                """
                )
        )
    }

    @Test
    func nonFinalClassRenderedAsFinal() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "OpenClassFixture",
            sources: [
                "OpenClassFixture.swift": """
                open class Vehicle {
                    public var speed: Int

                    public init(speed: Int) {
                        self.speed = speed
                    }

                    open func accelerate() -> Int {
                        return speed + 1
                    }
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)

        #expect(
            normalizedInterface(contents)
                == normalizedInterface(
                    """
                // swift-interface-format-version: 1.0
                // swift-compiler-version: Integration Test Swift
                // swift-module-flags: -target \(fixture.targetTriple) -enable-library-evolution -module-name OpenClassFixture
                import Swift

                open class Vehicle {
                  public var speed: Swift.Int { get set }
                  public init(speed: Swift.Int)
                  public func accelerate() -> Swift.Int
                }
                """
                )
        )
    }

    // MARK: - Protocols

    @Test
    func simpleProtocol() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "ProtoFixture",
            sources: [
                "ProtoFixture.swift": """
                public protocol Greeter {
                    func greet(name: String) -> String
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)

        #expect(
            normalizedInterface(contents)
                == normalizedInterface(
                    """
                // swift-interface-format-version: 1.0
                // swift-compiler-version: Integration Test Swift
                // swift-module-flags: -target \(fixture.targetTriple) -enable-library-evolution -module-name ProtoFixture
                import Swift

                public protocol Greeter {
                  func greet(name: Swift.String) -> Swift.String
                }
                """
                )
        )
    }

    @Test
    func protocolWithAssociatedType() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "AssocTypeFixture",
            sources: [
                "AssocTypeFixture.swift": """
                public protocol Repository {
                    associatedtype Item
                    func fetch(id: Int) -> Item
                    func store(item: Item) -> Bool
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)

        #expect(
            normalizedInterface(contents)
                == normalizedInterface(
                    """
                // swift-interface-format-version: 1.0
                // swift-compiler-version: Integration Test Swift
                // swift-module-flags: -target \(fixture.targetTriple) -enable-library-evolution -module-name AssocTypeFixture
                import Swift

                public protocol Repository {
                  associatedtype Item
                  func fetch(id: Swift.Int) -> Self.Item
                  func store(item: Self.Item) -> Swift.Bool
                }
                """
                )
        )
    }

    @Test
    func protocolWithMultipleAssociatedTypes() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "MultiAssocFixture",
            sources: [
                "MultiAssocFixture.swift": """
                public protocol DataSource {
                    associatedtype Item
                    associatedtype Section
                    func item(at: Int) -> Item
                    func section(at: Int) -> Section
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)

        #expect(
            normalizedInterface(contents)
                == normalizedInterface(
                    """
                // swift-interface-format-version: 1.0
                // swift-compiler-version: Integration Test Swift
                // swift-module-flags: -target \(fixture.targetTriple) -enable-library-evolution -module-name MultiAssocFixture
                import Swift

                public protocol DataSource {
                  associatedtype Item
                  associatedtype Section
                  func item(at: Swift.Int) -> Self.Item
                  func section(at: Swift.Int) -> Self.Section
                }
                """
                )
        )
    }

    @Test
    func protocolParameterGetsAnyPrefix() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "AnyProtoFixture",
            sources: [
                "AnyProtoFixture.swift": """
                public protocol Handler {
                    func handle()
                }

                public struct Router {
                    public init() {}

                    public func add(handler: any Handler) {}
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)

        #expect(
            normalizedInterface(contents)
                == normalizedInterface(
                    """
                // swift-interface-format-version: 1.0
                // swift-compiler-version: Integration Test Swift
                // swift-module-flags: -target \(fixture.targetTriple) -enable-library-evolution -module-name AnyProtoFixture
                import Swift

                public struct Router {
                  public init()
                  public func add(handler: any Handler)
                }

                public protocol Handler {
                  func handle()
                }
                """
                )
        )
    }

    // MARK: - Conformances

    @Test
    func codableConformanceMergesEncodableAndDecodable() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "CodableFixture",
            sources: [
                "CodableFixture.swift": """
                public struct Token: Codable {
                    public let value: String

                    public init(value: String) {
                        self.value = value
                    }
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)

        #expect(
            normalizedInterface(contents)
                == normalizedInterface(
                    """
                // swift-interface-format-version: 1.0
                // swift-compiler-version: Integration Test Swift
                // swift-module-flags: -target \(fixture.targetTriple) -enable-library-evolution -module-name CodableFixture
                import Swift

                public struct Token: Swift.Codable {
                  public var value: Swift.String { get }
                  public init(from: Swift.Decoder) throws
                  public init(value: Swift.String)
                  public func encode(to: Swift.Encoder) throws
                }
                """
                )
        )
    }

    @Test
    func hashableAbsorbsEquatable() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "HashableFixture",
            sources: [
                "HashableFixture.swift": """
                public struct ID: Hashable {
                    public let rawValue: String

                    public init(rawValue: String) {
                        self.rawValue = rawValue
                    }
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)

        #expect(
            normalizedInterface(contents)
                == normalizedInterface(
                    """
                // swift-interface-format-version: 1.0
                // swift-compiler-version: Integration Test Swift
                // swift-module-flags: -target \(fixture.targetTriple) -enable-library-evolution -module-name HashableFixture
                import Swift

                public struct ID: Swift.Hashable {
                  public var rawValue: Swift.String { get }
                  public var hashValue: Swift.Int { get }
                  public init(rawValue: Swift.String)
                  public func hash(into: inout Swift.Hasher)
                }
                """
                )
        )
    }

    @Test
    func codableAndHashableConformances() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "MultiConformFixture",
            sources: [
                "MultiConformFixture.swift": """
                public struct Item: Codable, Hashable {
                    public let id: Int

                    public init(id: Int) {
                        self.id = id
                    }
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)

        #expect(
            normalizedInterface(contents)
                == normalizedInterface(
                    """
                // swift-interface-format-version: 1.0
                // swift-compiler-version: Integration Test Swift
                // swift-module-flags: -target \(fixture.targetTriple) -enable-library-evolution -module-name MultiConformFixture
                import Swift

                public struct Item: Swift.Codable, Swift.Hashable {
                  public var id: Swift.Int { get }
                  public var hashValue: Swift.Int { get }
                  public init(id: Swift.Int)
                  public init(from: Swift.Decoder) throws
                  public func hash(into: inout Swift.Hasher)
                  public func encode(to: Swift.Encoder) throws
                }
                """
                )
        )
    }

    // MARK: - Foundation Types

    @Test
    func foundationBackedStruct() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "RecordFixture",
            sources: [
                "RecordFixture.swift": """
                import Foundation

                public protocol Greeter {
                    func greet(name: String) -> String
                }

                public struct Record: Codable {
                    public let id: UUID
                    public let createdAt: Date

                    public init(id: UUID, createdAt: Date) {
                        self.id = id
                        self.createdAt = createdAt
                    }
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)

        #expect(
            normalizedInterface(contents)
                == normalizedInterface(
                    """
                // swift-interface-format-version: 1.0
                // swift-compiler-version: Integration Test Swift
                // swift-module-flags: -target \(fixture.targetTriple) -enable-library-evolution -module-name RecordFixture
                import Swift
                import Foundation

                public struct Record: Swift.Codable {
                  public var id: Foundation.UUID { get }
                  public var createdAt: Foundation.Date { get }
                  public init(id: Foundation.UUID, createdAt: Foundation.Date)
                  public init(from: Swift.Decoder) throws
                  public func encode(to: Swift.Encoder) throws
                }

                public protocol Greeter {
                  func greet(name: Swift.String) -> Swift.String
                }
                """
                )
        )
    }

    // MARK: - Nested Types

    @Test
    func nestedStruct() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "NestedFixture",
            sources: [
                "NestedFixture.swift": """
                public struct Outer {
                    public struct Inner {
                        public let value: Int

                        public init(value: Int) {
                            self.value = value
                        }
                    }

                    public let inner: Inner

                    public init(inner: Inner) {
                        self.inner = inner
                    }
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)

        #expect(
            normalizedInterface(contents)
                == normalizedInterface(
                    """
                // swift-interface-format-version: 1.0
                // swift-compiler-version: Integration Test Swift
                // swift-module-flags: -target \(fixture.targetTriple) -enable-library-evolution -module-name NestedFixture
                import Swift

                public struct Outer {
                  public struct Inner {
                    public var value: Swift.Int { get }
                    public init(value: Swift.Int)
                  }

                  public var inner: Outer.Inner { get }
                  public init(inner: Outer.Inner)
                }
                """
                )
        )
    }

    @Test
    func nestedEnum() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "NestedEnumFixture",
            sources: [
                "NestedEnumFixture.swift": """
                public struct Container {
                    public enum Status {
                        case active
                        case inactive
                    }

                    public let status: Status

                    public init(status: Status) {
                        self.status = status
                    }
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)

        #expect(
            normalizedInterface(contents)
                == normalizedInterface(
                    """
                // swift-interface-format-version: 1.0
                // swift-compiler-version: Integration Test Swift
                // swift-module-flags: -target \(fixture.targetTriple) -enable-library-evolution -module-name NestedEnumFixture
                import Swift

                public struct Container {
                  public enum Status: Swift.Hashable {
                    case active
                    case inactive
                    public var hashValue: Swift.Int { get }
                    public func hash(into: inout Swift.Hasher)
                  }

                  public var status: Container.Status { get }
                  public init(status: Container.Status)
                }
                """
                )
        )
    }

    // MARK: - Generics

    @Test
    func genericStruct() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "GenericFixture",
            sources: [
                "GenericFixture.swift": """
                public struct Box<T> {
                    public let value: T

                    public init(value: T) {
                        self.value = value
                    }
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)

        #expect(
            normalizedInterface(contents)
                == normalizedInterface(
                    """
                // swift-interface-format-version: 1.0
                // swift-compiler-version: Integration Test Swift
                // swift-module-flags: -target \(fixture.targetTriple) -enable-library-evolution -module-name GenericFixture
                import Swift

                public struct Box<A> {
                  public var value: A { get }
                  public init(value: A)
                }
                """
                )
        )
    }

    @Test
    func genericWithMultipleParameters() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "MultiGenericFixture",
            sources: [
                "MultiGenericFixture.swift": """
                public struct Pair<A, B> {
                    public let first: A
                    public let second: B

                    public init(first: A, second: B) {
                        self.first = first
                        self.second = second
                    }
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)

        #expect(
            normalizedInterface(contents)
                == normalizedInterface(
                    """
                // swift-interface-format-version: 1.0
                // swift-compiler-version: Integration Test Swift
                // swift-module-flags: -target \(fixture.targetTriple) -enable-library-evolution -module-name MultiGenericFixture
                import Swift

                public struct Pair<A, B> {
                  public var first: A { get }
                  public var second: B { get }
                  public init(first: A, second: B)
                }
                """
                )
        )
    }

    @Test
    func constrainedGenericStructKeepsAssociatedTypeOwnerConstraint() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "ConstrainedGenericFixture",
            sources: [
                "ConstrainedGenericFixture.swift": """
                public protocol HostedValue {
                    associatedtype Host
                    associatedtype Coordinator
                }

                public struct LeafRecord<Content: HostedValue> {
                    public let content: Content

                    public init(content: Content, host: Content.Host, coordinator: Content.Coordinator) {
                        self.content = content
                    }
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)
        let normalized = normalizedInterface(contents)

        #expect(
            normalized.contains("public struct LeafRecord<A : HostedValue> {")
                || normalized.contains("public struct LeafRecord<A> where A : HostedValue {")
        )
        #expect(normalized.contains("public init(content: A, host: A.Host, coordinator: A.Coordinator)"))
        #expect(!normalized.contains("public struct LeafRecord<A> {"))
    }

    // MARK: - Method Effects

    @Test
    func methodReturningVoidOmitsReturnClause() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "VoidMethodFixture",
            sources: [
                "VoidMethodFixture.swift": """
                public struct Service {
                    public init() {}

                    public func reset() {}
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)

        #expect(
            normalizedInterface(contents)
                == normalizedInterface(
                    """
                // swift-interface-format-version: 1.0
                // swift-compiler-version: Integration Test Swift
                // swift-module-flags: -target \(fixture.targetTriple) -enable-library-evolution -module-name VoidMethodFixture
                import Swift

                public struct Service {
                  public init()
                  public func reset()
                }
                """
                )
        )
    }

    @Test
    func throwingMethod() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "ThrowsFixture",
            sources: [
                "ThrowsFixture.swift": """
                public struct Loader {
                    public init() {}

                    public func load(path: String) throws -> String {
                        return path
                    }
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)

        #expect(
            normalizedInterface(contents)
                == normalizedInterface(
                    """
                // swift-interface-format-version: 1.0
                // swift-compiler-version: Integration Test Swift
                // swift-module-flags: -target \(fixture.targetTriple) -enable-library-evolution -module-name ThrowsFixture
                import Swift

                public struct Loader {
                  public init()
                  public func load(path: Swift.String) throws -> Swift.String
                }
                """
                )
        )
    }

    @Test
    func asyncMethod() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "AsyncFixture",
            sources: [
                "AsyncFixture.swift": """
                public struct Fetcher {
                    public init() {}

                    public func fetch() async -> String {
                        return ""
                    }
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)

        #expect(
            normalizedInterface(contents)
                == normalizedInterface(
                    """
                // swift-interface-format-version: 1.0
                // swift-compiler-version: Integration Test Swift
                // swift-module-flags: -target \(fixture.targetTriple) -enable-library-evolution -module-name AsyncFixture
                import Swift

                public struct Fetcher {
                  public init()
                  public func fetch() async -> Swift.String
                }
                """
                )
        )
    }

    @Test
    func asyncThrowingMethod() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "AsyncThrowsFixture",
            sources: [
                "AsyncThrowsFixture.swift": """
                public struct API {
                    public init() {}

                    public func request(url: String) async throws -> String {
                        return url
                    }
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)

        #expect(
            normalizedInterface(contents)
                == normalizedInterface(
                    """
                // swift-interface-format-version: 1.0
                // swift-compiler-version: Integration Test Swift
                // swift-module-flags: -target \(fixture.targetTriple) -enable-library-evolution -module-name AsyncThrowsFixture
                import Swift

                public struct API {
                  public init()
                  public func request(url: Swift.String) async throws -> Swift.String
                }
                """
                )
        )
    }

    // MARK: - Initializers

    @Test
    func failableInitializer() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "FailableInitFixture",
            sources: [
                "FailableInitFixture.swift": """
                public struct Parser {
                    public let raw: String

                    public init?(raw: String) {
                        guard !raw.isEmpty else { return nil }
                        self.raw = raw
                    }
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)

        #expect(
            normalizedInterface(contents)
                == normalizedInterface(
                    """
                // swift-interface-format-version: 1.0
                // swift-compiler-version: Integration Test Swift
                // swift-module-flags: -target \(fixture.targetTriple) -enable-library-evolution -module-name FailableInitFixture
                import Swift

                public struct Parser {
                  public var raw: Swift.String { get }
                  public init?(raw: Swift.String)
                }
                """
                )
        )
    }

    @Test
    func multipleInitializers() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "MultiInitFixture",
            sources: [
                "MultiInitFixture.swift": """
                public struct Size {
                    public let width: Double
                    public let height: Double

                    public init(width: Double, height: Double) {
                        self.width = width
                        self.height = height
                    }

                    public init(square side: Double) {
                        self.width = side
                        self.height = side
                    }
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)

        #expect(
            normalizedInterface(contents)
                == normalizedInterface(
                    """
                // swift-interface-format-version: 1.0
                // swift-compiler-version: Integration Test Swift
                // swift-module-flags: -target \(fixture.targetTriple) -enable-library-evolution -module-name MultiInitFixture
                import Swift

                public struct Size {
                  public var width: Swift.Double { get }
                  public var height: Swift.Double { get }
                  public init(width: Swift.Double, height: Swift.Double)
                  public init(square: Swift.Double)
                }
                """
                )
        )
    }

    // MARK: - Filtering

    @Test
    func deinitAndOperatorsNotInInterface() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "FilterFixture",
            sources: [
                "FilterFixture.swift": """
                public final class Resource {
                    public let name: String

                    public init(name: String) {
                        self.name = name
                    }

                    deinit {}
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)

        #expect(
            normalizedInterface(contents)
                == normalizedInterface(
                    """
                // swift-interface-format-version: 1.0
                // swift-compiler-version: Integration Test Swift
                // swift-module-flags: -target \(fixture.targetTriple) -enable-library-evolution -module-name FilterFixture
                import Swift

                public final class Resource {
                  public var name: Swift.String { get }
                  public init(name: Swift.String)
                }
                """
                )
        )
    }

    @Test
    func operatorsFilteredFromInterface() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "OperatorFixture",
            sources: [
                "OperatorFixture.swift": """
                public struct Vector {
                    public let x: Double

                    public init(x: Double) {
                        self.x = x
                    }

                    public static func + (lhs: Vector, rhs: Vector) -> Vector {
                        Vector(x: lhs.x + rhs.x)
                    }
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)

        #expect(
            normalizedInterface(contents)
                == normalizedInterface(
                    """
                // swift-interface-format-version: 1.0
                // swift-compiler-version: Integration Test Swift
                // swift-module-flags: -target \(fixture.targetTriple) -enable-library-evolution -module-name OperatorFixture
                import Swift

                public struct Vector {
                  public var x: Swift.Double { get }
                  public init(x: Swift.Double)
                }
                """
                )
        )
    }

    @Test
    func opaqueReturnTypesPreserveProtocolConstraints() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "OpaqueFixture",
            sources: [
                "OpaqueFixture.swift": """
                public protocol Marker {}

                public protocol Maker {
                    associatedtype Output: Marker
                    func make() -> Output
                }

                public struct Token: Marker {
                    public init() {}
                }

                public struct Factory: Maker {
                    public init() {}

                    public func make() -> some Marker {
                        Token()
                    }
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)

        let normalized = normalizedInterface(contents)
        #expect(normalized.contains("public protocol Maker {"))
        #expect(normalized.contains("associatedtype Output"))
        #expect(normalized.contains("func make() -> some Marker"))
        #expect(normalized.contains("public struct Factory: Maker {"))
    }

    // MARK: - Multiple Source Files

    @Test
    func multipleSourceFiles() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "MultiFileFixture",
            sources: [
                "User.swift": """
                public struct User {
                    public let name: String

                    public init(name: String) {
                        self.name = name
                    }
                }
                """,
                "Group.swift": """
                public struct Group {
                    public let title: String

                    public init(title: String) {
                        self.title = title
                    }
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)

        let norm = normalizedInterface(contents)
        #expect(norm.contains(
            """
            public struct Group {
              public var title: Swift.String { get }
              public init(title: Swift.String)
            }
            """
        ))
        #expect(norm.contains(
            """
            public struct User {
              public var name: Swift.String { get }
              public init(name: Swift.String)
            }
            """
        ))
    }

    // MARK: - Optional Types

    @Test
    func optionalProperty() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "OptionalFixture",
            sources: [
                "OptionalFixture.swift": """
                public struct Profile {
                    public var nickname: String?
                    public let age: Int

                    public init(nickname: String?, age: Int) {
                        self.nickname = nickname
                        self.age = age
                    }
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)

        #expect(
            normalizedInterface(contents)
                == normalizedInterface(
                    """
                // swift-interface-format-version: 1.0
                // swift-compiler-version: Integration Test Swift
                // swift-module-flags: -target \(fixture.targetTriple) -enable-library-evolution -module-name OptionalFixture
                import Swift

                public struct Profile {
                  public var age: Swift.Int { get }
                  public var nickname: Swift.String? { get set }
                  public init(nickname: Swift.String?, age: Swift.Int)
                }
                """
                )
        )
    }

    // MARK: - Complex Scenarios

    @Test
    func structWithConformancesPropertiesInitAndMethods() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "ComplexFixture",
            sources: [
                "ComplexFixture.swift": """
                public struct User: Codable, Hashable {
                    public var name: String
                    public let age: Int

                    public init(name: String, age: Int) {
                        self.name = name
                        self.age = age
                    }

                    public func greet() -> String {
                        return "Hello, \\(name)"
                    }

                    public static func anonymous() -> User {
                        User(name: "anon", age: 0)
                    }
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)

        #expect(
            normalizedInterface(contents)
                == normalizedInterface(
                    """
                // swift-interface-format-version: 1.0
                // swift-compiler-version: Integration Test Swift
                // swift-module-flags: -target \(fixture.targetTriple) -enable-library-evolution -module-name ComplexFixture
                import Swift

                public struct User: Swift.Codable, Swift.Hashable {
                  public var age: Swift.Int { get }
                  public var name: Swift.String { get set }
                  public var hashValue: Swift.Int { get }
                  public init(from: Swift.Decoder) throws
                  public init(name: Swift.String, age: Swift.Int)
                  public func hash(into: inout Swift.Hasher)
                  public func greet() -> Swift.String
                  public func encode(to: Swift.Encoder) throws
                  public static func anonymous() -> User
                }
                """
                )
        )
    }

    @Test
    func protocolWithImplementingStruct() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "ProtoImplFixture",
            sources: [
                "ProtoImplFixture.swift": """
                public protocol Describable {
                    func describe() -> String
                }

                public struct Widget {
                    public let label: String

                    public init(label: String) {
                        self.label = label
                    }

                    public func render(target: any Describable) -> String {
                        return target.describe()
                    }
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)

        #expect(
            normalizedInterface(contents)
                == normalizedInterface(
                    """
                // swift-interface-format-version: 1.0
                // swift-compiler-version: Integration Test Swift
                // swift-module-flags: -target \(fixture.targetTriple) -enable-library-evolution -module-name ProtoImplFixture
                import Swift

                public protocol Describable {
                  func describe() -> Swift.String
                }

                public struct Widget {
                  public var label: Swift.String { get }
                  public init(label: Swift.String)
                  public func render(target: any Describable) -> Swift.String
                }
                """
                )
        )
    }

    // MARK: - Output Metadata

    @Test
    func interfaceHeaderContainsCorrectMetadata() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "HeaderFixture",
            sources: [
                "HeaderFixture.swift": """
                public struct Marker {}
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)

        #expect(
            normalizedInterface(contents)
                == normalizedInterface(
                    """
                // swift-interface-format-version: 1.0
                // swift-compiler-version: Integration Test Swift
                // swift-module-flags: -target \(fixture.targetTriple) -enable-library-evolution -module-name HeaderFixture
                import Swift

                public struct Marker {
                }
                """
                )
        )
    }

    @Test
    func logMessageIncludesSourceAndDestination() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "LogFixture",
            sources: [
                "LogFixture.swift": """
                public struct Marker {}
                """
            ]
        )
        let generator = integrationCompiler.makeGenerator()
        let result = try await generator.generate(
            frameworkBinaryURL: fixture.binaryURL,
            repositoryRootURL: fixture.repositoryRootURL,
            targetTriple: fixture.targetTriple
        )

        #expect(result.log.contains("Generated"))
        #expect(result.log.contains(result.interfaceURL.path))
    }

    @Test
    func swiftInterfaceFileWrittenToDisk() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "DiskFixture",
            sources: [
                "DiskFixture.swift": """
                public struct Marker {}
                """
            ]
        )
        let generator = integrationCompiler.makeGenerator()
        let result = try await generator.generate(
            frameworkBinaryURL: fixture.binaryURL,
            repositoryRootURL: fixture.repositoryRootURL,
            targetTriple: fixture.targetTriple
        )

        #expect(FileManager.default.fileExists(atPath: result.interfaceURL.path))
        #expect(result.interfaceURL.lastPathComponent.hasSuffix(".swiftinterface"))
    }

    // MARK: - Import Discovery

    @Test
    func noExtraImportsForSwiftOnlyTypes() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "SwiftOnlyFixture",
            sources: [
                "SwiftOnlyFixture.swift": """
                public struct Simple {
                    public let value: Int

                    public init(value: Int) {
                        self.value = value
                    }
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)

        #expect(
            normalizedInterface(contents)
                == normalizedInterface(
                    """
                // swift-interface-format-version: 1.0
                // swift-compiler-version: Integration Test Swift
                // swift-module-flags: -target \(fixture.targetTriple) -enable-library-evolution -module-name SwiftOnlyFixture
                import Swift

                public struct Simple {
                  public var value: Swift.Int { get }
                  public init(value: Swift.Int)
                }
                """
                )
        )
    }

    // MARK: - Phantom Generics

    @Test
    func phantomGenericParameterUsedOnlyInMethods() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "PhantomFixture",
            sources: [
                "PhantomFixture.swift": """
                public struct Phantom<T> {
                    public init() {}

                    public func id(_ value: T) -> T {
                        return value
                    }
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)

        #expect(
            normalizedInterface(contents)
                == normalizedInterface(
                    """
                // swift-interface-format-version: 1.0
                // swift-compiler-version: Integration Test Swift
                // swift-module-flags: -target \(fixture.targetTriple) -enable-library-evolution -module-name PhantomFixture
                import Swift

                public struct Phantom<A> {
                  public init()
                  public func id(_: A) -> A
                }
                """
                )
        )
    }

    // MARK: - Mutable Static Properties

    @Test
    func mutableStaticVarRenderedAsGetSet() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "MutableStaticFixture",
            sources: [
                "MutableStaticFixture.swift": """
                public struct Registry {
                    public static var count: Int = 0
                    public let name: String
                    public init(name: String) { self.name = name }
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)

        #expect(
            normalizedInterface(contents)
                == normalizedInterface(
                    """
                // swift-interface-format-version: 1.0
                // swift-compiler-version: Integration Test Swift
                // swift-module-flags: -target \(fixture.targetTriple) -enable-library-evolution -module-name MutableStaticFixture
                import Swift

                public struct Registry {
                  public var name: Swift.String { get }
                  public static var count: Swift.Int { get set }
                  public init(name: Swift.String)
                }
                """
                )
        )
    }

    // MARK: - Generic Methods

    @Test
    func genericMethodWithWhereClause() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "GenericMethodFixture",
            sources: [
                "GenericMethodFixture.swift": """
                public protocol Convertible {
                    init(value: String)
                }

                public struct Session {
                    public init() {}

                    public func respond<A: Convertible>(to prompt: String, generating type: A.Type) -> A {
                        type.init(value: prompt)
                    }
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)

        #expect(
            normalizedInterface(contents)
                == normalizedInterface(
                    """
                // swift-interface-format-version: 1.0
                // swift-compiler-version: Integration Test Swift
                // swift-module-flags: -target \(fixture.targetTriple) -enable-library-evolution -module-name GenericMethodFixture
                import Swift

                public protocol Convertible {
                  init(value: Swift.String)
                }

                public struct Session {
                  public init()
                  public func respond<A>(to: Swift.String, generating: A.Type) -> A where A : Convertible
                }
                """
                )
        )
    }

    @Test
    func protocolRequirementGenericMethodUsesMethodTypeParameter() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "ProtocolGenericMethodFixture",
            sources: [
                "ProtocolGenericMethodFixture.swift": """
                public struct Subviews {
                    public init() {}
                }

                public struct Context {
                    public init() {}
                }

                public protocol Layout {
                    func firstIndex<A: Hashable>(
                        of value: A,
                        subviews: Subviews,
                        context: Context
                    ) -> Int?
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)
        let normalized = normalizedInterface(contents)

        #expect(normalized.contains("public protocol Layout {"))
        #expect(
            normalized.contains(
                "func firstIndex<A1>(of: A1, subviews: Subviews, context: Context) -> Swift.Int? where A1 : Swift.Hashable"
            )
        )
        #expect(!normalized.contains("func firstIndex<Self>"))
    }

    @Test
    func constrainedExtensionMethodsOnGenericType() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "ConstrainedExtensionFixture",
            sources: [
                "ConstrainedExtensionFixture.swift": """
                public struct GenerationGuide<A> {}

                public extension GenerationGuide where A == String {
                    static func anyOf(_ choices: [String]) -> GenerationGuide<String> {
                        GenerationGuide<String>()
                    }
                }

                public extension GenerationGuide where A == Int {
                    static func minimum(_ value: Int) -> GenerationGuide<Int> {
                        GenerationGuide<Int>()
                    }
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)

        #expect(
            normalizedInterface(contents)
                == normalizedInterface(
                    """
                // swift-interface-format-version: 1.0
                // swift-compiler-version: Integration Test Swift
                // swift-module-flags: -target \(fixture.targetTriple) -enable-library-evolution -module-name ConstrainedExtensionFixture
                import Swift

                public struct GenerationGuide<A> {
                  public static func anyOf(_: [Swift.String]) -> GenerationGuide<Swift.String> where A == Swift.String
                  public static func minimum(_: Swift.Int) -> GenerationGuide<Swift.Int> where A == Swift.Int
                }
                """
                )
        )
    }

    @Test
    func protocolExtensionDefaultPropertyRendersAsExtension() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "ProtocolExtensionFixture",
            sources: [
                "ProtocolExtensionFixture.swift": """
                public protocol View {
                    associatedtype Body
                    var body: Self.Body { get }
                }

                public protocol PrimitiveView: View {}

                public extension PrimitiveView {
                    var body: Never {
                        fatalError()
                    }
                }

                public struct Leaf: PrimitiveView {
                    public init() {}
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)
        let normalized = normalizedInterface(contents)

        #expect(normalized.contains("public protocol View {"))
        #expect(normalized.contains("associatedtype Body"))
        #expect(normalized.contains("var body: Self.Body { get }"))
        #expect(normalized.contains("public protocol PrimitiveView: View {"))
        #expect(normalized.contains("extension PrimitiveView {"))
        #expect(normalized.contains("public var body: Swift.Never { get }"))
        #expect(normalized.contains("public struct Leaf: PrimitiveView"))
        #expect(!normalized.contains("public protocol PrimitiveView: View {\n  var body: Swift.Never { get }"))
    }

    @Test
    func protocolExtensionDefaultPropertyMaterializesConcreteAssociatedTypealias() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "ProtocolExtensionAssociatedTypeFixture",
            sources: [
                "ProtocolExtensionAssociatedTypeFixture.swift": """
                public protocol View {
                    associatedtype Body
                    var body: Self.Body { get }
                }

                public protocol PrimitiveView: View {}

                public extension PrimitiveView {
                    var body: Never {
                        fatalError()
                    }
                }

                public struct Leaf: PrimitiveView {
                    public init() {}
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)
        let normalized = normalizedInterface(contents)

        #expect(normalized.contains("public struct Leaf: PrimitiveView"))
        #expect(normalized.contains("public typealias Body = Swift.Never"))
    }

    @Test
    func concreteStaticMethodWitnessMaterializesAssociatedTypealias() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "ConcreteWitnessAssociatedTypeFixture",
            sources: [
                "ConcreteWitnessAssociatedTypeFixture.swift": """
                public struct _GestureOutputs<Value> {
                    public init() {}
                }

                public struct _GraphValue<Value> {
                    public init() {}
                }

                public struct _GestureInputs {
                    public init() {}
                }

                public protocol Gesture {
                    associatedtype Body: Gesture
                    associatedtype Value
                    var body: Body { get }
                    static func _makeGesture(
                        gesture: _GraphValue<Self>,
                        inputs: _GestureInputs
                    ) -> _GestureOutputs<Self.Value>
                }

                public struct EmptyGesture: Gesture {
                    public typealias Body = EmptyGesture
                    public typealias Value = Never
                    public var body: EmptyGesture { self }

                    public init() {}

                    public static func _makeGesture(
                        gesture: _GraphValue<EmptyGesture>,
                        inputs: _GestureInputs
                    ) -> _GestureOutputs<Never> {
                        .init()
                    }
                }

                public struct TapGesture: Gesture {
                    public typealias Body = EmptyGesture
                    public var body: EmptyGesture { EmptyGesture() }

                    public init() {}

                    public static func _makeGesture(
                        gesture: _GraphValue<TapGesture>,
                        inputs: _GestureInputs
                    ) -> _GestureOutputs<Void> {
                        .init()
                    }
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)
        let normalized = normalizedInterface(contents)

        #expect(normalized.contains("public struct TapGesture: Gesture {"))
        #expect(
            normalized.contains("public typealias Value = ()")
                || normalized.contains("public typealias Value = Swift.Void")
        )
    }

    @Test
    func protocolExtensionOpaquePropertyPreservesConstraint() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "ProtocolExtensionOpaqueFixture",
            sources: [
                "ProtocolExtensionOpaqueFixture.swift": """
                public protocol Marker {}

                public struct Token: Marker {
                    public init() {}
                }

                public protocol ViewLike {
                    associatedtype Body: Marker
                    var body: Body { get }
                }

                public protocol StyleableView: ViewLike {}

                public extension StyleableView {
                    var body: some Marker {
                        Token()
                    }
                }

                public struct Styled: StyleableView {
                    public init() {}
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)
        let normalized = normalizedInterface(contents)

        #expect(normalized.contains("public protocol ViewLike {"))
        #expect(normalized.contains("associatedtype Body: Marker"))
        #expect(normalized.contains("extension StyleableView {"))
        #expect(normalized.contains("public var body: some Marker { get }"))
        #expect(!normalized.contains("public var body: some { get }"))
        #expect(normalized.contains("public struct Styled: StyleableView"))
    }

    @Test
    func protocolExtensionWhereClauseReplacesSelfPlaceholder() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "ProtocolExtensionWhereClauseFixture",
            sources: [
                "ProtocolExtensionWhereClauseFixture.swift": """
                public protocol ArithmeticValue {}

                public struct EmptyScaleData: ArithmeticValue {
                    public init() {}
                }

                public protocol Scalable {
                    associatedtype ScaleData: ArithmeticValue
                    var scaleData: ScaleData { get set }
                }

                public extension Scalable where Self: ArithmeticValue {
                    var scaleData: Self {
                        get { self }
                        set {}
                    }
                }

                public extension Scalable where Self.ScaleData == EmptyScaleData {
                    var scaleData: EmptyScaleData {
                        get { EmptyScaleData() }
                        set {}
                    }
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)
        let normalized = normalizedInterface(contents)

        #expect(normalized.contains("extension Scalable where Self : ArithmeticValue {"))
        #expect(normalized.contains("public var scaleData: Self { get set }"))
        #expect(normalized.contains("extension Scalable where Self.ScaleData == EmptyScaleData {"))
        #expect(!normalized.contains("extension Scalable where A : ArithmeticValue"))
        #expect(!normalized.contains("extension Scalable where A.ScaleData == EmptyScaleData"))
    }

    @Test
    func opaqueSubscriptWitnessPreservesConstraint() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "OpaqueSubscriptFixture",
            sources: [
                "OpaqueSubscriptFixture.swift": """
                public protocol IndexedValues {
                    associatedtype Value: BinaryInteger
                    subscript(_ index: Int) -> Value { get }
                }

                public struct Counter: IndexedValues {
                    public init() {}

                    public subscript(_ index: Int) -> some BinaryInteger {
                        index
                    }
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)
        let normalized = normalizedInterface(contents)

        #expect(normalized.contains("public protocol IndexedValues {"))
        #expect(normalized.contains("associatedtype Value: Swift.BinaryInteger"))
        #expect(normalized.contains("public struct Counter: IndexedValues"))
        #expect(normalized.contains("public subscript(_: Swift.Int) -> some Swift.BinaryInteger { get }"))
        #expect(!normalized.contains("public subscript(_: Swift.Int) -> some { get }"))
    }

    @Test
    func externalNeverConformanceRendersAsExtension() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "NeverConformanceFixture",
            sources: [
                "NeverConformanceFixture.swift": """
                public protocol View {
                    associatedtype Body: View
                    var body: Body { get }
                }

                extension Never: View {
                    public var body: Never {
                        fatalError()
                    }
                }

                public protocol PrimitiveView: View {}

                public extension PrimitiveView {
                    var body: Never {
                        fatalError()
                    }
                }

                public struct Leaf: PrimitiveView {
                    public init() {}
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)
        let normalized = normalizedInterface(contents)

        #expect(normalized.contains("public protocol View {"))
        #expect(normalized.contains("associatedtype Body: View"))
        #expect(normalized.contains("extension Swift.Never: View {"))
        #expect(normalized.contains("public var body: Swift.Never { get }"))
        #expect(normalized.contains("public struct Leaf: PrimitiveView"))
    }

    @Test
    func constrainedExtensionSubscriptStaysOnGenericOwner() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "ConstrainedSubscriptFixture",
            sources: [
                "ConstrainedSubscriptFixture.swift": """
                public struct AccessibilityTrait {}

                public struct AccessibilityTraitSet: OptionSet {
                    public let rawValue: UInt64

                    public init(rawValue: UInt64) {
                        self.rawValue = rawValue
                    }
                }

                public struct AccessibilityNullableOptionSet<A> {
                    public init() {}
                }

                public extension AccessibilityNullableOptionSet where A == AccessibilityTraitSet {
                    subscript(_ trait: AccessibilityTrait, default defaultValue: Bool) -> Bool {
                        get { defaultValue }
                        set {}
                    }
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)
        let normalized = normalizedInterface(contents)

        #expect(normalized.contains("public struct AccessibilityNullableOptionSet<A> {"))
        #expect(normalized.contains("public subscript(_: AccessibilityTrait, `default`: Swift.Bool) -> Swift.Bool { get set }"))
        #expect(!normalized.contains("public struct AccessibilityTraitSet>"))
    }

    @Test
    func staticFalsePropertyIsEscaped() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "KeywordPropertyFixture",
            sources: [
                "KeywordPropertyFixture.swift": """
                public struct Flags {
                    public static var `false`: Bool {
                        true
                    }
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)
        let normalized = normalizedInterface(contents)

        #expect(normalized.contains("public struct Flags {"))
        #expect(normalized.contains("public static var `false`: Swift.Bool { get }"))
    }

    // MARK: - Unavailable Module Filtering

    @Test
    func unavailableModuleTypesAreFilteredOut() async throws {
        let fixture = try integrationCompiler.compileFrameworkWithUnavailableModule(
            moduleName: "MainModule",
            sources: [
                "MainModule.swift": """
                import PrivateHelper

                public struct Widget {
                    public var name: String
                    public var helper: PrivateHelper.Token

                    public init(name: String, helper: PrivateHelper.Token) {
                        self.name = name
                        self.helper = helper
                    }

                    public func describe() -> String { name }
                }
                """
            ],
            helperModuleName: "PrivateHelper",
            helperSources: [
                "PrivateHelper.swift": """
                public struct Token {
                    public var id: Int
                    public init(id: Int) { self.id = id }
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)
        let normalized = normalizedInterface(contents)

        // PrivateHelper module is unavailable, so:
        // - import PrivateHelper should NOT appear
        #expect(!normalized.contains("import PrivateHelper"))
        // - Members referencing PrivateHelper types should be filtered out
        #expect(!normalized.contains("PrivateHelper."))
        // - But Widget should still exist with its non-PrivateHelper members
        #expect(normalized.contains("public struct Widget"))
        #expect(normalized.contains("public func describe() -> Swift.String"))
    }

    // MARK: - Bare Opaque Types

    @Test
    func unresolvedOpaqueReturnTypePreservesConstraint() async throws {
        let fixture = try integrationCompiler.compileFramework(
            moduleName: "BareOpaqueFixture",
            sources: [
                "BareOpaqueFixture.swift": """
                public protocol Shape {
                    func path() -> String
                }

                public struct Circle: Shape {
                    public init() {}
                    public func path() -> String { "circle" }
                }

                public struct Canvas {
                    public init() {}
                    public func makeShape() -> some Shape {
                        Circle()
                    }
                    public var currentShape: some Shape {
                        Circle()
                    }
                    public func regularMethod() -> String { "hello" }
                }
                """
            ]
        )
        let contents = try await generateInterface(fixture: fixture)
        let normalized = normalizedInterface(contents)

        // Opaque return types should preserve the protocol constraint
        #expect(normalized.contains("-> some Shape"))
        #expect(normalized.contains(": some Shape {"))
        // The regular method should still be present
        #expect(normalized.contains("public func regularMethod() -> Swift.String"))
        // Canvas struct should still exist
        #expect(normalized.contains("public struct Canvas"))
    }

    // MARK: - Helpers

    private func generateInterface(fixture: CompiledFrameworkFixture) async throws -> String {
        let generator = integrationCompiler.makeGenerator()
        let result = try await generator.generate(
            frameworkBinaryURL: fixture.binaryURL,
            repositoryRootURL: fixture.repositoryRootURL,
            targetTriple: fixture.targetTriple
        )
        return try String(contentsOf: result.interfaceURL, encoding: .utf8)
    }
}
