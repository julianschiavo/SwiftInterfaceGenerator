# SwiftInterfaceGenerator

A Swift library that generates `.swiftinterface` files from compiled framework binaries.

## Overview

SwiftInterfaceGenerator analyzes a compiled framework binary and reconstructs a `.swiftinterface` file describing the module's public API. This is useful when you need a `.swiftinterface` for a framework that was built without library evolution enabled, or when you need to regenerate one from a binary artifact.

The generated interface includes:
- Type declarations (structs, classes, enums, protocols)
- Properties, methods, and initializers
- Enum cases with associated values
- Protocol conformances and associated types
- Proper `any`/existential syntax for protocol types

## Requirements

- macOS 26+
- Swift 6.2+
- Xcode command line tools

## Installation

Add SwiftInterfaceGenerator as a dependency in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/nicklama/SwiftInterfaceGenerator.git", from: "1.0.0"),
]
```

Then add it to your target's dependencies:

```swift
.target(
    name: "YourTarget",
    dependencies: ["SwiftInterfaceGenerator"]
),
```

## Usage

```swift
import SwiftInterfaceGenerator

let generator = SwiftInterfaceGenerator()

let result = try await generator.generate(
    frameworkBinaryURL: URL(fileURLWithPath: "/path/to/MyFramework.framework/MyFramework"),
    repositoryRootURL: URL(fileURLWithPath: "/path/to/output"),
    targetTriple: "arm64-apple-macosx15.0"
)

// The generated .swiftinterface file
print(result.interfaceURL.path)

// Pass this as a module search path (-I) to the Swift compiler
print(result.moduleSearchRootURL.path)
```

### Compiler Version

The generator automatically detects your Swift compiler version. You can override it by setting the `SWIFT_INTERFACE_COMPILER_VERSION` environment variable.

## License

SwiftInterfaceGenerator is available under the MIT license. See the [LICENSE](LICENSE) file for details.
