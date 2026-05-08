// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "APXTester",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "APXCore",
            targets: ["APXCore"]
        ),
        .executable(
            name: "apx-tester",
            targets: ["APXTesterCLI"]
        ),
        .executable(
            name: "APXTesterApp",
            targets: ["APXTesterApp"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        // Core library — all analysis logic lives here
        .target(
            name: "APXCore",
            path: "Sources/APXCore"
        ),
        // CLI executable — thin wrapper around APXCore
        .executableTarget(
            name: "APXTesterCLI",
            dependencies: [
                "APXCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/APXTesterCLI"
        ),
        // macOS SwiftUI app
        .executableTarget(
            name: "APXTesterApp",
            dependencies: ["APXCore"],
            path: "Sources/APXTesterApp"
        ),
        // Tests
        .testTarget(
            name: "APXCoreTests",
            dependencies: ["APXCore"],
            path: "Tests/APXCoreTests"
        ),
    ]
)
