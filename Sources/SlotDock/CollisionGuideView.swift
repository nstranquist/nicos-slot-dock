import AppKit
import SlotDockCore
import SwiftUI

/// In-settings compatibility guide for Slot Dock vs system Dock.
struct CollisionGuideView: View {
    @ObservedObject var store: SlotDockStore
    @State private var statusMessage: String?
    @State private var backupSummary: String?

    private let guide = CollisionGuide.default

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(guide.title)
                .font(.system(size: 13, weight: .semibold))
            Text(guide.summary)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            backupCard

            // Shortcut-first card for hiding the stock Dock.
            VStack(alignment: .leading, spacing: 6) {
                Label("Hide the system Dock (shortcut guide)", systemImage: "keyboard")
                    .font(.system(size: 12, weight: .semibold))
                Text(CollisionGuide.hideDockShortcutGuide)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.orange.opacity(0.08))
            )

            ForEach(guide.topics) { topic in
                VStack(alignment: .leading, spacing: 4) {
                    Text(topic.title)
                        .font(.system(size: 12, weight: .semibold))
                    Text("Slot Dock: \(topic.slotDockSide)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("System Dock: \(topic.systemDockSide)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(topic.recommendation)
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
            }

            Text("Actions (you confirm — mutative steps auto-snapshot first if no backup)")
                .font(.system(size: 11, weight: .semibold))
                .padding(.top, 4)

            ForEach(guide.actions) { action in
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(action.title)
                            .font(.system(size: 12, weight: .medium))
                        Text(action.detail)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(buttonTitle(for: action)) {
                        run(action)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(action.id == "restore-dock-prefs" && !SystemDockPrefsBackup.hasBackup)
                }
                .padding(.vertical, 2)
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { refreshBackupSummary() }
    }

    private var backupCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("System Dock prefs backup", systemImage: "externaldrive.badge.timemachine")
                .font(.system(size: 12, weight: .semibold))
            if let backupSummary {
                Text(backupSummary)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                Text("No snapshot yet. Mutative actions will create one automatically, or use “Snapshot current Dock prefs”.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Text(SystemDockPrefsSnapshot.defaultBackupURL.path)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
        )
    }

    private func refreshBackupSummary() {
        if let snap = SystemDockPrefsBackup.load() {
            backupSummary = snap.summaryText
        } else {
            backupSummary = nil
        }
    }

    private func buttonTitle(for action: CollisionAction) -> String {
        switch action.id {
        case "snapshot-dock-prefs": return "Snapshot"
        case "restore-dock-prefs": return "Restore…"
        case "apply-recommended": return "Apply…"
        default: break
        }
        switch action.kind {
        case .openSystemSettings: return "Open"
        case .appleScript: return "Run…"
        case .defaultsCommand: return "Run…"
        case .copyText: return "Copy"
        }
    }

    private func run(_ action: CollisionAction) {
        switch action.id {
        case "snapshot-dock-prefs":
            if let snap = SystemDockPrefsBackup.saveSnapshot(note: "manual snapshot", force: true) {
                statusMessage = "Snapshot saved.\n\(snap.summaryText)"
                refreshBackupSummary()
            } else {
                statusMessage = "Could not write snapshot."
            }
            SlotDockTelemetry.preferences.info("Collision action \(action.id, privacy: .public)")
            return
        case "restore-dock-prefs":
            guard let script = SystemDockPrefsBackup.restoreScript() else {
                statusMessage = "No snapshot to restore."
                return
            }
            confirmAndRunShell(
                script,
                title: action.title,
                preamble: "This restores your saved Dock prefs (autohide / delay) from:\n\(SystemDockPrefsBackup.backupURL.path)\n\n"
            )
            SlotDockTelemetry.preferences.info("Collision action \(action.id, privacy: .public)")
            return
        case "apply-recommended":
            confirmAndRunShell(
                SystemDockRecommended.applyScript(),
                title: action.title,
                preamble: """
                Recommended setup:
                • Snapshot current Dock prefs (if none yet)
                • Auto-hide ON
                • Show-delay 5 seconds
                • Restart Dock

                """,
                ensureSnapshotNote: "before apply-recommended"
            )
            SlotDockTelemetry.preferences.info("Collision action \(action.id, privacy: .public)")
            return
        default:
            break
        }

        switch action.kind {
        case .openSystemSettings:
            store.openMacDockSettings()
            statusMessage = "Opened System Settings (Desktop & Dock)."
        case .appleScript:
            _ = SystemDockPrefsBackup.ensureBackupBeforeMutation(note: "before \(action.id)")
            refreshBackupSummary()
            confirmAndRunAppleScript(action.payload, title: action.title)
        case .defaultsCommand:
            confirmAndRunShell(
                action.payload,
                title: action.title,
                ensureSnapshotNote: "before \(action.id)"
            )
        case .copyText:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(action.payload, forType: .string)
            statusMessage = "Copied to clipboard."
        }
        SlotDockTelemetry.preferences.info("Collision action \(action.id, privacy: .public)")
    }

    private func confirmAndRunAppleScript(_ source: String, title: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = """
        This will change system Dock preferences via AppleScript (with your confirmation). \
        A prefs snapshot was saved first if none existed.

        Script:
        \(source)
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Run Script")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {
            statusMessage = "Cancelled."
            return
        }
        var error: NSDictionary?
        if let script = NSAppleScript(source: source) {
            _ = script.executeAndReturnError(&error)
            if let error {
                statusMessage = "Script error: \(error[NSAppleScript.errorMessage] ?? "unknown")"
            } else {
                statusMessage = "System Dock preference updated."
            }
        }
    }

    /// User-confirmed shell for `defaults` + `killall Dock` helpers.
    private func confirmAndRunShell(
        _ script: String,
        title: String,
        preamble: String = "",
        ensureSnapshotNote: String? = nil
    ) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = """
        \(preamble)This runs the following in a shell and restarts the Dock (killall Dock). \
        Slot Dock never does this without your OK.

        \(ensureSnapshotNote != nil ? "A snapshot of current Dock prefs will be saved first if none exists.\n\n" : "")Commands:
        \(script)
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Run")
        alert.addButton(withTitle: "Copy Only")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        if response == .alertThirdButtonReturn {
            statusMessage = "Cancelled."
            return
        }
        if response == .alertSecondButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(script, forType: .string)
            statusMessage = "Copied. Paste in Terminal if you prefer to run it yourself."
            return
        }
        if let note = ensureSnapshotNote {
            _ = SystemDockPrefsBackup.ensureBackupBeforeMutation(note: note)
            refreshBackupSummary()
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-c", script]
        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 {
                statusMessage = "Done. System Dock restarted."
            } else {
                statusMessage = "Shell exited \(task.terminationStatus). Try Copy Only and run in Terminal."
            }
        } catch {
            statusMessage = "Could not run shell: \(error.localizedDescription)"
        }
    }
}

/// One-shot modal prompt when enabling colliding features.
@MainActor
enum CollisionGuidePrompt {
    static func presentIfNeeded(store: SlotDockStore) {
        guard !store.preferences.collisionGuideDismissed else { return }
        guard CollisionGuide.shouldPrompt(for: store.preferences) else { return }

        let alert = NSAlert()
        alert.messageText = "Slot Dock and the system Dock"
        alert.informativeText = """
        Slot Dock adds a bottom strip that can stack with the macOS Dock.

        “Turn Hiding On” only auto-hides the stock Dock — moving to the bottom of the screen still peeks it. \
        That is normal. To stop brief hovers from summoning it, raise the Dock show-delay (Settings → Options → System Dock compatibility). \
        You can snapshot your current Dock prefs before any change and restore later.

        Nothing is changed until you choose an action there.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Compatibility Guide")
        alert.addButton(withTitle: "Not Now")
        alert.addButton(withTitle: "Don’t Show Again")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            store.openSettings(tab: .options)
            NotificationCenter.default.post(name: .slotDockOpenCollisionGuide, object: nil)
        case .alertThirdButtonReturn:
            store.dismissCollisionGuide()
        default:
            break
        }
    }
}

extension Notification.Name {
    static let slotDockOpenCollisionGuide = Notification.Name("slotDockOpenCollisionGuide")
}
