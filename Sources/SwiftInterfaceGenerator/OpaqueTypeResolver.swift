import Foundation

/// Resolves opaque return type constraints by reading opaque type descriptors
/// from Mach-O binaries.
///
/// When `swift-demangle --compact` outputs `some` without a protocol constraint,
/// the actual constraint is stored in the opaque type descriptor's generic
/// requirements within the binary. This resolver reads those requirements and
/// maps them back to protocol names using symbol address information from `nm`.
struct OpaqueTypeResolver {

    /// A resolved opaque type constraint.
    struct ResolvedConstraint {
        /// The demangled description of the parent function or property,
        /// e.g. `"Canvas.makeShape() -> some"` or `"Canvas.currentShape : some"`.
        let parentDescription: String

        /// The protocol names that the opaque type must conform to,
        /// e.g. `["Shape"]`.
        let protocolNames: [String]
    }

    /// Attempts to resolve opaque type constraints from a Mach-O binary.
    ///
    /// Parses the raw `nm` output to build address-to-symbol mappings, then reads
    /// opaque type descriptor data from the binary to extract protocol constraints.
    ///
    /// - Parameters:
    ///   - binaryURL: The URL of the Mach-O binary file.
    ///   - rawNMOutput: The raw output from `nm -gU` (with addresses and mangled names).
    ///   - demangledNMOutput: The demangled output from `nm -gU | swift-demangle --compact`.
    /// - Returns: An array of resolved constraints, or an empty array if the binary
    ///   cannot be read or is not a Mach-O file.
    static func resolveConstraints(
        binaryURL: URL,
        rawNMOutput: String,
        demangledNMOutput: String
    ) -> [ResolvedConstraint] {
        guard let binaryData = try? Data(contentsOf: binaryURL) else {
            return []
        }

        // Parse demangled nm output: address → demangled description
        let demangledEntries = parseNMEntries(demangledNMOutput)

        // Build address → protocol name mapping from protocol descriptor symbols
        // Protocol descriptor symbols have the mangled suffix "Mp"
        var protocolNameByAddress: [UInt64: String] = [:]
        for (address, demangledName) in demangledEntries {
            if demangledName.hasPrefix("protocol descriptor for ") {
                let protocolName = String(demangledName.dropFirst("protocol descriptor for ".count))
                protocolNameByAddress[address] = protocolName
            }
        }

        // Find opaque type descriptor symbols and their parent descriptions
        var opaqueDescriptors: [(address: UInt64, parentDescription: String)] = []
        for (address, demangledName) in demangledEntries {
            guard demangledName.hasPrefix("opaque type descriptor for <<opaque return type of ") else {
                continue
            }
            // Extract parent description: everything between "...of " and ">>"
            let prefixEnd = demangledName.index(
                demangledName.startIndex,
                offsetBy: "opaque type descriptor for <<opaque return type of ".count
            )
            guard demangledName.hasSuffix(">>") else { continue }
            let suffixStart = demangledName.index(demangledName.endIndex, offsetBy: -2)
            let parentDescription = String(demangledName[prefixEnd..<suffixStart])
            opaqueDescriptors.append((address, parentDescription))
        }

        guard !opaqueDescriptors.isEmpty else { return [] }

        // Find the __TEXT segment for VM address to file offset translation
        guard let textSegment = findTextSegment(in: binaryData) else {
            return []
        }

        // Resolve each opaque type descriptor
        var results: [ResolvedConstraint] = []
        for (address, parentDescription) in opaqueDescriptors {
            guard address >= textSegment.vmaddr else { continue }
            let fileOffset = address - textSegment.vmaddr + textSegment.fileoff
            guard let protocols = readOpaqueTypeProtocols(
                from: binaryData,
                at: fileOffset,
                protocolNameByAddress: protocolNameByAddress,
                segmentVMAddr: textSegment.vmaddr,
                segmentFileOff: textSegment.fileoff
            ) else {
                continue
            }
            let normalizedProtocols = normalizedProtocolNames(
                protocols,
                for: parentDescription
            )
            if !normalizedProtocols.isEmpty {
                results.append(ResolvedConstraint(
                    parentDescription: parentDescription,
                    protocolNames: normalizedProtocols
                ))
            }
        }

        return results
    }

    /// Applies resolved opaque type constraints to demangled symbol lines.
    ///
    /// Replaces bare `some` in demangled descriptions with `some Protocol`
    /// based on the resolved constraints.
    ///
    /// - Parameters:
    ///   - demangledSymbols: The normalized demangled symbol lines.
    ///   - constraints: The resolved constraints from ``resolveConstraints(binaryURL:rawNMOutput:demangledNMOutput:)``.
    /// - Returns: The patched symbol lines with opaque type constraints restored.
    static func applyConstraints(
        to demangledSymbols: [String],
        constraints: [ResolvedConstraint]
    ) -> [String] {
        guard !constraints.isEmpty else { return demangledSymbols }

        // Build a lookup from parent description suffix patterns
        // e.g. "Canvas.makeShape() -> some" → "some Shape"
        var patchMap: [String: String] = [:]
        for constraint in constraints {
            let constraintSuffix = constraint.protocolNames.joined(separator: " & ")
            // For function returns: "Type.method() -> some" → replace "-> some" with "-> some Protocol"
            if constraint.parentDescription.hasSuffix(" -> some") {
                let prefix = String(constraint.parentDescription.dropLast(" -> some".count))
                patchMap[prefix] = "some \(constraintSuffix)"
            }
            // For properties: "Type.property : some" → replace ": some" with ": some Protocol"
            else if constraint.parentDescription.hasSuffix(" : some") {
                let prefix = String(constraint.parentDescription.dropLast(" : some".count))
                patchMap[prefix] = "some \(constraintSuffix)"
            }
        }

        return demangledSymbols.map { line in
            // Check if this line ends with "-> some" or ": some"
            if line.hasSuffix("-> some") {
                let linePrefix = String(line.dropLast("-> some".count)).trimmingCharacters(in: .whitespaces)
                if let replacement = patchMap[linePrefix] {
                    return String(line.dropLast("some".count)) + replacement
                }
            } else if line.hasSuffix(" : some") {
                // Property descriptors: "property descriptor for Type.prop : some"
                // Getter symbols: "Type.prop.getter : some"
                // Setter symbols: "Type.prop.setter : some"
                let memberPath: String
                if line.contains(".getter : some") {
                    memberPath = String(line.dropLast(".getter : some".count))
                } else if line.contains(".setter : some") {
                    memberPath = String(line.dropLast(".setter : some".count))
                } else if line.hasPrefix("property descriptor for ") {
                    memberPath = String(line.dropFirst("property descriptor for ".count).dropLast(" : some".count))
                } else {
                    memberPath = String(line.dropLast(" : some".count))
                }
                if let replacement = patchMap[memberPath] {
                    let insertionPoint = line.index(line.endIndex, offsetBy: -"some".count)
                    return String(line[..<insertionPoint]) + replacement
                }
            }
            return line
        }
    }

    // MARK: - Private

    private struct TextSegment {
        let vmaddr: UInt64
        let fileoff: UInt64
    }

    /// Parses nm output lines into (address, description) pairs.
    private static func parseNMEntries(_ output: String) -> [(address: UInt64, name: String)] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(maxSplits: 2, whereSeparator: \.isWhitespace)
            guard fields.count == 3,
                  fields[0].allSatisfy(\.isHexDigit),
                  fields[1].count == 1,
                  let address = UInt64(fields[0], radix: 16) else {
                return nil
            }
            return (address, String(fields[2]))
        }
    }

    /// Finds the __TEXT segment's VM address and file offset in a Mach-O binary.
    /// Handles both thin and fat (universal) binaries.
    private static func findTextSegment(in data: Data) -> TextSegment? {
        guard data.count >= 4 else { return nil }

        let magic = data.withUnsafeBytes { $0.load(as: UInt32.self) }

        switch magic {
        case 0xFEEDFACF:
            // 64-bit Mach-O
            return findTextSegmentIn64BitMachO(data, offset: 0)

        case 0xCAFEBABE, 0xBEBAFECE:
            // Fat/universal binary (big-endian header)
            return findTextSegmentInFatBinary(data)

        default:
            return nil
        }
    }

    private static func findTextSegmentIn64BitMachO(_ data: Data, offset: Int) -> TextSegment? {
        // Mach-O 64-bit header:
        // magic (4), cputype (4), cpusubtype (4), filetype (4),
        // ncmds (4), sizeofcmds (4), flags (4), reserved (4)
        // Total header size: 32 bytes
        guard data.count >= offset + 32 else { return nil }

        let ncmds: UInt32 = data.withUnsafeBytes {
            $0.load(fromByteOffset: offset + 16, as: UInt32.self)
        }

        var cmdOffset = offset + 32
        for _ in 0..<ncmds {
            guard data.count >= cmdOffset + 8 else { break }

            let cmd: UInt32 = data.withUnsafeBytes {
                $0.load(fromByteOffset: cmdOffset, as: UInt32.self)
            }
            let cmdsize: UInt32 = data.withUnsafeBytes {
                $0.load(fromByteOffset: cmdOffset + 4, as: UInt32.self)
            }

            // LC_SEGMENT_64 = 0x19
            if cmd == 0x19 {
                // segment_command_64:
                // cmd (4), cmdsize (4), segname[16] (16), vmaddr (8), vmsize (8),
                // fileoff (8), filesize (8), ...
                guard data.count >= cmdOffset + 48 else { break }

                let segname = data.subdata(in: (cmdOffset + 8)..<(cmdOffset + 24))
                let segNameString = String(
                    bytes: segname.prefix(while: { $0 != 0 }),
                    encoding: .utf8
                ) ?? ""

                if segNameString == "__TEXT" {
                    let vmaddr: UInt64 = data.withUnsafeBytes {
                        $0.load(fromByteOffset: cmdOffset + 24, as: UInt64.self)
                    }
                    let fileoff: UInt64 = data.withUnsafeBytes {
                        $0.load(fromByteOffset: cmdOffset + 40, as: UInt64.self)
                    }
                    return TextSegment(vmaddr: vmaddr, fileoff: fileoff)
                }
            }

            cmdOffset += Int(cmdsize)
        }

        return nil
    }

    private static func findTextSegmentInFatBinary(_ data: Data) -> TextSegment? {
        guard data.count >= 8 else { return nil }

        let nfatArch: UInt32 = data.withUnsafeBytes {
            UInt32(bigEndian: $0.load(fromByteOffset: 4, as: UInt32.self))
        }

        // fat_arch: cputype(4) cpusubtype(4) offset(4) size(4) align(4) = 20 bytes each
        let arm64CPUType: UInt32 = 0x0100_000C // CPU_TYPE_ARM64
        var archOffset = 8

        for _ in 0..<nfatArch {
            guard data.count >= archOffset + 20 else { break }

            let cputype: UInt32 = data.withUnsafeBytes {
                UInt32(bigEndian: $0.load(fromByteOffset: archOffset, as: UInt32.self))
            }
            let offset: UInt32 = data.withUnsafeBytes {
                UInt32(bigEndian: $0.load(fromByteOffset: archOffset + 8, as: UInt32.self))
            }

            if cputype == arm64CPUType {
                return findTextSegmentIn64BitMachO(data, offset: Int(offset))
            }

            archOffset += 20
        }

        // If no arm64 found, try the first slice
        if nfatArch > 0 {
            let offset: UInt32 = data.withUnsafeBytes {
                UInt32(bigEndian: $0.load(fromByteOffset: 16, as: UInt32.self))
            }
            return findTextSegmentIn64BitMachO(data, offset: Int(offset))
        }

        return nil
    }

    /// Reads the protocol constraints from an opaque type descriptor at the given file offset.
    private static func readOpaqueTypeProtocols(
        from data: Data,
        at fileOffset: UInt64,
        protocolNameByAddress: [UInt64: String],
        segmentVMAddr: UInt64,
        segmentFileOff: UInt64
    ) -> [String]? {
        let offset = Int(fileOffset)

        // OpaqueTypeDescriptor layout (when hasGenericSignature):
        // offset 0: flags (UInt32) - kind in bits 0-4, hasGenericSignature in bit 7
        // offset 4: parent (relative pointer, Int32)
        // offset 8: numParams (UInt16)
        // offset 10: numRequirements (UInt16)
        // offset 12: numKeyArguments (UInt16)
        // offset 14: numExtraArguments (UInt16)
        // offset 16: generic parameter descriptors (1 byte each)
        // aligned to 4: generic requirements (12 bytes each)
        guard data.count >= offset + 16 else { return nil }

        let flags: UInt32 = data.withUnsafeBytes {
            $0.load(fromByteOffset: offset, as: UInt32.self)
        }

        let kind = flags & 0x1F
        guard kind == 4 else { return nil } // 4 = OpaqueType

        let hasGenericSig = (flags & 0x80) != 0
        guard hasGenericSig else { return nil }

        let numParams: UInt16 = data.withUnsafeBytes {
            $0.load(fromByteOffset: offset + 8, as: UInt16.self)
        }
        let numRequirements: UInt16 = data.withUnsafeBytes {
            $0.load(fromByteOffset: offset + 10, as: UInt16.self)
        }

        // Generic parameters start at offset 16, 1 byte each
        let paramsStart = 16
        let requirementsStart = (paramsStart + Int(numParams) + 3) & ~3  // align to 4

        var protocols: [String] = []
        for i in 0..<Int(numRequirements) {
            let reqOffset = offset + requirementsStart + i * 12
            guard data.count >= reqOffset + 12 else { break }

            let reqFlags: UInt32 = data.withUnsafeBytes {
                $0.load(fromByteOffset: reqOffset, as: UInt32.self)
            }

            let reqKind = reqFlags & 0x3
            guard reqKind == 0 else { continue } // 0 = Protocol conformance

            // The protocol reference is a relative pointer at reqOffset + 8
            let relativeOffset: Int32 = data.withUnsafeBytes {
                $0.load(fromByteOffset: reqOffset + 8, as: Int32.self)
            }

            // Compute the VM address of the referenced protocol descriptor
            let refFileOffset = Int(reqOffset + 8) + Int(relativeOffset)
            guard refFileOffset >= 0 else { continue }
            let refVMAddr = UInt64(refFileOffset) - segmentFileOff + segmentVMAddr

            if let protocolName = protocolNameByAddress[refVMAddr] {
                protocols.append(protocolName)
            }
        }

        return protocols
    }

    private static func normalizedProtocolNames(
        _ protocols: [String],
        for parentDescription: String
    ) -> [String] {
        let deduplicated = protocols.reduce(into: [String]()) { result, protocolName in
            guard !result.contains(protocolName) else {
                return
            }
            result.append(protocolName)
        }

        guard
            let extensionOwner = extensionOwnerName(in: parentDescription),
            deduplicated.count > 1
        else {
            return deduplicated
        }

        let filtered = deduplicated.filter { protocolName in
            !matchesExtensionOwner(protocolName, extensionOwner: extensionOwner)
        }

        return filtered.isEmpty ? deduplicated : filtered
    }

    private static func extensionOwnerName(in parentDescription: String) -> String? {
        guard parentDescription.hasPrefix("(extension in "),
              let extensionSeparator = parentDescription.range(of: "):")
        else {
            return nil
        }

        let remainder = String(parentDescription[extensionSeparator.upperBound...])
        let memberPath: String
        if let propertySuffix = remainder.range(of: " : some", options: .backwards) {
            memberPath = String(remainder[..<propertySuffix.lowerBound])
        } else if let functionSuffix = remainder.range(of: " -> some", options: .backwards) {
            memberPath = String(remainder[..<functionSuffix.lowerBound])
        } else {
            return nil
        }

        let ownerPath = memberPath.firstIndex(of: "(").map {
            String(memberPath[..<$0])
        } ?? memberPath
        guard let memberSeparator = ownerPath.lastIndex(of: ".") else {
            return nil
        }

        return String(ownerPath[..<memberSeparator])
    }

    private static func matchesExtensionOwner(
        _ protocolName: String,
        extensionOwner: String
    ) -> Bool {
        protocolName == extensionOwner
            || simpleName(of: protocolName) == simpleName(of: extensionOwner)
    }

    private static func simpleName(of qualifiedName: String) -> String {
        qualifiedName.split(separator: ".").last.map(String.init) ?? qualifiedName
    }
}
