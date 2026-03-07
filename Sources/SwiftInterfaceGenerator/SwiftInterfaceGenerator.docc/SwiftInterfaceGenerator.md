# ``SwiftInterfaceGenerator``

Generate `.swiftinterface` files from compiled framework binaries.

## Overview

SwiftInterfaceGenerator analyzes a compiled framework binary and reconstructs a `.swiftinterface` file describing the module's public API.

Use this library when you need a `.swiftinterface` for a framework that was built without library evolution enabled, or when you need to regenerate one from a binary artifact.

The generated interface includes:

- Type declarations (structs, classes, enums, protocols)
- Properties, methods, and initializers
- Enum cases with associated values
- Protocol conformances and associated types
- Proper `any`/existential syntax for protocol types

### Quick Start

Create a ``SwiftInterfaceGenerator/SwiftInterfaceGenerator`` and call ``SwiftInterfaceGenerator/SwiftInterfaceGenerator/generate(frameworkBinaryURL:repositoryRootURL:targetTriple:)`` with the path to a compiled framework binary:

```swift
import SwiftInterfaceGenerator

let generator = SwiftInterfaceGenerator()
let result = try await generator.generate(
    frameworkBinaryURL: URL(fileURLWithPath: "/path/to/MyFramework.framework/MyFramework"),
    repositoryRootURL: URL(fileURLWithPath: "/path/to/output"),
    targetTriple: "arm64-apple-macosx15.0"
)

print(result.interfaceURL.path)
```

### Compiler Version

The generator automatically detects your Swift compiler version. You can override it by setting the `SWIFT_INTERFACE_COMPILER_VERSION` environment variable.

## Topics

### Generating Interfaces

- ``SwiftInterfaceGenerator/SwiftInterfaceGenerator``
- ``GeneratedSwiftInterface``

### Errors

- ``SwiftInterfaceGeneratorError``
