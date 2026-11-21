// swift-tools-version: 5.9
// The kernel's pure core (Shared/Core, Foundation only) as a library, so it is tested with `swift test` in seconds
// (ARCHITECTURE.md 4). The app and the helper compile the same files into their own modules and never import ArisCore;
// Aris.xcodeproj does not use this package.
import PackageDescription

let package = Package(
    name: "ArisCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ArisCore", targets: ["ArisCore"]),
    ],
    targets: [
        .target(
            name: "ArisCore",
            path: "Shared/Core",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "ArisCoreTests",
            dependencies: ["ArisCore"],
            path: "Tests/ArisCoreTests",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
    ]
)
