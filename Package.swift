// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VoiceSmith",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "VoiceSmith",
            path: "Sources/VoiceSmith",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "VoiceSmithTests",
            dependencies: ["VoiceSmith"],
            path: "Tests/VoiceSmithTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
