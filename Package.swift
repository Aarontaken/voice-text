// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "VoiceText",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "VoiceTextCore", targets: ["VoiceTextCore"]),
        .executable(name: "VoiceTextApp", targets: ["VoiceTextApp"])
    ],
    targets: [
        .target(
            name: "VoiceTextCore"
        ),
        .executableTarget(
            name: "VoiceTextApp",
            dependencies: ["VoiceTextCore"]
        ),
        .testTarget(
            name: "VoiceTextCoreTests",
            dependencies: ["VoiceTextCore"]
        )
    ]
)
