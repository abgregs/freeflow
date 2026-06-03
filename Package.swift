// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "River",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.9.0")
    ],
    targets: [
        .executableTarget(
            name: "River",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit")
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
