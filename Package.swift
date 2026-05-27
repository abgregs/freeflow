// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "FreeFlow",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "FreeFlow",
            path: "Sources/FreeFlow",
            exclude: ["Resources/Info.plist", "Resources/FreeFlow.entitlements"]
        ),
        .testTarget(
            name: "FreeFlowTests",
            dependencies: ["FreeFlow"],
            path: "Tests/FreeFlowTests"
        )
    ]
)
