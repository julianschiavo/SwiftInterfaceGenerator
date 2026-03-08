import Foundation
import Testing
@testable import SwiftInterfaceGenerator

private let builder = SwiftInterfaceBuilder()

// MARK: - Associated Type Descriptor

@Suite("parseAssociatedTypeDescriptor")
struct AssociatedTypeDescriptorTests {
    @Test
    func basicAssociatedType() {
        let result = builder.parseAssociatedTypeDescriptor(
            from: "associated type descriptor for Sample.Repository.Item",
            moduleName: "Sample"
        )
        #expect(result?.owner == "Repository")
        #expect(result?.associatedType == "Item")
    }

    @Test
    func nestedOwner() {
        let result = builder.parseAssociatedTypeDescriptor(
            from: "associated type descriptor for Sample.Outer.Inner.Element",
            moduleName: "Sample"
        )
        #expect(result?.owner == "Outer.Inner")
        #expect(result?.associatedType == "Element")
    }

    @Test
    func wrongModuleReturnsNil() {
        #expect(
            builder.parseAssociatedTypeDescriptor(
                from: "associated type descriptor for Other.Repository.Item",
                moduleName: "Sample"
            ) == nil
        )
    }

    @Test
    func unrelatedLineReturnsNil() {
        #expect(
            builder.parseAssociatedTypeDescriptor(
                from: "protocol descriptor for Sample.Foo",
                moduleName: "Sample"
            ) == nil
        )
    }

    @Test
    func singleComponentAfterModuleReturnsNil() {
        #expect(
            builder.parseAssociatedTypeDescriptor(
                from: "associated type descriptor for Sample.Item",
                moduleName: "Sample"
            ) == nil
        )
    }
}

// MARK: - Conformance Descriptor

@Suite("parseConformanceDescriptor")
struct ConformanceDescriptorTests {
    @Test
    func basicConformance() {
        let result = builder.parseConformanceDescriptor(
            from: "protocol conformance descriptor for Sample.Record : Swift.Codable in Sample",
            moduleName: "Sample"
        )
        #expect(result?.owner == "Record")
        #expect(result?.conformance == "Swift.Codable")
    }

    @Test
    func conformanceToExternalProtocol() {
        let result = builder.parseConformanceDescriptor(
            from: "protocol conformance descriptor for Sample.Widget : Foundation.NSCoding in Sample",
            moduleName: "Sample"
        )
        #expect(result?.owner == "Widget")
        #expect(result?.conformance == "Foundation.NSCoding")
    }

    @Test
    func nestedOwnerConformance() {
        let result = builder.parseConformanceDescriptor(
            from: "protocol conformance descriptor for Sample.Outer.Inner : Swift.Hashable in Sample",
            moduleName: "Sample"
        )
        #expect(result?.owner == "Outer.Inner")
        #expect(result?.conformance == "Swift.Hashable")
    }

    @Test
    func wrongModuleReturnsNil() {
        #expect(
            builder.parseConformanceDescriptor(
                from: "protocol conformance descriptor for Other.Record : Swift.Codable in Other",
                moduleName: "Sample"
            ) == nil
        )
    }

    @Test
    func malformedLineReturnsNil() {
        #expect(
            builder.parseConformanceDescriptor(
                from: "protocol conformance descriptor for Sample.Record Swift.Codable",
                moduleName: "Sample"
            ) == nil
        )
    }

    @Test
    func sendableConformance() {
        let result = builder.parseConformanceDescriptor(
            from: "protocol conformance descriptor for Sample.Config : Swift.Sendable in Sample",
            moduleName: "Sample"
        )
        #expect(result?.owner == "Config")
        #expect(result?.conformance == "Swift.Sendable")
    }

    @Test
    func genericOwnerStripsTypeParameters() {
        let result = builder.parseConformanceDescriptor(
            from: "protocol conformance descriptor for Sample.Container<A> : Swift.Sequence in Sample",
            moduleName: "Sample"
        )
        #expect(result?.owner == "Container")
        #expect(result?.conformance == "Swift.Sequence")
    }

    @Test
    func nestedGenericOwnerStripsTypeParameters() {
        let result = builder.parseConformanceDescriptor(
            from: "protocol conformance descriptor for Sample.Outer.Inner<A> : Swift.Hashable in Sample",
            moduleName: "Sample"
        )
        #expect(result?.owner == "Outer.Inner")
        #expect(result?.conformance == "Swift.Hashable")
    }

    @Test
    func nestedTypeAfterGenericOwnerIsPreserved() {
        let result = builder.parseConformanceDescriptor(
            from: "protocol conformance descriptor for Sample.Stream<A>.AsyncIterator : Swift.AsyncIteratorProtocol in Sample",
            moduleName: "Sample"
        )
        #expect(result?.owner == "Stream.AsyncIterator")
        #expect(result?.conformance == "Swift.AsyncIteratorProtocol")
    }
}

// MARK: - Property Descriptor

@Suite("parsePropertyDescriptor")
struct PropertyDescriptorTests {
    @Test
    func settableInstanceProperty() {
        let symbols = [
            "property descriptor for Sample.Record.name : Swift.String",
            "Sample.Record.name.getter : Swift.String",
            "Sample.Record.name.setter : (Swift.String) -> ()",
        ]
        let result = builder.parsePropertyDescriptor(
            from: symbols[0], sortedSymbols: .init(symbols), moduleName: "Sample"
        )
        #expect(result?.owner == "Record")
        #expect(result?.name == "name")
        #expect(result?.rawType == "Swift.String")
        #expect(result?.isStatic == false)
        #expect(result?.hasSetter == true)
    }

    @Test
    func getOnlyInstanceProperty() {
        let symbols = [
            "property descriptor for Sample.Record.id : Swift.Int",
            "Sample.Record.id.getter : Swift.Int",
        ]
        let result = builder.parsePropertyDescriptor(
            from: symbols[0], sortedSymbols: .init(symbols), moduleName: "Sample"
        )
        #expect(result?.owner == "Record")
        #expect(result?.name == "id")
        #expect(result?.rawType == "Swift.Int")
        #expect(result?.hasSetter == false)
    }

    @Test
    func staticPropertyAlwaysGetOnly() {
        let symbols = [
            "property descriptor for static Sample.Registry.shared : Sample.Registry",
            "static Sample.Registry.shared.getter : Sample.Registry",
            "Sample.Registry.shared.setter : (Sample.Registry) -> ()",
        ]
        let result = builder.parsePropertyDescriptor(
            from: symbols[0], sortedSymbols: .init(symbols), moduleName: "Sample"
        )
        #expect(result?.owner == "Registry")
        #expect(result?.name == "shared")
        #expect(result?.isStatic == true)
        #expect(result?.hasSetter == false)
    }

    @Test
    func propertyWithGenericType() {
        let symbols = [
            "property descriptor for Sample.Box.value : T",
            "Sample.Box.value.getter : T",
        ]
        let result = builder.parsePropertyDescriptor(
            from: symbols[0], sortedSymbols: .init(symbols), moduleName: "Sample"
        )
        #expect(result?.rawType == "T")
        #expect(result?.hasSetter == false)
    }

    @Test
    func propertyWithOptionalType() {
        let symbols = [
            "property descriptor for Sample.Config.label : Swift.String?",
            "Sample.Config.label.getter : Swift.String?",
            "Sample.Config.label.setter : (Swift.String?) -> ()",
        ]
        let result = builder.parsePropertyDescriptor(
            from: symbols[0], sortedSymbols: .init(symbols), moduleName: "Sample"
        )
        #expect(result?.rawType == "Swift.String?")
        #expect(result?.hasSetter == true)
    }

    @Test
    func propertyWithFoundationType() {
        let symbols = [
            "property descriptor for Sample.Manager.createdAt : Foundation.Date",
            "Sample.Manager.createdAt.getter : Foundation.Date",
        ]
        let result = builder.parsePropertyDescriptor(
            from: symbols[0], sortedSymbols: .init(symbols), moduleName: "Sample"
        )
        #expect(result?.rawType == "Foundation.Date")
    }

    @Test
    func nestedOwnerProperty() {
        let symbols = [
            "property descriptor for Sample.Outer.Inner.value : Swift.Int",
            "Sample.Outer.Inner.value.getter : Swift.Int",
        ]
        let result = builder.parsePropertyDescriptor(
            from: symbols[0], sortedSymbols: .init(symbols), moduleName: "Sample"
        )
        #expect(result?.owner == "Outer.Inner")
        #expect(result?.name == "value")
    }

    @Test
    func wrongModuleReturnsNil() {
        let symbols = [
            "property descriptor for Other.Record.name : Swift.String",
        ]
        #expect(
            builder.parsePropertyDescriptor(
                from: symbols[0], sortedSymbols: .init(symbols), moduleName: "Sample"
            ) == nil
        )
    }

    @Test
    func nonPropertyLineReturnsNil() {
        #expect(
            builder.parsePropertyDescriptor(
                from: "Sample.Record.name.getter : Swift.String",
                sortedSymbols: .init([]),
                moduleName: "Sample"
            ) == nil
        )
    }

    @Test
    func missingTypeSeparatorReturnsNil() {
        #expect(
            builder.parsePropertyDescriptor(
                from: "property descriptor for Sample.Record.name",
                sortedSymbols: .init([]),
                moduleName: "Sample"
            ) == nil
        )
    }
}

// MARK: - Enum Case

@Suite("parseEnumCase")
struct EnumCaseTests {
    @Test
    func payloadlessCase() {
        let result = builder.parseEnumCase(
            from: "enum case for Sample.State.idle(Sample.State) -> Sample.State",
            moduleName: "Sample"
        )
        #expect(result?.owner == "State")
        #expect(result?.name == "idle")
        #expect(result?.rawPayload == nil)
    }

    @Test
    func singlePayloadCase() {
        let result = builder.parseEnumCase(
            from: "enum case for Sample.State.message(Sample.State) -> (Swift.String) -> Sample.State",
            moduleName: "Sample"
        )
        #expect(result?.owner == "State")
        #expect(result?.name == "message")
        #expect(result?.rawPayload == "Swift.String")
    }

    @Test
    func tuplePayloadCase() {
        let result = builder.parseEnumCase(
            from: "enum case for Sample.Event.move(Sample.Event) -> (Swift.Int, Swift.Int) -> Sample.Event",
            moduleName: "Sample"
        )
        #expect(result?.owner == "Event")
        #expect(result?.name == "move")
        #expect(result?.rawPayload == "Swift.Int, Swift.Int")
    }

    @Test
    func payloadWithExternalType() {
        let result = builder.parseEnumCase(
            from: "enum case for Sample.Message.text(Sample.Message) -> (Foundation.Date) -> Sample.Message",
            moduleName: "Sample"
        )
        #expect(result?.owner == "Message")
        #expect(result?.name == "text")
        #expect(result?.rawPayload == "Foundation.Date")
    }

    @Test
    func nestedEnumCase() {
        let result = builder.parseEnumCase(
            from: "enum case for Sample.Outer.Status.active(Sample.Outer.Status) -> Sample.Outer.Status",
            moduleName: "Sample"
        )
        #expect(result?.owner == "Outer.Status")
        #expect(result?.name == "active")
        #expect(result?.rawPayload == nil)
    }

    @Test
    func wrongModuleReturnsNil() {
        #expect(
            builder.parseEnumCase(
                from: "enum case for Other.State.idle(Other.State) -> Other.State",
                moduleName: "Sample"
            ) == nil
        )
    }

    @Test
    func nonEnumLineReturnsNil() {
        #expect(
            builder.parseEnumCase(
                from: "nominal type descriptor for Sample.State",
                moduleName: "Sample"
            ) == nil
        )
    }
}

// MARK: - Protocol Method Descriptor

@Suite("parseProtocolMethodDescriptor")
struct ProtocolMethodDescriptorTests {
    @Test
    func simpleMethod() {
        let result = builder.parseProtocolMethodDescriptor(
            from: "method descriptor for Sample.Greeter.greet() -> Swift.String",
            moduleName: "Sample"
        )
        #expect(result?.owner == "Greeter")
        #expect(result?.rawSignature == "greet() -> Swift.String")
    }

    @Test
    func methodWithArguments() {
        let result = builder.parseProtocolMethodDescriptor(
            from: "method descriptor for Sample.Service.fetch(id: Swift.Int) -> Swift.String",
            moduleName: "Sample"
        )
        #expect(result?.owner == "Service")
        #expect(result?.rawSignature == "fetch(id: Swift.Int) -> Swift.String")
    }

    @Test
    func allocatingInitReturnsNil() {
        #expect(
            builder.parseProtocolMethodDescriptor(
                from: "method descriptor for Sample.Builder.__allocating_init() -> Sample.Builder",
                moduleName: "Sample"
            ) == nil
        )
    }

    @Test
    func wrongModuleReturnsNil() {
        #expect(
            builder.parseProtocolMethodDescriptor(
                from: "method descriptor for Other.Greeter.greet() -> Swift.String",
                moduleName: "Sample"
            ) == nil
        )
    }

    @Test
    func nestedOwnerMethod() {
        let result = builder.parseProtocolMethodDescriptor(
            from: "method descriptor for Sample.Outer.Protocol.run() -> ()",
            moduleName: "Sample"
        )
        #expect(result?.owner == "Outer.Protocol")
        #expect(result?.rawSignature == "run() -> ()")
    }

    @Test
    func genericMethodWithProtocolConstraint() {
        let result = builder.parseProtocolMethodDescriptor(
            from: "method descriptor for Sample.Layout.firstIndex<A where A: Swift.Hashable>(of: A, subviews: Sample.Subviews, context: Sample.Context) -> Swift.Int?",
            moduleName: "Sample"
        )
        #expect(result?.owner == "Layout")
        #expect(
            result?.rawSignature
                == "firstIndex<A where A: Swift.Hashable>(of: A, subviews: Sample.Subviews, context: Sample.Context) -> Swift.Int?"
        )
    }

    @Test
    func nonMethodLineReturnsNil() {
        #expect(
            builder.parseProtocolMethodDescriptor(
                from: "protocol descriptor for Sample.Greeter",
                moduleName: "Sample"
            ) == nil
        )
    }
}

// MARK: - Callable

@Suite("parseCallable")
struct CallableTests {
    @Test
    func instanceInitializer() {
        let result = builder.parseCallable(
            from: "Sample.Record.init(name: Swift.String) -> Sample.Record",
            isStatic: false,
            moduleName: "Sample"
        )
        #expect(result?.owner == "Record")
        #expect(result?.rawSignature == "init(name: Swift.String) -> Sample.Record")
        #expect(result?.isInitializer == true)
    }

    @Test
    func staticMethod() {
        let result = builder.parseCallable(
            from: "static Sample.Record.makeDefault() -> Sample.Record",
            isStatic: true,
            moduleName: "Sample"
        )
        #expect(result?.owner == "Record")
        #expect(result?.rawSignature == "makeDefault() -> Sample.Record")
        #expect(result?.isInitializer == false)
    }

    @Test
    func instanceMethod() {
        let result = builder.parseCallable(
            from: "Sample.Service.fetch(id: Swift.Int) -> Swift.String",
            isStatic: false,
            moduleName: "Sample"
        )
        #expect(result?.owner == "Service")
        #expect(result?.rawSignature == "fetch(id: Swift.Int) -> Swift.String")
        #expect(result?.isInitializer == false)
    }

    @Test
    func methodReturningVoid() {
        let result = builder.parseCallable(
            from: "Sample.Service.reset() -> ()",
            isStatic: false,
            moduleName: "Sample"
        )
        #expect(result?.rawSignature == "reset() -> ()")
        #expect(result?.isInitializer == false)
    }

    @Test
    func methodWithMultipleArguments() {
        let result = builder.parseCallable(
            from: "Sample.DB.insert(key: Swift.String, value: Swift.Int) -> Swift.Bool",
            isStatic: false,
            moduleName: "Sample"
        )
        #expect(result?.rawSignature == "insert(key: Swift.String, value: Swift.Int) -> Swift.Bool")
    }

    @Test
    func methodWithClosureArgument() {
        let result = builder.parseCallable(
            from: "Sample.Runner.run(block: () -> ()) -> ()",
            isStatic: false,
            moduleName: "Sample"
        )
        #expect(result?.rawSignature == "run(block: () -> ()) -> ()")
    }

    @Test
    func getterIsFiltered() {
        #expect(
            builder.parseCallable(
                from: "Sample.Record.name.getter : Swift.String",
                isStatic: false,
                moduleName: "Sample"
            ) == nil
        )
    }

    @Test
    func setterIsFiltered() {
        #expect(
            builder.parseCallable(
                from: "Sample.Record.name.setter : (Swift.String) -> ()",
                isStatic: false,
                moduleName: "Sample"
            ) == nil
        )
    }

    @Test
    func modifyAccessorIsFiltered() {
        #expect(
            builder.parseCallable(
                from: "Sample.Record.name.modify : Swift.String",
                isStatic: false,
                moduleName: "Sample"
            ) == nil
        )
    }

    @Test
    func deallocatingDeinitIsFiltered() {
        #expect(
            builder.parseCallable(
                from: "Sample.Record.__deallocating_deinit",
                isStatic: false,
                moduleName: "Sample"
            ) == nil
        )
    }

    @Test
    func deinitIsFiltered() {
        #expect(
            builder.parseCallable(
                from: "Sample.Record.deinit",
                isStatic: false,
                moduleName: "Sample"
            ) == nil
        )
    }

    @Test
    func allocatingInitIsNormalizedToInit() {
        let result = builder.parseCallable(
            from: "Sample.Record.__allocating_init() -> Sample.Record",
            isStatic: false,
            moduleName: "Sample"
        )
        #expect(result?.owner == "Record")
        #expect(result?.rawSignature == "init() -> Sample.Record")
        #expect(result?.isInitializer == true)
    }

    @Test
    func sameModuleConcreteExtensionMethodIsParsed() {
        let result = builder.parseCallable(
            from: "static (extension in Sample):Sample.GenerationGuide<A where A == Swift.String>.anyOf([Swift.String]) -> Sample.GenerationGuide<Swift.String>",
            isStatic: true,
            moduleName: "Sample",
            allowExtensionMembersOn: ["GenerationGuide"]
        )
        #expect(result?.owner == "GenerationGuide")
        #expect(
            result?.rawSignature
                == "anyOf([Swift.String]) -> Sample.GenerationGuide<Swift.String> where A == Swift.String"
        )
        #expect(result?.isInitializer == false)
    }

    @Test
    func infixOperatorIsFiltered() {
        #expect(
            builder.parseCallable(
                from: "Sample.Vector.+ infix(Sample.Vector, Sample.Vector) -> Sample.Vector",
                isStatic: true,
                moduleName: "Sample"
            ) == nil
        )
    }

    @Test
    func prefixOperatorIsFiltered() {
        #expect(
            builder.parseCallable(
                from: "Sample.Vector.prefix -(Sample.Vector) -> Sample.Vector",
                isStatic: true,
                moduleName: "Sample"
            ) == nil
        )
    }

    @Test
    func postfixOperatorIsFiltered() {
        #expect(
            builder.parseCallable(
                from: "Sample.Counter.postfix ++(Sample.Counter) -> Sample.Counter",
                isStatic: true,
                moduleName: "Sample"
            ) == nil
        )
    }

    @Test
    func wrongModuleReturnsNil() {
        #expect(
            builder.parseCallable(
                from: "Other.Record.init() -> Other.Record",
                isStatic: false,
                moduleName: "Sample"
            ) == nil
        )
    }

    @Test
    func staticPrefixMismatchReturnsNil() {
        #expect(
            builder.parseCallable(
                from: "Sample.Record.foo() -> ()",
                isStatic: true,
                moduleName: "Sample"
            ) == nil
        )
    }

    @Test
    func genericMethodWithWhereClause() {
        let result = builder.parseCallable(
            from: "Sample.Session.respond<A where A: Sample.Generable>(to: Swift.String, generating: A.Type) async throws -> Sample.Session.Response<A>",
            isStatic: false,
            moduleName: "Sample"
        )
        #expect(result?.owner == "Session")
        #expect(result?.rawSignature == "respond<A where A: Sample.Generable>(to: Swift.String, generating: A.Type) async throws -> Sample.Session.Response<A>")
        #expect(result?.isInitializer == false)
    }

    @Test
    func genericInitWithWhereClause() {
        let result = builder.parseCallable(
            from: "Sample.Format.init<A where A: Sample.Generable>(type: A.Type) -> Sample.Format",
            isStatic: false,
            moduleName: "Sample"
        )
        #expect(result?.owner == "Format")
        #expect(result?.rawSignature == "init<A where A: Sample.Generable>(type: A.Type) -> Sample.Format")
        #expect(result?.isInitializer == true)
    }

    @Test
    func staticGenericMethodWithWhereClause() {
        let result = builder.parseCallable(
            from: "static Sample.Guide.maximumCount<A where A == [A1]>(Swift.Int) -> Sample.Guide<[A1]>",
            isStatic: true,
            moduleName: "Sample"
        )
        #expect(result?.owner == "Guide")
        #expect(result?.rawSignature == "maximumCount<A where A == [A1]>(Swift.Int) -> Sample.Guide<[A1]>")
        #expect(result?.isInitializer == false)
    }

    @Test
    func nestedOwnerCallable() {
        let result = builder.parseCallable(
            from: "Sample.Outer.Inner.init() -> Sample.Outer.Inner",
            isStatic: false,
            moduleName: "Sample"
        )
        #expect(result?.owner == "Outer.Inner")
        #expect(result?.isInitializer == true)
    }

    @Test
    func failableInitializer() {
        let result = builder.parseCallable(
            from: "Sample.Parser.init(data: Foundation.Data) -> Sample.Parser?",
            isStatic: false,
            moduleName: "Sample"
        )
        #expect(result?.isInitializer == true)
        #expect(result?.rawSignature == "init(data: Foundation.Data) -> Sample.Parser?")
    }
}

// MARK: - Owner Member Path

@Suite("parseOwnerMemberPath")
struct OwnerMemberPathTests {
    @Test
    func basicPath() {
        let result = builder.parseOwnerMemberPath("Sample.Record.value", moduleName: "Sample")
        #expect(result?.owner == "Record")
        #expect(result?.name == "value")
    }

    @Test
    func nestedOwnerPath() {
        let result = builder.parseOwnerMemberPath("Sample.Outer.Inner.value", moduleName: "Sample")
        #expect(result?.owner == "Outer.Inner")
        #expect(result?.name == "value")
    }

    @Test
    func wrongModuleReturnsNil() {
        #expect(builder.parseOwnerMemberPath("Other.Record.value", moduleName: "Sample") == nil)
    }

    @Test
    func noMemberComponentReturnsNil() {
        #expect(builder.parseOwnerMemberPath("Sample.Record", moduleName: "Sample") == nil)
    }
}

// MARK: - Split Top Level

@Suite("splitTopLevel")
struct SplitTopLevelTests {
    @Test
    func emptyString() throws {
        let result = try builder.splitTopLevel("")
        #expect(result.isEmpty)
    }

    @Test
    func singleArgument() throws {
        let result = try builder.splitTopLevel("Swift.String")
        #expect(result == ["Swift.String"])
    }

    @Test
    func multipleArguments() throws {
        let result = try builder.splitTopLevel("Swift.String, Swift.Int, Swift.Bool")
        #expect(result == ["Swift.String", "Swift.Int", "Swift.Bool"])
    }

    @Test
    func nestedGenerics() throws {
        let result = try builder.splitTopLevel("Swift.Array<Swift.String>, Swift.Int")
        #expect(result == ["Swift.Array<Swift.String>", "Swift.Int"])
    }

    @Test
    func nestedParentheses() throws {
        let result = try builder.splitTopLevel("(Swift.Int, Swift.Int), Swift.String")
        #expect(result == ["(Swift.Int, Swift.Int)", "Swift.String"])
    }

    @Test
    func closureWithArrow() throws {
        let result = try builder.splitTopLevel("(Swift.Int) -> Swift.String, Swift.Bool")
        #expect(result == ["(Swift.Int) -> Swift.String", "Swift.Bool"])
    }

    @Test
    func deeplyNestedGenerics() throws {
        let result = try builder.splitTopLevel("Swift.Dictionary<Swift.String, Swift.Array<Swift.Int>>")
        #expect(result == ["Swift.Dictionary<Swift.String, Swift.Array<Swift.Int>>"])
    }

    @Test
    func unbalancedThrows() {
        #expect(throws: SwiftInterfaceGeneratorError.self) {
            try builder.splitTopLevel("Swift.Array<Swift.Int")
        }
    }
}

// MARK: - Cleaned Type Name

@Suite("cleanedTypeName")
struct CleanedTypeNameTests {
    @Test
    func removesModulePrefix() {
        #expect(builder.cleanedTypeName("Sample.Record", moduleName: "Sample") == "Record")
    }

    @Test
    func removesOwnedPrefix() {
        #expect(builder.cleanedTypeName("__owned Swift.String") == "Swift.String")
    }

    @Test
    func replacesCGAffineTransform() {
        #expect(builder.cleanedTypeName("__C.CGAffineTransform") == "CoreGraphics.CGAffineTransform")
    }

    @Test
    func replacesCGFloat() {
        #expect(builder.cleanedTypeName("__C.CGFloat") == "CoreGraphics.CGFloat")
    }

    @Test
    func replacesCGPoint() {
        #expect(builder.cleanedTypeName("__C.CGPoint") == "CoreGraphics.CGPoint")
    }

    @Test
    func replacesCGRect() {
        #expect(builder.cleanedTypeName("__C.CGRect") == "CoreGraphics.CGRect")
    }

    @Test
    func replacesCGSize() {
        #expect(builder.cleanedTypeName("__C.CGSize") == "CoreGraphics.CGSize")
    }

    @Test
    func replacesCGImage() {
        #expect(builder.cleanedTypeName("__C.CGImageRef") == "CoreGraphics.CGImage")
    }

    @Test
    func replacesCATransform3D() {
        #expect(builder.cleanedTypeName("__C.CATransform3D") == "QuartzCore.CATransform3D")
    }

    @Test
    func replacesNSCoder() {
        #expect(builder.cleanedTypeName("__C.NSCoder") == "Foundation.NSCoder")
    }

    @Test
    func replacesNSUserActivity() {
        #expect(builder.cleanedTypeName("__C.NSUserActivity") == "Foundation.NSUserActivity")
    }

    @Test
    func replacesNSHashTable() {
        #expect(builder.cleanedTypeName("__C.NSHashTable") == "Foundation.NSHashTable")
    }

    @Test
    func replacesIOSurfaceRef() {
        #expect(builder.cleanedTypeName("__C.IOSurfaceRef") == "IOSurfaceRef")
    }

    @Test
    func replacesAuditToken() {
        #expect(builder.cleanedTypeName("__C.audit_token_t") == "Darwin.audit_token_t")
    }

    @Test
    func replacesGenericPlaceholder() {
        #expect(builder.cleanedTypeName("A.T") == "T")
    }

    @Test
    func preservesMetatypeSyntax() {
        #expect(builder.cleanedTypeName("A.Type") == "A.Type")
    }

    @Test
    func preservesAssociatedTypePath() {
        #expect(builder.cleanedTypeName("A.PartiallyGenerated") == "A.PartiallyGenerated")
    }

    @Test
    func preservesAssociatedTypeElement() {
        #expect(builder.cleanedTypeName("A.Element") == "A.Element")
    }

    @Test
    func preservesAssociatedTypeIterator() {
        #expect(builder.cleanedTypeName("A.Iterator") == "A.Iterator")
    }

    @Test
    func noReplacementNeeded() {
        #expect(builder.cleanedTypeName("Swift.String") == "Swift.String")
    }

    @Test
    func stripsExtensionContextPrefix() {
        #expect(
            builder.cleanedTypeName(
                "(extension in Sample):Sample.Material.Context",
                moduleName: "Sample"
            ) == "Material.Context"
        )
    }

    @Test
    func removesRedundantExtensionConstraintClauseAfterConcreteGenericArguments() {
        #expect(
            builder.cleanedTypeName(
                "(extension in Sample):Sample.Store<Swift.Int><A where A == Swift.Int>.Node",
                moduleName: "Sample"
            ) == "Store<Swift.Int>.Node"
        )
    }

    @Test
    func combinedReplacements() {
        #expect(
            builder.cleanedTypeName("__owned Sample.Record", moduleName: "Sample") == "Record"
        )
    }
}

// MARK: - Rendered Type Name

@Suite("renderedTypeName")
struct RenderedTypeNameTests {
    @Test
    func plainType() {
        #expect(builder.renderedTypeName("Swift.String", protocolNames: []) == "Swift.String")
    }

    @Test
    func protocolGetsAnyPrefix() {
        #expect(
            builder.renderedTypeName("Greeter", protocolNames: ["Greeter"]) == "any Greeter"
        )
    }

    @Test
    func optionalProtocolGetsWrapped() {
        #expect(
            builder.renderedTypeName("Greeter?", protocolNames: ["Greeter"]) == "(any Greeter)?"
        )
    }

    @Test
    func nonProtocolOptionalUnchanged() {
        #expect(builder.renderedTypeName("Swift.String?", protocolNames: ["Greeter"]) == "Swift.String?")
    }

    @Test
    func stripsModulePrefix() {
        #expect(
            builder.renderedTypeName("Sample.Record", protocolNames: [], moduleName: "Sample") == "Record"
        )
    }

    @Test
    func nestedProtocolTypesGetAnyPrefix() {
        #expect(
            builder.renderedTypeName(
                "Swift.KeyValuePairs<Swift.String, ConvertibleToGeneratedContent>",
                protocolNames: ["ConvertibleToGeneratedContent"]
            ) == "Swift.KeyValuePairs<Swift.String, any ConvertibleToGeneratedContent>"
        )
        #expect(
            builder.renderedTypeName(
                "(Swift.String, ConvertibleToGeneratedContent)",
                protocolNames: ["ConvertibleToGeneratedContent"]
            ) == "(Swift.String, any ConvertibleToGeneratedContent)"
        )
    }
}

// MARK: - Escaped Identifier

@Suite("escapedIdentifier")
struct EscapedIdentifierTests {
    @Test
    func regularIdentifier() {
        #expect(builder.escapedIdentifier("name") == "name")
    }

    @Test
    func classKeyword() {
        #expect(builder.escapedIdentifier("class") == "`class`")
    }

    @Test
    func defaultKeyword() {
        #expect(builder.escapedIdentifier("default") == "`default`")
    }

    @Test
    func selfKeyword() {
        #expect(builder.escapedIdentifier("self") == "`self`")
    }

    @Test
    func returnKeyword() {
        #expect(builder.escapedIdentifier("return") == "`return`")
    }

    @Test
    func varKeyword() {
        #expect(builder.escapedIdentifier("var") == "`var`")
    }

    @Test
    func letKeyword() {
        #expect(builder.escapedIdentifier("let") == "`let`")
    }

    @Test
    func structKeyword() {
        #expect(builder.escapedIdentifier("struct") == "`struct`")
    }

    @Test
    func enumKeyword() {
        #expect(builder.escapedIdentifier("enum") == "`enum`")
    }

    @Test
    func protocolKeyword() {
        #expect(builder.escapedIdentifier("protocol") == "`protocol`")
    }

    @Test
    func initKeyword() {
        #expect(builder.escapedIdentifier("init") == "`init`")
    }

    @Test
    func whereKeyword() {
        #expect(builder.escapedIdentifier("where") == "`where`")
    }

    @Test
    func subscriptKeyword() {
        #expect(builder.escapedIdentifier("subscript") == "`subscript`")
    }

    @Test
    func importKeyword() {
        #expect(builder.escapedIdentifier("import") == "`import`")
    }

    @Test
    func nonKeywordUnchanged() {
        #expect(builder.escapedIdentifier("myVariable") == "myVariable")
    }
}

// MARK: - Normalized Module Name

@Suite("normalizedModuleName")
struct NormalizedModuleNameTests {
    @Test
    func frameworkBinaryURL() {
        let url = URL(fileURLWithPath: "/path/to/MyFramework.framework/MyFramework")
        #expect(builder.normalizedModuleName(for: url) == "MyFramework")
    }

    @Test
    func plainBinaryURL() {
        let url = URL(fileURLWithPath: "/path/to/MyLib")
        #expect(builder.normalizedModuleName(for: url) == "MyLib")
    }

    @Test
    func binaryWithExtension() {
        let url = URL(fileURLWithPath: "/path/to/MyLib.dylib")
        #expect(builder.normalizedModuleName(for: url) == "MyLib")
    }
}

// MARK: - Swiftinterface Filename

@Suite("swiftinterfaceFilename")
struct SwiftinterfaceFilenameTests {
    @Test
    func macOSTriple() {
        #expect(
            builder.swiftinterfaceFilename(for: "arm64-apple-macosx15.0")
                == "arm64-apple-macosx.swiftinterface"
        )
    }

    @Test
    func iOSTriple() {
        #expect(
            builder.swiftinterfaceFilename(for: "arm64-apple-ios17.0")
                == "arm64-apple-ios.swiftinterface"
        )
    }

    @Test
    func iOSSimulatorTriple() {
        #expect(
            builder.swiftinterfaceFilename(for: "arm64-apple-ios17.0-simulator")
                == "arm64-apple-ios-simulator.swiftinterface"
        )
    }

    @Test
    func shortTriple() {
        #expect(
            builder.swiftinterfaceFilename(for: "arm64")
                == "arm64.swiftinterface"
        )
    }

    @Test
    func x86Triple() {
        #expect(
            builder.swiftinterfaceFilename(for: "x86_64-apple-macosx14.0")
                == "x86_64-apple-macosx.swiftinterface"
        )
    }
}

// MARK: - Rendered Argument List

@Suite("renderedArgumentList")
struct RenderedArgumentListTests {
    @Test
    func emptyArguments() throws {
        #expect(try builder.renderedArgumentList("", protocolNames: [], moduleName: "Sample") == "")
    }

    @Test
    func singleLabeledArgument() throws {
        let result = try builder.renderedArgumentList(
            "name: Swift.String",
            protocolNames: [],
            moduleName: "Sample"
        )
        #expect(result == "name: Swift.String")
    }

    @Test
    func unlabeledArgument() throws {
        let result = try builder.renderedArgumentList(
            "Swift.Int",
            protocolNames: [],
            moduleName: ""
        )
        #expect(result == "_: Swift.Int")
    }

    @Test
    func multipleArguments() throws {
        let result = try builder.renderedArgumentList(
            "key: Swift.String, value: Swift.Int",
            protocolNames: [],
            moduleName: "Sample"
        )
        #expect(result == "key: Swift.String, value: Swift.Int")
    }

    @Test
    func argumentWithProtocolType() throws {
        let result = try builder.renderedArgumentList(
            "handler: Greeter",
            protocolNames: ["Greeter"],
            moduleName: ""
        )
        #expect(result == "handler: any Greeter")
    }

    @Test
    func argumentWithModuleStripping() throws {
        let result = try builder.renderedArgumentList(
            "record: Sample.Record",
            protocolNames: [],
            moduleName: "Sample"
        )
        #expect(result == "record: Record")
    }

    @Test
    func underscoreLabel() throws {
        let result = try builder.renderedArgumentList(
            "_: Swift.Int",
            protocolNames: [],
            moduleName: ""
        )
        #expect(result == "_: Swift.Int")
    }

    @Test
    func stripsExtensionContextPrefixesInArgumentTypes() throws {
        let result = try builder.renderedArgumentList(
            "_: (extension in Sample):Sample.Material.Context, in: inout (extension in Sample):Sample.Material.State",
            protocolNames: [],
            moduleName: "Sample"
        )
        #expect(result == "_: Material.Context, `in`: inout Material.State")
    }
}

// MARK: - Normalized Symbol Line

@Suite("normalizedSymbolLine")
struct NormalizedSymbolLineTests {
    @Test
    func standardNmOutput() {
        let result = SwiftInterfaceGenerator.normalizedSymbolLine(
            "0000000000001234 T nominal type descriptor for Sample.Record"
        )
        #expect(result == "nominal type descriptor for Sample.Record")
    }

    @Test
    func shortAddress() {
        let result = SwiftInterfaceGenerator.normalizedSymbolLine(
            "00ff S protocol descriptor for Sample.Greeter"
        )
        #expect(result == "protocol descriptor for Sample.Greeter")
    }

    @Test
    func alreadyNormalized() {
        let result = SwiftInterfaceGenerator.normalizedSymbolLine(
            "nominal type descriptor for Sample.Record"
        )
        #expect(result == "nominal type descriptor for Sample.Record")
    }

    @Test
    func emptyLine() {
        #expect(SwiftInterfaceGenerator.normalizedSymbolLine("") == "")
    }
}
