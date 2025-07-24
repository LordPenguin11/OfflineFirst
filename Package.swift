// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "OfflineFirst",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "OfflineFirst",
            targets: ["OfflineFirst"]),
    ],
    dependencies: [
        .package(path: "../aptive-core-ios"),
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "OfflineFirst",
            dependencies: [
                .product(name: "AspynNetwork", package: "aptive-core-ios"),
                .product(name: "SQLite", package: "SQLite.swift")
            ]
        ),
        .testTarget(
            name: "OfflineFirstTests",
            dependencies: ["OfflineFirst"]),
    ]
)
