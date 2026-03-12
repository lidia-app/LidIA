import SwiftUI
import AppKit

/// A settings row that lets the user record a custom keyboard shortcut.
/// Click "Record", press a key combo, and it saves as "option+space" format.
struct HotkeyRecorderRow: View {
    @Binding var hotkey: String
    var onChanged: (() -> Void)?

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Text("Hotkey")
            Spacer()
            if isRecording {
                Text("Press keys…")
                    .foregroundStyle(.orange)
                    .font(.system(.body, design: .rounded))
                Button("Cancel") {
                    stopRecording()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            } else {
                Text(displayString)
                    .foregroundStyle(.secondary)
                    .font(.system(.body, design: .rounded))
                Button("Change") {
                    startRecording()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            }
        }
    }

    private var displayString: String {
        let parts = hotkey.lowercased().split(separator: "+").map(String.init)
        var display: [String] = []
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            switch trimmed {
            case "control", "ctrl": display.append("⌃")
            case "option", "alt": display.append("⌥")
            case "shift": display.append("⇧")
            case "command", "cmd": display.append("⌘")
            default: display.append(trimmed.capitalized)
            }
        }
        return display.joined(separator: "")
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Ignore bare modifier keys
            guard event.keyCode != 0xFF else { return nil }

            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // Require at least one modifier
            guard !mods.isEmpty else {
                // Allow Escape to cancel
                if event.keyCode == 53 {
                    stopRecording()
                    return nil
                }
                return nil
            }

            var parts: [String] = []
            if mods.contains(.control) { parts.append("control") }
            if mods.contains(.option) { parts.append("option") }
            if mods.contains(.shift) { parts.append("shift") }
            if mods.contains(.command) { parts.append("command") }

            if let keyName = keyCodeToName(event.keyCode) {
                parts.append(keyName)
            }

            hotkey = parts.joined(separator: "+")
            stopRecording()
            onChanged?()
            return nil // swallow the event
        }
    }

    private func stopRecording() {
        isRecording = false
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    private func keyCodeToName(_ code: UInt16) -> String? {
        let map: [UInt16: String] = [
            0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
            8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
            16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p", 37: "l",
            38: "j", 39: "'", 40: "k", 41: ";", 42: "\\", 43: ",", 44: "/",
            45: "n", 46: "m", 47: ".", 48: "tab", 49: "space", 50: "`",
            36: "return", 51: "delete", 53: "escape",
            122: "f1", 120: "f2", 99: "f3", 118: "f4", 96: "f5", 94: "f6",
            98: "f7", 100: "f8", 101: "f9", 109: "f10", 103: "f11", 111: "f12",
        ]
        return map[code]
    }
}
