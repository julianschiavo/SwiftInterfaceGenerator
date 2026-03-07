# SwiftInterfaceGenerator

Generate `.swiftinterface` files from compiled framework binaries.

## Overview

SwiftInterfaceGenerator analyzes a compiled framework binary and reconstructs a `.swiftinterface` file describing the module's public API.

Use this package when you need a `.swiftinterface` for a framework that was built without library evolution enabled, or when you need to regenerate one from a binary artifact.

## Topics

### Essentials

- <doc:GettingStarted>
- ``SwiftInterfaceGenerator``

### Supporting Types

- ``GeneratedSwiftInterface``
- ``SwiftInterfaceGeneratorError``
