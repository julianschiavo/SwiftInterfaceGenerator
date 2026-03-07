# Getting Started with SwiftInterfaceGenerator

Add SwiftInterfaceGenerator to your project and generate your first `.swiftinterface` file.

## Overview

SwiftInterfaceGenerator is a Swift package that generates `.swiftinterface` files from compiled framework binaries. Follow the steps below to integrate it into your project.

## Add the Dependency

Add SwiftInterfaceGenerator to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/nicklama/SwiftInterfaceGenerator.git", from: "1.0.0"),
]
```

Then add it as a dependency of your target:

```swift
.target(
    name: "YourTarget",
    dependencies: ["SwiftInterfaceGenerator"]
),
```

## Generate an Interface

Import the module and create a ``SwiftInterfaceGenerator/SwiftInterfaceGenerator`` instance:

```swift
import SwiftInterfaceGenerator

let generator = SwiftInterfaceGenerator()
```

Call ``SwiftInterfaceGenerator/SwiftInterfaceGenerator/generate(frameworkBinaryURL:repositoryRootURL:targetTriple:)`` with the path to a compiled framework binary, an output directory, and the target triple:

```swift
let result = try await generator.generate(
    frameworkBinaryURL: URL(fileURLWithPath: "/path/to/MyFramework.framework/MyFramework"),
    repositoryRootURL: URL(fileURLWithPath: "/path/to/output"),
    targetTriple: "arm64-apple-macosx15.0"
)
```

## Use the Result

The returned ``GeneratedSwiftInterface`` provides:

- ``GeneratedSwiftInterface/interfaceURL``: The file URL of the generated `.swiftinterface`.
- ``GeneratedSwiftInterface/moduleSearchRootURL``: A directory you can pass as a module search path (`-I`) to the Swift compiler.
- ``GeneratedSwiftInterface/log``: A human-readable message describing what was generated.

```swift
print("Generated interface at: \(result.interfaceURL.path)")
print("Module search root: \(result.moduleSearchRootURL.path)")
print(result.log)
```

## Handle Errors

The generator throws ``SwiftInterfaceGeneratorError`` when something goes wrong:

```swift
do {
    let result = try await generator.generate(
        frameworkBinaryURL: binaryURL,
        repositoryRootURL: repoURL,
        targetTriple: "arm64-apple-macosx15.0"
    )
} catch let error as SwiftInterfaceGeneratorError {
    switch error {
    case .commandFailed(let command, let status, _, let stderr):
        print("Failed (\(status)): \(stderr)")
    case .missingRequiredSymbol(let symbol):
        print("Missing symbol: \(symbol)")
    case .unexpectedOutput(let message):
        print("Parse error: \(message)")
    }
}
```
