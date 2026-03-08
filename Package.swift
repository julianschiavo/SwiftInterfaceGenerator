// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SwiftInterfaceGenerator",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .library(
            name: "SwiftInterfaceGenerator",
            targets: ["SwiftInterfaceGenerator"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/swiftlang/swift-subprocess.git",
            from: "0.3.0"
        ),
        .package(
            url: "https://github.com/swiftlang/swift-syntax.git",
            from: "600.0.1"
        ),
        .package(
            url: "https://github.com/apple/swift-docc-plugin",
            from: "1.4.5"
        ),
    ],
    targets: [
        .target(
            name: "SwiftInterfaceGenerator",
            dependencies: [
                .product(name: "Subprocess", package: "swift-subprocess"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
            ]
        ),
        .testTarget(
            name: "SwiftInterfaceGeneratorTests",
            dependencies: ["SwiftInterfaceGenerator"]
        ),
    ]
)
