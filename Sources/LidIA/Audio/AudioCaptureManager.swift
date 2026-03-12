@preconcurrency import AVFoundation
import Observation
import os

enum AudioCaptureError: Error, LocalizedError {
    case micPermissionDenied
    case micUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .micPermissionDenied:
            "Microphone permission denied. Grant access in System Settings > Privacy & Security > Microphone."
        case .micUnavailable(let detail):
            "Microphone unavailable: \(detail)"
        }
    }
}

enum AudioCaptureMode: String, CaseIterable, Sendable {
    case micOnly = "Microphone Only"
    case micAndSystem = "Microphone + System Audio"
}

@Observable
@MainActor
final class AudioCaptureManager {
    enum CaptureStatus: Sendable {
        case healthy
        case warning(String)
        case fallbackToMic(String)
        case failed(String)
    }

    private static let logger = Logger(subsystem: "io.lidia.app", category: "AudioCaptureManager")

    private(set) var isCapturing = false
    private(set) var isPaused = false
    private(set) var activeCaptureMode: AudioCaptureMode = .micOnly
    private(set) var captureStatus: CaptureStatus = .healthy
    private(set) var elapsedTime: TimeInterval = 0
    private var pausedDuration: TimeInterval = 0
    private var pauseStart: Date?

    /// Consolidated audio tap state under a single lock to reduce contention
    /// on the real-time audio thread.
    struct AudioTapState: Sendable {
        var rms: Float = 0
        var micRMS: Float = 0
        var systemRMS: Float = 0
        var sourceEvents: [AudioSourceEvent] = []
        var accumulatedMicSamples: [Float] = []
        var accumulatedSystemSamples: [Float] = []
    }

    nonisolated let tapState = OSAllocatedUnfairLock(initialState: AudioTapState())

    /// Latest RMS value from the audio tap (thread-safe read).
    nonisolated var currentRMS: Float {
        tapState.withLock { $0.rms }
    }

    private var micEngine: AVAudioEngine?
    private var systemCapture: SystemAudioCapture?
    private var systemForwardTask: Task<Void, Never>?
    private var rmsForwardTask: Task<Void, Never>?
    private var timer: Timer?
    private var healthTask: Task<Void, Never>?
    private var startTime: Date?

    /// Whether to accumulate resampled samples for batch post-processing.
    /// Only needed for WhisperKit batch mode; streaming engines (Parakeet, AppleSpeech)
    /// consume chunks directly from the stream.
    var shouldAccumulate = true

    private var _audioStream: AsyncStream<AudioChunk>?
    private var _continuation: AsyncStream<AudioChunk>.Continuation?

    var audioStream: AsyncStream<AudioChunk> {
        guard let stream = _audioStream else {
            return AsyncStream { $0.finish() }
        }
        return stream
    }

    func startCapture(mode: AudioCaptureMode = .micOnly) async throws {
        guard !isCapturing else { return }
        captureStatus = .healthy
        let (stream, continuation) = AsyncStream.makeStream(of: AudioChunk.self)
        _audioStream = stream
        _continuation = continuation

        switch mode {
        case .micOnly:
            try await startMicOnlyCapture()
            activeCaptureMode = .micOnly
        case .micAndSystem:
            do {
                try await startSystemAudioCapture()
                activeCaptureMode = .micAndSystem
            } catch {
                Self.logger.warning("System audio capture failed, falling back to mic only: \(error.localizedDescription)")
                captureStatus = .fallbackToMic(error.localizedDescription)
                try await startMicOnlyCapture()
                activeCaptureMode = .micOnly
            }
        }

        isCapturing = true
        isPaused = false
        pausedDuration = 0
        pauseStart = nil
        startTime = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.startTime else { return }
                let total = Date().timeIntervalSince(start)
                let currentPause = self.isPaused ? Date().timeIntervalSince(self.pauseStart ?? Date()) : 0
                self.elapsedTime = total - self.pausedDuration - currentPause
            }
        }

        if activeCaptureMode == .micAndSystem {
            startHealthWatchdog()
        }
    }

    nonisolated func drainAccumulatedMicSamples() -> [Float] {
        tapState.withLock { state in
            let drained = state.accumulatedMicSamples
            state.accumulatedMicSamples.removeAll(keepingCapacity: false)
            return drained
        }
    }

    nonisolated func drainAccumulatedSystemSamples() -> [Float] {
        tapState.withLock { state in
            let drained = state.accumulatedSystemSamples
            state.accumulatedSystemSamples.removeAll(keepingCapacity: false)
            return drained
        }
    }

    nonisolated func drainSourceEvents() -> [AudioSourceEvent] {
        tapState.withLock { state in
            let drained = state.sourceEvents
            state.sourceEvents.removeAll(keepingCapacity: true)
            return drained
        }
    }

    /// Returns the latest per-source RMS values (mic and system independently).
    nonisolated func recentPerSourceRMS() -> CaptureService.PerSourceRMS {
        tapState.withLock { state in
            CaptureService.PerSourceRMS(mic: state.micRMS, system: state.systemRMS)
        }
    }

    func pauseCapture() {
        guard isCapturing, !isPaused else { return }
        isPaused = true
        pauseStart = Date()

        // Mute the tap — remove tap so no audio flows
        micEngine?.inputNode.removeTap(onBus: 0)
        tapState.withLock { $0.rms = 0 }
    }

    func resumeCapture() {
        guard isCapturing, isPaused else { return }
        if let start = pauseStart {
            pausedDuration += Date().timeIntervalSince(start)
        }
        isPaused = false
        pauseStart = nil

        // Re-install the tap if mic engine is active
        if let engine = micEngine {
            let continuation = _continuation
            let state = tapState
            let accumulate = shouldAccumulate
            engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) {
                buffer, _ in
                guard let channelData = buffer.floatChannelData,
                      buffer.frameLength > 0 else { return }
                let sampleRate = Int(buffer.format.sampleRate)
                let samples = Array(
                    UnsafeBufferPointer(start: channelData[0], count: Int(buffer.frameLength))
                )
                let chunk = AudioChunk(samples: samples, sampleRate: sampleRate, timestamp: Date().timeIntervalSince1970, source: .mic)
                let rms = AudioChunk.computeRMS(samples)
                state.withLock { s in
                    s.rms = rms
                    s.micRMS = rms
                    s.sourceEvents.append(AudioSourceEvent(source: .mic, timestamp: chunk.timestamp, rms: rms))
                    if accumulate {
                        let resampled = AudioResampler.resample(samples, from: sampleRate, to: 16000)
                        s.accumulatedMicSamples.append(contentsOf: resampled)
                    }
                }
                continuation?.yield(chunk)
            }
        }
    }

    func stopCapture() {
        // Stop mic engine if active
        micEngine?.inputNode.removeTap(onBus: 0)
        micEngine?.stop()
        micEngine = nil

        // Stop system audio capture if active
        if let systemCapture {
            Task { await systemCapture.stopCapture() }
            self.systemCapture = nil
        }
        systemForwardTask?.cancel()
        systemForwardTask = nil
        rmsForwardTask?.cancel()
        rmsForwardTask = nil

        timer?.invalidate()
        timer = nil
        healthTask?.cancel()
        healthTask = nil

        isCapturing = false
        tapState.withLock { state in
            state.rms = 0
            state.micRMS = 0
            state.systemRMS = 0
            state.accumulatedMicSamples.removeAll(keepingCapacity: false)
            state.accumulatedSystemSamples.removeAll(keepingCapacity: false)
            state.sourceEvents.removeAll()
        }
        _continuation?.finish()
        _continuation = nil
        _audioStream = nil
    }

    // MARK: - Mic-Only Capture (AVAudioEngine)

    private func startMicOnlyCapture() async throws {
        try await checkMicPermission()
        guard let continuation = _continuation else {
            throw AudioCaptureError.micUnavailable("Audio stream not initialized")
        }

        let engine = try Self.setupMicEngine(continuation: continuation, tapState: tapState, shouldAccumulate: shouldAccumulate)
        micEngine = engine
    }

    // MARK: - System Audio + Mic Capture (ScreenCaptureKit)

    private func startSystemAudioCapture() async throws {
        let capture = SystemAudioCapture()
        capture.tapStateRef = tapState
        capture.shouldAccumulate = shouldAccumulate
        let sourceStream = try await capture.startCapture(includeMic: true)
        systemCapture = capture
        captureStatus = .healthy
        systemForwardTask?.cancel()
        guard let continuation = _continuation else {
            throw AudioCaptureError.micUnavailable("Audio stream not initialized")
        }
        let state = tapState
        systemForwardTask = Task {
            for await chunk in sourceStream {
                if Task.isCancelled { break }
                continuation.yield(chunk)
                let rms = AudioChunk.computeRMS(chunk.samples)
                state.withLock { s in
                    switch chunk.source {
                    case .mic: s.micRMS = rms
                    case .system: s.systemRMS = rms
                    case .unknown: break
                    }
                    s.sourceEvents.append(AudioSourceEvent(source: chunk.source, timestamp: chunk.timestamp, rms: rms))
                }
            }
        }

        // Forward RMS from system capture
        rmsForwardTask?.cancel()
        let captureRef = capture
        rmsForwardTask = Task.detached {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                let rms = captureRef.currentRMS
                // Note: System audio capture updates per-source RMS in the chunk handler above.
                // This forward task only updates the combined RMS for the general quality indicator.
                state.withLock { $0.rms = rms }
            }
        }
    }

    private func startHealthWatchdog() {
        healthTask?.cancel()
        healthTask = Task { [weak self] in
            guard let self else { return }
            var restartAttempted = false
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, self.isCapturing else { continue }
                guard let systemCapture = self.systemCapture else { continue }

                if systemCapture.secondsSinceLastSample > 4 {
                    if !restartAttempted {
                        restartAttempted = true
                        self.captureStatus = .warning("System audio stream stalled, retrying…")
                        Self.logger.warning("System audio stream stalled; attempting restart")
                        do {
                            try await self.restartSystemCapture()
                            self.captureStatus = .healthy
                            restartAttempted = false
                            continue
                        } catch {
                            Self.logger.error("System audio restart failed: \(error.localizedDescription)")
                        }
                    }

                    self.captureStatus = .fallbackToMic("System audio unavailable, recording microphone only.")
                    do {
                        try await self.fallbackToMicOnly()
                        return
                    } catch {
                        self.captureStatus = .failed("Audio capture failed: \(error.localizedDescription)")
                        return
                    }
                }
            }
        }
    }

    private func restartSystemCapture() async throws {
        guard isCapturing else { return }
        if let systemCapture {
            await systemCapture.stopCapture()
        }
        systemForwardTask?.cancel()
        systemForwardTask = nil
        rmsForwardTask?.cancel()
        rmsForwardTask = nil
        try await startSystemAudioCapture()
    }

    private func fallbackToMicOnly() async throws {
        guard isCapturing else { return }

        if let systemCapture {
            await systemCapture.stopCapture()
            self.systemCapture = nil
        }
        rmsForwardTask?.cancel()
        rmsForwardTask = nil

        try await checkMicPermission()
        guard let continuation = _continuation else {
            throw AudioCaptureError.micUnavailable("Audio stream not initialized")
        }
        let engine = try Self.setupMicEngine(
            continuation: continuation,
            tapState: tapState,
            shouldAccumulate: shouldAccumulate
        )
        micEngine = engine
        activeCaptureMode = .micOnly
    }

    // MARK: - Mic Permission

    private func checkMicPermission() async throws {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .denied || status == .restricted {
            throw AudioCaptureError.micPermissionDenied
        }
        if status == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if !granted {
                throw AudioCaptureError.micPermissionDenied
            }
        }
    }

    // MARK: - Engine Setup (off main actor)

    /// Setup and start the AVAudioEngine off the main actor.
    /// AVAudioEngine has internal dispatch queue requirements that
    /// conflict with running on the main thread.
    private nonisolated static func setupMicEngine(
        continuation: AsyncStream<AudioChunk>.Continuation,
        tapState: OSAllocatedUnfairLock<AudioTapState>,
        shouldAccumulate: Bool
    ) throws -> AVAudioEngine {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        // Use nil format to accept the hardware's native format.
        // installTap cannot resample — must match hardware.
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) {
            buffer, _ in

            guard let channelData = buffer.floatChannelData,
                  buffer.frameLength > 0 else { return }

            let sampleRate = Int(buffer.format.sampleRate)
            let samples = Array(
                UnsafeBufferPointer(
                    start: channelData[0],
                    count: Int(buffer.frameLength)
                )
            )
            let chunk = AudioChunk(
                samples: samples,
                sampleRate: sampleRate,
                timestamp: Date().timeIntervalSince1970,
                source: .mic
            )
            let rms = AudioChunk.computeRMS(samples)
            // Single lock acquisition for RMS + source events + optional accumulation
            tapState.withLock { state in
                state.rms = rms
                state.micRMS = rms
                state.sourceEvents.append(AudioSourceEvent(source: .mic, timestamp: chunk.timestamp, rms: rms))
                if shouldAccumulate {
                    let resampled = AudioResampler.resample(samples, from: sampleRate, to: 16000)
                    state.accumulatedMicSamples.append(contentsOf: resampled)
                }
            }
            continuation.yield(chunk)
        }

        engine.prepare()
        try engine.start()
        return engine
    }
}
