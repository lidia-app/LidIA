import Foundation
import MLXAudioTTS
import MLXLMCommon
import os

/// Manages downloading and lifecycle of TTS models from HuggingFace.
@MainActor @Observable
final class TTSModelManager {
    private static let logger = Logger(subsystem: "io.lidia.app", category: "TTSModelManager")

    struct TTSModelInfo: Identifiable, Sendable {
        let id: String              // HuggingFace repo ID
        let name: String            // Display name
        let sizeDescription: String // e.g. "≈1.3 GB"
    }

    let availableModels: [TTSModelInfo] = [
        TTSModelInfo(id: "mlx-community/Kokoro-82M-8bit",
                     name: "Kokoro 82M (Recommended)", sizeDescription: "≈150 MB"),
        TTSModelInfo(id: "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-6bit",
                     name: "Qwen3-TTS 1.7B (VoiceDesign)", sizeDescription: "≈1.3 GB"),
        TTSModelInfo(id: "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit",
                     name: "Qwen3-TTS 0.6B (faster)", sizeDescription: "≈0.6 GB"),
    ]

    private(set) var downloadedModelIDs: Set<String> = []
    var downloadProgress: Double = 0
    var isDownloading = false
    var downloadError: String?

    var isTTSModelAvailable: Bool { !downloadedModelIDs.isEmpty }

    init() {
        scanForDownloadedModels()
    }

    /// Download a TTS model from HuggingFace using mlx-audio-swift's TTS.loadModel().
    func download(_ model: TTSModelInfo) async {
        guard !downloadedModelIDs.contains(model.id) else { return }
        isDownloading = true
        downloadProgress = 0
        downloadError = nil

        do {
            // TTS.loadModel() downloads from HuggingFace automatically and caches locally.
            Self.logger.info("Downloading TTS model: \(model.id)")
            downloadProgress = 0.1
            _ = try await TTS.loadModel(modelRepo: model.id)
            downloadedModelIDs.insert(model.id)
            downloadProgress = 1.0
            Self.logger.info("TTS model downloaded: \(model.name)")
        } catch {
            Self.logger.error("Failed to download TTS model: \(error.localizedDescription)")
            downloadError = error.localizedDescription
        }

        isDownloading = false
    }

    /// Delete a downloaded TTS model.
    func delete(_ model: TTSModelInfo) {
        // Remove from HuggingFace cache
        let hfCacheDir = hfCacheDirectory(for: model.id)
        if FileManager.default.fileExists(atPath: hfCacheDir.path) {
            try? FileManager.default.removeItem(at: hfCacheDir)
        }
        // Also remove mlx-audio subdirectory if present
        let mlxAudioDir = mlxAudioCacheDirectory(for: model.id)
        if FileManager.default.fileExists(atPath: mlxAudioDir.path) {
            try? FileManager.default.removeItem(at: mlxAudioDir)
        }
        downloadedModelIDs.remove(model.id)
        Self.logger.info("Deleted TTS model: \(model.name)")
    }

    private func scanForDownloadedModels() {
        for model in availableModels {
            // Check both possible cache locations
            let hfDir = hfCacheDirectory(for: model.id)
            let mlxDir = mlxAudioCacheDirectory(for: model.id)
            if directoryHasFiles(at: hfDir) || directoryHasFiles(at: mlxDir) {
                downloadedModelIDs.insert(model.id)
                Self.logger.debug("Found cached TTS model: \(model.name)")
            }
        }
    }

    /// HuggingFace hub cache: ~/.cache/huggingface/hub/models--{org}--{name}
    private func hfCacheDirectory(for id: String) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let sanitized = id.replacingOccurrences(of: "/", with: "--")
        return home.appendingPathComponent(".cache/huggingface/hub/models--\(sanitized)", isDirectory: true)
    }

    /// mlx-audio cache: ~/.cache/huggingface/hub/mlx-audio/{org}_{name}
    private func mlxAudioCacheDirectory(for id: String) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let sanitized = id.replacingOccurrences(of: "/", with: "_")
        return home.appendingPathComponent(".cache/huggingface/hub/mlx-audio/\(sanitized)", isDirectory: true)
    }

    private func directoryHasFiles(at url: URL) -> Bool {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: url.path) else {
            return false
        }
        return !contents.isEmpty
    }
}
