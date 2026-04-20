// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AI---AT---Swift-PRELIMINAR-",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        // Products define the libraries a package produces, making them visible to other packages.
        .library(
            name: "AI---AT---Swift-PRELIMINAR-",
            targets: ["AI---AT---Swift-PRELIMINAR-"]
        )
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "AI---AT---Swift-PRELIMINAR-",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "AI---AT---Swift-PRELIMINAR-Tests",
            dependencies: ["AI---AT---Swift-PRELIMINAR-"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
