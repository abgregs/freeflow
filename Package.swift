// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "River",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "River",
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
