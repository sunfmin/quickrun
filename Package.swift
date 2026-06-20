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
        // AppKit view layer: the floating-toolbar look (ToolbarStyle, the button
        // classes, the shared EditorToolbarContent) plus its offscreen snapshot
        // renderer. Sits between the AppKit-free model (QuickRunKit) and the app so
        // the toolbar can be built and rendered under test without launching the app.
        .target(
            name: "QuickRunUI",
            dependencies: ["QuickRunKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "QuickRun",
            dependencies: ["QuickRunKit", "QuickRunUI"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "QuickRunKitTests",
            dependencies: ["QuickRunKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "QuickRunUITests",
            dependencies: ["QuickRunUI"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
