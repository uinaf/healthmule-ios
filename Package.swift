// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "HealthMuleCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .watchOS(.v11),
    ],
    products: [
        .library(name: "HealthMuleCore", targets: ["HealthMuleCore"]),
        .library(
            name: "HealthMuleCompanion",
            targets: ["HealthMuleCompanion"]
        ),
        .executable(
            name: "SyncStoreBenchmark",
            targets: ["SyncStoreBenchmark"]
        ),
    ],
    targets: [
        .target(
            name: "HealthMuleCore",
            path: "Sources/HealthMuleCore"
        ),
        .target(
            name: "HealthMuleCompanion",
            path: "HealthMuleShared"
        ),
        .executableTarget(
            name: "SyncStoreBenchmark",
            dependencies: ["HealthMuleCore"],
            path: "Benchmarks/SyncStoreBenchmark"
        ),
        .testTarget(
            name: "HealthMuleCoreTests",
            dependencies: ["HealthMuleCore", "HealthMuleCompanion"],
            path: "Tests",
            sources: ["HealthMuleCoreTests"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
