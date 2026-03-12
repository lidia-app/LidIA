import AppKit
import SwiftUI

/// An `NSPanel` subclass that never becomes the main window,
/// so the app's main window keeps focus while this panel is visible.
class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Manages the lifecycle of the floating transcript panel.
@MainActor
final class FloatingPanelController {
    private var panel: FloatingPanel?

    /// Shows the panel with the given SwiftUI root view.
    /// If the panel already exists it is simply brought to front.
    func show<V: View>(rootView: V) {
        if let panel {
            panel.orderFront(nil)
            return
        }

        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 280),
            styleMask: [.titled, .nonactivatingPanel, .utilityWindow],
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

        // Anchor to bottom-right of the main screen.
        if let screen = NSScreen.main {
            let x = screen.visibleFrame.maxX - 360 - 20
            let y = screen.visibleFrame.minY + 20
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.contentView = NSHostingView(rootView: rootView)
        panel.orderFront(nil)
        self.panel = panel
    }

    /// Closes and releases the panel.
    func close() {
        panel?.close()
        panel = nil
    }

    /// Whether the panel is currently on-screen.
    var isVisible: Bool {
        panel?.isVisible ?? false
    }
}
