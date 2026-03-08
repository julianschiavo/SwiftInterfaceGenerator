import Foundation
import SwiftParser
import SwiftSyntax

/// Builds `.swiftinterface` file contents from demangled symbol data.
///
/// `SwiftInterfaceBuilder` is the core parser and renderer. It takes an array of demangled
/// symbol strings, discovers type declarations (structs, classes, enums, protocols) and their
/// members, then renders a valid `.swiftinterface` file as a string.
struct SwiftInterfaceBuilder: Sendable {
    private let renderableExternalModules: Set<String>?

    /// An intermediate representation of a discovered type declaration.
    struct Declaration: Sendable {
        /// The kind of Swift type declaration.
        enum Kind: Sendable {
            case `protocol`
            case `struct`
            case `class`
            case `enum`
        }

        /// A discovered property on a type.
        struct Property: Sendable, Hashable {
            let name: String
            let rawType: String
            let isStatic: Bool
            let hasSetter: Bool
            let extensionWhereClause: String
            let order: Int
        }

        /// A discovered associated type requirement on a protocol.
        struct AssociatedType: Sendable, Hashable {
            let name: String
            var conformances: [String]
            let order: Int
        }

        /// A discovered subscript requirement or member on a type.
        struct Subscript: Sendable, Hashable {
            let rawArguments: String
            let rawReturnType: String
            let hasSetter: Bool
            let extensionWhereClause: String
            let order: Int
        }

        /// A discovered method or initializer on a type.
        struct Callable: Sendable, Hashable {
            let rawSignature: String
            let isStatic: Bool
            let isInitializer: Bool
            let order: Int
        }

        /// A discovered enum case, optionally with an associated value payload.
        struct EnumCase: Sendable, Hashable {
            let name: String
            let rawPayload: String?
            let rawOwnerType: String?
            let order: Int
        }

        let fullName: String
        let order: Int
        var isExternalExtension = false
        var isProtocol = false
        var isClass = false
        var isOpen = false
        var conformances: [String] = []
        var associatedTypes: [AssociatedType] = []
        var properties: [Property] = []
        var extensionProperties: [Property] = []
        var subscripts: [Subscript] = []
        var extensionSubscripts: [Subscript] = []
        var initializers: [Callable] = []
        var extensionInitializers: [Callable] = []
        var methods: [Callable] = []
        var extensionMethods: [Callable] = []
        var staticMethods: [Callable] = []
        var extensionStaticMethods: [Callable] = []
        var enumCases: [EnumCase] = []

        /// Adds a protocol conformance if not already present.
        mutating func addConformance(_ conformance: String) {
            guard !conformances.contains(conformance) else {
                return
            }
            conformances.append(conformance)
        }

        /// Adds an associated type if not already present.
        mutating func addAssociatedType(_ name: String, order: Int) {
            guard !associatedTypes.contains(where: { $0.name == name }) else {
                return
            }
            associatedTypes.append(AssociatedType(name: name, conformances: [], order: order))
        }

        /// Adds an associated type conformance requirement if not already present.
        mutating func addAssociatedTypeConformance(
            associatedType name: String,
            conformance: String,
            order: Int
        ) {
            if let existingIndex = associatedTypes.firstIndex(where: { $0.name == name }) {
                guard !associatedTypes[existingIndex].conformances.contains(conformance) else {
                    return
                }
                associatedTypes[existingIndex].conformances.append(conformance)
                return
            }

            associatedTypes.append(
                AssociatedType(name: name, conformances: [conformance], order: order)
            )
        }

        /// Adds a property, deduplicating by name and static-ness.
        mutating func addProperty(_ property: Property) {
            if let existingIndex = properties.firstIndex(where: {
                $0.name == property.name && $0.isStatic == property.isStatic
            }) {
                if property.hasSetter && !properties[existingIndex].hasSetter {
                    properties[existingIndex] = property
                }
                return
            }
            properties.append(property)
        }

        /// Adds a protocol-extension property, deduplicating by name and static-ness.
        mutating func addExtensionProperty(_ property: Property) {
            if let existingIndex = extensionProperties.firstIndex(where: {
                $0.name == property.name
                    && $0.isStatic == property.isStatic
                    && $0.extensionWhereClause == property.extensionWhereClause
            }) {
                if property.hasSetter && !extensionProperties[existingIndex].hasSetter {
                    extensionProperties[existingIndex] = property
                }
                return
            }
            extensionProperties.append(property)
        }

        /// Adds a subscript, deduplicating by argument and return type.
        mutating func addSubscript(_ subscriptMember: Subscript) {
            guard !subscripts.contains(where: {
                $0.rawArguments == subscriptMember.rawArguments && $0.rawReturnType == subscriptMember.rawReturnType
            }) else {
                return
            }
            subscripts.append(subscriptMember)
        }

        /// Adds a protocol-extension subscript, deduplicating by arguments, return type, and constraint.
        mutating func addExtensionSubscript(_ subscriptMember: Subscript) {
            guard !extensionSubscripts.contains(where: {
                $0.rawArguments == subscriptMember.rawArguments
                    && $0.rawReturnType == subscriptMember.rawReturnType
                    && $0.extensionWhereClause == subscriptMember.extensionWhereClause
            }) else {
                return
            }
            extensionSubscripts.append(subscriptMember)
        }

        /// Adds an initializer, deduplicating by raw signature.
        mutating func addInitializer(_ callable: Callable) {
            guard !initializers.contains(where: { $0.rawSignature == callable.rawSignature }) else {
                return
            }
            initializers.append(callable)
        }

        /// Adds a protocol-extension initializer, deduplicating by raw signature.
        mutating func addExtensionInitializer(_ callable: Callable) {
            guard !extensionInitializers.contains(where: { $0.rawSignature == callable.rawSignature }) else {
                return
            }
            extensionInitializers.append(callable)
        }

        /// Adds an instance method, deduplicating by signature and static-ness.
        mutating func addMethod(_ callable: Callable) {
            guard !methods.contains(where: { $0.rawSignature == callable.rawSignature && $0.isStatic == callable.isStatic }) else {
                return
            }
            methods.append(callable)
        }

        /// Adds a protocol-extension instance method, deduplicating by signature and static-ness.
        mutating func addExtensionMethod(_ callable: Callable) {
            guard !extensionMethods.contains(where: {
                $0.rawSignature == callable.rawSignature && $0.isStatic == callable.isStatic
            }) else {
                return
            }
            extensionMethods.append(callable)
        }

        /// Adds a static method, deduplicating by raw signature.
        mutating func addStaticMethod(_ callable: Callable) {
            guard !staticMethods.contains(where: { $0.rawSignature == callable.rawSignature }) else {
                return
            }
            staticMethods.append(callable)
        }

        /// Adds a protocol-extension static method, deduplicating by raw signature.
        mutating func addExtensionStaticMethod(_ callable: Callable) {
            guard !extensionStaticMethods.contains(where: { $0.rawSignature == callable.rawSignature }) else {
                return
            }
            extensionStaticMethods.append(callable)
        }

        /// Adds an enum case, deduplicating by name.
        mutating func addEnumCase(_ enumCase: EnumCase) {
            guard !enumCases.contains(where: { $0.name == enumCase.name }) else {
                return
            }
            enumCases.append(enumCase)
        }

        /// Determines the declaration kind from the discovered metadata.
        ///
        /// All raw type-bearing strings from this declaration's members (excluding conformances).
        var rawTypeFragments: [String] {
            let callableFragments =
                initializers.map(\.rawSignature)
                + extensionInitializers.map(\.rawSignature)
                + methods.map(\.rawSignature)
                + extensionMethods.map(\.rawSignature)
                + staticMethods.map(\.rawSignature)
                + extensionStaticMethods.map(\.rawSignature)
            let propertyFragments =
                properties.map(\.rawType)
                + extensionProperties.flatMap { [$0.rawType, $0.extensionWhereClause] }
            let subscriptFragments =
                subscripts.flatMap { [$0.rawArguments, $0.rawReturnType] }
                + extensionSubscripts.flatMap { [$0.rawArguments, $0.rawReturnType, $0.extensionWhereClause] }
            let enumFragments =
                enumCases.compactMap(\.rawPayload)
                + enumCases.compactMap(\.rawOwnerType)
            return callableFragments + propertyFragments + subscriptFragments + enumFragments
        }

        /// Protocol takes priority, then enum (if cases exist), then class, defaulting to struct.
        var resolvedKind: Kind {
            if isProtocol {
                return .protocol
            }
            if !enumCases.isEmpty {
                return .enum
            }
            if isClass {
                return .class
            }
            return .struct
        }
    }

    init(renderableExternalModules: Set<String>? = nil) {
        self.renderableExternalModules = renderableExternalModules
    }

    /// Builds a complete `.swiftinterface` file string from demangled symbols.
    ///
    /// This is the main entry point. It discovers declarations from the symbol list,
    /// then renders them into a formatted interface string with the standard header.
    ///
    /// - Parameters:
    ///   - demangledSymbols: The array of demangled symbol lines to parse.
    ///   - targetTriple: The target triple for the interface header.
    ///   - moduleName: The module name for the interface header and symbol resolution.
    ///   - compilerVersion: The Swift compiler version string for the header.
    /// - Returns: A complete `.swiftinterface` file as a string.
    func makeInterface(
        demangledSymbols: [String],
        targetTriple: String,
        moduleName: String,
        compilerVersion: String
    ) -> String {
        let declarations = discoverDeclarations(from: demangledSymbols, moduleName: moduleName)
        return renderInterface(
            declarations: declarations,
            targetTriple: targetTriple,
            moduleName: moduleName,
            compilerVersion: compilerVersion
        )
    }

    /// A sorted array of symbols that supports efficient prefix-matching via binary search.
    struct SortedSymbols {
        let sorted: [String]

        init(_ symbols: [String]) {
            self.sorted = symbols.sorted()
        }

        func containsPrefix(_ prefix: String) -> Bool {
            var low = 0
            var high = sorted.count
            while low < high {
                let mid = (low + high) / 2
                if sorted[mid] < prefix {
                    low = mid + 1
                } else {
                    high = mid
                }
            }
            return low < sorted.count && sorted[low].hasPrefix(prefix)
        }
    }

    /// Iterates over demangled symbols and builds a dictionary of discovered declarations.
    ///
    /// Each symbol line is matched against known patterns (nominal type descriptors, protocol
    /// descriptors, metaclass markers, property descriptors, enum cases, method signatures,
    /// dispatch thunks, etc.) to populate the declaration model.
    ///
    /// - Parameters:
    ///   - demangledSymbols: The demangled symbol lines to scan.
    ///   - moduleName: The module name used to match symbol prefixes.
    /// - Returns: A dictionary keyed by fully-qualified type name, containing the
    ///   discovered ``Declaration`` for each type.
    func discoverDeclarations(
        from demangledSymbols: [String],
        moduleName: String
    ) -> [String: Declaration] {
        var declarations: [String: Declaration] = [:]
        let sortedSymbols = SortedSymbols(demangledSymbols)
        let protocolDescriptorPrefix = "protocol descriptor for \(moduleName)."
        let nominalTypePrefix = "nominal type descriptor for \(moduleName)."
        let metaclassPrefix = "metaclass for \(moduleName)."
        let classMetadataPrefix = "class metadata base offset for \(moduleName)."
        let protocolTypeNames = Set(
            demangledSymbols.compactMap {
                extractedTypeName(from: $0, prefix: protocolDescriptorPrefix, moduleName: moduleName)
            }
        )
        let concreteTypeNames = Set(
            demangledSymbols.compactMap {
                extractedTypeName(from: $0, prefix: nominalTypePrefix, moduleName: moduleName)
            }
        )
        let externalExtensionOwnerNames = Set(
            demangledSymbols.compactMap {
                sameModuleExtensionOwnerName(from: $0, moduleName: moduleName)
            }
        )
        let extensionMemberOwners = concreteTypeNames
            .union(protocolTypeNames)
            .union(externalExtensionOwnerNames)

        func declaration(named fullName: String, order: Int) -> Declaration {
            declarations[fullName] ?? Declaration(fullName: fullName, order: order)
        }

        func setDeclaration(_ declaration: Declaration) {
            declarations[declaration.fullName] = declaration
        }

        for (order, line) in demangledSymbols.enumerated() {
            if let fullName = extractedTypeName(
                from: line,
                prefix: protocolDescriptorPrefix,
                moduleName: moduleName
            ) {
                var value = declaration(named: fullName, order: order)
                value.isProtocol = true
                setDeclaration(value)
                continue
            }

            if let fullName = extractedTypeName(
                from: line,
                prefix: nominalTypePrefix,
                moduleName: moduleName
            ) {
                setDeclaration(declaration(named: fullName, order: order))
                continue
            }

            if let fullName = extractedTypeName(
                from: line,
                prefix: metaclassPrefix,
                moduleName: moduleName
            ) {
                var value = declaration(named: fullName, order: order)
                value.isClass = true
                setDeclaration(value)
                continue
            }

            if let fullName = extractedTypeName(
                from: line,
                prefix: classMetadataPrefix,
                moduleName: moduleName
            ) {
                var value = declaration(named: fullName, order: order)
                value.isClass = true
                setDeclaration(value)
                continue
            }

            if let (owner, associatedType) = parseAssociatedTypeDescriptor(from: line, moduleName: moduleName) {
                var value = declaration(named: owner, order: order)
                value.addAssociatedType(associatedType, order: order)
                setDeclaration(value)
                continue
            }

            if let (owner, associatedType, conformance) = parseAssociatedConformanceDescriptor(
                from: line,
                moduleName: moduleName
            ) {
                var value = declaration(named: owner, order: order)
                value.addAssociatedTypeConformance(
                    associatedType: associatedType,
                    conformance: conformance,
                    order: order
                )
                setDeclaration(value)
                continue
            }

            if let (owner, conformance) = parseConformanceDescriptor(from: line, moduleName: moduleName) {
                var value = declaration(named: owner, order: order)
                value.addConformance(conformance)
                setDeclaration(value)
                continue
            }

            if let (owner, conformance) = parseExternalConformanceDescriptor(
                from: line,
                moduleName: moduleName
            ) {
                var value = declaration(named: owner, order: order)
                value.isExternalExtension = true
                value.addConformance(conformance)
                setDeclaration(value)
                continue
            }

            if let (owner, conformance) = parseBaseConformanceDescriptor(from: line, moduleName: moduleName) {
                var value = declaration(named: owner, order: order)
                value.addConformance(conformance)
                setDeclaration(value)
                continue
            }

            if let subscriptMember = parseSubscriptDescriptor(
                from: line,
                sortedSymbols: sortedSymbols,
                moduleName: moduleName,
                allowExtensionMembersOn: extensionMemberOwners
            ) {
                var value = declaration(named: subscriptMember.owner, order: order)
                if !concreteTypeNames.contains(subscriptMember.owner),
                   !protocolTypeNames.contains(subscriptMember.owner) {
                    value.isExternalExtension = true
                }
                let subscriptDeclaration = Declaration.Subscript(
                    rawArguments: subscriptMember.rawArguments,
                    rawReturnType: subscriptMember.rawReturnType,
                    hasSetter: subscriptMember.hasSetter,
                    extensionWhereClause: extensionConstraintClause(
                        fromMemberDescriptor: line,
                        memberDescriptorPrefix: "property descriptor for ",
                        moduleName: moduleName
                    ),
                    order: order
                )
                if isSameModuleExtensionMember(
                    line,
                    memberPrefix: "property descriptor for ",
                    moduleName: moduleName
                ), protocolTypeNames.contains(subscriptMember.owner) {
                    value.addExtensionSubscript(subscriptDeclaration)
                } else {
                    value.addSubscript(subscriptDeclaration)
                }
                setDeclaration(value)
                continue
            }

            if let property = parsePropertyDescriptor(
                from: line,
                sortedSymbols: sortedSymbols,
                moduleName: moduleName,
                allowExtensionMembersOn: extensionMemberOwners
            ) {
                var value = declaration(named: property.owner, order: order)
                if !concreteTypeNames.contains(property.owner),
                   !protocolTypeNames.contains(property.owner) {
                    value.isExternalExtension = true
                }
                let propertyDeclaration = Declaration.Property(
                    name: property.name,
                    rawType: property.rawType,
                    isStatic: property.isStatic,
                    hasSetter: property.hasSetter,
                    extensionWhereClause: extensionConstraintClause(
                        fromMemberDescriptor: line,
                        memberDescriptorPrefix: "property descriptor for ",
                        moduleName: moduleName
                    ),
                    order: order
                )
                if isSameModuleExtensionMember(
                    line,
                    memberPrefix: "property descriptor for ",
                    moduleName: moduleName
                ), protocolTypeNames.contains(property.owner) {
                    value.addExtensionProperty(propertyDeclaration)
                } else {
                    value.addProperty(propertyDeclaration)
                }
                setDeclaration(value)
                continue
            }

            if let enumCase = parseEnumCase(from: line, moduleName: moduleName) {
                var value = declaration(named: enumCase.owner, order: order)
                value.addEnumCase(
                    Declaration.EnumCase(
                        name: enumCase.name,
                        rawPayload: enumCase.rawPayload,
                        rawOwnerType: enumCase.rawOwnerType,
                        order: order
                    )
                )
                setDeclaration(value)
                continue
            }

            if let property = parseProtocolPropertyDescriptor(
                from: line,
                sortedSymbols: sortedSymbols,
                moduleName: moduleName
            ) {
                var value = declaration(named: property.owner, order: order)
                value.addProperty(
                    Declaration.Property(
                        name: property.name,
                        rawType: property.rawType,
                        isStatic: property.isStatic,
                        hasSetter: property.hasSetter,
                        extensionWhereClause: "",
                        order: order
                    )
                )
                setDeclaration(value)
                continue
            }

            if let callable = parseProtocolMethodDescriptor(from: line, moduleName: moduleName) {
                var value = declaration(named: callable.owner, order: order)
                let isInit = callable.rawSignature.hasPrefix("init(") || callable.rawSignature.hasPrefix("init<")
                if isInit {
                    value.addInitializer(
                        Declaration.Callable(
                            rawSignature: callable.rawSignature,
                            isStatic: false,
                            isInitializer: true,
                            order: order
                        )
                    )
                } else {
                    value.addMethod(
                        Declaration.Callable(
                            rawSignature: callable.rawSignature,
                            isStatic: false,
                            isInitializer: false,
                            order: order
                        )
                    )
                }
                setDeclaration(value)
                continue
            }

            if let callable = parseCallable(
                from: line,
                isStatic: true,
                moduleName: moduleName,
                allowExtensionMembersOn: extensionMemberOwners
            ) {
                var value = declaration(named: callable.owner, order: order)
                if !concreteTypeNames.contains(callable.owner),
                   !protocolTypeNames.contains(callable.owner) {
                    value.isExternalExtension = true
                }
                let isProtocolExtensionMember = isSameModuleExtensionMember(
                    line,
                    memberPrefix: "static ",
                    moduleName: moduleName
                ) && protocolTypeNames.contains(callable.owner)
                if callable.isInitializer {
                    let callableDeclaration = Declaration.Callable(
                        rawSignature: callable.rawSignature,
                        isStatic: true,
                        isInitializer: true,
                        order: order
                    )
                    if isProtocolExtensionMember {
                        value.addExtensionInitializer(callableDeclaration)
                    } else {
                        value.addInitializer(callableDeclaration)
                    }
                } else {
                    let callableDeclaration = Declaration.Callable(
                        rawSignature: callable.rawSignature,
                        isStatic: true,
                        isInitializer: false,
                        order: order
                    )
                    if isProtocolExtensionMember {
                        value.addExtensionStaticMethod(callableDeclaration)
                    } else {
                        value.addStaticMethod(callableDeclaration)
                    }
                }
                setDeclaration(value)
                continue
            }

            if let callable = parseCallable(
                from: line,
                isStatic: false,
                moduleName: moduleName,
                allowExtensionMembersOn: extensionMemberOwners
            ) {
                var value = declaration(named: callable.owner, order: order)
                if !concreteTypeNames.contains(callable.owner),
                   !protocolTypeNames.contains(callable.owner) {
                    value.isExternalExtension = true
                }
                let isProtocolExtensionMember = isSameModuleExtensionMember(
                    line,
                    memberPrefix: "",
                    moduleName: moduleName
                ) && protocolTypeNames.contains(callable.owner)
                if callable.isInitializer {
                    let callableDeclaration = Declaration.Callable(
                        rawSignature: callable.rawSignature,
                        isStatic: false,
                        isInitializer: true,
                        order: order
                    )
                    if isProtocolExtensionMember {
                        value.addExtensionInitializer(callableDeclaration)
                    } else {
                        value.addInitializer(callableDeclaration)
                    }
                } else {
                    let callableDeclaration = Declaration.Callable(
                        rawSignature: callable.rawSignature,
                        isStatic: false,
                        isInitializer: false,
                        order: order
                    )
                    if isProtocolExtensionMember {
                        value.addExtensionMethod(callableDeclaration)
                    } else {
                        value.addMethod(callableDeclaration)
                    }
                }
                setDeclaration(value)
                continue
            }

            if let dispatchThunk = parseDispatchThunk(from: line, moduleName: moduleName) {
                var value = declaration(named: dispatchThunk.owner, order: order)
                value.isOpen = true
                if dispatchThunk.isInitializer {
                    value.addInitializer(
                        Declaration.Callable(
                            rawSignature: dispatchThunk.rawSignature,
                            isStatic: false,
                            isInitializer: true,
                            order: order
                        )
                    )
                } else {
                    value.addMethod(
                        Declaration.Callable(
                            rawSignature: dispatchThunk.rawSignature,
                            isStatic: false,
                            isInitializer: false,
                            order: order
                        )
                    )
                }
                setDeclaration(value)
                continue
            }
        }

        // Create stub declarations for nested types that are referenced in member
        // signatures but lack a nominal type descriptor (e.g. SPI types).
        let declaredNames = Set(declarations.keys)
        var stubs: [String: Declaration] = [:]
        // Scan all declared type names looking for references to undeclared nested types
        for parentName in declaredNames {
            let prefix = "\(parentName)."
            for decl in declarations.values {
                let stubCandidateFragments =
                    decl.properties.map(\.rawType)
                    + decl.extensionProperties.map(\.rawType)
                    + decl.subscripts.flatMap { [$0.rawArguments, $0.rawReturnType] }
                    + decl.extensionSubscripts.flatMap { [$0.rawArguments, $0.rawReturnType] }
                    + decl.enumCases.compactMap(\.rawPayload)
                for rawFragment in stubCandidateFragments {
                    guard rawFragment.contains(prefix) else { continue }
                    // Find all occurrences of ParentName.NestedType
                    var searchStart = rawFragment.startIndex
                    while let prefixRange = rawFragment.range(of: prefix, range: searchStart..<rawFragment.endIndex) {
                        let afterPrefix = rawFragment[prefixRange.upperBound...]
                        // Extract the nested type name (starts with uppercase)
                        guard let firstChar = afterPrefix.first, firstChar.isUppercase else {
                            searchStart = prefixRange.upperBound
                            continue
                        }
                        var nameEnd = prefixRange.upperBound
                        while nameEnd < rawFragment.endIndex {
                            let c = rawFragment[nameEnd]
                            guard c.isLetter || c.isNumber || c == "_" else { break }
                            nameEnd = rawFragment.index(after: nameEnd)
                        }
                        let nestedName = String(rawFragment[prefixRange.upperBound..<nameEnd])
                        let fullName = "\(parentName).\(nestedName)"
                        if !declaredNames.contains(fullName), stubs[fullName] == nil {
                            var stub = Declaration(
                                fullName: fullName,
                                order: Int.max - stubs.count
                            )
                            if declarations[parentName]?.isExternalExtension == true {
                                stub.isExternalExtension = true
                            }
                            stubs[fullName] = stub
                        }
                        searchStart = nameEnd
                    }
                }
            }
        }
        for (name, stub) in stubs {
            declarations[name] = stub
        }

        return declarations
    }

    func inferredModuleName(
        from demangledSymbols: [String],
        preferredModuleName: String
    ) -> String? {
        var counts: [String: Int] = [:]

        for line in demangledSymbols {
            guard let moduleName = inferredModuleName(from: line) else {
                continue
            }
            counts[moduleName, default: 0] += 1
        }

        guard
            let bestModule = counts.max(by: { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key > rhs.key
                }
                return lhs.value < rhs.value
            })?.key,
            bestModule != preferredModuleName
        else {
            return nil
        }

        return bestModule
    }

    /// Renders the full `.swiftinterface` file content from discovered declarations.
    ///
    /// Generates the standard header (format version, compiler version, module flags),
    /// import statements, and all top-level type declarations with their members.
    ///
    /// - Parameters:
    ///   - declarations: The discovered declarations to render.
    ///   - targetTriple: The target triple for the header.
    ///   - moduleName: The module name for the header and type name cleanup.
    ///   - compilerVersion: The compiler version string for the header.
    /// - Returns: The formatted `.swiftinterface` file content.
    func renderInterface(
        declarations: [String: Declaration],
        targetTriple: String,
        moduleName: String,
        compilerVersion: String
    ) -> String {
        let protocolNames = Set(
            declarations.values
                .filter { $0.resolvedKind == .protocol }
                .map(\.fullName)
        )
        let knownTypeComponents = localKnownTypeComponents(from: declarations)

        // Pre-compute children map: parent -> sorted child names (P4 optimization)
        var childrenMap: [String: [String]] = [:]
        for key in declarations.keys {
            if let parent = parentName(of: key, in: declarations) {
                childrenMap[parent, default: []].append(key)
            }
        }
        for key in childrenMap.keys {
            childrenMap[key]!.sort {
                declarations[$0, default: Declaration(fullName: $0, order: .max)].order
                    < declarations[$1, default: Declaration(fullName: $1, order: .max)].order
            }
        }

        // Pre-compute generic arity map (P3 optimization)
        let genericArityMap = precomputedGenericArities(declarations: declarations, moduleName: moduleName)

        let topLevelNames = declarations.keys
            .filter {
                parentName(of: $0, in: declarations) == nil
                    && declarations[$0]?.isExternalExtension != true
            }
            .sorted {
                declarations[$0, default: Declaration(fullName: $0, order: .max)].order
                    < declarations[$1, default: Declaration(fullName: $1, order: .max)].order
            }

        var lines = [
            "// swift-interface-format-version: 1.0",
            "// swift-compiler-version: \(compilerVersion)",
            "// swift-module-flags: -target \(targetTriple) -enable-library-evolution -module-name \(moduleName)",
            "import Swift",
        ]

        for module in discoveredImports(
            from: declarations,
            knownTypeComponents: knownTypeComponents,
            moduleName: moduleName
        ) {
            lines.append("import \(module)")
        }
        lines.append("")

        let allowedPrefixes = allowedModulePrefixes(
            knownTypeComponents: knownTypeComponents,
            moduleName: moduleName
        )

        for name in topLevelNames {
            lines.append(
                renderedDeclaration(
                    named: name,
                    declarations: declarations,
                    protocolNames: protocolNames,
                    knownTypeComponents: knownTypeComponents,
                    childrenMap: childrenMap,
                    genericArityMap: genericArityMap,
                    allowedPrefixes: allowedPrefixes,
                    moduleName: moduleName,
                    level: 0
                )
            )
            lines.append("")
        }

        for block in renderedExternalExtensionBlocks(
            declarations: declarations,
            protocolNames: protocolNames,
            knownTypeComponents: knownTypeComponents,
            allowedPrefixes: allowedPrefixes,
            moduleName: moduleName
        ) {
            lines.append(block)
            lines.append("")
        }

        for block in renderedProtocolExtensionBlocks(
            declarations: declarations,
            protocolNames: protocolNames,
            knownTypeComponents: knownTypeComponents,
            allowedPrefixes: allowedPrefixes,
            moduleName: moduleName
        ) {
            lines.append(block)
            lines.append("")
        }

        return lines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    /// Renders a single type declaration and its members as a string.
    ///
    /// Recursively renders nested type declarations. Handles struct, class (including open),
    /// enum, and protocol declarations with their properties, methods, initializers,
    /// enum cases, associated types, and conformances.
    ///
    /// - Parameters:
    ///   - fullName: The fully-qualified name of the declaration to render.
    ///   - declarations: All discovered declarations, for resolving nested types.
    ///   - protocolNames: The set of known protocol names, for `any` existential rendering.
    ///   - knownTypeComponents: Known type name components, used for generic parameter inference.
    ///   - moduleName: The module name for type name cleanup.
    ///   - level: The current indentation level (0 for top-level).
    /// - Returns: The rendered declaration string including its body and closing brace.
    private func renderedDeclaration(
        named fullName: String,
        declarations: [String: Declaration],
        protocolNames: Set<String>,
        knownTypeComponents: Set<String>,
        childrenMap: [String: [String]],
        genericArityMap: [String: Int],
        allowedPrefixes: Set<String>?,
        moduleName: String,
        level: Int
    ) -> String {
        guard let declaration = declarations[fullName] else {
            return ""
        }

        let indent = String(repeating: "  ", count: level)
        let childNames = declaration.resolvedKind == .protocol ? [] : (childrenMap[fullName] ?? [])
        let genericParameters = inferredGenericParameters(
            for: declaration,
            declarations: declarations,
            genericArityMap: genericArityMap,
            knownTypeComponents: knownTypeComponents,
            moduleName: moduleName
        )
        let genericClause = genericParameters.isEmpty ? "" : "<\(genericParameters.joined(separator: ", "))>"
        let genericWhereClause = renderedDeclarationGenericWhereClause(
            for: declaration,
            genericParameters: genericParameters,
            declarations: declarations,
            moduleName: moduleName
        )
        let name = escapedIdentifier(simpleName(of: fullName))
        let conformanceClause = renderedConformanceClause(
            for: declaration,
            allowedPrefixes: allowedPrefixes,
            moduleName: moduleName
        )
        let isProtocol = declaration.resolvedKind == .protocol
        let isOpenClass = declaration.resolvedKind == .class && declaration.isOpen
        let memberAccessPrefix = isProtocol ? "" : "public "

        let header: String
        switch declaration.resolvedKind {
        case .protocol:
            header = "\(indent)public protocol \(name)\(conformanceClause) {"
        case .struct:
            header = "\(indent)public struct \(name)\(genericClause)\(conformanceClause)\(genericWhereClause) {"
        case .class where isOpenClass:
            header = "\(indent)open class \(name)\(genericClause)\(conformanceClause)\(genericWhereClause) {"
        case .class:
            header = "\(indent)public final class \(name)\(genericClause)\(conformanceClause)\(genericWhereClause) {"
        case .enum:
            header = "\(indent)public enum \(name)\(genericClause)\(conformanceClause)\(genericWhereClause) {"
        }

        var body: [String] = []

        for childName in childNames {
            body.append(
                renderedDeclaration(
                    named: childName,
                    declarations: declarations,
                    protocolNames: protocolNames,
                    knownTypeComponents: knownTypeComponents,
                    childrenMap: childrenMap,
                    genericArityMap: genericArityMap,
                    allowedPrefixes: allowedPrefixes,
                    moduleName: moduleName,
                    level: level + 1
                )
            )
            body.append("")
        }

        for associatedType in declaration.associatedTypes.sorted(by: { $0.order < $1.order }) {
            let conformanceClause = renderedAssociatedTypeConformanceClause(
                for: associatedType,
                allowedPrefixes: allowedPrefixes,
                moduleName: moduleName
            )
            body.append(
                "\(indent)  associatedtype \(escapedIdentifier(associatedType.name))\(conformanceClause)"
            )
        }

        for typealiasName in selfAliasedAssociatedTypes(
            for: declaration,
            declarations: declarations,
            moduleName: moduleName
        ) {
            body.append("\(indent)  \(memberAccessPrefix)typealias \(escapedIdentifier(typealiasName)) = Self")
        }

        for enumCase in declaration.enumCases.sorted(by: { $0.order < $1.order }) {
            if let rawPayload = enumCase.rawPayload {
                guard
                    !containsUnrenderableExternalModuleReference(
                        rawPayload,
                        allowedPrefixes: allowedPrefixes
                    )
                else {
                    continue
                }
                body.append(
                    "\(indent)  case \(escapedIdentifier(enumCase.name))(\(renderedTypeName(rawPayload, protocolNames: protocolNames, moduleName: moduleName)))"
                )
            } else {
                body.append("\(indent)  case \(escapedIdentifier(enumCase.name))")
            }
        }

        for property in declaration.properties.sorted(by: { $0.order < $1.order }) {
            guard
                !containsUnrenderableExternalModuleReference(
                    property.rawType,
                    allowedPrefixes: allowedPrefixes
                ),
                declaration.resolvedKind == .protocol || !containsUnresolvedAssociatedTypeReference(property.rawType)
            else {
                continue
            }
            let rawType = resolvedOpaquePropertyType(
                property,
                in: declaration,
                declarations: declarations,
                moduleName: moduleName
            ) ?? property.rawType
            guard cleanedTypeName(rawType, moduleName: moduleName) != "some" else {
                continue
            }
            let renderedType = renderedTypeName(
                rawType,
                protocolNames: protocolNames,
                moduleName: moduleName
            )
            let accessors = property.hasSetter ? "{ get set }" : "{ get }"
            var propertyLine = "\(indent)  \(memberAccessPrefix)\(property.isStatic ? "static " : "")var \(escapedIdentifier(property.name)): \(renderedType) \(accessors)"
            if isProtocol {
                propertyLine = propertyLine.replacingSelfTypePattern()
            }
            body.append(propertyLine)
        }

        for subscriptMember in declaration.subscripts.sorted(by: { $0.order < $1.order }) {
            guard
                !containsUnrenderableExternalModuleReference(
                    subscriptMember.rawArguments,
                    allowedPrefixes: allowedPrefixes
                ),
                !containsUnrenderableExternalModuleReference(
                    subscriptMember.rawReturnType,
                    allowedPrefixes: allowedPrefixes
                )
            else {
                continue
            }
            let renderedArguments = (try? renderedArgumentList(
                subscriptMember.rawArguments,
                protocolNames: protocolNames,
                moduleName: moduleName
            )) ?? subscriptMember.rawArguments
            let rawReturnType = resolvedOpaqueSubscriptReturnType(
                subscriptMember,
                in: declaration,
                declarations: declarations,
                moduleName: moduleName
            ) ?? subscriptMember.rawReturnType
            guard cleanedTypeName(rawReturnType, moduleName: moduleName) != "some" else {
                continue
            }
            let renderedReturnType = renderedTypeName(
                rawReturnType,
                protocolNames: protocolNames,
                moduleName: moduleName
            )
            let accessors = subscriptMember.hasSetter ? "{ get set }" : "{ get }"
            var subscriptLine = "\(indent)  \(memberAccessPrefix)subscript(\(renderedArguments)) -> \(renderedReturnType) \(accessors)"
            if isProtocol {
                subscriptLine = subscriptLine.replacingSelfTypePattern()
            }
            body.append(subscriptLine)
        }

        let protocolOwnerName = isProtocol ? simpleName(of: fullName) : nil

        for initializer in declaration.initializers.sorted(by: { $0.order < $1.order }) {
            if let rendered = renderedCallable(
                initializer,
                protocolNames: protocolNames,
                allowedPrefixes: allowedPrefixes,
                level: level + 1,
                isProtocolRequirement: isProtocol,
                knownTypeComponents: knownTypeComponents,
                moduleName: moduleName,
                ownerName: protocolOwnerName,
                ownerGenericParameters: genericParameters,
                ownerDeclaration: declaration,
                declarations: declarations
            ) {
                body.append(rendered)
            }
        }

        for method in declaration.methods.sorted(by: { $0.order < $1.order }) {
            if let rendered = renderedCallable(
                method,
                protocolNames: protocolNames,
                allowedPrefixes: allowedPrefixes,
                level: level + 1,
                isProtocolRequirement: isProtocol,
                knownTypeComponents: knownTypeComponents,
                moduleName: moduleName,
                ownerName: protocolOwnerName,
                ownerGenericParameters: genericParameters,
                ownerDeclaration: declaration,
                declarations: declarations
            ) {
                body.append(rendered)
            }
        }

        for method in declaration.staticMethods.sorted(by: { $0.order < $1.order }) {
            if let rendered = renderedCallable(
                method,
                protocolNames: protocolNames,
                allowedPrefixes: allowedPrefixes,
                level: level + 1,
                isProtocolRequirement: isProtocol,
                knownTypeComponents: knownTypeComponents,
                moduleName: moduleName,
                ownerName: protocolOwnerName,
                ownerGenericParameters: genericParameters,
                ownerDeclaration: declaration,
                declarations: declarations
            ) {
                body.append(rendered)
            }
        }

        while body.last?.isEmpty == true {
            body.removeLast()
        }

        if body.isEmpty {
            return "\(header)\n\(indent)}"
        }

        return ([header] + body + ["\(indent)}"]).joined(separator: "\n")
    }

    private func renderedExternalExtensionBlocks(
        declarations: [String: Declaration],
        protocolNames: Set<String>,
        knownTypeComponents: Set<String>,
        allowedPrefixes: Set<String>?,
        moduleName: String
    ) -> [String] {
        declarations.values
            .filter {
                $0.isExternalExtension
                    && (
                        !$0.conformances.isEmpty
                            || !$0.properties.isEmpty
                            || !$0.subscripts.isEmpty
                            || !$0.initializers.isEmpty
                            || !$0.methods.isEmpty
                            || !$0.staticMethods.isEmpty
                    )
            }
            .sorted(by: { $0.order < $1.order })
            .compactMap {
                renderedExternalExtensionBlock(
                    for: $0,
                    declarations: declarations,
                    protocolNames: protocolNames,
                    knownTypeComponents: knownTypeComponents,
                    allowedPrefixes: allowedPrefixes,
                    moduleName: moduleName
                )
            }
    }

    private func renderedExternalExtensionBlock(
        for declaration: Declaration,
        declarations: [String: Declaration],
        protocolNames: Set<String>,
        knownTypeComponents: Set<String>,
        allowedPrefixes: Set<String>?,
        moduleName: String
    ) -> String? {
        let ownerName = renderedQualifiedDeclarationName(declaration.fullName, moduleName: moduleName)
        guard !containsUnrenderableExternalModuleReference(
            declaration.fullName,
            allowedPrefixes: allowedPrefixes
        ) else {
            return nil
        }
        let conformanceClause = renderedConformanceClause(
            for: declaration,
            allowedPrefixes: allowedPrefixes,
            moduleName: moduleName
        )

        var body: [String] = []

        for property in declaration.properties.sorted(by: { $0.order < $1.order }) {
            guard
                !containsUnrenderableExternalModuleReference(
                    property.rawType,
                    allowedPrefixes: allowedPrefixes
                )
            else {
                continue
            }
            let rawType = resolvedOpaquePropertyType(
                property,
                in: declaration,
                declarations: declarations,
                moduleName: moduleName
            ) ?? property.rawType
            guard cleanedTypeName(rawType, moduleName: moduleName) != "some" else {
                continue
            }
            let renderedType = renderedTypeName(
                rawType,
                protocolNames: protocolNames,
                moduleName: moduleName
            )
            let accessors = property.hasSetter ? "{ get set }" : "{ get }"
            body.append(
                "  public \(property.isStatic ? "static " : "")var \(escapedIdentifier(property.name)): \(renderedType) \(accessors)"
                    .replacingSelfTypePattern()
            )
        }

        for subscriptMember in declaration.subscripts.sorted(by: { $0.order < $1.order }) {
            guard
                !containsUnrenderableExternalModuleReference(
                    subscriptMember.rawArguments,
                    allowedPrefixes: allowedPrefixes
                ),
                !containsUnrenderableExternalModuleReference(
                    subscriptMember.rawReturnType,
                    allowedPrefixes: allowedPrefixes
                )
            else {
                continue
            }
            let renderedArguments = (try? renderedArgumentList(
                subscriptMember.rawArguments,
                protocolNames: protocolNames,
                moduleName: moduleName
            )) ?? subscriptMember.rawArguments
            let rawReturnType = resolvedOpaqueSubscriptReturnType(
                subscriptMember,
                in: declaration,
                declarations: declarations,
                moduleName: moduleName
            ) ?? subscriptMember.rawReturnType
            guard cleanedTypeName(rawReturnType, moduleName: moduleName) != "some" else {
                continue
            }
            let renderedReturnType = renderedTypeName(
                rawReturnType,
                protocolNames: protocolNames,
                moduleName: moduleName
            )
            let accessors = subscriptMember.hasSetter ? "{ get set }" : "{ get }"
            body.append(
                "  public subscript(\(renderedArguments)) -> \(renderedReturnType) \(accessors)"
                    .replacingSelfTypePattern()
            )
        }

        for initializer in declaration.initializers.sorted(by: { $0.order < $1.order }) {
            if let rendered = renderedCallable(
                initializer,
                protocolNames: protocolNames,
                allowedPrefixes: allowedPrefixes,
                level: 1,
                isProtocolRequirement: false,
                knownTypeComponents: knownTypeComponents,
                moduleName: moduleName,
                ownerDeclaration: declaration,
                declarations: declarations,
                forcePublicAccess: true
            ) {
                body.append(rendered.replacingSelfTypePattern())
            }
        }

        for method in declaration.methods.sorted(by: { $0.order < $1.order }) {
            if let rendered = renderedCallable(
                method,
                protocolNames: protocolNames,
                allowedPrefixes: allowedPrefixes,
                level: 1,
                isProtocolRequirement: false,
                knownTypeComponents: knownTypeComponents,
                moduleName: moduleName,
                ownerDeclaration: declaration,
                declarations: declarations,
                forcePublicAccess: true
            ) {
                body.append(rendered.replacingSelfTypePattern())
            }
        }

        for method in declaration.staticMethods.sorted(by: { $0.order < $1.order }) {
            if let rendered = renderedCallable(
                method,
                protocolNames: protocolNames,
                allowedPrefixes: allowedPrefixes,
                level: 1,
                isProtocolRequirement: false,
                knownTypeComponents: knownTypeComponents,
                moduleName: moduleName,
                ownerDeclaration: declaration,
                declarations: declarations,
                forcePublicAccess: true
            ) {
                body.append(rendered.replacingSelfTypePattern())
            }
        }

        guard !body.isEmpty || !conformanceClause.isEmpty else {
            return nil
        }

        return (["extension \(ownerName)\(conformanceClause) {"] + body + ["}"]).joined(
            separator: "\n"
        )
    }

    private func renderedProtocolExtensionBlocks(
        declarations: [String: Declaration],
        protocolNames: Set<String>,
        knownTypeComponents: Set<String>,
        allowedPrefixes: Set<String>?,
        moduleName: String
    ) -> [String] {
        declarations.values
            .filter {
                $0.resolvedKind == .protocol
                    && (
                        !$0.extensionProperties.isEmpty
                            || !$0.extensionSubscripts.isEmpty
                            || !$0.extensionInitializers.isEmpty
                            || !$0.extensionMethods.isEmpty
                            || !$0.extensionStaticMethods.isEmpty
                    )
            }
            .sorted(by: { $0.order < $1.order })
            .flatMap {
                renderedProtocolExtensionBlocks(
                    for: $0,
                    declarations: declarations,
                    protocolNames: protocolNames,
                    knownTypeComponents: knownTypeComponents,
                    allowedPrefixes: allowedPrefixes,
                    moduleName: moduleName
                )
            }
    }

    private func renderedProtocolExtensionBlocks(
        for declaration: Declaration,
        declarations: [String: Declaration],
        protocolNames: Set<String>,
        knownTypeComponents: Set<String>,
        allowedPrefixes: Set<String>?,
        moduleName: String
    ) -> [String] {
        let ownerName = renderedQualifiedDeclarationName(declaration.fullName, moduleName: moduleName)
        var blocks: [String] = []

        let unconstrainedProperties = declaration.extensionProperties
            .filter { $0.extensionWhereClause.isEmpty }
        let unconstrainedSubscripts = declaration.extensionSubscripts
            .filter { $0.extensionWhereClause.isEmpty }

        let unconstrainedBlock = renderedProtocolExtensionBlock(
            ownerName: ownerName,
            whereClause: "",
            properties: unconstrainedProperties,
            subscripts: unconstrainedSubscripts,
            initializers: declaration.extensionInitializers,
            methods: declaration.extensionMethods,
            staticMethods: declaration.extensionStaticMethods,
            ownerDeclaration: declaration,
            declarations: declarations,
            protocolNames: protocolNames,
            knownTypeComponents: knownTypeComponents,
            allowedPrefixes: allowedPrefixes,
            moduleName: moduleName
        )
        if let unconstrainedBlock {
            blocks.append(unconstrainedBlock)
        }

        let constrainedWhereClauses = Array(
            Set(
                declaration.extensionProperties.map(\.extensionWhereClause)
                    + declaration.extensionSubscripts.map(\.extensionWhereClause)
            )
        )
        .filter { !$0.isEmpty }
        .sorted()

        for whereClause in constrainedWhereClauses {
            let block = renderedProtocolExtensionBlock(
                ownerName: ownerName,
                whereClause: whereClause,
                properties: declaration.extensionProperties.filter { $0.extensionWhereClause == whereClause },
                subscripts: declaration.extensionSubscripts.filter { $0.extensionWhereClause == whereClause },
                initializers: [],
                methods: [],
                staticMethods: [],
                ownerDeclaration: declaration,
                declarations: declarations,
                protocolNames: protocolNames,
                knownTypeComponents: knownTypeComponents,
                allowedPrefixes: allowedPrefixes,
                moduleName: moduleName
            )
            if let block {
                blocks.append(block)
            }
        }

        return blocks
    }

    private func renderedProtocolExtensionBlock(
        ownerName: String,
        whereClause: String,
        properties: [Declaration.Property],
        subscripts: [Declaration.Subscript],
        initializers: [Declaration.Callable],
        methods: [Declaration.Callable],
        staticMethods: [Declaration.Callable],
        ownerDeclaration: Declaration,
        declarations: [String: Declaration],
        protocolNames: Set<String>,
        knownTypeComponents: Set<String>,
        allowedPrefixes: Set<String>?,
        moduleName: String
    ) -> String? {
        guard !containsUnrenderableExternalModuleReference(whereClause, allowedPrefixes: allowedPrefixes) else {
            return nil
        }

        var body: [String] = []

        for property in properties.sorted(by: { $0.order < $1.order }) {
            guard
                !containsUnrenderableExternalModuleReference(
                    property.rawType,
                    allowedPrefixes: allowedPrefixes
                ),
                !containsUnrenderableExternalModuleReference(
                    property.extensionWhereClause,
                    allowedPrefixes: allowedPrefixes
                )
            else {
                continue
            }
            let rawType = resolvedOpaquePropertyType(
                property,
                in: ownerDeclaration,
                declarations: declarations,
                moduleName: moduleName
            ) ?? property.rawType
            guard cleanedTypeName(rawType, moduleName: moduleName) != "some" else {
                continue
            }
            let renderedType = renderedTypeName(
                rawType,
                protocolNames: protocolNames,
                moduleName: moduleName
            )
            let accessors = property.hasSetter ? "{ get set }" : "{ get }"
            let propertyLine = "  public \(property.isStatic ? "static " : "")var \(escapedIdentifier(property.name)): \(renderedType) \(accessors)"
                .replacingSelfTypePattern()
            body.append(propertyLine)
        }

        for subscriptMember in subscripts.sorted(by: { $0.order < $1.order }) {
            guard
                !containsUnrenderableExternalModuleReference(
                    subscriptMember.rawArguments,
                    allowedPrefixes: allowedPrefixes
                ),
                !containsUnrenderableExternalModuleReference(
                    subscriptMember.rawReturnType,
                    allowedPrefixes: allowedPrefixes
                ),
                !containsUnrenderableExternalModuleReference(
                    subscriptMember.extensionWhereClause,
                    allowedPrefixes: allowedPrefixes
                )
            else {
                continue
            }
            let renderedArguments = (try? renderedArgumentList(
                subscriptMember.rawArguments,
                protocolNames: protocolNames,
                moduleName: moduleName
            )) ?? subscriptMember.rawArguments
            let rawReturnType = resolvedOpaqueSubscriptReturnType(
                subscriptMember,
                in: ownerDeclaration,
                declarations: declarations,
                moduleName: moduleName
            ) ?? subscriptMember.rawReturnType
            guard cleanedTypeName(rawReturnType, moduleName: moduleName) != "some" else {
                continue
            }
            let renderedReturnType = renderedTypeName(
                rawReturnType,
                protocolNames: protocolNames,
                moduleName: moduleName
            )
            let accessors = subscriptMember.hasSetter ? "{ get set }" : "{ get }"
            let subscriptLine = "  public subscript(\(renderedArguments)) -> \(renderedReturnType) \(accessors)"
                .replacingSelfTypePattern()
            body.append(subscriptLine)
        }

        for initializer in initializers.sorted(by: { $0.order < $1.order }) {
            if let rendered = renderedCallable(
                initializer,
                protocolNames: protocolNames,
                allowedPrefixes: allowedPrefixes,
                level: 1,
                isProtocolRequirement: true,
                knownTypeComponents: knownTypeComponents,
                moduleName: moduleName,
                ownerName: simpleName(of: ownerDeclaration.fullName),
                ownerDeclaration: ownerDeclaration,
                declarations: declarations,
                forcePublicAccess: true
            ) {
                body.append(rendered)
            }
        }

        for method in methods.sorted(by: { $0.order < $1.order }) {
            if let rendered = renderedCallable(
                method,
                protocolNames: protocolNames,
                allowedPrefixes: allowedPrefixes,
                level: 1,
                isProtocolRequirement: true,
                knownTypeComponents: knownTypeComponents,
                moduleName: moduleName,
                ownerName: simpleName(of: ownerDeclaration.fullName),
                ownerDeclaration: ownerDeclaration,
                declarations: declarations,
                forcePublicAccess: true
            ) {
                body.append(rendered)
            }
        }

        for method in staticMethods.sorted(by: { $0.order < $1.order }) {
            if let rendered = renderedCallable(
                method,
                protocolNames: protocolNames,
                allowedPrefixes: allowedPrefixes,
                level: 1,
                isProtocolRequirement: true,
                knownTypeComponents: knownTypeComponents,
                moduleName: moduleName,
                ownerName: simpleName(of: ownerDeclaration.fullName),
                ownerDeclaration: ownerDeclaration,
                declarations: declarations,
                forcePublicAccess: true
            ) {
                body.append(rendered)
            }
        }

        guard !body.isEmpty else {
            return nil
        }

        let renderedWhereClause = whereClause.replacingSelfTypePattern()
        return (["extension \(ownerName)\(renderedWhereClause) {"] + body + ["}"]).joined(
            separator: "\n"
        )
    }

    private func renderedQualifiedDeclarationName(_ fullName: String, moduleName: String) -> String {
        cleanedTypeName(fullName, moduleName: moduleName)
            .split(separator: ".")
            .map { escapedIdentifier(String($0)) }
            .joined(separator: ".")
    }

    /// Renders the conformance clause (e.g. `: Hashable, Codable`) for a declaration.
    ///
    /// Applies several normalizations:
    /// - Merges `Encodable` + `Decodable` into `Codable`.
    /// - Removes `Equatable` when `Hashable` is present.
    /// - Filters out unsupported Foundation attribute conformances.
    ///
    /// - Parameters:
    ///   - declaration: The declaration whose conformances to render.
    ///   - protocolNames: Known protocol names for type name rendering.
    ///   - moduleName: The module name for type name cleanup.
    /// - Returns: The conformance clause string (e.g. `": Hashable, Codable"`), or an
    ///   empty string if there are no conformances.
    private func renderedConformanceClause(
        for declaration: Declaration,
        allowedPrefixes: Set<String>?,
        moduleName: String
    ) -> String {
        renderedConformanceClause(for: declaration.conformances, allowedPrefixes: allowedPrefixes, moduleName: moduleName)
    }

    private func renderedAssociatedTypeConformanceClause(
        for associatedType: Declaration.AssociatedType,
        allowedPrefixes: Set<String>?,
        moduleName: String
    ) -> String {
        renderedConformanceClause(for: associatedType.conformances, allowedPrefixes: allowedPrefixes, moduleName: moduleName)
    }

    private func renderedConformanceClause(
        for rawConformances: [String],
        allowedPrefixes: Set<String>?,
        moduleName: String
    ) -> String {
        var conformances = normalizedConformances(rawConformances)
        if let allowedPrefixes {
            conformances = conformances.filter { conformance in
                !containsUnrenderableExternalModuleReference(conformance, allowedPrefixes: allowedPrefixes)
            }
        }
        guard !conformances.isEmpty else {
            return ""
        }

        return ": " + conformances
            .map { cleanedTypeName($0, moduleName: moduleName) }
            .joined(separator: ", ")
    }

    private func selfAliasedAssociatedTypes(
        for declaration: Declaration,
        declarations: [String: Declaration],
        moduleName: String
    ) -> [String] {
        guard declaration.resolvedKind != .protocol else {
            return []
        }

        var typealiases: [String] = []

        for conformance in declaration.conformances {
            let cleanedConformance = cleanedTypeName(conformance, moduleName: moduleName)
            guard let protocolDeclaration = declarations.values.first(where: {
                $0.resolvedKind == .protocol
                    && (
                        cleanedTypeName($0.fullName, moduleName: moduleName) == cleanedConformance
                            || simpleName(of: $0.fullName) == cleanedConformance
                    )
            }) else {
                continue
            }

            for associatedType in protocolDeclaration.associatedTypes where associatedType.name == "PartiallyGenerated" {
                guard !typealiases.contains(associatedType.name) else {
                    continue
                }
                typealiases.append(associatedType.name)
            }
        }

        return typealiases
    }

    /// Normalizes conformance lists for declarations and associated types.
    ///
    /// Applies the same cleanup rules as interface inheritance clauses:
    /// - removes unsupported attribute-related conformances
    /// - folds `Encodable` + `Decodable` into `Codable`
    /// - drops redundant `Equatable` when `Hashable` is present
    private static let unsupportedConformances: Set<String> = [
        "Foundation.AttributeScope",
        "Foundation.AttributedStringKey",
        "Foundation.DecodableAttributedStringKey",
        "Foundation.DecodingConfigurationProviding",
        "Foundation.EncodableAttributedStringKey",
        "Foundation.EncodingConfigurationProviding",
    ]

    private func normalizedConformances(_ rawConformances: [String]) -> [String] {
        var hasEncodable = false
        var hasDecodable = false
        var hasHashable = false

        var conformances = rawConformances.filter { conformance in
            if Self.unsupportedConformances.contains(conformance) { return false }
            if conformance == "Swift.Encodable" { hasEncodable = true }
            if conformance == "Swift.Decodable" { hasDecodable = true }
            if conformance == "Swift.Hashable" { hasHashable = true }
            return true
        }

        if hasEncodable, hasDecodable {
            conformances.removeAll { $0 == "Swift.Encodable" || $0 == "Swift.Decodable" }
            if !conformances.contains("Swift.Codable") {
                conformances.insert("Swift.Codable", at: 0)
            }
        }

        if hasHashable {
            conformances.removeAll { $0 == "Swift.Equatable" }
        }

        return conformances
    }

    /// Infers generic parameter names for a declaration by scanning its members.
    ///
    /// Uses the pre-computed generic arity map to determine how many
    /// generic parameters the type has, then scans property types, method signatures, and
    /// enum payloads for unrecognized tokens that likely represent generic parameter names.
    /// Falls back to synthetic names (`T0`, `T1`, ...) if not enough are discovered.
    ///
    /// - Parameters:
    ///   - declaration: The declaration to infer generic parameters for.
    ///   - declarations: All declarations, for cross-referencing type names.
    ///   - knownTypeComponents: Known type name tokens to exclude from inference.
    ///   - moduleName: The module name to exclude from inference.
    /// - Returns: An array of inferred generic parameter names.
    private func inferredGenericParameters(
        for declaration: Declaration,
        declarations: [String: Declaration],
        genericArityMap: [String: Int],
        knownTypeComponents: Set<String>,
        moduleName: String
    ) -> [String] {
        let arity = genericArityMap[declaration.fullName] ?? 0
        guard arity > 0 else {
            return []
        }

        var genericParameters: [String] = []
        var excludedTokens = Self.genericExcludedTokens
        if !moduleName.isEmpty {
            excludedTokens.insert(moduleName)
        }

        var seenParameters: Set<String> = []
        let descendantFragments = declarations.values
            .filter { $0.fullName.hasPrefix("\(declaration.fullName).") }
            .sorted(by: { $0.order < $1.order })
            .flatMap(\.rawTypeFragments)
        let fragments = declaration.rawTypeFragments + descendantFragments

        for fragment in fragments {
            for token in genericParameterTokens(in: fragment, moduleName: moduleName) {
                if !isLikelyDeclarationTypeParameter(
                    token,
                    knownTypeComponents: knownTypeComponents,
                    excludedTokens: excludedTokens
                ) {
                    continue
                }
                if seenParameters.insert(token).inserted {
                    genericParameters.append(token)
                    if genericParameters.count == arity {
                        return genericParameters
                    }
                }
            }
        }

        while genericParameters.count < arity {
            genericParameters.append("T\(genericParameters.count)")
        }

        return Array(genericParameters.prefix(arity))
    }

    private func renderedDeclarationGenericWhereClause(
        for declaration: Declaration,
        genericParameters: [String],
        declarations: [String: Declaration],
        moduleName: String
    ) -> String {
        let constraints = inferredDeclarationGenericConstraints(
            for: declaration,
            genericParameters: genericParameters,
            declarations: declarations,
            moduleName: moduleName
        )
        guard !constraints.isEmpty else {
            return ""
        }
        return " where \(constraints.joined(separator: ", "))"
    }

    private func inferredDeclarationGenericConstraints(
        for declaration: Declaration,
        genericParameters: [String],
        declarations: [String: Declaration],
        moduleName: String
    ) -> [String] {
        guard !genericParameters.isEmpty else {
            return []
        }

        let genericParameterSet = Set(genericParameters)
        let associatedTypeReferences = declarationAssociatedTypeReferences(
            for: declaration,
            genericParameters: genericParameterSet,
            moduleName: moduleName
        )

        return genericParameters.compactMap { parameter in
            guard let members = associatedTypeReferences[parameter], !members.isEmpty,
                  let protocolDeclaration = protocolDeclaringAssociatedTypes(
                    members,
                    declarations: declarations
                  ) else {
                return nil
            }

            return "\(parameter) : \(renderedQualifiedDeclarationName(protocolDeclaration.fullName, moduleName: moduleName))"
        }
    }

    private func declarationAssociatedTypeReferences(
        for declaration: Declaration,
        genericParameters: Set<String>,
        moduleName: String
    ) -> [String: Set<String>] {
        declaration.rawTypeFragments.reduce(into: [String: Set<String>]()) { result, fragment in
            for (parameter, members) in associatedTypeMemberReferences(
                in: fragment,
                genericParameters: genericParameters,
                moduleName: moduleName
            ) {
                result[parameter, default: []].formUnion(members)
            }
        }
    }

    private func associatedTypeMemberReferences(
        in fragment: String,
        genericParameters: Set<String>,
        moduleName: String
    ) -> [String: Set<String>] {
        let cleanedFragment = cleanedTypeName(fragment, moduleName: moduleName)
        let pattern = #/\b([A-Z][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)\b/#

        return cleanedFragment.matches(of: pattern).reduce(into: [String: Set<String>]()) { result, match in
            let parameter = String(match.1)
            guard genericParameters.contains(parameter) else {
                return
            }

            result[parameter, default: []].insert(String(match.2))
        }
    }

    private func protocolDeclaringAssociatedTypes(
        _ associatedTypeNames: Set<String>,
        declarations: [String: Declaration]
    ) -> Declaration? {
        guard !associatedTypeNames.isEmpty else {
            return nil
        }

        let candidates = declarations.values
            .filter { $0.resolvedKind == .protocol }
            .compactMap { declaration -> (declaration: Declaration, extraCount: Int)? in
                let providedNames = Set(declaration.associatedTypes.map(\.name))
                guard providedNames.isSuperset(of: associatedTypeNames) else {
                    return nil
                }

                return (declaration, providedNames.count - associatedTypeNames.count)
            }
            .sorted {
                if $0.extraCount != $1.extraCount {
                    return $0.extraCount < $1.extraCount
                }
                return $0.declaration.fullName < $1.declaration.fullName
            }

        guard let bestMatch = candidates.first else {
            return nil
        }
        if let nextBest = candidates.dropFirst().first,
           nextBest.extraCount == bestMatch.extraCount {
            return nil
        }

        return bestMatch.declaration
    }

    /// Discovers which external modules are referenced in the given declarations.
    ///
    /// Scans all conformances, property types, method signatures, and enum payloads
    /// for references to external modules (Foundation, CoreGraphics, Dispatch, etc.).
    ///
    /// - Parameters:
    ///   - declarations: The pre-computed declarations to scan.
    ///   - moduleName: The module name used to match symbol prefixes.
    /// - Returns: An ordered array of external module names referenced by the symbols.
    func discoveredExternalModules(
        from declarations: [String: Declaration],
        moduleName: String
    ) -> [String] {
        let knownTypeComponents = localKnownTypeComponents(from: declarations)

        return discoveredImports(
            from: declarations,
            knownTypeComponents: knownTypeComponents,
            moduleName: moduleName
        )
    }

    private func discoveredImports(
        from declarations: [String: Declaration],
        knownTypeComponents: Set<String>,
        moduleName: String
    ) -> [String] {
        var rawFragments: [String] = []
        for declaration in declarations.values.sorted(by: { $0.order < $1.order }) {
            if declaration.isExternalExtension {
                rawFragments.append(declaration.fullName)
            }
            rawFragments.append(contentsOf: declaration.conformances)
            rawFragments.append(contentsOf: declaration.rawTypeFragments)
        }

        var modules: [String] = []
        var seen: Set<String> = []

        func addModule(_ module: String) {
            if seen.insert(module).inserted {
                modules.append(module)
            }
        }

        for fragment in rawFragments {
            for module in importedModuleCandidates(
                in: fragment,
                knownTypeComponents: knownTypeComponents,
                moduleName: moduleName
            ) {
                addModule(module)
            }

            let cleanedFragment = cleanedTypeName(fragment, moduleName: moduleName)
            for module in importedModuleCandidates(
                in: cleanedFragment,
                knownTypeComponents: knownTypeComponents,
                moduleName: moduleName
            ) {
                addModule(module)
            }
        }

        return modules
    }

    private func localKnownTypeComponents(
        from declarations: [String: Declaration]
    ) -> Set<String> {
        Set(
            declarations.values
                .filter { !$0.isExternalExtension }
                .flatMap { $0.fullName.split(separator: ".").map(String.init) }
        )
    }

    /// Renders a method or initializer declaration as a Swift source line.
    ///
    /// Parses the raw demangled signature to extract the method name, argument list, effects
    /// (async/throws), and return type. Filters out unsupported signatures such as allocating
    /// initializers, operators, and internal compiler artifacts.
    ///
    /// - Parameters:
    ///   - callable: The callable to render.
    ///   - protocolNames: Known protocol names for existential type rendering.
    ///   - level: The indentation level.
    ///   - isProtocolRequirement: Whether this is a protocol requirement (omits `public`).
    ///   - moduleName: The module name for type name cleanup.
    ///   - ownerName: For protocol requirements, the protocol's simple name (used to
    ///     rewrite `A.` self-type references).
    /// - Returns: The rendered method/initializer line, or `nil` if the signature is filtered out.
    private func renderedCallable(
        _ callable: Declaration.Callable,
        protocolNames: Set<String>,
        allowedPrefixes: Set<String>?,
        level: Int,
        isProtocolRequirement: Bool,
        knownTypeComponents: Set<String>,
        moduleName: String,
        ownerName: String? = nil,
        ownerGenericParameters: [String] = [],
        ownerDeclaration: Declaration,
        declarations: [String: Declaration],
        forcePublicAccess: Bool = false
    ) -> String? {
        let indent = String(repeating: "  ", count: level)
        let rawSignature = callable.rawSignature
        guard
            !rawSignature.contains(".T =="),
            !containsOperatorNotation(rawSignature),
            !containsUnrenderableExternalModuleReference(
                rawSignature,
                allowedPrefixes: allowedPrefixes
            )
        else {
            return nil
        }
        // Find the argument list opening paren. If the signature has a generic
        // clause (e.g. `init<A where A: Seq, A.Element == (X, Y)>(args)`),
        // we must skip past the closing `>` to avoid matching a `(` inside
        // the where clause.
        let openingParenthesis: String.Index
        if let angleBracket = rawSignature.firstIndex(of: "<"),
           let firstParen = rawSignature.firstIndex(of: "("),
           angleBracket < firstParen,
           let closingAngle = matchingClosingDelimiter(
               in: rawSignature, from: angleBracket, open: "<", close: ">"
           ) {
            guard let paren = rawSignature[rawSignature.index(after: closingAngle)...].firstIndex(of: "(") else {
                return nil
            }
            openingParenthesis = paren
        } else {
            guard let paren = rawSignature.firstIndex(of: "(") else {
                return nil
            }
            openingParenthesis = paren
        }

        guard
            let closingParenthesis = matchingClosingParenthesis(
                in: rawSignature,
                from: openingParenthesis
            )
        else {
            return nil
        }

        let arguments = String(rawSignature[rawSignature.index(after: openingParenthesis)..<closingParenthesis])
        let trailingSignature = String(rawSignature[rawSignature.index(after: closingParenthesis)...])
        let effects: String
        let returnType: String
        let trailingWhereClause: String

        if let returnArrow = topLevelArrowRange(in: trailingSignature) {
            effects = String(trailingSignature[..<returnArrow.lowerBound])
                .trimmingCharacters(in: .whitespaces)
            let rawReturnSection = String(trailingSignature[returnArrow.upperBound...])
                .trimmingCharacters(in: .whitespaces)
            let parsedReturn = splitTrailingWhereClause(from: rawReturnSection)
            returnType = parsedReturn.returnType
            trailingWhereClause = parsedReturn.whereClause
        } else {
            let parsedEffects = splitImplicitVoidSignature(from: trailingSignature)
            effects = parsedEffects.effects
            returnType = "()"
            trailingWhereClause = parsedEffects.whereClause
        }

        var renderedArguments = (try? renderedArgumentList(
            arguments,
            protocolNames: protocolNames,
            moduleName: moduleName
        )) ?? arguments
        let renderedEffects = effects.isEmpty ? "" : " \(effects)"
        let resolvedReturnType = resolvedOpaqueCallableReturnType(
            callable,
            rawReturnType: returnType,
            in: ownerDeclaration,
            declarations: declarations,
            moduleName: moduleName
        ) ?? returnType
        guard cleanedTypeName(resolvedReturnType, moduleName: moduleName) != "some" else {
            return nil
        }
        let renderedReturnType = renderedTypeName(
            resolvedReturnType,
            protocolNames: protocolNames,
            moduleName: moduleName
        )
        let returnClause = renderedReturnType == "()" ? "" : " -> \(renderedReturnType)"
        let initializerKeyword = renderedReturnType.hasSuffix("?") ? "init?" : "init"

        // Extract generic clause if present (e.g. "respond<A where A: Mod.Proto>" → name "respond", params "<A>", where "where A : Proto")
        let head = String(rawSignature[..<openingParenthesis])
        let genericParsed = parseGenericClause(head, moduleName: moduleName)
        let methodName = genericParsed.name
        let genericParameters = resolvedMethodGenericParameters(
            explicitGenericParamClause: genericParsed.paramClause,
            arguments: arguments,
            returnType: returnType,
            genericWhereClause: genericParsed.whereClause,
            trailingWhereClause: trailingWhereClause,
            isProtocolRequirement: isProtocolRequirement,
            ownerGenericParameters: ownerGenericParameters,
            knownTypeComponents: knownTypeComponents,
            moduleName: moduleName
        )
        let genericParamClause = genericParameters.isEmpty ? "" : "<\(genericParameters.joined(separator: ", "))>"
        let whereClause = combinedWhereClause(
            genericParsed.whereClause,
            trailingWhereClause
        )
        renderedArguments = applyingPackExpansionSyntax(
            to: renderedArguments,
            packParameters: genericParsed.packParameters
        )

        let accessPrefix = (isProtocolRequirement && !forcePublicAccess) ? "" : "public "

        var result: String
        if callable.isInitializer {
            result = "\(indent)\(accessPrefix)\(initializerKeyword)\(genericParamClause)(\(renderedArguments))\(renderedEffects)\(whereClause)"
        } else {
            result = "\(indent)\(accessPrefix)\(callable.isStatic ? "static " : "")func \(escapedIdentifier(methodName))\(genericParamClause)(\(renderedArguments))\(renderedEffects)\(returnClause)\(whereClause)"
        }

        if isProtocolRequirement {
            result = result.replacingSelfTypePattern()
        }

        return result
    }

    private func resolvedMethodGenericParameters(
        explicitGenericParamClause: String,
        arguments: String,
        returnType: String,
        genericWhereClause: String,
        trailingWhereClause: String,
        isProtocolRequirement: Bool,
        ownerGenericParameters: [String],
        knownTypeComponents: Set<String>,
        moduleName: String
    ) -> [String] {
        let explicitParameters = parseGenericParameters(from: explicitGenericParamClause)
        let ownerGenericSet = Set(ownerGenericParameters)
        let explicitMethodParameters = explicitParameters.filter { !ownerGenericSet.contains($0) }
        let genericConstraintClauses = [genericWhereClause, trailingWhereClause]
            .filter { !$0.isEmpty }
        var referencedMethodParameters: [String] = []
        var referencedParameterSet: Set<String> = []

        for fragment in [arguments, returnType] + genericConstraintClauses {
            for token in numberedGenericPlaceholderTokens(in: fragment)
            where isLikelyMethodTypeParameter(token, knownTypeComponents: knownTypeComponents) {
                guard referencedParameterSet.insert(token).inserted else {
                    continue
                }
                referencedMethodParameters.append(token)
            }
        }

        if explicitParameters == ["Self"] {
            if !referencedMethodParameters.isEmpty {
                return referencedMethodParameters
            }

            // Protocol requirement descriptors can surface `Self` as the explicit method
            // generic parameter while the actual placeholders only appear textually in the
            // where clause (for example `where A1 : Hashable`). In that case SwiftSyntax
            // can fail to recover the undeclared placeholder from the synthetic parse, so
            // fall back to scanning numbered placeholders directly from the constraint text.
            for clause in genericConstraintClauses {
                for token in numberedGenericPlaceholderTokens(in: clause) where isLikelyMethodTypeParameter(
                    token,
                    knownTypeComponents: knownTypeComponents
                ) {
                    return [token]
                }
            }

            return []
        }

        if isProtocolRequirement,
           !explicitParameters.isEmpty,
           explicitParameters.allSatisfy(isProtocolSelfPlaceholder),
           !referencedMethodParameters.isEmpty,
           explicitParameters.allSatisfy({ !referencedParameterSet.contains($0) }) {
            return referencedMethodParameters
        }

        if explicitParameters.contains(where: ownerGenericSet.contains),
           !referencedMethodParameters.isEmpty {
            return referencedMethodParameters
        }

        if explicitMethodParameters.isEmpty {
            return []
        }

        if !explicitMethodParameters.contains(where: isPackGenericParameter),
           explicitMethodParameters.allSatisfy(isSingleLetterGenericPlaceholder),
           referencedMethodParameters.contains(where: { !explicitMethodParameters.contains($0) }) {
            return referencedMethodParameters
        }

        return explicitMethodParameters
    }

    private func parseGenericParameters(from clause: String) -> [String] {
        let trimmed = clause.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("<"), trimmed.hasSuffix(">") else {
            return []
        }
        return String(trimmed.dropFirst().dropLast())
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func numberedGenericPlaceholderTokens(in fragment: String) -> [String] {
        var seen: Set<String> = []
        return fragment.matches(of: #/\b([A-Z][A-Za-z0-9_]*[0-9]+)\b/#).compactMap { match in
            let token = String(match.1)
            guard seen.insert(token).inserted else {
                return nil
            }
            return token
        }
    }

    private func isProtocolSelfPlaceholder(_ token: String) -> Bool {
        token.count == 1 && token.first?.isUppercase == true
    }

    private func isSingleLetterGenericPlaceholder(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespaces)
        return trimmed.count == 1 && trimmed.first?.isUppercase == true
    }

    private func isPackGenericParameter(_ token: String) -> Bool {
        token.trimmingCharacters(in: .whitespaces).hasPrefix("each ")
    }

    private func isLikelyMethodTypeParameter(
        _ token: String,
        knownTypeComponents: Set<String>
    ) -> Bool {
        guard token.count > 1 || token.first == "A" else {
            return false
        }
        guard token.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else {
            return false
        }
        guard token.first?.isUppercase == true else {
            return false
        }
        guard !Self.genericExcludedTokens.contains(token), !knownTypeComponents.contains(token) else {
            return false
        }
        return token != "Self"
    }

    private func isLikelyDeclarationTypeParameter(
        _ token: String,
        knownTypeComponents: Set<String>,
        excludedTokens: Set<String>
    ) -> Bool {
        guard token.first?.isUppercase == true else {
            return false
        }
        guard token.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else {
            return false
        }
        guard !excludedTokens.contains(token), !knownTypeComponents.contains(token) else {
            return false
        }
        if token.count > 1, token.dropFirst().allSatisfy(\.isNumber) {
            return false
        }
        return token != "Self"
    }

    private func resolvedOpaquePropertyType(
        _ property: Declaration.Property,
        in declaration: Declaration,
        declarations: [String: Declaration],
        moduleName: String
    ) -> String? {
        guard cleanedTypeName(property.rawType, moduleName: moduleName) == "some" else {
            return nil
        }

        for protocolDeclaration in protocolDeclarations(
            conformedToBy: declaration,
            declarations: declarations,
            moduleName: moduleName
        ) {
            guard let requirement = protocolDeclaration.properties.first(where: {
                $0.name == property.name && $0.isStatic == property.isStatic
            }),
            let opaqueType = opaqueType(
                fromRequirementReturnType: requirement.rawType,
                in: protocolDeclaration,
                moduleName: moduleName
            ) else {
                continue
            }

            return opaqueType
        }

        return nil
    }

    private func resolvedOpaqueCallableReturnType(
        _ callable: Declaration.Callable,
        rawReturnType: String,
        in declaration: Declaration,
        declarations: [String: Declaration],
        moduleName: String
    ) -> String? {
        guard !callable.isInitializer,
              cleanedTypeName(rawReturnType, moduleName: moduleName) == "some",
              let requirementKey = callableRequirementKey(
                  for: callable.rawSignature,
                  isStatic: callable.isStatic,
                  moduleName: moduleName
              ) else {
            return nil
        }

        for protocolDeclaration in protocolDeclarations(
            conformedToBy: declaration,
            declarations: declarations,
            moduleName: moduleName
        ) {
            let requirements = callable.isStatic
                ? protocolDeclaration.staticMethods
                : protocolDeclaration.methods

            for requirement in requirements {
                guard callableRequirementKey(
                    for: requirement.rawSignature,
                    isStatic: callable.isStatic,
                    moduleName: moduleName
                ) == requirementKey,
                let requirementReturnType = parsedCallableSignatureComponents(
                    from: requirement.rawSignature
                )?.returnType,
                let opaqueType = opaqueType(
                    fromRequirementReturnType: requirementReturnType,
                    in: protocolDeclaration,
                    moduleName: moduleName
                ) else {
                    continue
                }

                return opaqueType
            }
        }

        return nil
    }

    private func resolvedOpaqueSubscriptReturnType(
        _ subscriptMember: Declaration.Subscript,
        in declaration: Declaration,
        declarations: [String: Declaration],
        moduleName: String
    ) -> String? {
        guard cleanedTypeName(subscriptMember.rawReturnType, moduleName: moduleName) == "some" else {
            return nil
        }

        let requirementKey = subscriptRequirementKey(
            for: subscriptMember.rawArguments,
            moduleName: moduleName
        )

        for protocolDeclaration in protocolDeclarations(
            conformedToBy: declaration,
            declarations: declarations,
            moduleName: moduleName
        ) {
            for requirement in protocolDeclaration.subscripts {
                guard subscriptRequirementKey(
                    for: requirement.rawArguments,
                    moduleName: moduleName
                ) == requirementKey,
                let opaqueType = opaqueType(
                    fromRequirementReturnType: requirement.rawReturnType,
                    in: protocolDeclaration,
                    moduleName: moduleName
                ) else {
                    continue
                }

                return opaqueType
            }

            for property in protocolDeclaration.properties where property.name == "subscript" {
                guard let functionType = parsedFunctionPropertyType(
                    from: property.rawType,
                    moduleName: moduleName
                ),
                subscriptRequirementKey(
                    for: functionType.arguments,
                    moduleName: moduleName
                ) == requirementKey,
                let opaqueType = opaqueType(
                    fromRequirementReturnType: functionType.returnType,
                    in: protocolDeclaration,
                    moduleName: moduleName
                ) else {
                    continue
                }

                return opaqueType
            }
        }

        return nil
    }

    private func protocolDeclarations(
        conformedToBy declaration: Declaration,
        declarations: [String: Declaration],
        moduleName: String
    ) -> [Declaration] {
        var result: [Declaration] = []
        var visited: Set<String> = []

        func visit(_ rawConformance: String) {
            let cleanedConformance = cleanedTypeName(rawConformance, moduleName: moduleName)
            guard let protocolDeclaration = declarations.values.first(where: {
                $0.resolvedKind == .protocol
                    && (
                        cleanedTypeName($0.fullName, moduleName: moduleName) == cleanedConformance
                            || simpleName(of: $0.fullName) == cleanedConformance
                    )
            }),
            visited.insert(protocolDeclaration.fullName).inserted else {
                return
            }

            result.append(protocolDeclaration)
            for inheritedConformance in protocolDeclaration.conformances {
                visit(inheritedConformance)
            }
        }

        for conformance in declaration.conformances {
            visit(conformance)
        }

        return result
    }

    private func opaqueType(
        fromRequirementReturnType rawReturnType: String,
        in protocolDeclaration: Declaration,
        moduleName: String
    ) -> String? {
        let associatedTypeNames = Set(protocolDeclaration.associatedTypes.map(\.name))
        let cleanedReturnType = cleanedTypeName(rawReturnType, moduleName: moduleName)

        let associatedTypeName: String
        if associatedTypeNames.contains(cleanedReturnType) {
            associatedTypeName = cleanedReturnType
        } else if let separator = cleanedReturnType.lastIndex(of: ".") {
            let candidate = String(cleanedReturnType[cleanedReturnType.index(after: separator)...])
            guard associatedTypeNames.contains(candidate) else {
                return nil
            }
            associatedTypeName = candidate
        } else {
            return nil
        }

        guard let associatedType = protocolDeclaration.associatedTypes.first(where: {
            $0.name == associatedTypeName
        }) else {
            return nil
        }

        let conformances = normalizedConformances(associatedType.conformances)
        guard !conformances.isEmpty else {
            return nil
        }

        return "some " + conformances
            .map { cleanedTypeName($0, moduleName: moduleName) }
            .joined(separator: " & ")
    }

    private func callableRequirementKey(
        for rawSignature: String,
        isStatic: Bool,
        moduleName: String
    ) -> String? {
        guard let components = parsedCallableSignatureComponents(from: rawSignature) else {
            return nil
        }

        let cleanedArguments = cleanedTypeName(components.arguments, moduleName: moduleName)
        let labels = parsedTupleType(fromArgumentList: cleanedArguments)?.elements.map {
            $0.firstName?.text ?? "_"
        } ?? [cleanedArguments]

        return "\(isStatic ? "static" : "instance")|\(components.name)|\(labels.joined(separator: ","))"
    }

    private func subscriptRequirementKey(
        for rawArguments: String,
        moduleName: String
    ) -> String {
        let cleanedArguments = cleanedTypeName(rawArguments, moduleName: moduleName)
        let labels = parsedTupleType(fromArgumentList: cleanedArguments)?.elements.map {
            $0.firstName?.text ?? "_"
        } ?? [cleanedArguments]

        return labels.joined(separator: ",")
    }

    private func parsedCallableSignatureComponents(
        from rawSignature: String
    ) -> (name: String, arguments: String, returnType: String)? {
        let openingParenthesis: String.Index
        if let angleBracket = rawSignature.firstIndex(of: "<"),
           let firstParen = rawSignature.firstIndex(of: "("),
           angleBracket < firstParen,
           let closingAngle = matchingClosingDelimiter(
               in: rawSignature,
               from: angleBracket,
               open: "<",
               close: ">"
           ) {
            guard let parenthesis = rawSignature[rawSignature.index(after: closingAngle)...].firstIndex(of: "(") else {
                return nil
            }
            openingParenthesis = parenthesis
        } else {
            guard let parenthesis = rawSignature.firstIndex(of: "(") else {
                return nil
            }
            openingParenthesis = parenthesis
        }

        guard let closingParenthesis = matchingClosingParenthesis(
            in: rawSignature,
            from: openingParenthesis
        ) else {
            return nil
        }

        let head = String(rawSignature[..<openingParenthesis])
        let arguments = String(
            rawSignature[rawSignature.index(after: openingParenthesis)..<closingParenthesis]
        )
        let trailingSignature = String(rawSignature[rawSignature.index(after: closingParenthesis)...])
        let returnType: String

        if let returnArrow = topLevelArrowRange(in: trailingSignature) {
            let rawReturnSection = String(trailingSignature[returnArrow.upperBound...])
                .trimmingCharacters(in: .whitespaces)
            returnType = splitTrailingWhereClause(from: rawReturnSection).returnType
        } else {
            returnType = "()"
        }

        return (
            name: parseGenericClause(head, moduleName: "").name,
            arguments: arguments,
            returnType: returnType
        )
    }

    private func parsedFunctionPropertyType(
        from rawType: String,
        moduleName: String
    ) -> (arguments: String, returnType: String)? {
        let cleanedRawType = cleanedTypeName(rawType, moduleName: moduleName)
            .trimmingCharacters(in: .whitespaces)
        guard let returnArrow = topLevelArrowRange(in: cleanedRawType) else {
            return nil
        }

        let rawArguments = String(cleanedRawType[..<returnArrow.lowerBound])
            .trimmingCharacters(in: .whitespaces)
        let rawReturnType = String(cleanedRawType[returnArrow.upperBound...])
            .trimmingCharacters(in: .whitespaces)

        let arguments: String
        if rawArguments.first == "(", rawArguments.last == ")" {
            arguments = String(rawArguments.dropFirst().dropLast())
        } else {
            arguments = rawArguments
        }

        return (
            arguments: arguments,
            returnType: splitTrailingWhereClause(from: rawReturnType).returnType
        )
    }

    /// Renders a raw argument list string into cleaned Swift parameter syntax.
    ///
    /// Splits the argument string at top-level commas, resolves labels vs unlabeled
    /// parameters, and applies type name cleanup and existential wrapping.
    ///
    /// - Parameters:
    ///   - rawArguments: The raw comma-separated argument list from a demangled signature.
    ///   - protocolNames: Known protocol names for existential rendering.
    ///   - moduleName: The module name for type name cleanup.
    /// - Returns: The rendered argument list string.
    /// - Throws: ``SwiftInterfaceGeneratorError/unexpectedOutput(_:)`` if the argument
    ///   list has unbalanced delimiters.
    func renderedArgumentList(
        _ rawArguments: String,
        protocolNames: Set<String>,
        moduleName: String
    ) throws -> String {
        let sanitizedArguments = cleanedTypeName(rawArguments, moduleName: moduleName)
        return try parsedTupleType(fromArgumentList: sanitizedArguments)?.elements.map { element in
            let label = element.firstName?.text ?? "_"
            let renderedLabel = label == "_" ? "_" : escapedIdentifier(label)
            return "\(renderedLabel): \(renderedTupleElementType(element, protocolNames: protocolNames, moduleName: moduleName))"
        }.joined(separator: ", ")
            ?? {
                throw SwiftInterfaceGeneratorError.unexpectedOutput(
                    "Unbalanced argument list: \(sanitizedArguments)"
                )
            }()
    }

    private func renderedTupleElementType(
        _ element: TupleTypeElementSyntax,
        protocolNames: Set<String>,
        moduleName: String
    ) -> String {
        var rendered = renderedTypeName(
            element.type.trimmedDescription,
            protocolNames: protocolNames,
            moduleName: moduleName
        )
        if element.inoutKeyword != nil {
            rendered = "inout \(rendered)"
        }
        if element.ellipsis != nil {
            rendered += "..."
        }
        return rendered
    }

    private static let genericExcludedTokens: Set<String> = [
        "Any", "AnyObject", "Bool", "Data", "Date", "Decoder", "Double",
        "Encoder", "Error", "Float", "Hasher", "IndexPath", "Int", "Int32",
        "Int64", "Never", "Self", "String", "Type", "UInt", "UInt32",
        "UInt64", "URL", "UUID", "Void", "_", "autoclosure", "async", "class", "func",
        "init", "inout", "mutating", "nil", "some", "static", "throws", "where",
    ]

    private static let typeReplacements: [(String, String)] = [
        ("__owned ", ""),
        ("@Swift.MainActor", "@MainActor"),
        ("Swift.Actor", "_Concurrency.Actor"),
        ("Swift.AsyncIteratorProtocol", "_Concurrency.AsyncIteratorProtocol"),
        ("Swift.AsyncSequence", "_Concurrency.AsyncSequence"),
        ("Swift.ContinuousClock", "_Concurrency.ContinuousClock"),
        ("__C.CGAffineTransform", "CoreGraphics.CGAffineTransform"),
        ("__C.CGFloat", "CoreGraphics.CGFloat"),
        ("__C.CGPoint", "CoreGraphics.CGPoint"),
        ("__C.CGRect", "CoreGraphics.CGRect"),
        ("__C.CGSize", "CoreGraphics.CGSize"),
        ("__C.CGImageRef", "CoreGraphics.CGImage"),
        ("__C.CALayer", "QuartzCore.CALayer"),
        ("__C.CATransform3D", "QuartzCore.CATransform3D"),
        ("__C.NSCoder", "Foundation.NSCoder"),
        ("__C.NSUserActivity", "Foundation.NSUserActivity"),
        ("__C.NSHashTable", "Foundation.NSHashTable"),
        ("__C.IOSurfaceRef", "IOSurfaceRef"),
        ("__C.audit_token_t", "Darwin.audit_token_t"),
    ]

    /// Cleans a raw demangled type name for use in a `.swiftinterface` file.
    ///
    /// Removes the current module prefix, strips `__owned` annotations, and rewrites
    /// Objective-C bridged type names (`__C.CGRect`, `__C.NSCoder`, etc.) to their
    /// Swift-native equivalents (`CoreGraphics.CGRect`, `Foundation.NSCoder`).
    ///
    /// - Parameters:
    ///   - rawTypeName: The raw type name from demangled output.
    ///   - moduleName: The current module name to strip (defaults to empty).
    /// - Returns: The cleaned type name suitable for a `.swiftinterface` file.
    func cleanedTypeName(
        _ rawTypeName: String,
        moduleName: String = ""
    ) -> String {
        var cleaned = rawTypeName.replacing(/\(extension in [^)]+\):/, with: "")
        if !moduleName.isEmpty {
            cleaned = cleaned.replacingOccurrences(of: "\(moduleName).", with: "")
        }
        for (from, to) in Self.typeReplacements {
            if cleaned.contains(from) {
                cleaned = cleaned.replacingOccurrences(of: from, with: to)
            }
        }
        return removingRedundantExtensionConstraintClauses(
            in: normalizingPrimaryAssociatedTypeExistentials(
                in: replacingDemanglerPackSyntax(in: cleaned)
            )
        )
            .replacingADotPattern()
            .replacingProtocolKeyword()
    }

    private func removingRedundantExtensionConstraintClauses(in string: String) -> String {
        guard string.contains("><") else {
            return string
        }

        var result = ""
        result.reserveCapacity(string.count)

        var index = string.startIndex
        while index < string.endIndex {
            let character = string[index]
            result.append(character)

            guard
                character == ">",
                let nextIndex = string.index(index, offsetBy: 1, limitedBy: string.endIndex),
                nextIndex < string.endIndex,
                string[nextIndex] == "<",
                let clauseEnd = matchingClosingDelimiter(
                    in: string,
                    from: nextIndex,
                    open: "<",
                    close: ">"
                )
            else {
                index = string.index(after: index)
                continue
            }

            let clauseContents = String(string[string.index(after: nextIndex)..<clauseEnd])
            if clauseContents.contains(" where ") {
                index = string.index(after: clauseEnd)
                continue
            }

            index = string.index(after: index)
        }

        return result
    }

    private func normalizingPrimaryAssociatedTypeExistentials(in string: String) -> String {
        guard string.contains("<") && string.contains("==") else {
            return string
        }

        var result = ""
        var index = string.startIndex

        while index < string.endIndex {
            let character = string[index]
            guard character == "<",
                  let closingAngle = matchingClosingDelimiter(
                      in: string,
                      from: index,
                      open: "<",
                      close: ">"
                  ),
                  let replacement = normalizedPrimaryAssociatedTypeExistentialClause(
                      String(string[index...closingAngle])
                  ) else {
                result.append(character)
                index = string.index(after: index)
                continue
            }

            result += replacement
            index = string.index(after: closingAngle)
        }

        return result
    }

    private func normalizedPrimaryAssociatedTypeExistentialClause(_ clause: String) -> String? {
        guard clause.first == "<", clause.last == ">" else {
            return nil
        }

        let body = String(
            clause[clause.index(after: clause.startIndex)..<clause.index(before: clause.endIndex)]
        )
        .trimmingCharacters(in: .whitespaces)
        guard body.contains("==") else {
            return nil
        }

        let parts = body
            .components(separatedBy: "==")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        guard parts.count == 2 else {
            return nil
        }

        let left = parts[0]
        let right = parts[1]

        if left == right {
            if left.hasPrefix("Self.") {
                return "<\(left)>"
            }
            guard let firstCharacter = left.first, firstCharacter.isUppercase else {
                return nil
            }
            return ""
        }

        let selfTypePrefix = "Self."
        if left.hasPrefix(selfTypePrefix), let firstCharacter = right.first, firstCharacter.isUppercase {
            return "<\(right)>"
        }
        if right.hasPrefix(selfTypePrefix), let firstCharacter = left.first, firstCharacter.isUppercase {
            return "<\(left)>"
        }

        return nil
    }

    private func replacingDemanglerPackSyntax(in string: String) -> String {
        let marker = "Pack{"
        guard string.contains(marker) else {
            return string
        }

        var result = ""
        var searchStart = string.startIndex

        while let range = string.range(
            of: marker,
            range: searchStart..<string.endIndex
        ) {
            result += string[searchStart..<range.lowerBound]

            let openingBrace = string.index(before: range.upperBound)
            guard let closingBrace = matchingClosingDelimiter(
                in: string,
                from: openingBrace,
                open: "{",
                close: "}"
            ) else {
                result += string[range.lowerBound...]
                return result
            }

            let body = String(string[range.upperBound..<closingBrace])
            result += normalizedDemanglerPackBody(body)
            searchStart = string.index(after: closingBrace)
        }

        result += string[searchStart...]
        return result
    }

    private func normalizedDemanglerPackBody(_ body: String) -> String {
        let normalized = replacingDemanglerPackSyntax(in: body)
        guard normalized.hasPrefix("repeat "),
              !normalized.hasPrefix("repeat each ") else {
            return normalized
        }

        return "repeat each " + normalized.dropFirst("repeat ".count)
    }

    /// Renders a type name with proper existential syntax for protocols.
    ///
    /// Applies ``cleanedTypeName(_:moduleName:)`` first, then wraps known protocol types
    /// in `any` syntax. Optional protocol types are rendered as `(any Protocol)?`.
    ///
    /// - Parameters:
    ///   - rawTypeName: The raw type name from demangled output.
    ///   - protocolNames: The set of known protocol names in the module.
    ///   - moduleName: The current module name for type name cleanup.
    /// - Returns: The rendered type name with existential syntax applied.
    func renderedTypeName(
        _ rawTypeName: String,
        protocolNames: Set<String>,
        moduleName: String = ""
    ) -> String {
        let cleaned = cleanedTypeName(rawTypeName, moduleName: moduleName)
        let rewritten: String
        if let typeSyntax = parsedTypeSyntax(from: cleaned) {
            rewritten = ExistentialTypeRewriter(protocolNames: protocolNames)
                .visit(typeSyntax)
                .trimmedDescription
        } else {
            rewritten = cleaned
        }

        return normalizedExistentialComposition(
            in: normalizedRedundantAnyMetatype(rewritten)
        )
    }

    private func normalizedRedundantAnyMetatype(_ string: String) -> String {
        let nestedAnyMetatype = /any\s*\((?<innerAny>any [^()]+)\)\.Type/
        var result = string

        while let match = result.firstMatch(of: nestedAnyMetatype) {
            let innerProtocol = String(match.innerAny)
                .replacing(/^any\s+/, with: "")
            result.replaceSubrange(
                match.range,
                with: "any \(innerProtocol).Type"
            )
        }

        return result
    }

    private func parsedTypeSyntax(from source: String) -> TypeSyntax? {
        var parser = Parser(source)
        let type = TypeSyntax.parse(from: &parser)
        guard !type.hasError else {
            return nil
        }
        return type
    }

    private func parsedTupleType(fromArgumentList source: String) -> TupleTypeSyntax? {
        guard let parsedType = parsedTypeSyntax(from: "(\(source))") else {
            return nil
        }
        return parsedType.as(TupleTypeSyntax.self)
    }

    private func cleanedTypeFragment(
        from fragment: String,
        moduleName: String
    ) -> (returnType: String, whereClause: String) {
        let cleanedFragment = cleanedTypeName(fragment, moduleName: moduleName)
        let typeFragment = cleanedFragment.firstIndex(of: "(").map {
            String(cleanedFragment[$0...])
        } ?? cleanedFragment
        return splitTrailingWhereClause(from: typeFragment)
    }

    private func parsedTypeFragment(from fragment: String, moduleName: String) -> TypeSyntax? {
        parsedTypeSyntax(from: cleanedTypeFragment(from: fragment, moduleName: moduleName).returnType)
    }

    private func genericParameterTokens(in fragment: String, moduleName: String) -> [String] {
        let parts = cleanedTypeFragment(from: fragment, moduleName: moduleName)

        var tokens: [String] = []
        if let typeSyntax = parsedTypeSyntax(from: parts.returnType) {
            let collector = GenericParameterTokenCollector()
            collector.walk(typeSyntax)
            tokens.append(contentsOf: collector.tokens)
        }
        if !parts.whereClause.isEmpty {
            tokens.append(contentsOf: genericRequirementTokens(in: parts.whereClause))
        }
        return tokens
    }

    private func referencedTypeArities(
        in fragment: String,
        moduleName: String
    ) -> [(name: String, arity: Int)] {
        guard let typeSyntax = parsedTypeFragment(from: fragment, moduleName: moduleName) else {
            return []
        }

        let collector = TypeReferenceCollector()
        collector.walk(typeSyntax)
        return collector.references
    }

    private func genericRequirementTokens(in clause: String) -> [String] {
        let requirements = clause.replacing(/^\s*where\s+/, with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !requirements.isEmpty else {
            return []
        }

        var parser = Parser("func _<T>() where \(requirements) {}")
        let declaration = DeclSyntax.parse(from: &parser)
        guard let function = declaration.as(FunctionDeclSyntax.self),
              let whereClause = function.genericWhereClause else {
            return []
        }

        let collector = GenericParameterTokenCollector()
        collector.walk(whereClause)
        return collector.tokens
    }

    private final class GenericParameterTokenCollector: SyntaxVisitor {
        var tokens: [String] = []

        init() {
            super.init(viewMode: .sourceAccurate)
        }

        override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
            if !(node.parent?.is(MemberTypeSyntax.self) ?? false) {
                tokens.append(node.name.text)
            }
            return .visitChildren
        }
    }

    private final class TypeReferenceCollector: SyntaxVisitor {
        var references: [(name: String, arity: Int)] = []

        init() {
            super.init(viewMode: .sourceAccurate)
        }

        override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
            references.append((node.name.text, node.genericArgumentClause?.arguments.count ?? 0))
            return .visitChildren
        }

        override func visit(_ node: MemberTypeSyntax) -> SyntaxVisitorContinueKind {
            references.append((fullName(of: node), node.genericArgumentClause?.arguments.count ?? 0))
            return .visitChildren
        }

        private func fullName(of node: MemberTypeSyntax) -> String {
            "\(baseName(of: node.baseType)).\(node.name.text)"
        }

        private func baseName(of type: TypeSyntax) -> String {
            if let identifier = type.as(IdentifierTypeSyntax.self) {
                return identifier.name.text
            }
            if let member = type.as(MemberTypeSyntax.self) {
                return fullName(of: member)
            }
            return type.trimmedDescription
        }
    }

    private final class ExistentialTypeRewriter: SyntaxRewriter {
        private let protocolNames: Set<String>

        init(protocolNames: Set<String>) {
            self.protocolNames = protocolNames
            super.init(viewMode: .sourceAccurate)
        }

        override func visit(_ node: IdentifierTypeSyntax) -> TypeSyntax {
            guard shouldWrap(node) else {
                return super.visit(node)
            }
            return wrappedExistential(around: super.visit(node))
        }

        override func visit(_ node: MemberTypeSyntax) -> TypeSyntax {
            let visited = super.visit(node)
            guard let visitedMember = visited.as(MemberTypeSyntax.self),
                  shouldWrap(visitedMember) else {
                return visited
            }
            return wrappedExistential(around: visited)
        }

        private func shouldWrap(_ node: IdentifierTypeSyntax) -> Bool {
            guard protocolNames.contains(node.trimmedDescription) else {
                return false
            }
            guard !(node.parent?.is(SomeOrAnyTypeSyntax.self) ?? false) else {
                return false
            }
            guard !(node.parent?.is(MemberTypeSyntax.self) ?? false) else {
                return false
            }
            return true
        }

        private func shouldWrap(_ node: MemberTypeSyntax) -> Bool {
            guard protocolNames.contains(node.trimmedDescription) else {
                return false
            }
            return !(node.parent?.is(SomeOrAnyTypeSyntax.self) ?? false)
        }

        override func visit(_ node: OptionalTypeSyntax) -> TypeSyntax {
            let visited = super.visit(node)
            guard let optional = visited.as(OptionalTypeSyntax.self),
                  optional.wrappedType.is(SomeOrAnyTypeSyntax.self) else {
                return visited
            }
            return TypeSyntax(optional.with(\.wrappedType, parenthesized(optional.wrappedType)))
        }

        override func visit(_ node: ImplicitlyUnwrappedOptionalTypeSyntax) -> TypeSyntax {
            let visited = super.visit(node)
            guard let iuo = visited.as(ImplicitlyUnwrappedOptionalTypeSyntax.self),
                  iuo.wrappedType.is(SomeOrAnyTypeSyntax.self) else {
                return visited
            }
            return TypeSyntax(iuo.with(\.wrappedType, parenthesized(iuo.wrappedType)))
        }

        override func visit(_ node: MetatypeTypeSyntax) -> TypeSyntax {
            let visited = super.visit(node)
            guard let metatype = visited.as(MetatypeTypeSyntax.self),
                  metatype.baseType.is(SomeOrAnyTypeSyntax.self) else {
                return visited
            }
            return TypeSyntax(metatype.with(\.baseType, parenthesized(metatype.baseType)))
        }

        private func wrappedExistential(around type: some TypeSyntaxProtocol) -> TypeSyntax {
            TypeSyntax(
                SomeOrAnyTypeSyntax(
                    someOrAnySpecifier: .keyword(.any).with(\.trailingTrivia, .space),
                    constraint: type
                )
            )
        }

        private func parenthesized(_ type: TypeSyntax) -> TypeSyntax {
            TypeSyntax(
                TupleTypeSyntax(
                    leftParen: .leftParenToken(),
                    elements: TupleTypeElementListSyntax([
                        TupleTypeElementSyntax(type: type)
                    ]),
                    rightParen: .rightParenToken()
                )
            )
        }
    }

    /// Parses an associated type descriptor symbol line.
    ///
    /// Matches lines like `"associated type descriptor for Module.Protocol.Element"` and
    /// extracts the owning protocol name and associated type name.
    ///
    /// - Parameters:
    ///   - line: The demangled symbol line to parse.
    ///   - moduleName: The module name prefix to match.
    /// - Returns: A tuple of `(owner, associatedType)`, or `nil` if the line doesn't match.
    func parseAssociatedTypeDescriptor(
        from line: String,
        moduleName: String
    ) -> (owner: String, associatedType: String)? {
        let prefix = "associated type descriptor for \(moduleName)."
        guard line.hasPrefix(prefix) else {
            return nil
        }

        let remainder = String(line.dropFirst(prefix.count))
        guard let separator = remainder.lastIndex(of: ".") else {
            return nil
        }

        return (
            owner: String(remainder[..<separator]),
            associatedType: String(remainder[remainder.index(after: separator)...])
        )
    }

    /// Parses a protocol conformance descriptor symbol line.
    ///
    /// Matches lines like `"protocol conformance descriptor for Module.Type : Swift.Hashable in Module"`
    /// and extracts the conforming type and the protocol it conforms to.
    ///
    /// - Parameters:
    ///   - line: The demangled symbol line to parse.
    ///   - moduleName: The module name prefix to match.
    /// - Returns: A tuple of `(owner, conformance)`, or `nil` if the line doesn't match.
    func parseConformanceDescriptor(
        from line: String,
        moduleName: String
    ) -> (owner: String, conformance: String)? {
        let prefix = "protocol conformance descriptor for \(moduleName)."
        guard line.hasPrefix(prefix) else {
            return nil
        }

        let remainder = String(line.dropFirst(prefix.count))
        guard
            let conformanceSeparator = remainder.range(of: " : "),
            let moduleSeparator = remainder.range(of: " in ", range: conformanceSeparator.upperBound..<remainder.endIndex)
        else {
            return nil
        }

        let owner = removingGenericArguments(from: String(remainder[..<conformanceSeparator.lowerBound]))
        let conformance = String(remainder[conformanceSeparator.upperBound..<moduleSeparator.lowerBound])
        return (owner, conformance)
    }

    func parseExternalConformanceDescriptor(
        from line: String,
        moduleName: String
    ) -> (owner: String, conformance: String)? {
        let prefix = "protocol conformance descriptor for "
        let suffix = " in \(moduleName)"
        guard line.hasPrefix(prefix), line.hasSuffix(suffix) else {
            return nil
        }

        let remainder = String(line.dropFirst(prefix.count).dropLast(suffix.count))
        guard let conformanceSeparator = remainder.range(of: " : ") else {
            return nil
        }

        let owner = removingGenericArguments(from: String(remainder[..<conformanceSeparator.lowerBound]))
        let conformance = String(remainder[conformanceSeparator.upperBound...])
        guard !owner.hasPrefix("\(moduleName).") else {
            return nil
        }

        return (owner, conformance)
    }

    /// Parses a protocol base conformance descriptor symbol line.
    ///
    /// Matches lines like `"base conformance descriptor for Module.Protocol: Swift.Sendable"`
    /// and extracts the inheriting protocol name and inherited protocol.
    ///
    /// - Parameters:
    ///   - line: The demangled symbol line to parse.
    ///   - moduleName: The module name prefix to match.
    /// - Returns: A tuple of `(owner, conformance)`, or `nil` if the line doesn't match.
    func parseBaseConformanceDescriptor(
        from line: String,
        moduleName: String
    ) -> (owner: String, conformance: String)? {
        let prefix = "base conformance descriptor for \(moduleName)."
        guard line.hasPrefix(prefix) else {
            return nil
        }

        let remainder = String(line.dropFirst(prefix.count))
        guard let separator = remainder.range(of: ": ") else {
            return nil
        }

        let owner = removingGenericArguments(from: String(remainder[..<separator.lowerBound]))
        let conformance = String(remainder[separator.upperBound...])
        return (owner, conformance)
    }

    /// Parses an associated conformance descriptor symbol line.
    ///
    /// Matches lines like
    /// `"associated conformance descriptor for Module.Protocol.Module.Protocol.Element: Module.Displayable"`
    /// and extracts the owning protocol, associated type name, and required conformance.
    ///
    /// - Parameters:
    ///   - line: The demangled symbol line to parse.
    ///   - moduleName: The module name prefix to match.
    /// - Returns: A tuple of `(owner, associatedType, conformance)`, or `nil` if the line
    ///   doesn't match.
    func parseAssociatedConformanceDescriptor(
        from line: String,
        moduleName: String
    ) -> (owner: String, associatedType: String, conformance: String)? {
        let prefix = "associated conformance descriptor for \(moduleName)."
        guard line.hasPrefix(prefix) else {
            return nil
        }

        let remainder = String(line.dropFirst(prefix.count))
        guard let separator = remainder.range(of: ": ") else {
            return nil
        }

        let lhs = String(remainder[..<separator.lowerBound])
        let conformance = String(remainder[separator.upperBound...])
        guard let ownerSeparator = lhs.range(of: ".\(moduleName).") else {
            return nil
        }

        let owner = String(lhs[..<ownerSeparator.lowerBound])
        guard !owner.isEmpty else {
            return nil
        }

        let associatedPath = String(lhs[ownerSeparator.upperBound...])
        let ownerPrefix = "\(owner)."
        let associatedTypePath: String
        if associatedPath.hasPrefix(ownerPrefix) {
            associatedTypePath = String(associatedPath.dropFirst(ownerPrefix.count))
        } else {
            associatedTypePath = associatedPath
        }

        let associatedType: String
        if let nameSeparator = associatedTypePath.lastIndex(of: ".") {
            associatedType = String(associatedTypePath[associatedTypePath.index(after: nameSeparator)...])
        } else {
            associatedType = associatedTypePath
        }

        guard !associatedType.isEmpty else {
            return nil
        }
        return (owner, associatedType, conformance)
    }

    /// Parses a property descriptor symbol line.
    ///
    /// Matches lines like `"property descriptor for Module.Type.propertyName : Swift.String"`
    /// and extracts the owner, property name, type, and whether it's static. Also scans the
    /// full symbol list for corresponding getter/setter symbols to determine mutability.
    ///
    /// - Parameters:
    ///   - line: The demangled symbol line to parse.
    ///   - sortedSymbols: Sorted symbols for efficient getter/setter detection via prefix search.
    ///   - moduleName: The module name prefix to match.
    /// - Returns: A tuple of property metadata, or `nil` if the line doesn't match.
    func parsePropertyDescriptor(
        from line: String,
        sortedSymbols: SortedSymbols,
        moduleName: String,
        allowExtensionMembersOn allowedExtensionOwners: Set<String> = []
    ) -> (owner: String, name: String, rawType: String, isStatic: Bool, hasSetter: Bool)? {
        let prefix = "property descriptor for "
        guard line.hasPrefix(prefix) else {
            return nil
        }

        var remainder = String(line.dropFirst(prefix.count))
        let isStatic: Bool
        if remainder.hasPrefix("static ") {
            isStatic = true
            remainder.removeFirst("static ".count)
        } else {
            isStatic = false
        }

        let extensionPrefix = "(extension in \(moduleName)):"
        let isExtensionMember: Bool
        if remainder.hasPrefix(extensionPrefix) {
            isExtensionMember = true
            remainder.removeFirst(extensionPrefix.count)
        } else {
            isExtensionMember = false
        }

        guard
            (isExtensionMember || remainder.hasPrefix("\(moduleName).")),
            let typeSeparator = remainder.range(of: " : ")
        else {
            return nil
        }

        let path = String(remainder[..<typeSeparator.lowerBound])
        let rawType = String(remainder[typeSeparator.upperBound...])
        let member = isExtensionMember
            ? parseAnyOwnerMemberPath(path, moduleName: moduleName)
            : parseOwnerMemberPath(path, moduleName: moduleName).map {
                (owner: $0.owner, name: $0.name, symbolOwner: $0.owner, isLocalOwner: true)
            }
        guard let member else {
            return nil
        }
        let resolvedOwner = removingGenericArguments(from: member.owner)
        if isExtensionMember, !allowedExtensionOwners.contains(resolvedOwner) {
            return nil
        }

        let staticPrefix = isStatic ? "static " : ""
        let memberPrefix = isExtensionMember
            ? (member.isLocalOwner ? "\(extensionPrefix)\(moduleName)." : extensionPrefix)
            : "\(moduleName)."
        let getterPrefix = "\(staticPrefix)\(memberPrefix)\(member.symbolOwner).\(member.name).getter : "
        let setterPrefix = "\(staticPrefix)\(memberPrefix)\(member.symbolOwner).\(member.name).setter : "
        let dispatchSetterPrefix = "dispatch thunk of \(moduleName).\(member.owner).\(member.name).setter : "

        let hasGetter = sortedSymbols.containsPrefix(getterPrefix)
        let hasSetter = (hasGetter && sortedSymbols.containsPrefix(setterPrefix))
            || sortedSymbols.containsPrefix(dispatchSetterPrefix)

        return (
            owner: resolvedOwner,
            name: member.name,
            rawType: rawType,
            isStatic: isStatic,
            hasSetter: hasSetter
        )
    }

    /// Parses a subscript descriptor symbol line.
    ///
    /// Matches lines like `"property descriptor for Module.Type.subscript(Swift.Int) -> Swift.String"`
    /// and extracts the owning type, argument list, result type, and setter availability.
    ///
    /// - Parameters:
    ///   - line: The demangled symbol line to parse.
    ///   - sortedSymbols: Sorted symbols for efficient getter/setter detection via prefix search.
    ///   - moduleName: The module name prefix to match.
    /// - Returns: A tuple of subscript metadata, or `nil` if the line doesn't match.
    func parseSubscriptDescriptor(
        from line: String,
        sortedSymbols: SortedSymbols,
        moduleName: String,
        allowExtensionMembersOn allowedExtensionOwners: Set<String> = []
    ) -> (owner: String, rawArguments: String, rawReturnType: String, hasSetter: Bool)? {
        let prefix = "property descriptor for "
        guard line.hasPrefix(prefix) else {
            return nil
        }

        var remainder = String(line.dropFirst(prefix.count))
        let extensionPrefix = "(extension in \(moduleName)):"
        let isExtensionMember: Bool
        if remainder.hasPrefix(extensionPrefix) {
            isExtensionMember = true
            remainder.removeFirst(extensionPrefix.count)
        } else {
            isExtensionMember = false
        }

        let modulePrefix = "\(moduleName)."
        let isLocalOwner = remainder.hasPrefix(modulePrefix)
        if !isExtensionMember || isLocalOwner {
            guard remainder.hasPrefix(modulePrefix) else {
                return nil
            }
            remainder.removeFirst(modulePrefix.count)
        }
        guard let subscriptRange = remainder.range(of: ".subscript(") else {
            return nil
        }
        let openingParenthesis = remainder.index(before: subscriptRange.upperBound)
        guard
            let closingParenthesis = matchingClosingParenthesis(
                in: remainder,
                from: openingParenthesis
            ),
            let returnArrow = remainder.range(
                of: " -> ",
                range: remainder.index(after: closingParenthesis)..<remainder.endIndex
            )
        else {
            return nil
        }

        let owner = String(remainder[..<subscriptRange.lowerBound])
        let resolvedOwner = removingGenericArguments(from: owner)
        if isExtensionMember, !allowedExtensionOwners.contains(resolvedOwner) {
            return nil
        }
        let rawArguments = String(remainder[subscriptRange.upperBound..<closingParenthesis])
        let rawReturnType = String(remainder[returnArrow.upperBound...])

        let memberPrefix = isExtensionMember
            ? (isLocalOwner ? "\(extensionPrefix)\(moduleName)." : extensionPrefix)
            : modulePrefix
        let getterPrefix = "\(memberPrefix)\(owner).subscript.getter : "
        let setterPrefix = "\(memberPrefix)\(owner).subscript.setter : "
        let dispatchSetterPrefix = "dispatch thunk of \(moduleName).\(owner).subscript.setter : "

        let hasSetter = sortedSymbols.containsPrefix(setterPrefix)
            || sortedSymbols.containsPrefix(dispatchSetterPrefix)
        let hasGetter = sortedSymbols.containsPrefix(getterPrefix)
        guard hasGetter else {
            return nil
        }

        return (
            owner: resolvedOwner,
            rawArguments: rawArguments,
            rawReturnType: rawReturnType,
            hasSetter: hasSetter
        )
    }

    /// Parses an enum case symbol line.
    ///
    /// Matches lines like `"enum case for Module.Type.caseName(Module.Type) -> (Swift.String) -> Module.Type"`
    /// and extracts the owning enum, case name, and optional associated value payload.
    ///
    /// - Parameters:
    ///   - line: The demangled symbol line to parse.
    ///   - moduleName: The module name prefix to match.
    /// - Returns: A tuple of `(owner, name, rawPayload, rawOwnerType)`, or `nil` if the line doesn't match.
    func parseEnumCase(
        from line: String,
        moduleName: String
    ) -> (owner: String, name: String, rawPayload: String?, rawOwnerType: String?)? {
        let prefix = "enum case for \(moduleName)."
        guard line.hasPrefix(prefix) else {
            return nil
        }

        let remainder = String(line.dropFirst(prefix.count))
        guard let caseSignatureSeparator = remainder.range(of: ") -> ") else {
            return nil
        }

        let casePathWithType = String(remainder[..<caseSignatureSeparator.lowerBound])
        guard let openingParenthesis = casePathWithType.firstIndex(of: "(") else {
            return nil
        }

        let casePath = String(casePathWithType[..<openingParenthesis])
        guard let caseNameSeparator = memberDotIndex(in: casePath, before: casePath.endIndex)
        else {
            return nil
        }

        let owner = String(casePath[..<caseNameSeparator])
        let name = removingGenericArguments(
            from: String(casePath[casePath.index(after: caseNameSeparator)...])
        )
        let tail = String(remainder[caseSignatureSeparator.upperBound...])
            .replacingOccurrences(of: "\(moduleName).", with: "")
        let rawOwnerType: String
        let rawPayload: String?

        if let payloadArrow = topLevelArrowRange(in: tail) {
            rawOwnerType = String(tail[payloadArrow.upperBound...]).trimmingCharacters(in: .whitespaces)
            var payload = String(tail[..<payloadArrow.lowerBound]).trimmingCharacters(in: .whitespaces)
            if payload.first == "(", payload.last == ")" {
                payload.removeFirst()
                payload.removeLast()
            }
            rawPayload = payload
        } else {
            rawOwnerType = tail.trimmingCharacters(in: .whitespaces)
            rawPayload = nil
        }

        guard removingGenericArguments(from: rawOwnerType) == owner else {
            return (owner, name, nil, nil)
        }

        return (owner, name, rawPayload, rawOwnerType)
    }

    /// Parses a protocol method descriptor symbol line.
    ///
    /// Matches lines like `"method descriptor for Module.Protocol.methodName(...) -> ..."`
    /// and extracts the owning protocol and the raw method signature.
    ///
    /// - Parameters:
    ///   - line: The demangled symbol line to parse.
    ///   - moduleName: The module name prefix to match.
    /// - Returns: A tuple of `(owner, rawSignature)`, or `nil` if the line doesn't match.
    func parseProtocolMethodDescriptor(
        from line: String,
        moduleName: String
    ) -> (owner: String, rawSignature: String)? {
        let prefix = "method descriptor for \(moduleName)."
        guard line.hasPrefix(prefix) else {
            return nil
        }

        let remainder = String(line.dropFirst(prefix.count))
        guard
            !remainder.contains("__allocating_init"),
            !containsAccessorLikeSymbol(remainder)
        else {
            return nil
        }
        guard
            let openingParenthesis = remainder.firstIndex(of: "("),
            let memberSeparator = memberDotIndex(in: remainder, before: openingParenthesis)
        else {
            return nil
        }

        let owner = String(remainder[..<memberSeparator])
        let signature = String(remainder[remainder.index(after: memberSeparator)...])
        return (owner, signature)
    }

    /// Parses a protocol property requirement descriptor line.
    ///
    /// Matches lines like `"method descriptor for Module.Protocol.name.getter : Swift.String"`
    /// and `"method descriptor for static Module.Protocol.value.getter : Swift.Int"`.
    ///
    /// - Parameters:
    ///   - line: The demangled symbol line to parse.
    ///   - sortedSymbols: Sorted symbols for efficient setter detection via prefix search.
    ///   - moduleName: The module name prefix to match.
    /// - Returns: A tuple of property metadata, or `nil` if the line doesn't match.
    func parseProtocolPropertyDescriptor(
        from line: String,
        sortedSymbols: SortedSymbols,
        moduleName: String
    ) -> (owner: String, name: String, rawType: String, isStatic: Bool, hasSetter: Bool)? {
        let prefix = "method descriptor for "
        guard line.hasPrefix(prefix) else {
            return nil
        }

        var remainder = String(line.dropFirst(prefix.count))
        let isStatic: Bool
        if remainder.hasPrefix("static ") {
            isStatic = true
            remainder.removeFirst("static ".count)
        } else {
            isStatic = false
        }

        guard remainder.hasPrefix("\(moduleName).") else {
            return nil
        }

        let getterToken = ".getter : "
        guard let getterRange = remainder.range(of: getterToken) else {
            return nil
        }

        let path = String(remainder[..<getterRange.lowerBound])
        guard let member = parseOwnerMemberPath(path, moduleName: moduleName) else {
            return nil
        }

        let rawType = String(remainder[getterRange.upperBound...])
        let staticPrefix = isStatic ? "static " : ""
        let setterPrefix = "method descriptor for \(staticPrefix)\(moduleName).\(member.owner).\(member.name).setter : "
        let hasSetter = sortedSymbols.containsPrefix(setterPrefix)

        return (
            owner: member.owner,
            name: member.name,
            rawType: rawType,
            isStatic: isStatic,
            hasSetter: hasSetter
        )
    }

    /// Parses a method or initializer symbol line from a concrete type.
    ///
    /// Matches lines like `"Module.Type.methodName(...) -> ..."` (instance) or
    /// `"static Module.Type.methodName(...) -> ..."` (static). Filters out getters, setters,
    /// deinitializers, and operator overloads.
    ///
    /// - Parameters:
    ///   - line: The demangled symbol line to parse.
    ///   - isStatic: Whether to match `static` prefixed symbols.
    ///   - moduleName: The module name prefix to match.
    /// - Returns: A tuple of `(owner, rawSignature, isInitializer)`, or `nil` if the line
    ///   doesn't match.
    func parseCallable(
        from line: String,
        isStatic: Bool,
        moduleName: String,
        allowExtensionMembersOn allowedExtensionOwners: Set<String> = []
    ) -> (owner: String, rawSignature: String, isInitializer: Bool)? {
        let staticPrefix = isStatic ? "static " : ""
        guard line.hasPrefix(staticPrefix) else {
            return nil
        }

        var remainder = String(line.dropFirst(staticPrefix.count))
        let extensionPrefix = "(extension in \(moduleName)):"
        let isExtensionMember: Bool
        if remainder.hasPrefix(extensionPrefix) {
            isExtensionMember = true
            remainder.removeFirst(extensionPrefix.count)
        } else {
            isExtensionMember = false
        }

        let modulePrefix = "\(moduleName)."
        let isLocalOwner = remainder.hasPrefix(modulePrefix)
        if !isExtensionMember || isLocalOwner {
            guard remainder.hasPrefix(modulePrefix) else {
                return nil
            }
            remainder.removeFirst(modulePrefix.count)
        }
        guard
            !containsAccessorLikeSymbol(remainder),
            !remainder.contains(".__deallocating_deinit"),
            !remainder.contains(".deinit"),
            !containsOperatorNotation(remainder),
            let openingParenthesis = remainder.firstIndex(of: "("),
            let memberSeparator = memberDotIndex(in: remainder, before: openingParenthesis)
        else {
            return nil
        }

        let ownerPath = String(remainder[..<memberSeparator])
        let owner = removingGenericArguments(from: ownerPath)
        if isExtensionMember, !allowedExtensionOwners.contains(owner) {
            return nil
        }

        var rawSignature = String(remainder[remainder.index(after: memberSeparator)...])
        if rawSignature.hasPrefix("__allocating_init") {
            rawSignature = "init" + rawSignature.dropFirst("__allocating_init".count)
        }

        let extensionConstraintClause = isExtensionMember && isLocalOwner
            ? cleanedExtensionConstraintClause(from: ownerPath, moduleName: moduleName)
            : ""
        rawSignature += extensionConstraintClause

        return (
            owner,
            rawSignature,
            rawSignature.hasPrefix("init(") || rawSignature.hasPrefix("init<")
        )
    }

    /// Parses a dispatch thunk symbol line (used for open class methods).
    ///
    /// Matches lines like `"dispatch thunk of Module.Type.methodName(...) -> ..."`.
    /// The presence of a dispatch thunk indicates the owning class is `open`.
    ///
    /// - Parameters:
    ///   - line: The demangled symbol line to parse.
    ///   - moduleName: The module name prefix to match.
    /// - Returns: A tuple of `(owner, rawSignature, isInitializer)`, or `nil` if the line
    ///   doesn't match.
    func parseDispatchThunk(
        from line: String,
        moduleName: String
    ) -> (owner: String, rawSignature: String, isInitializer: Bool)? {
        let prefix = "dispatch thunk of \(moduleName)."
        guard line.hasPrefix(prefix) else {
            return nil
        }

        let remainder = String(line.dropFirst(prefix.count))
        guard
            !containsAccessorLikeSymbol(remainder),
            !remainder.contains(".__deallocating_deinit"),
            !remainder.contains(".deinit"),
            !remainder.contains("__allocating_init"),
            !containsOperatorNotation(remainder),
            let openingParenthesis = remainder.firstIndex(of: "("),
            let memberSeparator = memberDotIndex(in: remainder, before: openingParenthesis)
        else {
            return nil
        }

        let owner = String(remainder[..<memberSeparator])
        let rawSignature = String(remainder[remainder.index(after: memberSeparator)...])
        return (owner, rawSignature, rawSignature.hasPrefix("init(") || rawSignature.hasPrefix("init<"))
    }

    /// Splits a module-qualified `Type.member` path into owner and member components.
    ///
    /// For example, given `"Module.MyStruct.myProperty"` and module name `"Module"`,
    /// returns `(owner: "MyStruct", name: "myProperty")`.
    ///
    /// - Parameters:
    ///   - qualifiedPath: The fully-qualified path including module prefix.
    ///   - moduleName: The module name prefix to strip.
    /// - Returns: A tuple of `(owner, name)`, or `nil` if the path doesn't start with
    ///   the module prefix or has no dot separator.
    func parseOwnerMemberPath(
        _ qualifiedPath: String,
        moduleName: String
    ) -> (owner: String, name: String)? {
        let prefix = "\(moduleName)."
        guard qualifiedPath.hasPrefix(prefix) else {
            return nil
        }

        let stripped = String(qualifiedPath.dropFirst(prefix.count))
        guard let separator = memberDotIndex(in: stripped, before: stripped.endIndex) else {
            return nil
        }

        return (
            owner: String(stripped[..<separator]),
            name: String(stripped[stripped.index(after: separator)...])
        )
    }

    private func parseAnyOwnerMemberPath(
        _ qualifiedPath: String,
        moduleName: String
    ) -> (owner: String, name: String, symbolOwner: String, isLocalOwner: Bool)? {
        if let localMember = parseOwnerMemberPath(qualifiedPath, moduleName: moduleName) {
            return (
                owner: localMember.owner,
                name: localMember.name,
                symbolOwner: localMember.owner,
                isLocalOwner: true
            )
        }

        guard let separator = memberDotIndex(in: qualifiedPath, before: qualifiedPath.endIndex) else {
            return nil
        }

        let owner = String(qualifiedPath[..<separator])
        return (
            owner: owner,
            name: String(qualifiedPath[qualifiedPath.index(after: separator)...]),
            symbolOwner: owner,
            isLocalOwner: false
        )
    }

    private func sameModuleExtensionOwnerName(
        from line: String,
        moduleName: String
    ) -> String? {
        let extensionPrefix = "(extension in \(moduleName)):"
        guard let prefixRange = line.range(of: extensionPrefix) else {
            return nil
        }

        let remainder = String(line[prefixRange.upperBound...])
        let ownerPath: String

        if let subscriptRange = remainder.range(of: ".subscript(") {
            ownerPath = String(remainder[..<subscriptRange.lowerBound])
        } else if let accessorRange = remainder.range(of: ".getter : ")
            ?? remainder.range(of: ".setter : ")
            ?? remainder.range(of: ".modify : ")
            ?? remainder.range(of: ".read : ")
        {
            let path = String(remainder[..<accessorRange.lowerBound])
            guard let separator = memberDotIndex(in: path, before: path.endIndex) else {
                return nil
            }
            ownerPath = String(path[..<separator])
        } else if let typeSeparator = remainder.range(of: " : ") {
            let path = String(remainder[..<typeSeparator.lowerBound])
            guard let separator = memberDotIndex(in: path, before: path.endIndex) else {
                return nil
            }
            ownerPath = String(path[..<separator])
        } else if let openingParenthesis = remainder.firstIndex(of: "("),
                  let separator = memberDotIndex(in: remainder, before: openingParenthesis) {
            ownerPath = String(remainder[..<separator])
        } else {
            return nil
        }

        let localPrefix = "\(moduleName)."
        let normalizedOwner = ownerPath.hasPrefix(localPrefix)
            ? String(ownerPath.dropFirst(localPrefix.count))
            : ownerPath

        return removingGenericArguments(from: normalizedOwner)
    }

    private func isSameModuleExtensionMember(
        _ line: String,
        memberPrefix: String,
        moduleName: String
    ) -> Bool {
        guard line.hasPrefix(memberPrefix) else {
            return false
        }

        var remainder = String(line.dropFirst(memberPrefix.count))
        if remainder.hasPrefix("static ") {
            remainder.removeFirst("static ".count)
        }

        return remainder.hasPrefix("(extension in \(moduleName)):\(moduleName).")
    }

    private func extensionConstraintClause(
        fromMemberDescriptor line: String,
        memberDescriptorPrefix: String,
        moduleName: String
    ) -> String {
        guard line.hasPrefix(memberDescriptorPrefix) else {
            return ""
        }

        var remainder = String(line.dropFirst(memberDescriptorPrefix.count))
        if remainder.hasPrefix("static ") {
            remainder.removeFirst("static ".count)
        }

        let extensionPrefix = "(extension in \(moduleName)):"
        guard remainder.hasPrefix(extensionPrefix) else {
            return ""
        }
        remainder.removeFirst(extensionPrefix.count)

        guard let memberSeparator = memberDotIndex(in: remainder, before: remainder.endIndex) else {
            return ""
        }

        let ownerPathWithModule = String(remainder[..<memberSeparator])
        let modulePrefix = "\(moduleName)."
        guard ownerPathWithModule.hasPrefix(modulePrefix) else {
            return ""
        }

        let ownerPath = String(ownerPathWithModule.dropFirst(modulePrefix.count))
        return cleanedExtensionConstraintClause(from: ownerPath, moduleName: moduleName)
    }

    private func containsAccessorLikeSymbol(_ remainder: String) -> Bool {
        remainder.contains(".getter :")
            || remainder.contains(".setter :")
            || remainder.contains(".modify :")
            || remainder.contains(".init :")
            || remainder.contains(".unsafeAddressor :")
            || remainder.contains(".unsafeMutableAddressor :")
    }

    private func containsOperatorNotation(_ string: String) -> Bool {
        string.contains(" infix(")
            || string.contains(" infix<")
            || string.contains("infix ")
            || string.contains(" prefix(")
            || string.contains(" prefix<")
            || string.contains("prefix ")
            || string.contains(" postfix(")
            || string.contains(" postfix<")
            || string.contains("postfix ")
    }

    /// Parses a generic clause from a method head like `"respond<A where A: Mod.Proto>"`.
    ///
    /// Returns the bare method name, the generic parameter clause (e.g. `"<A>"`),
    /// and the where clause (e.g. `" where A : Proto"`). If there is no generic clause,
    /// returns the original name with empty param and where clauses.
    ///
    /// For same-type constraints (e.g. `<A where A == [A1]>`), detects that the declared
    /// param `A` is a parent type param and replaces it with undeclared params from the
    /// constraint RHS (e.g. `A1`), producing `<A1>` as the method's generic param clause.
    private func parseGenericClause(
        _ head: String,
        moduleName: String
    ) -> (name: String, paramClause: String, whereClause: String, packParameters: Set<String>) {
        guard let angleBracketStart = head.firstIndex(of: "<") else {
            return (name: head, paramClause: "", whereClause: "", packParameters: Set<String>())
        }
        guard let angleBracketEnd = matchingClosingDelimiter(
            in: head,
            from: angleBracketStart,
            open: "<",
            close: ">"
        ) else {
            return (name: head, paramClause: "", whereClause: "", packParameters: Set<String>())
        }

        let name = String(head[..<angleBracketStart])
        let genericContent = String(head[head.index(after: angleBracketStart)..<angleBracketEnd])

        let whereRange = genericContent.range(of: " where ")
        if let whereRange {
            var declaredParams = String(genericContent[..<whereRange.lowerBound])
                .trimmingCharacters(in: .whitespaces)
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            let rawConstraints = String(genericContent[whereRange.upperBound...])
                .trimmingCharacters(in: .whitespaces)
            let cleanedConstraints = cleanedTypeName(rawConstraints, moduleName: moduleName)
                .replacing(/(\w):\s*/) { match in "\(match.1) : " }

            declaredParams = fixSameTypeConstraintParams(
                declaredParams: declaredParams,
                whereClause: cleanedConstraints
            )
            let packParameters = packParameterNames(from: declaredParams)
            let renderedWhereClause = applyingPackExpansionSyntax(
                toWhereClause: cleanedConstraints,
                packParameters: packParameters
            )
            let renderedParamClause = declaredParams.isEmpty
                ? ""
                : "<\(declaredParams.joined(separator: ", "))>"

            return (
                name: name,
                paramClause: renderedParamClause,
                whereClause: " where \(renderedWhereClause)",
                packParameters: packParameters
            )
        }

        let params = genericContent.trimmingCharacters(in: .whitespaces)
        let renderedParamClause = params.isEmpty ? "" : "<\(params)>"
        return (
            name: name,
            paramClause: renderedParamClause,
            whereClause: "",
            packParameters: packParameterNames(from: params.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespaces)
            })
        )
    }

    /// Fixes generic parameter declarations for same-type constraints.
    ///
    /// When a declared param appears on the LHS of a `==` constraint (e.g. `A == [A1]`),
    /// it's a parent type param being constrained, not a new method param. The undeclared
    /// identifiers on the RHS (e.g. `A1`) are the actual new method params.
    private func fixSameTypeConstraintParams(
        declaredParams: [String],
        whereClause: String
    ) -> [String] {
        let sameTypePattern = #/^\s*(\w+)\s*==\s*(.+?)\s*$/#
        let identifierPattern = #/\b([A-Z][A-Za-z]*[0-9]+)\b/#
        let constraints = whereClause.components(separatedBy: ", ")
        let declaredParamsSet = Set(declaredParams)
        var paramsToRemove: Set<String> = []
        var paramsToAdd: [String] = []
        var paramsToAddSet: Set<String> = []

        for constraint in constraints {
            guard let match = constraint.wholeMatch(of: sameTypePattern) else {
                continue
            }

            let lhs = String(match.1)
            let rhs = String(match.2)

            guard declaredParamsSet.contains(lhs) else {
                continue
            }

            // Find undeclared generic-param-like identifiers in the RHS
            let undeclaredParams = rhs.matches(of: identifierPattern)
                .map { String($0.1) }
                .filter { !declaredParamsSet.contains($0) }
                .filter { paramsToAddSet.insert($0).inserted }

            if !undeclaredParams.isEmpty {
                paramsToRemove.insert(lhs)
                paramsToAdd.append(contentsOf: undeclaredParams)
            }
        }

        guard !paramsToRemove.isEmpty else {
            return declaredParams
        }

        var result = declaredParams.filter { !paramsToRemove.contains($0) }
        result.append(contentsOf: paramsToAdd)
        return result
    }

    /// Finds the last dot that separates the owner path from the member name,
    /// ignoring dots inside generic angle brackets (e.g. `<A where A: Module.Protocol>`).
    ///
    /// For `"Session.respond<A where A: Mod.Generable>("`, this returns the index of the
    /// dot between `Session` and `respond`, not the dot inside the generic clause.
    ///
    /// - Parameters:
    ///   - string: The remainder string to search.
    ///   - before: The upper bound index (typically the first `(`).
    /// - Returns: The index of the owner/member separator dot, or `nil` if none exists.
    private func memberDotIndex(in string: String, before upperBound: String.Index) -> String.Index? {
        var lastDot: String.Index?
        var depth = 0
        var previousCharacter: Character?
        var index = string.startIndex

        while index < upperBound {
            let character = string[index]
            switch character {
            case "<":
                if previousCharacter != "-" {
                    depth += 1
                }
            case ">":
                if previousCharacter != "-" && depth > 0 {
                    depth -= 1
                }
            case "." where depth == 0:
                lastDot = index
            default:
                break
            }

            previousCharacter = character
            index = string.index(after: index)
        }

        return lastDot
    }

    private func packParameterNames(from declaredParams: [String]) -> Set<String> {
        Set(
            declaredParams.compactMap { parameter in
                guard parameter.hasPrefix("each ") else {
                    return nil
                }
                return String(parameter.dropFirst("each ".count)).trimmingCharacters(in: .whitespaces)
            }
        )
    }

    private func applyingPackExpansionSyntax(
        to string: String,
        packParameters: Set<String>
    ) -> String {
        guard !packParameters.isEmpty else {
            return string
        }

        return packParameters.sorted().reduce(string) { result, parameter in
            replacingPackExpansionParameter(parameter, in: result)
        }
    }

    private func applyingPackExpansionSyntax(
        toWhereClause whereClause: String,
        packParameters: Set<String>
    ) -> String {
        guard !packParameters.isEmpty else {
            return whereClause
        }

        return packParameters.sorted().reduce(whereClause) { result, parameter in
            replacingPackExpansionConstraintParameter(parameter, in: result)
        }
    }

    private func replacingPackExpansionParameter(
        _ parameter: String,
        in string: String
    ) -> String {
        let token = "repeat \(parameter)"
        return replacingLiteralOccurrences(of: token, in: string) { range in
            guard hasWordBoundary(after: range.upperBound, in: string) else {
                return String(string[range])
            }

            return "repeat each \(parameter)"
        }
    }

    private func replacingPackExpansionConstraintParameter(
        _ parameter: String,
        in string: String
    ) -> String {
        guard !parameter.isEmpty else {
            return string
        }

        var result = ""
        var searchStart = string.startIndex

        while let range = string.range(
            of: parameter,
            range: searchStart..<string.endIndex
        ) {
            result += string[searchStart..<range.lowerBound]

            guard hasWordBoundary(before: range.lowerBound, in: string),
                  let replacementEnd = packConstraintReplacementEnd(
                      in: string,
                      startingAt: range.upperBound
                  ) else {
                result += string[range]
                searchStart = range.upperBound
                continue
            }

            result += "repeat each \(parameter) :"
            searchStart = replacementEnd
        }

        result += string[searchStart...]
        return result
    }

    private func removingGenericArguments(from string: String) -> String {
        var result = ""
        var depth = 0
        var previousCharacter: Character?

        for character in string {
            switch character {
            case "<":
                if previousCharacter != "-" {
                    depth += 1
                }
            case ">":
                if previousCharacter != "-" && depth > 0 {
                    depth -= 1
                }
            default:
                if depth == 0 {
                    result.append(character)
                }
            }

            previousCharacter = character
        }

        return result.trimmingCharacters(in: .whitespaces)
    }

    private func cleanedExtensionConstraintClause(
        from ownerPath: String,
        moduleName: String
    ) -> String {
        guard
            let angleBracketStart = ownerPath.firstIndex(of: "<"),
            let angleBracketEnd = matchingClosingDelimiter(
                in: ownerPath,
                from: angleBracketStart,
                open: "<",
                close: ">"
            )
        else {
            return ""
        }

        let genericClause = ownerPath[ownerPath.index(after: angleBracketStart)..<angleBracketEnd]
        guard let whereRange = genericClause.range(of: " where ") else {
            return ""
        }

        let rawConstraints = String(genericClause[whereRange.upperBound...])
            .trimmingCharacters(in: .whitespaces)
        let cleanedConstraints = cleanedTypeName(rawConstraints, moduleName: moduleName)
            .replacing(/(\w):\s*/) { match in "\(match.1) : " }

        return cleanedConstraints.isEmpty ? "" : " where \(cleanedConstraints)"
    }

    private func splitTrailingWhereClause(from returnSection: String) -> (returnType: String, whereClause: String) {
        guard let whereRange = returnSection.range(of: " where ", options: .backwards) else {
            return (returnSection, "")
        }

        let trailingClause = String(returnSection[whereRange.lowerBound...]).trimmingCharacters(in: .whitespaces)
        if let inlineSplit = splitInlinedWhereClause(from: returnSection, whereRange: whereRange) {
            return inlineSplit
        }

        guard isFunctionWhereClause(trailingClause) else {
            return (returnSection, "")
        }

        return (
            String(returnSection[..<whereRange.lowerBound]).trimmingCharacters(in: .whitespaces),
            trailingClause
        )
    }

    private func splitInlinedWhereClause(
        from returnSection: String,
        whereRange: Range<String.Index>
    ) -> (returnType: String, whereClause: String)? {
        let constraintStart = whereRange.upperBound
        var angleDepth = 0
        var parenthesisDepth = 0
        var bracketDepth = 0
        var endOfConstraints = returnSection.endIndex
        var index = constraintStart

        while index < returnSection.endIndex {
            let character = returnSection[index]
            switch character {
            case "<":
                angleDepth += 1
            case ">":
                if angleDepth > 0 {
                    angleDepth -= 1
                } else if angleDepth == 0 && parenthesisDepth == 0 && bracketDepth == 0 {
                    guard returnSection.index(after: index) < returnSection.endIndex,
                          returnSection[returnSection.index(after: index)] == "." else {
                        return nil
                    }
                    endOfConstraints = index
                    break
                }
            case "(":
                parenthesisDepth += 1
            case ")":
                parenthesisDepth = max(0, parenthesisDepth - 1)
            case "[":
                bracketDepth += 1
            case "]":
                bracketDepth = max(0, bracketDepth - 1)
            default:
                break
            }
            index = returnSection.index(after: index)
        }

        guard endOfConstraints != returnSection.endIndex else {
            return nil
        }

        let whereClause = String(returnSection[whereRange.lowerBound...endOfConstraints])
            .trimmingCharacters(in: .whitespaces)
            .dropFirst("where ".count)
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: ">"))

        let leadingType = String(returnSection[..<whereRange.lowerBound])
        let suffix = String(returnSection[returnSection.index(after: endOfConstraints)...])
        let cleanedLeadingType = leadingType.hasSuffix("<")
            ? String(leadingType.dropLast())
            : leadingType
        let cleanedWhere = "where \(whereClause)"
        let renderedWhere = String(cleanedWhere.trimmingCharacters(in: .whitespaces))

        guard !genericRequirementTokens(in: renderedWhere).isEmpty else {
            return nil
        }

        return (
            "\(cleanedLeadingType)\(suffix)",
            renderedWhere
        )
    }

    private func isFunctionWhereClause(_ clause: String) -> Bool {
        guard clause.hasPrefix("where ") else { return false }
        var parser = Parser("func x() \(clause) {}")
        let declaration = DeclSyntax.parse(from: &parser)
        guard let function = declaration.as(FunctionDeclSyntax.self) else {
            return false
        }
        return function.genericWhereClause != nil
    }

    private func splitImplicitVoidSignature(from trailingSignature: String) -> (effects: String, whereClause: String) {
        let trimmedSignature = trailingSignature.trimmingCharacters(in: .whitespaces)
        guard !trimmedSignature.isEmpty else {
            return ("", "")
        }

        if trimmedSignature.hasPrefix("where ") {
            return ("", trimmedSignature)
        }

        guard let whereRange = trimmedSignature.range(of: " where ", options: .backwards) else {
            return (trimmedSignature, "")
        }

        return (
            String(trimmedSignature[..<whereRange.lowerBound]).trimmingCharacters(in: .whitespaces),
            String(trimmedSignature[whereRange.lowerBound...]).trimmingCharacters(in: .whitespaces)
        )
    }

    private func topLevelArrowRange(in string: String) -> Range<String.Index>? {
        var angleDepth = 0
        var braceDepth = 0
        var bracketDepth = 0
        var parenthesisDepth = 0
        var previousCharacter: Character?
        var index = string.startIndex

        while index < string.endIndex {
            let character = string[index]
            switch character {
            case "(":
                parenthesisDepth += 1
            case ")":
                if parenthesisDepth > 0 {
                    parenthesisDepth -= 1
                }
            case "[":
                bracketDepth += 1
            case "]":
                if bracketDepth > 0 {
                    bracketDepth -= 1
                }
            case "{":
                braceDepth += 1
            case "}":
                if braceDepth > 0 {
                    braceDepth -= 1
                }
            case "<":
                if previousCharacter != "-" {
                    angleDepth += 1
                }
            case ">":
                if previousCharacter != "-" && angleDepth > 0 {
                    angleDepth -= 1
                }
            case "-":
                let nextIndex = string.index(after: index)
                if angleDepth == 0,
                   braceDepth == 0,
                   bracketDepth == 0,
                   parenthesisDepth == 0,
                   nextIndex < string.endIndex,
                   string[nextIndex] == ">" {
                    return index..<string.index(after: nextIndex)
                }
            default:
                break
            }

            previousCharacter = character
            index = string.index(after: index)
        }

        return nil
    }

    private func normalizedExistentialComposition(in string: String) -> String {
        let parts = splitTopLevelComposition(in: string)
        guard parts.count > 1 else {
            return string
        }

        let trimmedParts = parts.map { $0.trimmingCharacters(in: .whitespaces) }
        guard trimmedParts.contains(where: { $0.hasPrefix("any ") }) else {
            return string
        }

        let normalizedParts = trimmedParts.map { part in
            guard part.hasPrefix("any ") else {
                return part
            }
            return String(part.dropFirst("any ".count))
        }

        return "any " + normalizedParts.joined(separator: " & ")
    }

    private func splitTopLevelComposition(in string: String) -> [String] {
        var parts: [String] = []
        var angleDepth = 0
        var braceDepth = 0
        var bracketDepth = 0
        var parenthesisDepth = 0
        var previousCharacter: Character?
        var componentStart = string.startIndex
        var index = string.startIndex

        while index < string.endIndex {
            let character = string[index]
            switch character {
            case "(":
                parenthesisDepth += 1
            case ")":
                if parenthesisDepth > 0 {
                    parenthesisDepth -= 1
                }
            case "[":
                bracketDepth += 1
            case "]":
                if bracketDepth > 0 {
                    bracketDepth -= 1
                }
            case "{":
                braceDepth += 1
            case "}":
                if braceDepth > 0 {
                    braceDepth -= 1
                }
            case "<":
                if previousCharacter != "-" {
                    angleDepth += 1
                }
            case ">":
                if previousCharacter != "-" && angleDepth > 0 {
                    angleDepth -= 1
                }
            case "&":
                if angleDepth == 0,
                   braceDepth == 0,
                   bracketDepth == 0,
                   parenthesisDepth == 0 {
                    parts.append(String(string[componentStart..<index]))
                    componentStart = string.index(after: index)
                }
            default:
                break
            }

            previousCharacter = character
            index = string.index(after: index)
        }

        if componentStart < string.endIndex {
            parts.append(String(string[componentStart...]))
        }

        return parts
    }

    private func combinedWhereClause(_ lhs: String, _ rhs: String) -> String {
        let lhsConstraints = lhs.replacing(/^\s*where\s+/, with: "")
            .trimmingCharacters(in: .whitespaces)
        let rhsConstraints = rhs.replacing(/^\s*where\s+/, with: "")
            .trimmingCharacters(in: .whitespaces)

        switch (lhsConstraints.isEmpty, rhsConstraints.isEmpty) {
        case (true, true):
            return ""
        case (false, true):
            return " where \(lhsConstraints)"
        case (true, false):
            return " where \(rhsConstraints)"
        case (false, false):
            return " where \(lhsConstraints), \(rhsConstraints)"
        }
    }

    private func containsUnresolvedAssociatedTypeReference(_ string: String) -> Bool {
        string.contains(/\b[A-Z][0-9]*\.[A-Z][A-Za-z0-9_]*\b/)
    }

    private func allowedModulePrefixes(
        knownTypeComponents: Set<String>,
        moduleName: String
    ) -> Set<String>? {
        guard let renderableExternalModules else {
            return nil
        }
        return knownTypeComponents
            .union(renderableExternalModules)
            .union(["Swift", moduleName])
    }

    private func containsUnrenderableExternalModuleReference(
        _ string: String,
        allowedPrefixes: Set<String>?
    ) -> Bool {
        guard let allowedPrefixes else {
            return false
        }

        // Apply type replacements so that known __C.X → Module.X mappings
        // resolve to allowed module prefixes instead of triggering the filter
        var resolved = string
        for (from, to) in Self.typeReplacements {
            if resolved.contains(from) {
                resolved = resolved.replacingOccurrences(of: from, with: to)
            }
        }

        return moduleLikePrefixes(in: resolved).contains { prefix in
            !allowedPrefixes.contains(prefix)
        }
    }

    private func importedModuleCandidates(
        in string: String,
        knownTypeComponents: Set<String>,
        moduleName: String
    ) -> [String] {
        moduleLikePrefixes(in: string)
            .filter { prefix in
                prefix != "Swift"
                    && prefix != "__C"
                    && prefix != moduleName
                    && !knownTypeComponents.contains(prefix)
            }
            .filter { prefix in
                renderableExternalModules?.contains(prefix) ?? true
            }
            .sorted()
    }

    private func moduleLikePrefixes(in string: String) -> Set<String> {
        Set(
            string.matches(of: #/\b([A-Z_][A-Za-z0-9_]{1,}|os)\./#).map {
                String($0.1)
            }
            .filter(isModuleImportCandidate)
        )
    }

    private func isModuleImportCandidate(_ prefix: String) -> Bool {
        guard !Self.genericExcludedTokens.contains(prefix) else {
            return false
        }

        return prefix.wholeMatch(of: #/^[A-Z][0-9]*$/#) == nil
    }

    private func replacingLiteralOccurrences(
        of literal: String,
        in string: String,
        replacement: (Range<String.Index>) -> String
    ) -> String {
        guard !literal.isEmpty else {
            return string
        }

        var result = ""
        var searchStart = string.startIndex

        while let range = string.range(
            of: literal,
            range: searchStart..<string.endIndex
        ) {
            result += string[searchStart..<range.lowerBound]
            result += replacement(range)
            searchStart = range.upperBound
        }

        result += string[searchStart...]
        return result
    }

    private func packConstraintReplacementEnd(
        in string: String,
        startingAt index: String.Index
    ) -> String.Index? {
        var cursor = index
        while cursor < string.endIndex, string[cursor].isWhitespace {
            cursor = string.index(after: cursor)
        }

        guard cursor < string.endIndex, string[cursor] == ":" else {
            return nil
        }

        return string.index(after: cursor)
    }

    private func hasWordBoundary(
        before index: String.Index,
        in string: String
    ) -> Bool {
        guard index > string.startIndex else {
            return true
        }

        return !isWordCharacter(string[string.index(before: index)])
    }

    private func hasWordBoundary(
        after index: String.Index,
        in string: String
    ) -> Bool {
        guard index < string.endIndex else {
            return true
        }

        return !isWordCharacter(string[index])
    }

    private func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    /// Extracts a type name from a symbol line by stripping a known prefix.
    ///
    /// - Parameters:
    ///   - line: The demangled symbol line.
    ///   - prefix: The prefix to strip (e.g. `"nominal type descriptor for Module."`).
    /// - Returns: The type name after the prefix, or `nil` if the line doesn't match.
    private func extractedTypeName(from line: String, prefix: String, moduleName: String) -> String? {
        if line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count))
        }

        let extensionPrefix = prefix.replacing(
            "\(moduleName).",
            with: "(extension in \(moduleName)):\(moduleName)."
        )
        guard line.hasPrefix(extensionPrefix) else {
            return nil
        }
        return String(line.dropFirst(extensionPrefix.count))
    }

    private func inferredModuleName(from line: String) -> String? {
        for prefix in Self.moduleInferencePrefixes where line.hasPrefix(prefix) {
            let suffix = line.dropFirst(prefix.count)
            guard let separator = suffix.firstIndex(of: ".") else {
                return nil
            }
            return String(suffix[..<separator])
        }

        return nil
    }

    /// Returns the parent type name if `fullName` is a nested type within a known declaration.
    ///
    /// For example, if `fullName` is `"Outer.Inner"` and `"Outer"` exists in `declarations`,
    /// returns `"Outer"`.
    ///
    /// - Parameters:
    ///   - fullName: The fully-qualified type name to check.
    ///   - declarations: All known declarations.
    /// - Returns: The parent type name, or `nil` if this is a top-level type.
    private func parentName(of fullName: String, in declarations: [String: Declaration]) -> String? {
        guard let separator = fullName.lastIndex(of: ".") else {
            return nil
        }

        let candidate = String(fullName[..<separator])
        return declarations[candidate] == nil ? nil : candidate
    }

    /// Pre-computes generic arities for all declarations in a single pass over all fragments.
    private func precomputedGenericArities(
        declarations: [String: Declaration],
        moduleName: String
    ) -> [String: Int] {
        let declarationNames = Set(declarations.keys)
        guard !declarationNames.isEmpty else { return [:] }
        let knownTypeComponents = localKnownTypeComponents(from: declarations)

        var allFragments: [String] = []
        for declaration in declarations.values {
            allFragments.append(contentsOf: declaration.conformances)
            allFragments.append(contentsOf: declaration.rawTypeFragments)
        }

        var arityMap: [String: Int] = [:]

        for fragment in allFragments {
            let references = referencedTypeArities(in: fragment, moduleName: moduleName)
            for reference in references {
                guard declarationNames.contains(reference.name) else {
                    continue
                }
                arityMap[reference.name] = max(arityMap[reference.name, default: 0], reference.arity)
            }
        }

        for declaration in declarations.values where declaration.resolvedKind != .protocol {
            guard arityMap[declaration.fullName, default: 0] == 0 else {
                continue
            }
            guard parentName(of: declaration.fullName, in: declarations) == nil else {
                continue
            }

            let inferredArity = inferredGenericArityFromMemberPlaceholders(
                for: declaration,
                knownTypeComponents: knownTypeComponents,
                moduleName: moduleName
            )
            guard inferredArity > 0 else {
                continue
            }
            arityMap[declaration.fullName] = inferredArity
        }

        return arityMap
    }

    private func inferredGenericArityFromMemberPlaceholders(
        for declaration: Declaration,
        knownTypeComponents: Set<String>,
        moduleName: String
    ) -> Int {
        var excludedTokens = Self.genericExcludedTokens
        if !moduleName.isEmpty {
            excludedTokens.insert(moduleName)
        }

        let propertyFragments = declaration.properties.map(\.rawType)
        let extensionPropertyFragments = declaration.extensionProperties.map(\.rawType)
        let subscriptFragments = declaration.subscripts.flatMap { [$0.rawArguments, $0.rawReturnType] }
        let extensionSubscriptFragments = declaration.extensionSubscripts.flatMap { [$0.rawArguments, $0.rawReturnType] }
        let enumPayloadFragments = declaration.enumCases.compactMap(\.rawPayload)
        let enumOwnerFragments = declaration.enumCases.compactMap(\.rawOwnerType)
        let fragments =
            propertyFragments
            + extensionPropertyFragments
            + subscriptFragments
            + extensionSubscriptFragments
            + enumPayloadFragments
            + enumOwnerFragments

        var genericParameters: Set<String> = []
        for fragment in fragments {
            for token in genericParameterTokens(in: fragment, moduleName: moduleName) {
                guard isLikelyDeclarationTypeParameter(
                    token,
                    knownTypeComponents: knownTypeComponents,
                    excludedTokens: excludedTokens
                ) else {
                    continue
                }
                genericParameters.insert(token)
            }
        }

        return genericParameters.count
    }

    /// Returns the simple (unqualified) name from a dot-separated fully-qualified name.
    ///
    /// For example, `"Outer.Inner"` returns `"Inner"`.
    private func simpleName(of fullName: String) -> String {
        guard let separator = fullName.lastIndex(of: ".") else {
            return fullName
        }
        return String(fullName[fullName.index(after: separator)...])
    }

    /// Finds the index of the matching closing delimiter for a given opening delimiter.
    ///
    /// Handles nested pairs of the same delimiter type. For example, given `<A<B>, C>`,
    /// starting from the first `<` returns the index of the final `>`.
    ///
    /// - Parameters:
    ///   - string: The string to search.
    ///   - openingIndex: The index of the opening delimiter.
    ///   - open: The opening delimiter character.
    ///   - close: The closing delimiter character.
    /// - Returns: The index of the matching closing delimiter, or `nil` if unbalanced.
    private func matchingClosingDelimiter(
        in string: String,
        from openingIndex: String.Index,
        open: Character,
        close: Character
    ) -> String.Index? {
        var depth = 0

        for index in string.indices[openingIndex...] {
            let character = string[index]
            switch character {
            case open:
                depth += 1
            case close:
                depth -= 1
                if depth == 0 {
                    return index
                }
            default:
                break
            }
        }

        return nil
    }

    /// Finds the index of the closing parenthesis matching the given opening parenthesis.
    ///
    /// Convenience wrapper around ``matchingClosingDelimiter(in:from:open:close:)``
    /// for parentheses.
    private func matchingClosingParenthesis(
        in string: String,
        from openingIndex: String.Index
    ) -> String.Index? {
        matchingClosingDelimiter(
            in: string,
            from: openingIndex,
            open: "(",
            close: ")"
        )
    }

    /// Splits a string at top-level commas, respecting nested delimiters.
    ///
    /// Commas inside parentheses `()`, angle brackets `<>`, and square brackets `[]` are
    /// not treated as separators. Correctly handles the arrow operator `->` so that `<` and
    /// `>` within arrows are not mistaken for generic delimiters.
    ///
    /// - Parameter string: The string to split.
    /// - Returns: An array of trimmed components.
    /// - Throws: ``SwiftInterfaceGeneratorError/unexpectedOutput(_:)`` if delimiters
    ///   are unbalanced.
    func splitTopLevel(_ string: String) throws -> [String] {
        try parsedTupleType(fromArgumentList: string)?.elements.map { element in
            var result = element.firstName.map { "\($0.text): " } ?? ""
            result += element.type.trimmedDescription
            return result
        } ?? {
            throw SwiftInterfaceGeneratorError.unexpectedOutput("Unbalanced argument list: \(string)")
        }()
    }

    /// Derives the module name from a framework binary URL.
    ///
    /// Uses the file name without its extension (e.g. `"MyFramework"` from
    /// `"MyFramework.framework/MyFramework"` or `"MyFramework.dylib"`).
    ///
    /// - Parameter frameworkBinaryURL: The URL of the framework binary.
    /// - Returns: The normalized module name.
    func normalizedModuleName(for frameworkBinaryURL: URL) -> String {
        let candidate = frameworkBinaryURL.deletingPathExtension().lastPathComponent
        if !candidate.isEmpty {
            return candidate
        }
        return frameworkBinaryURL.lastPathComponent
    }

    private static let moduleInferencePrefixes: [String] = [
        "protocol descriptor for ",
        "nominal type descriptor for ",
        "metaclass for ",
        "class metadata base offset for ",
    ]

    private static let swiftKeywords: Set<String> = [
        "Any",
        "Self",
        "as",
        "associatedtype",
        "break",
        "case",
        "catch",
        "class",
        "continue",
        "deinit",
        "default",
        "defer",
        "do",
        "else",
        "enum",
        "extension",
        "fallthrough",
        "false",
        "for",
        "func",
        "guard",
        "if",
        "import",
        "in",
        "init",
        "inout",
        "internal",
        "is",
        "let",
        "nil",
        "operator",
        "Protocol",
        "private",
        "protocol",
        "public",
        "repeat",
        "rethrows",
        "return",
        "self",
        "static",
        "struct",
        "subscript",
        "super",
        "switch",
        "throw",
        "throws",
        "true",
        "try",
        "typealias",
        "var",
        "while",
        "where",
    ]

    /// Wraps a Swift keyword in backticks to make it a valid identifier.
    ///
    /// Non-keyword identifiers are returned unchanged.
    ///
    /// - Parameter identifier: The identifier to potentially escape.
    /// - Returns: The identifier, backtick-escaped if it's a Swift keyword.
    func escapedIdentifier(_ identifier: String) -> String {
        if Self.swiftKeywords.contains(identifier) {
            return "`\(identifier)`"
        }
        return identifier
    }

    /// Generates the `.swiftinterface` filename for a given target triple.
    ///
    /// Strips version numbers from the platform component of the triple. For example,
    /// `"arm64-apple-ios18.2-simulator"` becomes `"arm64-apple-ios-simulator.swiftinterface"`.
    ///
    /// - Parameter targetTriple: The target triple (e.g. `"arm64-apple-macosx15.0"`).
    /// - Returns: The normalized filename (e.g. `"arm64-apple-macosx.swiftinterface"`).
    func swiftinterfaceFilename(for targetTriple: String) -> String {
        let parts = targetTriple.split(separator: "-")
        guard parts.count >= 3 else {
            return "\(targetTriple).swiftinterface"
        }

        let architecture = String(parts[0])
        let vendor = String(parts[1])
        let platform = String(parts[2].filter { !$0.isNumber && $0 != "." })
        let suffix = parts.dropFirst(3).joined(separator: "-")
        let triple = suffix.isEmpty
            ? "\(architecture)-\(vendor)-\(platform)"
            : "\(architecture)-\(vendor)-\(platform)-\(suffix)"
        return "\(triple).swiftinterface"
    }
}

// MARK: - Optimized string replacements for patterns requiring lookbehinds

private extension String {
    /// Replaces `A.X` (where X is [A-Z][0-9]?) with just `X`, only when not preceded by a word character.
    /// Equivalent to: s/(?<!\w)A\.([A-Z][0-9]?)(?!\w)/$1/g
    func replacingADotPattern() -> String {
        guard self.contains("A.") else { return self }
        var result = ""
        result.reserveCapacity(count)
        var i = startIndex
        while i < endIndex {
            let c = self[i]
            if c == "A" {
                let nextI = index(after: i)
                if nextI < endIndex && self[nextI] == "." {
                    // Check lookbehind: char before i must NOT be a word char
                    let precededByWord = i > startIndex && {
                        let prev = self[index(before: i)]
                        return prev.isLetter || prev.isNumber || prev == "_"
                    }()
                    if !precededByWord {
                        let dotNext = index(after: nextI)
                        // Check lookahead: next char after dot must be [A-Z]
                        if dotNext < endIndex && self[dotNext].isUppercase {
                            let captureStart = dotNext
                            var captureEnd = index(after: captureStart)
                            // Optional digit after the uppercase letter
                            if captureEnd < endIndex && self[captureEnd].isNumber {
                                captureEnd = index(after: captureEnd)
                            }
                            // Check that char after capture is NOT a word char
                            let followedByWord = captureEnd < endIndex && {
                                let next = self[captureEnd]
                                return next.isLetter || next.isNumber || next == "_"
                            }()
                            if !followedByWord {
                                result += self[captureStart..<captureEnd]
                                i = captureEnd
                                continue
                            }
                        }
                    }
                }
            }
            result.append(c)
            i = index(after: i)
        }
        return result
    }

    /// Replaces bare `Protocol` with `` `Protocol` ``, only when not preceded/followed by word chars or backticks.
    /// Equivalent to: s/(?<![\w`])Protocol(?![\w`])/`Protocol`/g
    func replacingProtocolKeyword() -> String {
        let needle = "Protocol"
        guard self.contains(needle) else { return self }
        var result = ""
        result.reserveCapacity(count + 4)
        var searchStart = startIndex
        while let range = self.range(of: needle, range: searchStart..<endIndex) {
            // Check lookbehind
            let precededByWordOrBacktick = range.lowerBound > startIndex && {
                let prev = self[index(before: range.lowerBound)]
                return prev.isLetter || prev.isNumber || prev == "_" || prev == "`"
            }()
            // Check lookahead
            let followedByWordOrBacktick = range.upperBound < endIndex && {
                let next = self[range.upperBound]
                return next.isLetter || next.isNumber || next == "_" || next == "`"
            }()
            result += self[searchStart..<range.lowerBound]
            if precededByWordOrBacktick || followedByWordOrBacktick {
                result += needle
            } else {
                result += "`Protocol`"
            }
            searchStart = range.upperBound
        }
        result += self[searchStart...]
        return result
    }

    /// Replaces `A.` with `Self.` only when not preceded by a word character.
    /// Equivalent to: s/(?<!\w)A\./Self./g
    func replacingSelfTypePattern() -> String {
        guard self.contains("A") else { return self }
        var result = ""
        result.reserveCapacity(count + 16)
        var i = startIndex
        while i < endIndex {
            let c = self[i]
            if c == "A" {
                let precededByWord = i > startIndex && {
                    let prev = self[index(before: i)]
                    return prev.isLetter || prev.isNumber || prev == "_"
                }()
                if !precededByWord {
                    let nextI = index(after: i)
                    let nextChar: Character? = nextI < endIndex ? self[nextI] : nil
                    if nextChar == "." {
                        // A.Something → Self.Something
                        result += "Self."
                        i = index(after: nextI)
                        continue
                    } else if nextChar == nil || nextChar == ">" || nextChar == "," || nextChar == ")" || nextChar == "?" || nextChar == " " {
                        // Bare A at end, or A>, A,, A), A?, A<space> → Self
                        result += "Self"
                        i = nextI
                        continue
                    }
                }
            }
            result.append(c)
            i = index(after: i)
        }
        return result
    }
}
