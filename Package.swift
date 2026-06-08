// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AudioLivenessDetection",
    platforms: [
        .iOS(.v13),
        .macOS(.v11),
    ],
    products: [
        .library(
            name: "AudioLivenessDetection",
            targets: ["AudioLivenessDetection"]
        ),
    ],
    targets: [
        .target(
            name: "AudioLivenessDetection",
            path: "Sources/AudioLivenessDetection"
        ),
        .testTarget(
            name: "AudioLivenessDetectionTests",
            dependencies: ["AudioLivenessDetection"],
            path: "Tests/AudioLivenessDetectionTests"
        ),
        .executableTarget(
            name: "AudioLivenessDemoCLI",
            dependencies: ["AudioLivenessDetection"],
            path: "Examples/CLI"
        ),
        .executableTarget(
            name: "AudioLivenessDemo",
            dependencies: ["AudioLivenessDetection"],
            path: "Examples/iOSDemo"
        ),
    ]
)
