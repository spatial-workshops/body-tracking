// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BodyTracking",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0")
    ],
    targets: [
        .executableTarget(
            name: "BodyTracking",
            dependencies: [.product(name: "Yams", package: "Yams")],
            path: "Sources/BodyTracking",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
