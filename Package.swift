// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "HealthRelayCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "HealthRelayCore", targets: ["HealthRelayCore"]),
    ],
    targets: [
        .target(
            name: "HealthRelayCore",
            path: "Sources/HealthRelayCore"
        ),
        .testTarget(
            name: "HealthRelayCoreTests",
            dependencies: ["HealthRelayCore"],
            path: "Tests",
            sources: ["HealthRelayCoreTests"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
