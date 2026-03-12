import AppKit
import CoreAudio
import CoreGraphics
import Observation
import os

/// Detects active calls/meetings by monitoring system-level audio: when both the
/// microphone (input) and speaker (output) are active simultaneously, a two-way
/// conversation is happening. App-agnostic — works with any meeting app, phone call,
/// or browser-based meeting.
///
/// During active recording, also polls for process/window presence of the detected
/// app since LidIA's own mic usage masks the CoreAudio idle signal.
@MainActor
@Observable
final class MeetingDetector {
    private static let logger = Logger(subsystem: "io.lidia.app", category: "MeetingDetector")

    /// The detected call/meeting context, or nil if no call is active.
    var detectedApp: DetectedApp?
    /// User dismissed the banner for the current detection.
    var isDismissed = false
    /// Fires when a detected call/meeting becomes inactive.
    var meetingAppBecameInactive = false

    struct DetectedApp: Sendable {
        let name: String
        let bundleID: String
        let pid: pid_t
    }

    private var isMonitoring = false
    private var inputListenerBlock: AudioObjectPropertyListenerBlock?
    private var outputListenerBlock: AudioObjectPropertyListenerBlock?
    private var inputDeviceID: AudioObjectID = 0
    private var outputDeviceID: AudioObjectID = 0

    /// Tracks whether mic (input) and speaker (output) are active.
    private var micActive = false
    private var outputActive = false
    /// Grace period to avoid triggering on momentary mic activations (Siri, dictation).
    private var confirmationTask: Task<Void, Never>?

    /// Task that polls whether the tracked meeting app still has visible windows.
    private var activeMonitorTask: Task<Void, Never>?
    /// The app we are actively tracking during a recording.
    private var trackedApp: DetectedApp?

    /// LidIA's own bundle ID — excluded from detection.
    private static let selfBundleID = Bundle.main.bundleIdentifier ?? "io.lidia.app"

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        // Get default input device (mic)
        inputDeviceID = getDefaultDevice(selector: kAudioHardwarePropertyDefaultInputDevice)
        // Get default output device (speaker)
        outputDeviceID = getDefaultDevice(selector: kAudioHardwarePropertyDefaultOutputDevice)

        guard inputDeviceID != 0 else {
            Self.logger.error("Could not get default input device")
            isMonitoring = false
            return
        }
        guard outputDeviceID != 0 else {
            Self.logger.error("Could not get default output device")
            isMonitoring = false
            return
        }

        // Listen for mic state changes
        inputListenerBlock = addIsRunningListener(deviceID: inputDeviceID) { [weak self] isRunning in
            Task { @MainActor [weak self] in
                self?.micActive = isRunning
                self?.evaluateCallState()
            }
        }

        // Listen for speaker state changes
        outputListenerBlock = addIsRunningListener(deviceID: outputDeviceID) { [weak self] isRunning in
            Task { @MainActor [weak self] in
                self?.outputActive = isRunning
                self?.evaluateCallState()
            }
        }

        Self.logger.info("Monitoring started — input device \(self.inputDeviceID), output device \(self.outputDeviceID)")
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        detectedApp = nil
        isDismissed = false
        micActive = false
        outputActive = false
        confirmationTask?.cancel()
        confirmationTask = nil

        removeIsRunningListener(deviceID: inputDeviceID, block: inputListenerBlock)
        inputListenerBlock = nil
        removeIsRunningListener(deviceID: outputDeviceID, block: outputListenerBlock)
        outputListenerBlock = nil

        Self.logger.info("Monitoring stopped")
    }

    /// Dismiss the current detection (user closed the banner).
    func dismiss() {
        isDismissed = true
    }

    // MARK: - Core Detection Logic

    /// Evaluates whether a call is happening: mic + speaker both active = two-way conversation.
    private func evaluateCallState() {
        if micActive && outputActive {
            // Both active — likely a call. Wait briefly to filter out transient activations.
            if detectedApp == nil && !isDismissed && confirmationTask == nil {
                confirmationTask = Task {
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    // Re-check after grace period
                    if self.micActive && self.outputActive && self.detectedApp == nil && !self.isDismissed {
                        let app = self.identifyActiveApp()
                        self.detectedApp = app
                        self.isDismissed = false
                        Self.logger.info("Call detected: \(app.name) (\(app.bundleID))")
                    }
                    self.confirmationTask = nil
                }
            }
        } else if !micActive {
            // Mic went idle — call likely ended
            confirmationTask?.cancel()
            confirmationTask = nil
            if detectedApp != nil {
                meetingAppBecameInactive = true
                Self.logger.info("Call ended (mic idle)")
            }
            detectedApp = nil
            isDismissed = false
        }
    }

    /// Try to identify which app is driving the call.
    /// Uses the frontmost app as a reasonable heuristic — during a call, the meeting app
    /// is usually in focus. Falls back to a generic label.
    private func identifyActiveApp() -> DetectedApp {
        // Check frontmost app first
        if let front = NSWorkspace.shared.frontmostApplication,
           let bundleID = front.bundleIdentifier,
           bundleID != Self.selfBundleID {
            let name = front.localizedName ?? bundleID
            return DetectedApp(name: name, bundleID: bundleID, pid: front.processIdentifier)
        }
        // Fallback: scan running apps for known meeting apps
        if let known = findKnownMeetingApp() {
            return known
        }
        // Generic fallback
        return DetectedApp(name: "Unknown App", bundleID: "unknown", pid: 0)
    }

    /// Well-known meeting/call apps — used as a secondary signal to identify the app.
    private static let knownMeetingApps: Set<String> = [
        "us.zoom.xos",
        "com.microsoft.teams2",
        "com.microsoft.teams",
        "com.tinyspeck.slackmacgap",
        "com.google.Chrome",
        "com.apple.Safari",
        "com.webex.meetingmanager",
        "com.cisco.webexmeetingsapp",
        "com.apple.FaceTime",
        "com.hnc.Discord",
        "net.whatsapp.WhatsApp",
        "com.brave.Browser",
        "org.mozilla.firefox",
        "com.microsoft.edgemac",
    ]

    private func findKnownMeetingApp() -> DetectedApp? {
        for app in NSWorkspace.shared.runningApplications {
            guard let bundleID = app.bundleIdentifier,
                  bundleID != Self.selfBundleID,
                  Self.knownMeetingApps.contains(bundleID) else { continue }
            let name = app.localizedName ?? bundleID
            return DetectedApp(name: name, bundleID: bundleID, pid: app.processIdentifier)
        }
        return nil
    }

    // MARK: - CoreAudio Helpers

    private func getDefaultDevice(selector: AudioObjectPropertySelector) -> AudioObjectID {
        var deviceID = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID
        )
        return status == noErr ? deviceID : 0
    }

    private func addIsRunningListener(
        deviceID: AudioObjectID,
        handler: @escaping @Sendable (Bool) -> Void
    ) -> AudioObjectPropertyListenerBlock {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            var isRunning: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &isRunning)
            handler(isRunning != 0)
        }
        AudioObjectAddPropertyListenerBlock(deviceID, &address, DispatchQueue.main, block)
        return block
    }

    private func removeIsRunningListener(deviceID: AudioObjectID, block: AudioObjectPropertyListenerBlock?) {
        guard let block else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(deviceID, &address, DispatchQueue.main, block)
    }

    // MARK: - Active Window/Process Monitoring (for use during recording)

    /// Begin polling for the tracked app's window/process presence.
    /// Call this when a recording starts so that we can detect the meeting ending
    /// even though LidIA's own mic usage masks the CoreAudio idle signal.
    func startActiveMonitoring() {
        trackedApp = detectedApp ?? findKnownMeetingApp()

        guard let tracked = trackedApp else {
            Self.logger.info("No app to track — active monitoring not started")
            return
        }

        Self.logger.info("Active monitoring started for \(tracked.name) (PID \(tracked.pid))")

        activeMonitorTask?.cancel()
        activeMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self else { return }

                if let freshApp = self.findKnownMeetingApp(), freshApp.bundleID != tracked.bundleID {
                    Self.logger.info("App changed to \(freshApp.name) — updating tracker")
                    self.trackedApp = freshApp
                    continue
                }

                if !self.isAppStillActive(tracked) {
                    Self.logger.info("\(tracked.name) no longer active — signalling inactive")
                    self.meetingAppBecameInactive = true
                    self.detectedApp = nil
                    return
                }
            }
        }
    }

    /// Stop active window/process monitoring (called when recording stops).
    func stopActiveMonitoring() {
        activeMonitorTask?.cancel()
        activeMonitorTask = nil
        trackedApp = nil
    }

    /// Check if the given app is still running AND has at least one visible on-screen window.
    private func isAppStillActive(_ app: DetectedApp) -> Bool {
        guard app.pid != 0 else { return false }

        let runningApps = NSWorkspace.shared.runningApplications
        let isRunning = runningApps.contains { $0.processIdentifier == app.pid && !$0.isTerminated }
        guard isRunning else {
            Self.logger.debug("\(app.name) process (PID \(app.pid)) no longer running")
            return false
        }

        // For browsers, just check process is running — can't distinguish meeting tabs
        let browserBundleIDs: Set<String> = [
            "com.google.Chrome", "com.apple.Safari", "com.brave.Browser",
            "org.mozilla.firefox", "com.microsoft.edgemac",
        ]
        if browserBundleIDs.contains(app.bundleID) {
            return true
        }

        // For native apps, check for visible windows
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[CFString: Any]] else {
            return true
        }

        let hasVisibleWindow = windowList.contains { info in
            guard let ownerPID = info[kCGWindowOwnerPID] as? pid_t,
                  ownerPID == app.pid else { return false }
            if let bounds = info[kCGWindowBounds] as? [String: CGFloat] {
                let width = bounds["Width"] ?? 0
                let height = bounds["Height"] ?? 0
                if width < 100 || height < 100 { return false }
            }
            return true
        }

        if !hasVisibleWindow {
            Self.logger.debug("\(app.name) has no visible windows")
        }
        return hasVisibleWindow
    }
}
