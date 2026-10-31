// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Issoku",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "IssokuCore",
            targets: ["IssokuCore"]
        ),
        .executable(
            name: "Issoku",
            targets: ["Issoku"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "IssokuCore",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .executableTarget(
            name: "Issoku",
            dependencies: ["IssokuCore"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "IssokuCoreTests",
            dependencies: ["IssokuCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "IssokuTests",
            dependencies: ["Issoku"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
