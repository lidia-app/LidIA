import AVFoundation
import os

/// Plays WAV audio chunks sequentially without blocking the caller.
/// Enqueue data, and it plays in order. Signals when all items finish.
@MainActor
final class AudioPlaybackQueue {
    private static let logger = Logger(subsystem: "io.lidia.app", category: "AudioPlaybackQueue")

    private var queue: [Data] = []
    private var currentPlayer: AVAudioPlayer?
    private var delegate: PlaybackDelegate?
    private var isPlaying = false

    /// Continuation to signal when the queue drains completely.
    private var drainContinuation: CheckedContinuation<Void, Never>?

    /// Enqueue audio data for sequential playback. Non-blocking.
    func enqueue(_ data: Data) {
        guard !data.isEmpty else { return }
        queue.append(data)
        if !isPlaying {
            playNext()
        }
    }

    /// Wait until all queued audio has finished playing.
    func waitUntilDrained() async {
        guard isPlaying || !queue.isEmpty else { return }
        await withCheckedContinuation { cont in
            drainContinuation = cont
        }
    }

    /// Stop all playback and clear the queue.
    func stop() {
        queue.removeAll()
        currentPlayer?.stop()
        currentPlayer = nil
        delegate = nil
        isPlaying = false
        drainContinuation?.resume()
        drainContinuation = nil
    }

    private func playNext() {
        guard let data = queue.first else {
            isPlaying = false
            drainContinuation?.resume()
            drainContinuation = nil
            return
        }
        queue.removeFirst()

        do {
            let player = try AVAudioPlayer(data: data)
            self.currentPlayer = player
            player.prepareToPlay()

            let del = PlaybackDelegate { [weak self] in
                self?.onPlaybackFinished()
            }
            self.delegate = del
            player.delegate = del
            isPlaying = true
            player.play()
            Self.logger.debug("Playing chunk: \(data.count) bytes, duration: \(player.duration)s")
        } catch {
            Self.logger.error("Playback failed: \(error)")
            playNext() // Skip failed chunk, try next
        }
    }

    private func onPlaybackFinished() {
        currentPlayer = nil
        delegate = nil
        playNext()
    }
}

/// AVAudioPlayerDelegate bridge. @unchecked Sendable is safe because:
/// - Only stored property is an immutable `let` closure
/// - NSObject base class prevents compiler-synthesized Sendable conformance
private final class PlaybackDelegate: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    let onFinish: @MainActor @Sendable () -> Void
    init(onFinish: @escaping @MainActor @Sendable () -> Void) { self.onFinish = onFinish }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in onFinish() }
    }
}
