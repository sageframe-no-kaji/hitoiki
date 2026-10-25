// swift-tools-version: 6.0

// The ho-01 spike harness. Its own package: the root package never references it,
// so the root build, hooks, and SwiftLint never see it. ho-02 deletes this directory.

import PackageDescription

let package = Package(
    name: "IssokuSpike",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "issoku-spike",
            path: "Sources/IssokuSpike",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
