// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "River",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.9.0"),
        // Auto-update for the DMG channel (planning 0009). upToNextMajor so 2.x
        // patch/minor updates flow in but a 3.0 (potential API break) is opt-in.
        .package(url: "https://github.com/sparkle-project/Sparkle", .upToNextMajor(from: "2.6.0"))
    ],
    targets: [
        .executableTarget(
            name: "River",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/River",
            exclude: ["Resources/Info.plist", "Resources/River.entitlements"]
        ),
        .testTarget(
            name: "RiverTests",
            dependencies: ["River"],
            path: "Tests/RiverTests"
        )
    ]
)
