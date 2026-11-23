// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "InstaBoxManager",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS("27.0")
    ],
    products: [
        .executable(
            name: "InstaBoxManager",
            targets: ["InstaBoxManager"]
        )
    ],
    targets: [
        .executableTarget(
            name: "InstaBoxManager",
            path: "Sources/InstaBoxManager",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Security"),
                .linkedFramework("WebKit"),
                .linkedFramework("Charts"),
                .linkedFramework("Network")
            ]
        )
    ]
)
