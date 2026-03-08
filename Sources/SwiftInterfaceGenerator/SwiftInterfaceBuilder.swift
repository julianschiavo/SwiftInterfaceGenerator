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
            let order: Int
        }

        let fullName: String
        let order: Int
        var isProtocol = false
        var isClass = false
        var isOpen = false
        var conformances: [String] = []
        var associatedTypes: [AssociatedType] = []
        var properties: [Property] = []
        var subscripts: [Subscript] = []
        var initializers: [Callable] = []
        var methods: [Callable] = []
        var staticMethods: [Callable] = []
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

        /// Adds a subscript, deduplicating by argument and return type.
        mutating func addSubscript(_ subscriptMember: Subscript) {
            guard !subscripts.contains(where: {
                $0.rawArguments == subscriptMember.rawArguments && $0.rawReturnType == subscriptMember.rawReturnType
            }) else {
                return
            }
            subscripts.append(subscriptMember)
        }

        /// Adds an initializer, deduplicating by raw signature.
        mutating func addInitializer(_ callable: Callable) {
            guard !initializers.contains(where: { $0.rawSignature == callable.rawSignature }) else {
                return
            }
            initializers.append(callable)
        }

        /// Adds an instance method, deduplicating by signature and static-ness.
        mutating func addMethod(_ callable: Callable) {
            guard !methods.contains(where: { $0.rawSignature == callable.rawSignature && $0.isStatic == callable.isStatic }) else {
                return
            }
            methods.append(callable)
        }

        /// Adds a static method, deduplicating by raw signature.
        mutating func addStaticMethod(_ callable: Callable) {
            guard !staticMethods.contains(where: { $0.rawSignature == callable.rawSignature }) else {
                return
            }
            staticMethods.append(callable)
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
            initializers.map(\.rawSignature) +
            methods.map(\.rawSignature) +
            staticMethods.map(\.rawSignature) +
            properties.map(\.rawType) +
            enumCases.compactMap(\.rawPayload)
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
        let concreteTypeNames = Set(
            demangledSymbols.compactMap {
                extractedTypeName(from: $0, prefix: nominalTypePrefix)
            }
        )

        func declaration(named fullName: String, order: Int) -> Declaration {
            declarations[fullName] ?? Declaration(fullName: fullName, order: order)
        }

        func setDeclaration(_ declaration: Declaration) {
            declarations[declaration.fullName] = declaration
        }

        for (order, line) in demangledSymbols.enumerated() {
            if let fullName = extractedTypeName(from: line, prefix: protocolDescriptorPrefix) {
                var value = declaration(named: fullName, order: order)
                value.isProtocol = true
                setDeclaration(value)
                continue
            }

            if let fullName = extractedTypeName(from: line, prefix: nominalTypePrefix) {
                setDeclaration(declaration(named: fullName, order: order))
                continue
            }

            if let fullName = extractedTypeName(from: line, prefix: metaclassPrefix) {
                var value = declaration(named: fullName, order: order)
                value.isClass = true
                setDeclaration(value)
                continue
            }

            if let fullName = extractedTypeName(from: line, prefix: classMetadataPrefix) {
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

            if let (owner, conformance) = parseBaseConformanceDescriptor(from: line, moduleName: moduleName) {
                var value = declaration(named: owner, order: order)
                value.addConformance(conformance)
                setDeclaration(value)
                continue
            }

            if let subscriptMember = parseSubscriptDescriptor(
                from: line,
                sortedSymbols: sortedSymbols,
                moduleName: moduleName
            ) {
                var value = declaration(named: subscriptMember.owner, order: order)
                value.addSubscript(
                    Declaration.Subscript(
                        rawArguments: subscriptMember.rawArguments,
                        rawReturnType: subscriptMember.rawReturnType,
                        hasSetter: subscriptMember.hasSetter,
                        order: order
                    )
                )
                setDeclaration(value)
                continue
            }

            if let property = parsePropertyDescriptor(
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
                        order: order
                    )
                )
                setDeclaration(value)
                continue
            }

            if let enumCase = parseEnumCase(from: line, moduleName: moduleName) {
                var value = declaration(named: enumCase.owner, order: order)
                value.addEnumCase(
                    Declaration.EnumCase(
                        name: enumCase.name,
                        rawPayload: enumCase.rawPayload,
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
                allowExtensionMembersOn: concreteTypeNames
            ) {
                var value = declaration(named: callable.owner, order: order)
                if callable.isInitializer {
                    value.addInitializer(
                        Declaration.Callable(
                            rawSignature: callable.rawSignature,
                            isStatic: true,
                            isInitializer: true,
                            order: order
                        )
                    )
                } else {
                    value.addStaticMethod(
                        Declaration.Callable(
                            rawSignature: callable.rawSignature,
                            isStatic: true,
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
                isStatic: false,
                moduleName: moduleName,
                allowExtensionMembersOn: concreteTypeNames
            ) {
                var value = declaration(named: callable.owner, order: order)
                if callable.isInitializer {
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
            }
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
        let knownTypeComponents = Set(
            declarations.keys.flatMap { $0.split(separator: ".").map(String.init) }
        )

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
            .filter { parentName(of: $0, in: declarations) == nil }
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
        let childNames = childrenMap[fullName] ?? []
        let genericParameters = inferredGenericParameters(
            for: declaration,
            genericArityMap: genericArityMap,
            knownTypeComponents: knownTypeComponents,
            moduleName: moduleName
        )
        let genericClause = genericParameters.isEmpty ? "" : "<\(genericParameters.joined(separator: ", "))>"
        let name = escapedIdentifier(simpleName(of: fullName))
        let conformanceClause = renderedConformanceClause(
            for: declaration,
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
            header = "\(indent)public struct \(name)\(genericClause)\(conformanceClause) {"
        case .class where isOpenClass:
            header = "\(indent)open class \(name)\(genericClause)\(conformanceClause) {"
        case .class:
            header = "\(indent)public final class \(name)\(genericClause)\(conformanceClause) {"
        case .enum:
            header = "\(indent)public enum \(name)\(genericClause)\(conformanceClause) {"
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
                !containsUnresolvedAssociatedTypeReference(property.rawType)
            else {
                continue
            }
            let renderedType = renderedTypeName(
                property.rawType,
                protocolNames: protocolNames,
                moduleName: moduleName
            )
            let accessors = property.hasSetter ? "{ get set }" : "{ get }"
            body.append(
                "\(indent)  \(memberAccessPrefix)\(property.isStatic ? "static " : "")var \(escapedIdentifier(property.name)): \(renderedType) \(accessors)"
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
            let renderedReturnType = renderedTypeName(
                subscriptMember.rawReturnType,
                protocolNames: protocolNames,
                moduleName: moduleName
            )
            let accessors = subscriptMember.hasSetter ? "{ get set }" : "{ get }"
            body.append(
                "\(indent)  \(memberAccessPrefix)subscript(\(renderedArguments)) -> \(renderedReturnType) \(accessors)"
            )
        }

        let protocolOwnerName = isProtocol ? simpleName(of: fullName) : nil

        for initializer in declaration.initializers.sorted(by: { $0.order < $1.order }) {
            if let rendered = renderedCallable(
                initializer,
                protocolNames: protocolNames,
                allowedPrefixes: allowedPrefixes,
                level: level + 1,
                isProtocolRequirement: isProtocol,
                moduleName: moduleName,
                ownerName: protocolOwnerName
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
                moduleName: moduleName,
                ownerName: protocolOwnerName
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
                moduleName: moduleName,
                ownerName: protocolOwnerName
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
        moduleName: String
    ) -> String {
        renderedConformanceClause(for: declaration.conformances, moduleName: moduleName)
    }

    private func renderedAssociatedTypeConformanceClause(
        for associatedType: Declaration.AssociatedType,
        moduleName: String
    ) -> String {
        renderedConformanceClause(for: associatedType.conformances, moduleName: moduleName)
    }

    private func renderedConformanceClause(
        for rawConformances: [String],
        moduleName: String
    ) -> String {
        let conformances = normalizedConformances(rawConformances)
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
        for fragment in declaration.rawTypeFragments {
            for token in genericParameterTokens(in: fragment, moduleName: moduleName) {
                if knownTypeComponents.contains(token) || excludedTokens.contains(token) {
                    continue
                }
                if seenParameters.insert(token).inserted {
                    genericParameters.append(token)
                }
            }
        }

        while genericParameters.count < arity {
            genericParameters.append("T\(genericParameters.count)")
        }

        return Array(genericParameters.prefix(arity))
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
        let knownTypeComponents = Set(
            declarations.keys.flatMap { $0.split(separator: ".").map(String.init) }
        )

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
        moduleName: String,
        ownerName: String? = nil
    ) -> String? {
        let indent = String(repeating: "  ", count: level)
        let rawSignature = callable.rawSignature
        guard
            !rawSignature.contains(".T =="),
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

        let head = String(rawSignature[..<openingParenthesis])
        if head.contains(" infix") || head.contains("prefix ") || head.contains("postfix ") {
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
        let renderedReturnType = renderedTypeName(
            returnType,
            protocolNames: protocolNames,
            moduleName: moduleName
        )
        let returnClause = renderedReturnType == "()" ? "" : " -> \(renderedReturnType)"
        let initializerKeyword = renderedReturnType.hasSuffix("?") ? "init?" : "init"

        // Extract generic clause if present (e.g. "respond<A where A: Mod.Proto>" → name "respond", params "<A>", where "where A : Proto")
        let genericParsed = parseGenericClause(head, moduleName: moduleName)
        let methodName = genericParsed.name
        let genericParamClause = genericParsed.paramClause
        let whereClause = combinedWhereClause(
            genericParsed.whereClause,
            trailingWhereClause
        )
        renderedArguments = applyingPackExpansionSyntax(
            to: renderedArguments,
            packParameters: genericParsed.packParameters
        )

        let accessPrefix = isProtocolRequirement ? "" : "public "

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
        try parsedTupleType(fromArgumentList: rawArguments)?.elements.map { element in
            let label = element.firstName?.text ?? "_"
            let renderedLabel = label == "_" ? "_" : escapedIdentifier(label)
            return "\(renderedLabel): \(renderedTupleElementType(element, protocolNames: protocolNames, moduleName: moduleName))"
        }.joined(separator: ", ")
            ?? {
                throw SwiftInterfaceGeneratorError.unexpectedOutput(
                    "Unbalanced argument list: \(rawArguments)"
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
        "UInt64", "URL", "UUID", "Void", "_", "async", "class", "func",
        "init", "inout", "mutating", "nil", "some", "static", "throws", "where",
    ]

    private static let typeReplacements: [(String, String)] = [
        ("__owned ", ""),
        ("Swift.Actor", "_Concurrency.Actor"),
        ("Swift.AsyncIteratorProtocol", "_Concurrency.AsyncIteratorProtocol"),
        ("Swift.AsyncSequence", "_Concurrency.AsyncSequence"),
        ("__C.CGAffineTransform", "CoreGraphics.CGAffineTransform"),
        ("__C.CGFloat", "CoreGraphics.CGFloat"),
        ("__C.CGPoint", "CoreGraphics.CGPoint"),
        ("__C.CGRect", "CoreGraphics.CGRect"),
        ("__C.CGSize", "CoreGraphics.CGSize"),
        ("__C.CGImageRef", "CoreGraphics.CGImage"),
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
        var cleaned = rawTypeName
        if !moduleName.isEmpty {
            cleaned = cleaned.replacingOccurrences(of: "\(moduleName).", with: "")
        }
        for (from, to) in Self.typeReplacements {
            if cleaned.contains(from) {
                cleaned = cleaned.replacingOccurrences(of: from, with: to)
            }
        }
        return cleaned
            .replacingADotPattern()
            .replacingProtocolKeyword()
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
        guard let typeSyntax = parsedTypeSyntax(from: cleaned) else {
            return cleaned
        }

        return ExistentialTypeRewriter(protocolNames: protocolNames)
            .visit(typeSyntax)
            .trimmedDescription
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
        moduleName: String
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

        guard
            remainder.hasPrefix("\(moduleName)."),
            let typeSeparator = remainder.range(of: " : ")
        else {
            return nil
        }

        let path = String(remainder[..<typeSeparator.lowerBound])
        let rawType = String(remainder[typeSeparator.upperBound...])
        guard let member = parseOwnerMemberPath(path, moduleName: moduleName) else {
            return nil
        }

        let staticPrefix = isStatic ? "static " : ""
        let getterPrefix = "\(staticPrefix)\(moduleName).\(member.owner).\(member.name).getter : "
        let setterPrefix = "\(staticPrefix)\(moduleName).\(member.owner).\(member.name).setter : "
        let dispatchSetterPrefix = "dispatch thunk of \(moduleName).\(member.owner).\(member.name).setter : "

        let hasGetter = sortedSymbols.containsPrefix(getterPrefix)
        let hasSetter = (hasGetter && sortedSymbols.containsPrefix(setterPrefix))
            || sortedSymbols.containsPrefix(dispatchSetterPrefix)

        return (
            owner: member.owner,
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
        moduleName: String
    ) -> (owner: String, rawArguments: String, rawReturnType: String, hasSetter: Bool)? {
        let prefix = "property descriptor for \(moduleName)."
        guard line.hasPrefix(prefix) else {
            return nil
        }

        let remainder = String(line.dropFirst(prefix.count))
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
        let rawArguments = String(remainder[subscriptRange.upperBound..<closingParenthesis])
        let rawReturnType = String(remainder[returnArrow.upperBound...])

        let getterPrefix = "\(moduleName).\(owner).subscript.getter : "
        let setterPrefix = "\(moduleName).\(owner).subscript.setter : "
        let dispatchSetterPrefix = "dispatch thunk of \(moduleName).\(owner).subscript.setter : "

        let hasSetter = sortedSymbols.containsPrefix(setterPrefix)
            || sortedSymbols.containsPrefix(dispatchSetterPrefix)
        let hasGetter = sortedSymbols.containsPrefix(getterPrefix)
        guard hasGetter else {
            return nil
        }

        return (
            owner: owner,
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
    /// - Returns: A tuple of `(owner, name, rawPayload)`, or `nil` if the line doesn't match.
    func parseEnumCase(
        from line: String,
        moduleName: String
    ) -> (owner: String, name: String, rawPayload: String?)? {
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
        guard let caseNameSeparator = casePath.lastIndex(of: ".")
        else {
            return nil
        }

        let owner = String(casePath[..<caseNameSeparator])
        let name = String(casePath[casePath.index(after: caseNameSeparator)...])
        let tail = String(remainder[caseSignatureSeparator.upperBound...])
            .replacingOccurrences(of: "\(moduleName).", with: "")

        if tail == owner {
            return (owner, name, nil)
        }

        let ownerSuffix = " -> \(owner)"
        guard tail.hasSuffix(ownerSuffix) else {
            return (owner, name, nil)
        }

        var payload = String(tail.dropLast(ownerSuffix.count))
        if payload.first == "(", payload.last == ")" {
            payload.removeFirst()
            payload.removeLast()
        }

        return (owner, name, payload)
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
        guard !remainder.contains("__allocating_init") else {
            return nil
        }
        guard
            let openingParenthesis = remainder.firstIndex(of: "("),
            let memberSeparator = remainder[..<openingParenthesis].lastIndex(of: ".")
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
        guard remainder.hasPrefix(modulePrefix) else {
            return nil
        }
        remainder.removeFirst(modulePrefix.count)
        guard
            !remainder.contains(".getter :"),
            !remainder.contains(".setter :"),
            !remainder.contains(".modify :"),
            !remainder.contains(".__deallocating_deinit"),
            !remainder.contains(".deinit"),
            !remainder.contains(" infix"),
            !remainder.contains("prefix "),
            !remainder.contains("postfix "),
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

        let extensionConstraintClause = isExtensionMember
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
            !remainder.contains(".getter :"),
            !remainder.contains(".setter :"),
            !remainder.contains(".modify :"),
            !remainder.contains(".__deallocating_deinit"),
            !remainder.contains(".deinit"),
            !remainder.contains("__allocating_init"),
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
        guard let separator = stripped.lastIndex(of: ".") else {
            return nil
        }

        return (
            owner: String(stripped[..<separator]),
            name: String(stripped[stripped.index(after: separator)...])
        )
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

        let name = String(head[..<angleBracketStart])
        let genericContent = String(head[head.index(after: angleBracketStart)...])
            .trimmingCharacters(in: CharacterSet(charactersIn: ">"))

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

            return (
                name: name,
                paramClause: "<\(declaredParams.joined(separator: ", "))>",
                whereClause: " where \(renderedWhereClause)",
                packParameters: packParameters
            )
        }

        let params = genericContent.trimmingCharacters(in: .whitespaces)
        return (
            name: name,
            paramClause: "<\(params)>",
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

        return (
            String(returnSection[..<whereRange.lowerBound]).trimmingCharacters(in: .whitespaces),
            String(returnSection[whereRange.lowerBound...]).trimmingCharacters(in: .whitespaces)
        )
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
            .union(["Swift", "__C", moduleName])
    }

    private func containsUnrenderableExternalModuleReference(
        _ string: String,
        allowedPrefixes: Set<String>?
    ) -> Bool {
        guard let allowedPrefixes else {
            return false
        }

        return moduleLikePrefixes(in: string).contains { prefix in
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
        )
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
    private func extractedTypeName(from line: String, prefix: String) -> String? {
        guard line.hasPrefix(prefix) else {
            return nil
        }
        return String(line.dropFirst(prefix.count))
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

        return arityMap
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
        "associatedtype",
        "class",
        "deinit",
        "default",
        "enum",
        "extension",
        "func",
        "import",
        "init",
        "inout",
        "internal",
        "let",
        "operator",
        "Protocol",
        "private",
        "protocol",
        "public",
        "return",
        "self",
        "static",
        "struct",
        "subscript",
        "typealias",
        "var",
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
        guard self.contains("A.") else { return self }
        var result = ""
        result.reserveCapacity(count + 16)
        var i = startIndex
        while i < endIndex {
            let c = self[i]
            if c == "A" {
                let nextI = index(after: i)
                if nextI < endIndex && self[nextI] == "." {
                    let precededByWord = i > startIndex && {
                        let prev = self[index(before: i)]
                        return prev.isLetter || prev.isNumber || prev == "_"
                    }()
                    if !precededByWord {
                        result += "Self."
                        i = index(after: nextI)
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
