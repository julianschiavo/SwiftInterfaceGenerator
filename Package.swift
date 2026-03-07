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
    ],
    targets: [
        .target(
            name: "SwiftInterfaceGenerator",
            dependencies: [
                .product(name: "Subprocess", package: "swift-subprocess"),
            ]
        ),
        .testTarget(
            name: "SwiftInterfaceGeneratorTests",
            dependencies: ["SwiftInterfaceGenerator"]
        ),
    ]
)
