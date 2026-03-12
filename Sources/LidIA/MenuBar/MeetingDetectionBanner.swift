import AppKit
import SwiftUI

/// Manages a floating Granola-style banner that appears when a meeting is detected.
/// Shows "Meeting detected — Chrome" with a Record button and dismiss X.
@MainActor
final class MeetingDetectionBannerController {
    private var panel: NSPanel?
    private var autoDismissTask: Task<Void, Never>?

    func show(appName: String, onRecord: @escaping () -> Void) {
        // Don't show if already visible
        if panel?.isVisible == true { return }

        close()

        let bannerView = MeetingDetectionBannerView(
            appName: appName,
            onRecord: { [weak self] in
                onRecord()
                self?.close()
            },
            onDismiss: { [weak self] in
                self?.close()
            }
        )

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 350, height: 60),
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

        // Position: top-center, below the menu bar
        if let screen = NSScreen.main {
            let x = screen.visibleFrame.midX - 175
            let y = screen.visibleFrame.maxY - 80
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.contentView = NSHostingView(rootView: bannerView)
        panel.orderFront(nil)
        self.panel = panel

        // Auto-dismiss after 15 seconds
        autoDismissTask?.cancel()
        autoDismissTask = Task {
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else { return }
            close()
        }
    }

    func close() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        panel?.close()
        panel = nil
    }

    var isVisible: Bool {
        panel?.isVisible ?? false
    }
}

// MARK: - Banner SwiftUI View

private struct MeetingDetectionBannerView: View {
    let appName: String
    let onRecord: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Pulsing indicator
            PulsingIndicator()

            VStack(alignment: .leading, spacing: 1) {
                Text("Meeting detected")
                    .font(.callout.bold())
                Text(appName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                onRecord()
            } label: {
                Label("Record Meeting", systemImage: "mic.fill")
                    .font(.caption2.bold())
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.small)
            .help("Start recording this meeting")

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
    }
}

// MARK: - Pulsing Indicator

private struct PulsingIndicator: View {
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(.orange)
            .frame(width: 8, height: 8)
            .shadow(color: .orange.opacity(isPulsing ? 0.8 : 0.3), radius: isPulsing ? 6 : 3)
            .scaleEffect(isPulsing ? 1.3 : 1.0)
            .animation(
                .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
    }
}
