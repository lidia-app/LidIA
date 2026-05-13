// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LidIA",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v26)
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "1.0.0"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", "0.12.6"..<"0.13.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", branch: "main"),
        .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", branch: "main"),
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
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "MLXAudioTTS", package: "mlx-audio-swift"),
                .product(name: "MLXAudioSTT", package: "mlx-audio-swift"),
                .product(name: "MLXAudioCore", package: "mlx-audio-swift"),
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "SpeechVAD", package: "speech-swift"),
                .product(name: "SpeechEnhancement", package: "speech-swift"),
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
