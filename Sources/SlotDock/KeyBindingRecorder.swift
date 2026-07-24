import AppKit
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

            Button("Clear") {
                binding = .unbound
                stopListening()
                onChange()
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
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
            // Ignore pure modifier presses
            let chars = event.charactersIgnoringModifiers ?? ""
            guard let first = chars.first, !event.modifierFlags.contains(.function) else {
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
                characters: String(first),
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

    private func stopListening() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        listening = false
    }
}
