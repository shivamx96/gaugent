// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "Gaugent",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "GaugentCore", targets: ["GaugentCore"]),
        .executable(name: "Gaugent", targets: ["Gaugent"])
    ],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.0")],
    targets: [
        .target(
            name: "GaugentCore",
            path: "Sources/GaugentCore"
        ),
        .executableTarget(
            name: "Gaugent",
            dependencies: ["GaugentCore", .product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Gaugent"
        ),
        .testTarget(name: "GaugentAppTests", dependencies: ["Gaugent", "GaugentCore"]),
        .testTarget(
            name: "GaugentCoreTests",
            dependencies: ["GaugentCore"],
            path: "Tests/GaugentCoreTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
