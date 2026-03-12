# Dependencies

LidIA uses the following open-source libraries. We're grateful to their maintainers.

## Direct Dependencies

| Library | License | Purpose |
|---------|---------|---------|
| [WhisperKit](https://github.com/argmaxinc/WhisperKit) | MIT | Local Whisper model inference for speech-to-text |
| [FluidAudio](https://github.com/FluidInference/FluidAudio) | Apache-2.0 | Speaker diarization, VAD, and ASR via CoreML |
| [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) | MIT | On-device LLM inference using Apple MLX |

## Transitive Dependencies

| Library | License | Via |
|---------|---------|-----|
| [mlx-swift](https://github.com/ml-explore/mlx-swift) | MIT | mlx-swift-lm |
| [swift-transformers](https://github.com/huggingface/swift-transformers) | Apache-2.0 | WhisperKit, FluidAudio, mlx-swift-lm |
| [swift-argument-parser](https://github.com/apple/swift-argument-parser) | Apache-2.0 | WhisperKit |
| [swift-jinja](https://github.com/huggingface/swift-jinja) | Apache-2.0 | swift-transformers |
| [swift-collections](https://github.com/apple/swift-collections) | Apache-2.0 | swift-transformers, swift-jinja |
| [swift-crypto](https://github.com/apple/swift-crypto) | Apache-2.0 | swift-transformers |
| [swift-asn1](https://github.com/apple/swift-asn1) | Apache-2.0 | swift-crypto |
| [swift-numerics](https://github.com/apple/swift-numerics) | Apache-2.0 | mlx-swift |
| [yyjson](https://github.com/ibireme/yyjson) | MIT | swift-transformers |
