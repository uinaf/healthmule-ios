// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "HealthRelayCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .watchOS(.v11),
    ],
    products: [
        .library(name: "HealthRelayCore", targets: ["HealthRelayCore"]),
        .library(
            name: "HealthRelayCompanion",
            targets: ["HealthRelayCompanion"]
        ),
    ],
    targets: [
        .target(
            name: "HealthRelayCore",
            path: "Sources/HealthRelayCore"
        ),
        .target(
            name: "HealthRelayCompanion",
            path: "HealthRelayShared"
        ),
        .testTarget(
            name: "HealthRelayCoreTests",
            dependencies: ["HealthRelayCore", "HealthRelayCompanion"],
            path: "Tests",
            sources: ["HealthRelayCoreTests"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
