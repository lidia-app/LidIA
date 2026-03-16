// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LidIA",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v26)
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.12.0"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.1"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", revision: "6bb84aac13f76ca5e2c3ff312bc072977e684ff4"),
        .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", revision: "fcbd04daa1bf"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
        .package(path: "Packages/LidIAKit"),
        .package(url: "https://github.com/soniqo/speech-swift.git", branch: "main"),
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
                .product(name: "MLXAudioSTT", package: "mlx-audio-swift"),
                .product(name: "MLXAudioCore", package: "mlx-audio-swift"),
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "SpeechVAD", package: "speech-swift"),
            ],
            path: "Sources/LidIA",
            exclude: ["Resources/LidIA.entitlements", "Resources/Info.plist", "Resources/AppIcon.icns"],
            resources: [
                .process("Resources/Assets.xcassets"),
                .process("Resources/en.lproj"),
                .process("Resources/es.lproj"),
            ]
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
