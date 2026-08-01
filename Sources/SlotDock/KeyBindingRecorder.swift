import AppKit
import Carbon
import SlotDockCore
import SwiftUI

/// Compact remappable shortcut control for Options.
struct KeyBindingRow: View {
    let title: String
    let help: String
    @Binding var binding: KeyBinding
    var onChange: () -> Void

    @State private var listening = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                Text(help)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { binding.enabled },
                set: { on in
                    binding.enabled = on
                    if on, binding.keyEquivalent.isEmpty {
                        // leave unbound until recorded
                    }
                    onChange()
                }
            ))
            .labelsHidden()
            .help("Enable this shortcut")
            .accessibilityLabel("Enable \(title)")

            Button {
                if listening {
                    stopListening()
                } else {
                    startListening()
                }
            } label: {
                Text(listening ? "Press keys…" : binding.displayString)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .frame(minWidth: 88)
            }
            .buttonStyle(.bordered)
            .help("Click then press a new shortcut (Esc cancels)")
            .accessibilityLabel("Set \(title) shortcut")

            Button("Clear") {
                binding = .unbound
                stopListening()
                onChange()
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Clear \(title) shortcut")
        }
        .onDisappear { stopListening() }
    }

    private func startListening() {
        stopListening()
        listening = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Esc cancels without changing
            if event.keyCode == 53 {
                Task { @MainActor in stopListening() }
                return nil
            }
            let capturedKey: String
            if let special = Self.specialKey(for: event.keyCode) {
                capturedKey = special
            } else if let first = event.charactersIgnoringModifiers?.first,
                      !event.modifierFlags.contains(.function)
            {
                capturedKey = String(first)
            } else {
                return nil
            }
            // Require at least one modifier for safety (except we allow if user holds none for rare cases — require Command or Control)
            let cmd = event.modifierFlags.contains(.command)
            let opt = event.modifierFlags.contains(.option)
            let shift = event.modifierFlags.contains(.shift)
            let ctrl = event.modifierFlags.contains(.control)
            guard cmd || ctrl || opt else {
                // Nudge: refuse bare letters so everyday typing isn't bound by accident
                NSSound.beep()
                return nil
            }
            let next = KeyBinding.fromCapture(
                characters: capturedKey,
                command: cmd,
                option: opt,
                shift: shift,
                control: ctrl
            )
            Task { @MainActor in
                binding = next
                stopListening()
                onChange()
            }
            return nil
        }
    }

    private static func specialKey(for keyCode: UInt16) -> String? {
        switch Int(keyCode) {
        case kVK_F1: return "<f1>"
        case kVK_F2: return "<f2>"
        case kVK_F3: return "<f3>"
        case kVK_F4: return "<f4>"
        case kVK_F5: return "<f5>"
        case kVK_F6: return "<f6>"
        case kVK_F7: return "<f7>"
        case kVK_F8: return "<f8>"
        case kVK_F9: return "<f9>"
        case kVK_F10: return "<f10>"
        case kVK_F11: return "<f11>"
        case kVK_F12: return "<f12>"
        case kVK_UpArrow: return "<up>"
        case kVK_DownArrow: return "<down>"
        case kVK_LeftArrow: return "<left>"
        case kVK_RightArrow: return "<right>"
        case kVK_Home: return "<home>"
        case kVK_End: return "<end>"
        case kVK_PageUp: return "<pageup>"
        case kVK_PageDown: return "<pagedown>"
        case kVK_Return: return "<return>"
        case kVK_Tab: return "<tab>"
        case kVK_Space: return "<space>"
        case kVK_Delete: return "<delete>"
        case kVK_ForwardDelete: return "<forwarddelete>"
        case kVK_Escape: return "<escape>"
        default: return nil
        }
    }

    private func stopListening() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        listening = false
    }
}
