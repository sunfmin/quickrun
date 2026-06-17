// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuickRun",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "QuickRunKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "QuickRun",
            dependencies: ["QuickRunKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "QuickRunKitTests",
            dependencies: ["QuickRunKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
