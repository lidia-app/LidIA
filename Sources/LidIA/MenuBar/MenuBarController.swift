import AppKit
import SwiftUI
import SwiftData

@MainActor
final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var clickMonitor: Any?

    func setup(
        session: RecordingSession,
        eventKitManager: EventKitManager,
        googleCalendarMonitor: GoogleCalendarMonitor,
        meetingDetector: MeetingDetector,
        settings: AppSettings,
        modelContainer: ModelContainer
    ) {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = Self.makeMenuBarIcon()
            button.action = #selector(togglePopover)
            button.target = self
        }
        self.statusItem = statusItem

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 480)
        popover.behavior = .transient
        popover.animates = true

        let menuBarView = MenuBarView()
            .environment(session)
            .environment(eventKitManager)
            .environment(googleCalendarMonitor)
            .environment(meetingDetector)
            .environment(settings)
            .modelContainer(modelContainer)

        popover.contentViewController = NSHostingController(rootView: menuBarView)
        self.popover = popover
    }

    @objc private func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            closePopover()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.closePopover()
            }
        }
    }

    private func closePopover() {
        popover?.performClose(nil)
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
        }
        clickMonitor = nil
    }

    func updateBadge(actionItemCount: Int) {
        guard let button = statusItem?.button else { return }
        button.title = actionItemCount > 0 ? " \(actionItemCount)" : ""
    }

    func showRecordingIndicator(_ isRecording: Bool) {
        guard let button = statusItem?.button else { return }
        button.image = isRecording ? Self.makeRecordingIcon() : Self.makeMenuBarIcon()
    }

    // MARK: - Custom Icon Drawing

    private static func makeMenuBarIcon() -> NSImage {
        if let icon = NSImage(named: "MenuBarIcon") {
            icon.isTemplate = true
            return icon
        }
        return drawLegacyMenuBarIcon()
    }

    /// Fallback template icon used when the asset catalog image is unavailable.
    private static func drawLegacyMenuBarIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let inset = rect.insetBy(dx: 1, dy: 1)

            // Ear outline — a C-shaped curve open to the left
            let ear = NSBezierPath()
            ear.lineWidth = 1.5
            ear.lineCapStyle = .round

            // Start bottom-left, curve up and around
            let cx = inset.midX + 1
            let cy = inset.midY
            let r: CGFloat = 7.0

            // Main ear arc (roughly 270° arc, open on the left)
            ear.appendArc(
                withCenter: NSPoint(x: cx, y: cy),
                radius: r,
                startAngle: 220,
                endAngle: -40,
                clockwise: true
            )
            NSColor.black.setStroke()
            ear.stroke()

            // Inner "canal" — a small inward hook at the bottom
            let canal = NSBezierPath()
            canal.lineWidth = 1.3
            canal.lineCapStyle = .round
            canal.move(to: NSPoint(x: cx - 1, y: cy - 2))
            canal.curve(to: NSPoint(x: cx + 1, y: cy + 2),
                        controlPoint1: NSPoint(x: cx + 3, y: cy - 1),
                        controlPoint2: NSPoint(x: cx + 3, y: cy + 1))
            canal.stroke()

            // Sound wave arcs — 2 concentric arcs to the left of the ear
            for i in 0..<2 {
                let waveR: CGFloat = CGFloat(3 + i * 3)
                let wave = NSBezierPath()
                wave.lineWidth = 1.2
                wave.lineCapStyle = .round
                wave.appendArc(
                    withCenter: NSPoint(x: cx - 3, y: cy),
                    radius: waveR,
                    startAngle: 140,
                    endAngle: 220,
                    clockwise: false
                )
                NSColor.black.withAlphaComponent(CGFloat(0.9 - Double(i) * 0.25)).setStroke()
                wave.stroke()
            }

            return true
        }
        image.isTemplate = true
        return image
    }

    /// Recording state icon: a filled circle (record dot) with small waveform bars.
    private static func makeRecordingIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            // Red record dot
            let dotRect = NSRect(x: 2, y: 6, width: 6, height: 6)
            let dot = NSBezierPath(ovalIn: dotRect)
            NSColor.red.setFill()
            dot.fill()

            // 3 waveform bars to the right
            let barWidth: CGFloat = 2.0
            let barX: CGFloat = 11
            let heights: [CGFloat] = [6, 10, 7]
            for (i, h) in heights.enumerated() {
                let x = barX + CGFloat(i) * (barWidth + 1.5)
                let y = (rect.height - h) / 2
                let bar = NSBezierPath(
                    roundedRect: NSRect(x: x, y: y, width: barWidth, height: h),
                    xRadius: barWidth / 2,
                    yRadius: barWidth / 2
                )
                NSColor.black.setFill()
                bar.fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
