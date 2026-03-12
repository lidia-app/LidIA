import SwiftUI
import FluidAudio

struct SetupWizardView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ModelManager.self) private var modelManager
    @Environment(TTSModelManager.self) private var ttsModelManager

    enum Step {
        case welcome
        case downloading
        case ready
    }

    @State private var step: Step = .welcome

    // Download selections
    @State private var downloadParakeet = true
    @State private var downloadLLM = true
    @State private var downloadTTS = true

    // Download state
    @State private var currentDownloadLabel = ""
    @State private var currentDownloadStep = 0
    @State private var totalDownloadSteps = 0
    @State private var parakeetError: String?

    private var defaultTTSModel: TTSModelManager.TTSModelInfo {
        ttsModelManager.availableModels.first!
    }

    private var parakeetModelsExist: Bool {
        AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory(for: .v3), version: .v3)
    }

    private var selectedCount: Int {
        (downloadParakeet ? 1 : 0) + (downloadLLM ? 1 : 0) + (downloadTTS ? 1 : 0)
    }

    var body: some View {
        VStack(spacing: 24) {
            switch step {
            case .welcome:
                welcomeView
            case .downloading:
                downloadingView
            case .ready:
                readyView
            }
        }
        .padding(40)
        .frame(width: 520, height: 480)
        .onAppear {
            if parakeetModelsExist {
                downloadParakeet = false
            }
            if modelManager.isModelLoaded {
                downloadLLM = false
            }
            if ttsModelManager.isTTSModelAvailable {
                downloadTTS = false
            }
        }
    }

    // MARK: - Welcome

    private var welcomeView: some View {
        VStack(spacing: 20) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("Welcome to LidIA")
                .font(.title.bold())

            VStack(alignment: .leading, spacing: 12) {
                Text("LidIA can run entirely on your Mac — your audio and meetings never leave your device.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Select which local models to download:")
                    .font(.subheadline.bold())

                VStack(alignment: .leading, spacing: 10) {
                    modelToggle(
                        isOn: $downloadParakeet,
                        icon: "waveform",
                        iconColor: .blue,
                        title: "Parakeet TDT 0.6B",
                        subtitle: "Speech-to-text for live transcription (~200 MB)",
                        alreadyDownloaded: parakeetModelsExist
                    )

                    modelToggle(
                        isOn: $downloadLLM,
                        icon: "text.badge.star",
                        iconColor: .orange,
                        title: ModelManager.defaultModel.name,
                        subtitle: "Language model for summaries & action items (~\(String(format: "%.1f", ModelManager.defaultModel.sizeGB)) GB)",
                        alreadyDownloaded: modelManager.isModelLoaded
                    )

                    modelToggle(
                        isOn: $downloadTTS,
                        icon: "speaker.wave.2",
                        iconColor: .purple,
                        title: defaultTTSModel.name,
                        subtitle: "Text-to-speech for voice assistant (\(defaultTTSModel.sizeDescription))",
                        alreadyDownloaded: ttsModelManager.isTTSModelAvailable
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 12) {
                Button(selectedCount > 0 ? "Download Selected Models" : "Continue Without Local Models") {
                    if selectedCount > 0 {
                        startDownloads()
                    } else {
                        settings.hasCompletedSetup = true
                    }
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)

                if selectedCount > 0 {
                    Button("Skip — I have my own API keys") {
                        settings.hasCompletedSetup = true
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.caption)

                    Text("Cerebras offers a free tier (1M tokens/day). DeepSeek and NVIDIA NIM are also supported.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private func modelToggle(
        isOn: Binding<Bool>,
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        alreadyDownloaded: Bool
    ) -> some View {
        HStack(spacing: 10) {
            if alreadyDownloaded {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .frame(width: 20)
            } else {
                Toggle("", isOn: isOn)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
            }

            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.subheadline.bold())
                    if alreadyDownloaded {
                        Text("Downloaded")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 8))
    }

    // MARK: - Downloading

    private var downloadingView: some View {
        VStack(spacing: 20) {
            Text("Step \(currentDownloadStep) of \(totalDownloadSteps)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(currentDownloadLabel)
                .font(.title2.bold())

            if currentDownloadLabel.contains("LLM") || currentDownloadLabel.contains(ModelManager.defaultModel.name) {
                ProgressView(value: modelManager.downloadProgress)
                    .frame(maxWidth: 300)

                Text("\(Int(modelManager.downloadProgress * 100))%")
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else if currentDownloadLabel.contains("TTS") {
                if ttsModelManager.downloadProgress > 0 && ttsModelManager.downloadProgress < 1 {
                    ProgressView(value: ttsModelManager.downloadProgress)
                        .frame(maxWidth: 300)
                } else {
                    ProgressView()
                        .controlSize(.large)
                }
            } else {
                ProgressView()
                    .controlSize(.large)

                Text("This may take a minute...")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if let error = parakeetError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)

                Button("Retry") {
                    parakeetError = nil
                    startDownloads()
                }
                .buttonStyle(.glass)
            }

            if let error = modelManager.downloadError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)

                Button("Retry") {
                    startDownloads()
                }
                .buttonStyle(.glass)
            }

            if let error = ttsModelManager.downloadError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)

                Button("Retry") {
                    startDownloads()
                }
                .buttonStyle(.glass)
            }

            Button("Cancel") {
                modelManager.cancelDownload()
                step = .welcome
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Ready

    private var readyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("All Set!")
                .font(.title.bold())

            VStack(alignment: .leading, spacing: 8) {
                if parakeetModelsExist {
                    Label("Parakeet TDT ready for transcription", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                }
                if modelManager.isModelLoaded {
                    Label("\(ModelManager.defaultModel.name) ready for summaries", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                }
                if ttsModelManager.isTTSModelAvailable {
                    Label("\(defaultTTSModel.name) ready for voice assistant", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                }
            }
            .font(.subheadline)

            Text("Everything runs locally on your Mac. No data leaves your device.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Start Using LidIA") {
                if modelManager.isModelLoaded {
                    settings.llmProvider = .mlx
                    settings.selectedMLXModelID = ModelManager.defaultModel.id
                }
                settings.hasCompletedSetup = true
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
    }

    // MARK: - Download Orchestration

    private func startDownloads() {
        let steps = selectedCount
        guard steps > 0 else {
            settings.hasCompletedSetup = true
            return
        }

        totalDownloadSteps = steps
        currentDownloadStep = 0
        step = .downloading

        Task {
            // Step 1: Parakeet (if selected)
            if downloadParakeet && !parakeetModelsExist {
                currentDownloadStep += 1
                currentDownloadLabel = "Downloading Parakeet TDT"
                do {
                    try await AsrModels.download(version: .v3)
                    let streamingDir = ParakeetEngine.streamingModelsDirectory()
                    try await ParakeetEngine.downloadStreamingModelsIfNeeded(to: streamingDir)
                } catch {
                    parakeetError = error.localizedDescription
                    return
                }
            }

            // Step 2: LLM (if selected)
            if downloadLLM && !modelManager.isModelLoaded {
                currentDownloadStep += 1
                currentDownloadLabel = "Downloading \(ModelManager.defaultModel.name)"
                modelManager.downloadModel(ModelManager.defaultModel.id)

                // Wait for LLM download to finish
                while modelManager.isDownloading {
                    try? await Task.sleep(for: .milliseconds(500))
                }
                if modelManager.downloadError != nil { return }
            }

            // Step 3: TTS (if selected)
            if downloadTTS && !ttsModelManager.isTTSModelAvailable {
                currentDownloadStep += 1
                currentDownloadLabel = "Downloading \(defaultTTSModel.name)"
                guard let ttsModel = ttsModelManager.availableModels.first else {
                    ttsModelManager.downloadError = "No TTS models available. Check your internet connection."
                    return
                }
                await ttsModelManager.download(ttsModel)
                if ttsModelManager.downloadError != nil { return }
            }

            step = .ready
        }
    }
}
