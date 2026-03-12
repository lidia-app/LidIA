import AVFoundation
import CoreGraphics
import Foundation
import os
import ScreenCaptureKit

/// Captures system audio (what the other meeting participants say) + microphone
/// using ScreenCaptureKit's SCStream. This replaces the mic-only AVAudioEngine
/// approach for meeting recording.
@MainActor
final class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private let audioQueue = DispatchQueue(label: "io.lidia.app.systemaudio")

    /// Thread-safe continuation access from the audio callback queue.
    private nonisolated let _continuation = OSAllocatedUnfairLock<AsyncStream<AudioChunk>.Continuation?>(initialState: nil)

    /// Reference to the parent AudioCaptureManager's consolidated tap state,
    /// used to accumulate resampled samples for batch post-processing.
    /// Set once from @MainActor before startCapture(), then read from the audio callback queue.
    nonisolated(unsafe) var tapStateRef: OSAllocatedUnfairLock<AudioCaptureManager.AudioTapState>?
    nonisolated(unsafe) var shouldAccumulate: Bool = true

    nonisolated let _currentRMS = OSAllocatedUnfairLock(initialState: Float(0))
    nonisolated let _lastSampleUptime = OSAllocatedUnfairLock(initialState: Date().timeIntervalSince1970)
    nonisolated var currentRMS: Float {
        _currentRMS.withLock { $0 }
    }
    nonisolated var secondsSinceLastSample: TimeInterval {
        let last = _lastSampleUptime.withLock { $0 }
        return max(0, Date().timeIntervalSince1970 - last)
    }

    /// Starts capturing system audio (+ optionally mic) and returns an async stream of audio chunks.
    func startCapture(includeMic: Bool) async throws -> AsyncStream<AudioChunk> {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            throw SystemAudioCaptureError.screenCapturePermissionDenied
        }

        let (stream, continuation) = AsyncStream.makeStream(of: AudioChunk.self)
        _continuation.withLock { $0 = continuation }
        _lastSampleUptime.withLock { $0 = Date().timeIntervalSince1970 }

        // Get shareable content — we need a display to create a content filter
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else {
            throw SystemAudioCaptureError.noDisplay
        }

        // Create a filter that captures the entire display (we only want audio)
        let filter = SCContentFilter(display: display, excludingWindows: [])

        // Configure for audio-only capture
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 16000  // Match Whisper/Apple Speech expectations
        config.channelCount = 1
        config.captureMicrophone = includeMic

        // Minimal video to reduce overhead (can't fully disable video in SCStream)
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1) // 1 fps minimum

        let scStream = SCStream(filter: filter, configuration: config, delegate: self)
        try scStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
        if includeMic {
            try scStream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: audioQueue)
        }

        try await scStream.startCapture()
        self.stream = scStream

        return stream
    }

    func stopCapture() async {
        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil
        _continuation.withLock { cont in
            cont?.finish()
            cont = nil
        }
        _currentRMS.withLock { $0 = 0 }
    }

    // MARK: - SCStreamOutput

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        switch outputType {
        case .microphone:
            handleAudioBuffer(sampleBuffer, source: .mic)
        case .audio:
            handleAudioBuffer(sampleBuffer, source: .system)
        default:
            break
        }
    }

    private nonisolated func handleAudioBuffer(_ sampleBuffer: CMSampleBuffer, source: AudioSource) {
        do {
            try sampleBuffer.withAudioBufferList { audioBufferList, _ in
                guard let description = sampleBuffer.formatDescription?.audioStreamBasicDescription else { return }

                let sampleRate = Int(description.mSampleRate)
                let bufferPointer = audioBufferList.unsafePointer
                let bufferCount = Int(bufferPointer.pointee.mNumberBuffers)

                guard bufferCount > 0 else { return }

                let audioBuffer = bufferPointer.pointee.mBuffers
                guard let data = audioBuffer.mData else { return }
                let frameCount = Int(audioBuffer.mDataByteSize) / MemoryLayout<Float>.size

                guard frameCount > 0 else { return }

                let floatPointer = data.assumingMemoryBound(to: Float.self)
                let samples = Array(UnsafeBufferPointer(start: floatPointer, count: frameCount))

                let chunk = AudioChunk(
                    samples: samples,
                    sampleRate: sampleRate,
                    timestamp: Date().timeIntervalSince1970,
                    source: source
                )

                let rms = AudioChunk.computeRMS(samples)
                _currentRMS.withLock { $0 = rms }
                _lastSampleUptime.withLock { $0 = Date().timeIntervalSince1970 }
                _ = _continuation.withLock { $0?.yield(chunk) }

                // Accumulate resampled samples into the parent's consolidated tap state
                if shouldAccumulate, let tapState = tapStateRef {
                    let resampled = sampleRate == 16000 ? samples : AudioResampler.resample(samples, from: sampleRate, to: 16000)
                    tapState.withLock { state in
                        if source == .mic {
                            state.accumulatedMicSamples.append(contentsOf: resampled)
                        } else {
                            state.accumulatedSystemSamples.append(contentsOf: resampled)
                        }
                    }
                }
            }
        } catch {
            // Skip malformed buffers
        }
    }

    // MARK: - SCStreamDelegate

    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Logger(subsystem: "io.lidia.app", category: "SystemAudioCapture")
            .error("Stream stopped with error: \(error.localizedDescription)")
        _continuation.withLock { cont in
            cont?.finish()
            cont = nil
        }
    }
}

enum SystemAudioCaptureError: Error, LocalizedError {
    case noDisplay
    case screenCapturePermissionDenied

    var errorDescription: String? {
        switch self {
        case .noDisplay:
            "No display found for screen capture. System audio capture requires at least one active display."
        case .screenCapturePermissionDenied:
            "Screen Recording permission denied. Enable LidIA in System Settings > Privacy & Security > Screen Recording."
        }
    }
}
