import AppKit
import SwiftUI

/// Manages a floating pill-shaped recording indicator that sits above all windows.
@MainActor
final class RecordingPillController {
    private var panel: FloatingPanel?

    private static let positionXKey = "recordingPill.position.x"
    private static let positionYKey = "recordingPill.position.y"

    func show(session: RecordingSession, onStop: @escaping () -> Void) {
        if let panel {
            panel.orderFront(nil)
            return
        }

        let pillView = RecordingPillView(session: session, onStop: onStop)

        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 56, height: 160),
            styleMask: [.nonactivatingPanel, .utilityWindow, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Restore saved position, or default to top-right
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.positionXKey) != nil {
            let x = defaults.double(forKey: Self.positionXKey)
            let y = defaults.double(forKey: Self.positionYKey)
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else if let screen = NSScreen.main {
            let x = screen.visibleFrame.maxX - 72
            let y = screen.visibleFrame.maxY - 180
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.contentView = NSHostingView(rootView: pillView)
        panel.orderFront(nil)
        self.panel = panel
    }

    func close() {
        // Save position before closing
        if let panel {
            let origin = panel.frame.origin
            UserDefaults.standard.set(origin.x, forKey: Self.positionXKey)
            UserDefaults.standard.set(origin.y, forKey: Self.positionYKey)
        }
        panel?.close()
        panel = nil
    }

    var isVisible: Bool {
        panel?.isVisible ?? false
    }
}

// MARK: - Recording Pill SwiftUI View

private struct RecordingPillView: View {
    let session: RecordingSession
    let onStop: () -> Void

    @State private var elapsed: TimeInterval = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var isPendingAutoStop: Bool {
        session.autoStopCountdown != nil
    }

    var body: some View {
        VStack(spacing: 8) {
            if isPendingAutoStop {
                autoStopCountdownView
            } else {
                normalRecordingView
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
        .glassEffect(.regular, in: .capsule)
        .onReceive(timer) { _ in
            elapsed = session.elapsedTime
        }
        .animation(.easeInOut(duration: 0.3), value: isPendingAutoStop)
    }

    // MARK: - Normal Recording

    private var normalRecordingView: some View {
        Group {
            // Pulsing red dot
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)
                .shadow(color: .red.opacity(0.6), radius: 4)
                .symbolEffect(.pulse, isActive: true)

            // Waveform
            Image(systemName: "waveform")
                .font(.caption)
                .foregroundStyle(.secondary)
                .symbolEffect(.variableColor.iterative, isActive: true)

            // Elapsed time
            Text(formatTime(elapsed))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)

            if let overrun = session.calendarOverrunMinutes {
                Text("+\(overrun)m over")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.orange)
            }

            qualityBadge

            Divider()
                .frame(width: 20)

            // Stop button
            Button {
                onStop()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Auto-Stop Countdown

    private var autoStopCountdownView: some View {
        Group {
            // Pulsing orange dot
            Circle()
                .fill(.orange)
                .frame(width: 10, height: 10)
                .shadow(color: .orange.opacity(0.6), radius: 4)
                .symbolEffect(.pulse, isActive: true)

            // Reason
            Text(session.autoStopReason ?? "Stopping")
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            // Countdown
            Text("\(session.autoStopCountdown ?? 0)s")
                .font(.system(.title3, design: .monospaced).bold())
                .foregroundStyle(.orange)

            Divider()
                .frame(width: 20)

            // Keep Recording button
            Button {
                session.cancelAutoStop()
            } label: {
                Image(systemName: "play.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            .buttonStyle(.plain)
            .help("Keep Recording")

            // Confirm Stop button
            Button {
                session.confirmAutoStop()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Stop Now")
        }
    }

    @ViewBuilder
    private var qualityBadge: some View {
        switch session.audioQualityState {
        case .good:
            Label("Good", systemImage: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.green)
        case .lowInput:
            Label("Low", systemImage: "waveform.badge.minus")
                .font(.caption2)
                .foregroundStyle(.yellow)
        case .clipping:
            Label("Hot", systemImage: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
        case .noInput:
            Label("No Input", systemImage: "mic.slash.fill")
                .font(.caption2)
                .foregroundStyle(.red)
        }
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
