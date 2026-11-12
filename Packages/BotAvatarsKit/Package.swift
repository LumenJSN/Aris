// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BotAvatarsKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "BotAvatarsKit", targets: ["BotAvatarsKit"])
    ],
    targets: [
        .target(
            name: "BotAvatarsKit",
            swiftSettings: [
                .unsafeFlags(["-Ounchecked"], .when(configuration: .release)),
            ]
        ),
        /* the harness: offscreen stills for the tests, the comparison and
           the bench; not part of the library product */
        .target(
            name: "BotAvatarsRendering",
            dependencies: ["BotAvatarsKit"],
            path: "Tools/BotAvatarsRendering"
        ),
        .executableTarget(
            name: "botavatar-still",
            dependencies: ["BotAvatarsKit", "BotAvatarsRendering"],
            path: "Tools/BotAvatarStill"
        ),
        .executableTarget(
            name: "botavatar-bench",
            dependencies: ["BotAvatarsKit"],
            path: "Tools/BotAvatarBench"
        ),
        .testTarget(
            name: "BotAvatarsKitTests",
            dependencies: ["BotAvatarsKit", "BotAvatarsRendering"]
        ),
    ]
)
