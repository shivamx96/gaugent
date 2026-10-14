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
    targets: [
        .target(
            name: "GaugentCore",
            path: "Sources/GaugentCore"
        ),
        .executableTarget(
            name: "Gaugent",
            dependencies: ["GaugentCore"],
            path: "Sources/Gaugent"
        ),
        .testTarget(
            name: "GaugentCoreTests",
            dependencies: ["GaugentCore"],
            path: "Tests/GaugentCoreTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
