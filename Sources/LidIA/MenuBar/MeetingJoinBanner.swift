import AppKit
import SwiftUI

/// Data for a meeting that's about to start. May or may not have a joinable link.
struct PendingMeetingBanner: Equatable {
    let eventID: String
    let title: String
    let start: Date
    let end: Date
    let meetingLink: URL?
    let attendees: [String]
}

/// Manages a persistent Granola-style floating banner that appears before meetings.
/// Shows meeting title, time, and a "Join Meeting" button that opens the link and starts recording.
@MainActor
final class MeetingJoinBannerController {
    private var panel: NSPanel?
    private var staleDismissTask: Task<Void, Never>?

    /// Currently displayed meeting ID (prevents duplicate banners).
    private(set) var currentEventID: String?

    func show(
        meeting: PendingMeetingBanner,
        onJoin: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        // Don't re-show the same meeting
        if currentEventID == meeting.eventID, panel?.isVisible == true { return }

        close()
        currentEventID = meeting.eventID

        let bannerView = MeetingJoinBannerView(
            meeting: meeting,
            onJoin: { [weak self] in
                onJoin()
                self?.close()
            },
            onDismiss: { [weak self] in
                onDismiss()
                self?.close()
            }
        )

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 56),
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

        // Position: top-center, below menu bar
        if let screen = NSScreen.main {
            let x = screen.visibleFrame.midX - 190
            let y = screen.visibleFrame.maxY - 72
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.contentView = NSHostingView(rootView: bannerView)
        panel.orderFront(nil)
        self.panel = panel

        // Auto-dismiss if the meeting has been running 30+ min with no action
        staleDismissTask?.cancel()
        let staleTimeout = meeting.start.addingTimeInterval(30 * 60).timeIntervalSinceNow
        if staleTimeout > 0 {
            staleDismissTask = Task {
                try? await Task.sleep(for: .seconds(staleTimeout))
                guard !Task.isCancelled else { return }
                close()
            }
        }
    }

    func close() {
        staleDismissTask?.cancel()
        staleDismissTask = nil
        panel?.close()
        panel = nil
        currentEventID = nil
    }

    var isVisible: Bool {
        panel?.isVisible ?? false
    }
}

// MARK: - Banner SwiftUI View

private struct MeetingJoinBannerView: View {
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    let meeting: PendingMeetingBanner
    let onJoin: () -> Void
    let onDismiss: () -> Void

    private var timeString: String {
        let start = Self.timeFormatter.string(from: meeting.start)
        let end = Self.timeFormatter.string(from: meeting.end)
        return "\(start) – \(end)"
    }

    private var hasLink: Bool { meeting.meetingLink != nil }

    private var meetingAppIcon: String {
        guard let link = meeting.meetingLink else { return "record.circle" }
        let host = link.host?.lowercased() ?? ""
        if host.contains("meet.google") { return "video.fill" }
        if host.contains("zoom") { return "video.fill" }
        if host.contains("teams") { return "person.3.fill" }
        return "link"
    }

    private var buttonTitle: String {
        hasLink ? "Join Meeting" : "Record Meeting"
    }

    private var buttonSubtitle: String {
        hasLink ? "& start recording" : "start transcription"
    }

    var body: some View {
        HStack(spacing: 0) {
            // Dismiss button
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)

            // Colored accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [.red, .orange],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 4, height: 32)
                .padding(.horizontal, 6)

            // Meeting info
            VStack(alignment: .leading, spacing: 1) {
                Text(meeting.title)
                    .font(.caption.bold())
                    .lineLimit(1)
                Text(timeString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            // Join button
            Button {
                onJoin()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: meetingAppIcon)
                        .font(.caption)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(buttonTitle)
                            .font(.caption.bold())
                        Text(buttonSubtitle)
                            .font(.system(size: 8))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
    }
}
