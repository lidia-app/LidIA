// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LidIA",
    platforms: [
        .macOS(.v26)
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.12.0"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.1"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", revision: "6bb84aac13f76ca5e2c3ff312bc072977e684ff4"),
        .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", revision: "e4910d5180aca24986e39f1d674fd42f1f8dfaa1"),
        .package(path: "Packages/LidIAKit"),
    ],
    targets: [
        .executableTarget(
            name: "LidIA",
            dependencies: [
                "WhisperKit",
                "FluidAudio",
                "LidIAKit",
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXAudioTTS", package: "mlx-audio-swift"),
                .product(name: "MLXAudioCore", package: "mlx-audio-swift"),
            ],
            path: "Sources/LidIA",
            exclude: ["Resources/LidIA.entitlements", "Resources/Info.plist", "Resources/AppIcon.icns"],
            resources: [.process("Resources/Assets.xcassets")]
        ),
        .executableTarget(
            name: "LidiaMCP",
            dependencies: [],
            path: "Sources/LidiaMCP",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "LidIATests",
            dependencies: [
                "LidIA",
                "LidIAKit",
            ],
            path: "Tests/LidIATests"
        ),
    ]
)
