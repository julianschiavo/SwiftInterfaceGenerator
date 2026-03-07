import Foundation

/// Builds `.swiftinterface` file contents from demangled symbol data.
///
/// `SwiftInterfaceBuilder` is the core parser and renderer. It takes an array of demangled
/// symbol strings, discovers type declarations (structs, classes, enums, protocols) and their
/// members, then renders a valid `.swiftinterface` file as a string.
struct SwiftInterfaceBuilder: Sendable {
    private let renderableExternalModules: Set<String>?

    /// An intermediate representation of a discovered type declaration.
    private struct Declaration: Sendable {
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
    private func discoverDeclarations(
        from demangledSymbols: [String],
        moduleName: String
    ) -> [String: Declaration] {
        var declarations: [String: Declaration] = [:]
        let concreteTypeNames = Set(
            demangledSymbols.compactMap {
                extractedTypeName(
                    from: $0,
                    prefix: "nominal type descriptor for \(moduleName)."
                )
            }
        )

        func declaration(named fullName: String, order: Int) -> Declaration {
            declarations[fullName] ?? Declaration(fullName: fullName, order: order)
        }

        func setDeclaration(_ declaration: Declaration) {
            declarations[declaration.fullName] = declaration
        }

        for (order, line) in demangledSymbols.enumerated() {
            if let fullName = extractedTypeName(
                from: line,
                prefix: "protocol descriptor for \(moduleName)."
            ) {
                var value = declaration(named: fullName, order: order)
                value.isProtocol = true
                setDeclaration(value)
                continue
            }

            if let fullName = extractedTypeName(
                from: line,
                prefix: "nominal type descriptor for \(moduleName)."
            ) {
                setDeclaration(declaration(named: fullName, order: order))
                continue
            }

            if let fullName = extractedTypeName(
                from: line,
                prefix: "metaclass for \(moduleName)."
            ) {
                var value = declaration(named: fullName, order: order)
                value.isClass = true
                setDeclaration(value)
                continue
            }

            if let fullName = extractedTypeName(
                from: line,
                prefix: "class metadata base offset for \(moduleName)."
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

            if let (owner, conformance) = parseBaseConformanceDescriptor(from: line, moduleName: moduleName) {
                var value = declaration(named: owner, order: order)
                value.addConformance(conformance)
                setDeclaration(value)
                continue
            }

            if let subscriptMember = parseSubscriptDescriptor(
                from: line,
                demangledSymbols: demangledSymbols,
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
                demangledSymbols: demangledSymbols,
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
                demangledSymbols: demangledSymbols,
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
    private func renderInterface(
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

        for name in topLevelNames {
            lines.append(
                renderedDeclaration(
                    named: name,
                    declarations: declarations,
                    protocolNames: protocolNames,
                    knownTypeComponents: knownTypeComponents,
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
        moduleName: String,
        level: Int
    ) -> String {
        guard let declaration = declarations[fullName] else {
            return ""
        }

        let indent = String(repeating: "  ", count: level)
        let childNames = declarations.keys
            .filter { parentName(of: $0, in: declarations) == fullName }
            .sorted {
                declarations[$0, default: Declaration(fullName: $0, order: .max)].order
                    < declarations[$1, default: Declaration(fullName: $1, order: .max)].order
            }
        let genericParameters = inferredGenericParameters(
            for: declaration,
            declarations: declarations,
            knownTypeComponents: knownTypeComponents,
            moduleName: moduleName
        )
        let genericClause = genericParameters.isEmpty ? "" : "<\(genericParameters.joined(separator: ", "))>"
        let name = escapedIdentifier(simpleName(of: fullName))
        let conformanceClause = renderedConformanceClause(
            for: declaration,
            protocolNames: protocolNames,
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
            guard !property.rawType.contains("CoreGraphics.Region") else {
                continue
            }
            guard
                !containsUnrenderableExternalModuleReference(
                    property.rawType,
                    knownTypeComponents: knownTypeComponents,
                    moduleName: moduleName
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
                    knownTypeComponents: knownTypeComponents,
                    moduleName: moduleName
                ),
                !containsUnrenderableExternalModuleReference(
                    subscriptMember.rawReturnType,
                    knownTypeComponents: knownTypeComponents,
                    moduleName: moduleName
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
                knownTypeComponents: knownTypeComponents,
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
                knownTypeComponents: knownTypeComponents,
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
                knownTypeComponents: knownTypeComponents,
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
        protocolNames: Set<String>,
        moduleName: String
    ) -> String {
        let conformances = normalizedConformances(declaration.conformances)
        guard !conformances.isEmpty else {
            return ""
        }

        return ": " + conformances
            .map { cleanedTypeName($0, moduleName: moduleName) }
            .joined(separator: ", ")
    }

    /// Renders the conformance clause for an associated type requirement.
    ///
    /// - Parameters:
    ///   - associatedType: The associated type to render.
    ///   - moduleName: The module name for type name cleanup.
    /// - Returns: A clause like `": Sendable"`, or an empty string.
    private func renderedAssociatedTypeConformanceClause(
        for associatedType: Declaration.AssociatedType,
        moduleName: String
    ) -> String {
        let conformances = normalizedConformances(associatedType.conformances)
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
    private func normalizedConformances(_ rawConformances: [String]) -> [String] {
        var conformances = rawConformances
        let unsupportedConformances: Set<String> = [
            "Foundation.AttributeScope",
            "Foundation.AttributedStringKey",
            "Foundation.DecodableAttributedStringKey",
            "Foundation.DecodingConfigurationProviding",
            "Foundation.EncodableAttributedStringKey",
            "Foundation.EncodingConfigurationProviding",
        ]
        conformances.removeAll { unsupportedConformances.contains($0) }

        if conformances.contains("Swift.Encodable"), conformances.contains("Swift.Decodable") {
            conformances.removeAll { $0 == "Swift.Encodable" || $0 == "Swift.Decodable" }
            if !conformances.contains("Swift.Codable") {
                conformances.insert("Swift.Codable", at: 0)
            }
        }

        if conformances.contains("Swift.Hashable"), conformances.contains("Swift.Equatable") {
            conformances.removeAll { $0 == "Swift.Equatable" }
        }

        return conformances
    }

    /// Infers generic parameter names for a declaration by scanning its members.
    ///
    /// Uses ``inferredGenericArity(for:declarations:moduleName:)`` to determine how many
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
        knownTypeComponents: Set<String>,
        moduleName: String
    ) -> [String] {
        let arity = inferredGenericArity(
            for: declaration.fullName,
            declarations: declarations,
            moduleName: moduleName
        )
        guard arity > 0 else {
            return []
        }

        let callableSignatures = (declaration.initializers + declaration.methods + declaration.staticMethods)
            .map { typePortionOfSignature($0.rawSignature) }
        let rawFragments: [String] =
            declaration.properties.map(\.rawType) +
            declaration.enumCases.compactMap(\.rawPayload) +
            callableSignatures

        var genericParameters: [String] = []
        var excludedTokens: Set<String> = [
            "Any",
            "AnyObject",
            "Bool",
            "Data",
            "Date",
            "Decoder",
            "Double",
            "Encoder",
            "Error",
            "Float",
            "Hasher",
            "IndexPath",
            "Int",
            "Int32",
            "Int64",
            "Never",
            "Self",
            "String",
            "Type",
            "UInt",
            "UInt32",
            "UInt64",
            "URL",
            "UUID",
            "Void",
            "_",
            "async",
            "class",
            "func",
            "init",
            "inout",
            "mutating",
            "nil",
            "some",
            "static",
            "throws",
            "where",
        ]
        if !moduleName.isEmpty {
            excludedTokens.insert(moduleName)
        }

        for fragment in rawFragments {
            for token in bareTokens(in: fragment) {
                if knownTypeComponents.contains(token) || excludedTokens.contains(token) {
                    continue
                }
                if !genericParameters.contains(token) {
                    genericParameters.append(token)
                }
            }
        }

        while genericParameters.count < arity {
            genericParameters.append("T\(genericParameters.count)")
        }

        return Array(genericParameters.prefix(arity))
    }

    /// Extracts bare identifier tokens from a type signature string.
    ///
    /// Splits on non-alphanumeric/underscore characters and excludes tokens that appear
    /// immediately after a dot (which are module-qualified suffixes, not standalone names).
    ///
    /// - Parameter string: The raw signature string to tokenize.
    /// - Returns: An array of bare identifier tokens found in the string.
    private func bareTokens(in string: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var precededByDot = false
        var previousCharacter: Character?

        for character in string {
            if character.isLetter || character.isNumber || character == "_" {
                if current.isEmpty {
                    precededByDot = previousCharacter == "."
                }
                current.append(character)
            } else {
                if !current.isEmpty {
                    let followedByDot = character == "."
                    if !precededByDot && !followedByDot {
                        tokens.append(current)
                    }
                    current.removeAll(keepingCapacity: true)
                }
            }
            previousCharacter = character
        }

        if !current.isEmpty, !precededByDot {
            tokens.append(current)
        }

        return tokens
    }

    /// Discovers which system modules need to be imported based on type references.
    ///
    /// Scans all conformances, property types, method signatures, and enum payloads for
    /// references to known system modules (Foundation, CoreGraphics, Dispatch, etc.) and
    /// returns the set of required import statements.
    ///
    /// - Parameter declarations: All discovered declarations to scan.
    /// - Returns: An ordered array of module names to import.
    func discoveredExternalModules(
        from demangledSymbols: [String],
        moduleName: String
    ) -> [String] {
        let declarations = discoverDeclarations(from: demangledSymbols, moduleName: moduleName)
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
            rawFragments.append(contentsOf: declaration.initializers.map(\.rawSignature))
            rawFragments.append(contentsOf: declaration.methods.map(\.rawSignature))
            rawFragments.append(contentsOf: declaration.staticMethods.map(\.rawSignature))
            rawFragments.append(contentsOf: declaration.properties.map(\.rawType))
            rawFragments.append(contentsOf: declaration.enumCases.compactMap(\.rawPayload))
        }

        var modules: [String] = []

        func addModule(_ module: String) {
            guard !modules.contains(module) else {
                return
            }
            modules.append(module)
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
        knownTypeComponents: Set<String>,
        level: Int,
        isProtocolRequirement: Bool,
        moduleName: String,
        ownerName: String? = nil
    ) -> String? {
        let indent = String(repeating: "  ", count: level)
        let rawSignature = callable.rawSignature
        guard
            !rawSignature.contains(".T =="),
            !rawSignature.contains("CoreGraphics.Region"),
            !containsUnrenderableExternalModuleReference(
                rawSignature,
                knownTypeComponents: knownTypeComponents,
                moduleName: moduleName
            )
        else {
            return nil
        }
        guard
            let returnArrow = rawSignature.range(of: " -> ", options: .backwards)
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
        let effects = rawSignature[rawSignature.index(after: closingParenthesis)..<returnArrow.lowerBound]
            .trimmingCharacters(in: .whitespaces)
        let rawReturnSection = String(rawSignature[returnArrow.upperBound...])
        let (returnType, trailingWhereClause) = splitTrailingWhereClause(from: rawReturnSection)
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
            result = result.replacingOccurrences(
                of: #"(?<!\w)A\."#,
                with: "Self.",
                options: .regularExpression
            )
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
        guard !rawArguments.isEmpty else {
            return ""
        }

        return try splitTopLevel(rawArguments).map { rawArgument in
            guard let colonIndex = firstTopLevelColon(in: rawArgument) else {
                return "_: \(renderedTypeName(rawArgument, protocolNames: protocolNames, moduleName: moduleName))"
            }

            let label = rawArgument[..<colonIndex].trimmingCharacters(in: .whitespaces)
            let rawType = rawArgument[rawArgument.index(after: colonIndex)...]
                .trimmingCharacters(in: .whitespaces)
            let renderedLabel = label == "_" ? "_" : escapedIdentifier(String(label))
            return "\(renderedLabel): \(renderedTypeName(rawType, protocolNames: protocolNames, moduleName: moduleName))"
        }.joined(separator: ", ")
    }

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
        return cleaned
            .replacingOccurrences(of: "__owned ", with: "")
            .replacingOccurrences(of: "Swift.Actor", with: "_Concurrency.Actor")
            .replacingOccurrences(of: "Swift.AsyncIteratorProtocol", with: "_Concurrency.AsyncIteratorProtocol")
            .replacingOccurrences(of: "Swift.AsyncSequence", with: "_Concurrency.AsyncSequence")
            .replacingOccurrences(of: "__C.CGAffineTransform", with: "CoreGraphics.CGAffineTransform")
            .replacingOccurrences(of: "__C.CGFloat", with: "CoreGraphics.CGFloat")
            .replacingOccurrences(of: "__C.CGPoint", with: "CoreGraphics.CGPoint")
            .replacingOccurrences(of: "__C.CGRect", with: "CoreGraphics.CGRect")
            .replacingOccurrences(of: "__C.CGSize", with: "CoreGraphics.CGSize")
            .replacingOccurrences(of: "__C.CGImageRef", with: "CoreGraphics.CGImage")
            .replacingOccurrences(of: "__C.CATransform3D", with: "QuartzCore.CATransform3D")
            .replacingOccurrences(of: "__C.NSCoder", with: "Foundation.NSCoder")
            .replacingOccurrences(of: "__C.NSUserActivity", with: "Foundation.NSUserActivity")
            .replacingOccurrences(of: "__C.NSHashTable", with: "Foundation.NSHashTable")
            .replacingOccurrences(of: "__C.IOSurfaceRef", with: "IOSurfaceRef")
            .replacingOccurrences(of: "__C.audit_token_t", with: "Darwin.audit_token_t")
            .replacingOccurrences(
                of: #"(?<!\w)A\.([A-Z][0-9]?)(?!\w)"#,
                with: "$1",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?<![\w`])Protocol(?![\w`])"#,
                with: "`Protocol`",
                options: .regularExpression
            )
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
        return renderedNestedTypeName(cleaned, protocolNames: protocolNames)
    }

    private func renderedNestedTypeName(
        _ typeName: String,
        protocolNames: Set<String>
    ) -> String {
        let trimmed = typeName.trimmingCharacters(in: .whitespaces)

        if protocolNames.contains(trimmed) {
            return "any \(trimmed)"
        }

        if trimmed.hasPrefix("inout ") {
            let inner = String(trimmed.dropFirst("inout ".count))
            return "inout \(renderedNestedTypeName(inner, protocolNames: protocolNames))"
        }

        if let effectArrowRange = topLevelArrowRange(in: trimmed) {
            let left = String(trimmed[..<effectArrowRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let right = String(trimmed[effectArrowRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            let leftRendered = renderedNestedTypeName(left, protocolNames: protocolNames)
            let rightRendered = renderedNestedTypeName(right, protocolNames: protocolNames)
            return "\(leftRendered) -> \(rightRendered)"
        }

        if trimmed.hasSuffix("?") {
            let inner = String(trimmed.dropLast())
            let renderedInner = renderedNestedTypeName(inner, protocolNames: protocolNames)
            if renderedInner.hasPrefix("any ") {
                return "(\(renderedInner))?"
            }
            return "\(renderedInner)?"
        }

        if trimmed.hasPrefix("["),
           trimmed.hasSuffix("]") {
            let inner = String(trimmed.dropFirst().dropLast())
            if let colonIndex = firstTopLevelColon(in: inner) {
                let key = inner[..<colonIndex].trimmingCharacters(in: .whitespaces)
                let value = inner[inner.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
                return "[\(renderedNestedTypeName(String(key), protocolNames: protocolNames)) : \(renderedNestedTypeName(String(value), protocolNames: protocolNames))]"
            }
            return "[\(renderedNestedTypeName(inner, protocolNames: protocolNames))]"
        }

        if let angleBracketStart = trimmed.firstIndex(of: "<"),
           let closingAngle = matchingClosingDelimiter(
                in: trimmed,
                from: angleBracketStart,
                open: "<",
                close: ">"
           ),
           trimmed.index(after: closingAngle) == trimmed.endIndex {
            let base = String(trimmed[..<angleBracketStart])
            let rawArguments = String(trimmed[trimmed.index(after: angleBracketStart)..<closingAngle])
            if let arguments = try? splitTopLevel(rawArguments) {
                let renderedArguments = arguments.map {
                    renderedNestedTypeName($0, protocolNames: protocolNames)
                }.joined(separator: ", ")
                return "\(base)<\(renderedArguments)>"
            }
        }

        if trimmed.hasPrefix("("),
           trimmed.hasSuffix(")"),
           let open = trimmed.firstIndex(of: "("),
           let closingParenthesis = matchingClosingParenthesis(in: trimmed, from: open),
           trimmed.index(after: closingParenthesis) == trimmed.endIndex {
            let inner = String(trimmed[trimmed.index(after: open)..<closingParenthesis])
            if let elements = try? splitTopLevel(inner), !elements.isEmpty {
                let renderedElements = elements.map { element in
                    guard let colonIndex = firstTopLevelColon(in: element) else {
                        return renderedNestedTypeName(element, protocolNames: protocolNames)
                    }

                    let label = element[..<colonIndex].trimmingCharacters(in: .whitespaces)
                    let type = element[element.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
                    return "\(label): \(renderedNestedTypeName(String(type), protocolNames: protocolNames))"
                }.joined(separator: ", ")
                return "(\(renderedElements))"
            }
        }

        if trimmed.hasSuffix(".Type") {
            let inner = String(trimmed.dropLast(".Type".count))
            let renderedInner = renderedNestedTypeName(inner, protocolNames: protocolNames)
            if renderedInner.hasPrefix("any ") {
                return "(\(renderedInner)).Type"
            }
            return "\(renderedInner).Type"
        }

        return wrappedProtocolLeaves(in: trimmed, protocolNames: protocolNames)
    }

    private func wrappedProtocolLeaves(
        in typeName: String,
        protocolNames: Set<String>
    ) -> String {
        protocolNames
            .sorted { $0.count > $1.count }
            .reduce(typeName) { current, protocolName in
                let escapedName = NSRegularExpression.escapedPattern(for: protocolName)
                let pattern = #"(?<![\w.])(?<!any )\#(escapedName)(?![\w.])"#
                return current.replacingOccurrences(
                    of: pattern,
                    with: "any \(protocolName)",
                    options: .regularExpression
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
    ///   - demangledSymbols: The full list of demangled symbols (for getter/setter detection).
    ///   - moduleName: The module name prefix to match.
    /// - Returns: A tuple of property metadata, or `nil` if the line doesn't match.
    func parsePropertyDescriptor(
        from line: String,
        demangledSymbols: [String],
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

        let hasGetter = demangledSymbols.contains(where: { $0.hasPrefix(getterPrefix) })
        let hasSetter = (hasGetter && demangledSymbols.contains(where: { $0.hasPrefix(setterPrefix) }))
            || demangledSymbols.contains(where: { $0.hasPrefix(dispatchSetterPrefix) })

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
    ///   - demangledSymbols: The full list of demangled symbols (for getter/setter detection).
    ///   - moduleName: The module name prefix to match.
    /// - Returns: A tuple of subscript metadata, or `nil` if the line doesn't match.
    func parseSubscriptDescriptor(
        from line: String,
        demangledSymbols: [String],
        moduleName: String
    ) -> (owner: String, rawArguments: String, rawReturnType: String, hasSetter: Bool)? {
        let prefix = "property descriptor for \(moduleName)."
        guard line.hasPrefix(prefix) else {
            return nil
        }

        let remainder = String(line.dropFirst(prefix.count))
        let openingParenthesis: String.Index
        if let subscriptRange = remainder.range(of: ".subscript(") {
            openingParenthesis = remainder.index(before: subscriptRange.upperBound)
        } else {
            return nil
        }
        guard
            let closingParenthesis = matchingClosingParenthesis(
                in: remainder,
                from: openingParenthesis
            ),
            let subscriptRange = remainder.range(of: ".subscript("),
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

        let hasSetter = demangledSymbols.contains(where: { $0.hasPrefix(setterPrefix) })
            || demangledSymbols.contains(where: { $0.hasPrefix(dispatchSetterPrefix) })
        let hasGetter = demangledSymbols.contains(where: { $0.hasPrefix(getterPrefix) })
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
    ///   - demangledSymbols: The full list of demangled symbols (for setter detection).
    ///   - moduleName: The module name prefix to match.
    /// - Returns: A tuple of property metadata, or `nil` if the line doesn't match.
    func parseProtocolPropertyDescriptor(
        from line: String,
        demangledSymbols: [String],
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
        let hasSetter = demangledSymbols.contains(where: { $0.hasPrefix(setterPrefix) })

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

    /// Extracts a type name from a symbol line by stripping a known prefix.
    ///
    /// - Parameters:
    ///   - line: The demangled symbol line.
    ///   - prefix: The prefix to strip (e.g. `"nominal type descriptor for Module."`).
    /// - Returns: The type name after the prefix, or `nil` if the line doesn't match.
    /// Extracts only the type-bearing portion of a method signature, excluding the method name.
    ///
    /// For `"makeIterator() -> Stream<A>.Iterator"`, returns `"() -> Stream<A>.Iterator"`.
    /// For `"init(value: T) -> Box<T>"`, returns `"(value: T) -> Box<T>"`.
    /// This prevents method names from being mistaken for generic parameters.
    private func typePortionOfSignature(_ signature: String) -> String {
        guard let openParen = signature.firstIndex(of: "(") else {
            return signature
        }
        // For generic methods like "respond<A where A: Mod.Proto>(...)", include the generic clause
        if let angleBracket = signature.firstIndex(of: "<"), angleBracket < openParen {
            return String(signature[angleBracket...])
        }
        return String(signature[openParen...])
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
                .replacingOccurrences(
                    of: #"(\w):\s*"#,
                    with: "$1 : ",
                    options: .regularExpression
                )

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
        let sameTypePattern = #"(\w+)\s*==\s*(.+)"#
        guard let sameTypeRegex = try? NSRegularExpression(pattern: sameTypePattern) else {
            return declaredParams
        }

        let constraints = whereClause.components(separatedBy: ", ")
        var paramsToRemove: Set<String> = []
        var paramsToAdd: [String] = []

        for constraint in constraints {
            let nsConstraint = constraint as NSString
            guard let match = sameTypeRegex.firstMatch(
                in: constraint,
                range: NSRange(location: 0, length: nsConstraint.length)
            ) else {
                continue
            }

            let lhs = nsConstraint.substring(with: match.range(at: 1))
            let rhs = nsConstraint.substring(with: match.range(at: 2))

            guard declaredParams.contains(lhs) else {
                continue
            }

            // Find undeclared generic-param-like identifiers in the RHS
            guard let identRegex = try? NSRegularExpression(pattern: #"\b([A-Z][A-Za-z]*[0-9]+)\b"#) else {
                continue
            }
            let nsRhs = rhs as NSString
            let rhsMatches = identRegex.matches(in: rhs, range: NSRange(location: 0, length: nsRhs.length))
            let undeclaredParams = rhsMatches
                .map { nsRhs.substring(with: $0.range(at: 1)) }
                .filter { !declaredParams.contains($0) && !paramsToAdd.contains($0) }

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
            let escapedParameter = NSRegularExpression.escapedPattern(for: parameter)
            return result.replacingOccurrences(
                of: #"(?<!each )repeat \#(escapedParameter)\b"#,
                with: "repeat each \(parameter)",
                options: .regularExpression
            )
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
            let escapedParameter = NSRegularExpression.escapedPattern(for: parameter)
            return result.replacingOccurrences(
                of: #"\b\#(escapedParameter)\s*:"#,
                with: "repeat each \(parameter) :",
                options: .regularExpression
            )
        }
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
            .replacingOccurrences(
                of: #"(\w):\s*"#,
                with: "$1 : ",
                options: .regularExpression
            )

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

    private func combinedWhereClause(_ lhs: String, _ rhs: String) -> String {
        let lhsConstraints = lhs.replacingOccurrences(of: #"^\s*where\s+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        let rhsConstraints = rhs.replacingOccurrences(of: #"^\s*where\s+"#, with: "", options: .regularExpression)
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
        string.range(
            of: #"\b[A-Z][0-9]*\.[A-Z][A-Za-z0-9_]*\b"#,
            options: .regularExpression
        ) != nil
    }

    private func containsUnrenderableExternalModuleReference(
        _ string: String,
        knownTypeComponents: Set<String>,
        moduleName: String
    ) -> Bool {
        guard let renderableExternalModules else {
            return false
        }

        let allowedPrefixes = knownTypeComponents
            .union(renderableExternalModules)
            .union(["Swift", "__C", moduleName])

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
        guard let regex = try? NSRegularExpression(pattern: #"\b([A-Z_][A-Za-z0-9_]{1,}|os)\."#) else {
            return []
        }

        let nsString = string as NSString
        let range = NSRange(location: 0, length: nsString.length)
        return Set(
            regex.matches(in: string, range: range).map {
                nsString.substring(with: $0.range(at: 1))
            }
        )
    }

    private func extractedTypeName(from line: String, prefix: String) -> String? {
        guard line.hasPrefix(prefix) else {
            return nil
        }
        return String(line.dropFirst(prefix.count))
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

    /// Infers the number of generic parameters a type has by scanning usage across all declarations.
    ///
    /// Looks for patterns like `"Module.TypeName<A, B>"` in conformances, property types,
    /// method signatures, and enum payloads to determine the maximum observed arity.
    ///
    /// - Parameters:
    ///   - fullName: The type name to check for generic usage.
    ///   - declarations: All declarations to scan.
    ///   - moduleName: The module name for building the search needle.
    /// - Returns: The maximum observed generic arity, or 0 if no generic usage is found.
    private func inferredGenericArity(
        for fullName: String,
        declarations: [String: Declaration],
        moduleName: String = ""
    ) -> Int {
        let needle = "\(moduleName.isEmpty ? "" : "\(moduleName).")\(fullName)<"
        var maximumArity = 0

        for declaration in declarations.values {
            let fragments =
                declaration.conformances +
                declaration.properties.map(\.rawType) +
                declaration.initializers.map(\.rawSignature) +
                declaration.methods.map(\.rawSignature) +
                declaration.staticMethods.map(\.rawSignature) +
                declaration.enumCases.compactMap(\.rawPayload)

            for fragment in fragments {
                guard let range = fragment.range(of: needle) else {
                    continue
                }

                let openingIndex = fragment.index(before: range.upperBound)
                guard let closingIndex = matchingClosingDelimiter(
                    in: fragment,
                    from: openingIndex,
                    open: "<",
                    close: ">"
                ) else {
                    continue
                }

                let rawArguments = String(fragment[fragment.index(after: openingIndex)..<closingIndex])
                if let arguments = try? splitTopLevel(rawArguments) {
                    maximumArity = max(maximumArity, arguments.count)
                }
            }
        }

        return maximumArity
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

    /// Finds the index of the first colon that is not nested inside brackets, parentheses, or angle brackets.
    ///
    /// Used to separate parameter labels from types in argument lists. Respects the arrow
    /// operator `->` by not treating `<` after `-` as a depth increase.
    ///
    /// - Parameter string: The string to search.
    /// - Returns: The index of the first top-level colon, or `nil` if none exists.
    private func firstTopLevelColon(in string: String) -> String.Index? {
        var depth = 0
        var previousCharacter: Character?

        for index in string.indices {
            let character = string[index]
            switch character {
            case "(", "[", "<":
                if character == "<" && previousCharacter == "-" {
                    break
                }
                depth += 1
            case ")", "]", ">":
                if character == ">" && previousCharacter == "-" {
                    break
                }
                depth -= 1
            case ":" where depth == 0:
                return index
            default:
                break
            }

            previousCharacter = character
        }

        return nil
    }

    /// Finds the last top-level `->` in a type string, ignoring nested delimiters.
    private func topLevelArrowRange(in string: String) -> Range<String.Index>? {
        var depth = 0
        var previousCharacter: Character?
        var arrowRange: Range<String.Index>?

        for index in string.indices {
            let character = string[index]
            if character == ">" && previousCharacter == "-" && depth == 0 {
                let lowerBound = string.index(before: index)
                arrowRange = lowerBound..<string.index(after: index)
                previousCharacter = character
                continue
            }

            switch character {
            case "(", "[":
                depth += 1
            case "<":
                if previousCharacter != "-" {
                    depth += 1
                }
            case ")", "]":
                depth -= 1
            case ">":
                if previousCharacter != "-" {
                    depth -= 1
                }
            default:
                break
            }

            previousCharacter = character
        }

        return arrowRange
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
        var parts: [String] = []
        var current = ""
        var depth = 0
        var previousCharacter: Character?

        for character in string {
            switch character {
            case "(", "[":
                depth += 1
                current.append(character)
            case "<":
                if previousCharacter == "-" {
                    current.append(character)
                } else {
                    depth += 1
                    current.append(character)
                }
            case ")", "]", ">":
                if character == ">" && previousCharacter == "-" {
                    current.append(character)
                    previousCharacter = character
                    continue
                }
                depth -= 1
                current.append(character)
            case "," where depth == 0:
                parts.append(current.trimmingCharacters(in: .whitespaces))
                current.removeAll(keepingCapacity: true)
            default:
                current.append(character)
            }
            previousCharacter = character
        }

        if depth != 0 {
            throw SwiftInterfaceGeneratorError.unexpectedOutput("Unbalanced argument list: \(string)")
        }

        let trimmed = current.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            parts.append(trimmed)
        }
        return parts
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
