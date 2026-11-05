// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Hitoiki",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "HitoikiCore",
            targets: ["HitoikiCore"]
        ),
        .executable(
            name: "Hitoiki",
            targets: ["Hitoiki"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "HitoikiCore",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .executableTarget(
            name: "Hitoiki",
            dependencies: ["HitoikiCore"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "HitoikiCoreTests",
            dependencies: ["HitoikiCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "HitoikiTests",
            dependencies: ["Hitoiki"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
