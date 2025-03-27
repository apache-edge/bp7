// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "bp7",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v18),
        .tvOS(.v18)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "BP7",
            targets: ["BP7"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/apache-edge/cbor.git", from: "0.0.1"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "BP7",
            dependencies: [
                .product(name: "CBOR", package: "cbor")
            ]
        ),
        .testTarget(
            name: "BP7Tests",
            dependencies: ["BP7"]
        ),
    ]
)
