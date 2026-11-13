// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BodyTracking",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "BodyTracking",
            path: "Sources/BodyTracking",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
