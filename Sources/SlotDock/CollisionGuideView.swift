import AppKit
import SlotDockCore
import SwiftUI

/// In-settings compatibility guide for Slot Dock vs system Dock.
struct CollisionGuideView: View {
    @ObservedObject var store: SlotDockStore
    @State private var statusMessage: String?
    @State private var backupSummary: String?
    @State private var isRunning = false

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
                    .disabled(isRunning || (action.id == "restore-dock-prefs" && !SystemDockPrefsBackup.hasBackup))
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
            let conflictWarning: String = {
                guard let saved = SystemDockPrefsBackup.load() else { return "" }
                let current = SystemDockPrefsBackup.capture(note: "conflict check")
                guard !saved.managedValuesEqual(to: current) else { return "" }
                return "The current Dock values differ from this older snapshot. Restoring will overwrite those newer values.\n\n"
            }()
            confirmAndRunShell(
                script,
                title: action.title,
                preamble: "\(conflictWarning)This restores your saved Dock prefs (autohide / delay) from:\n\(SystemDockPrefsBackup.backupURL.path)\n\n"
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
            confirmAndRunAppleScript(
                action.payload,
                title: action.title,
                ensureSnapshotNote: "before \(action.id)"
            )
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

    private func confirmAndRunAppleScript(
        _ source: String,
        title: String,
        ensureSnapshotNote: String? = nil
    ) {
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
        if let ensureSnapshotNote,
           SystemDockPrefsBackup.ensureBackupBeforeMutation(note: ensureSnapshotNote) == nil
        {
            statusMessage = "Could not save a Dock preference snapshot; nothing was changed."
            return
        }
        refreshBackupSummary()
        isRunning = true
        statusMessage = "Updating system Dock…"
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            if let script = NSAppleScript(source: source) {
                let result = script.executeAndReturnError(&error)
                if error == nil, result.stringValue?.hasPrefix("ERROR:") == true {
                    error = [NSAppleScript.errorMessage: result.stringValue ?? "AppleScript returned an error."]
                }
            } else {
                error = [NSAppleScript.errorMessage: "Could not create AppleScript."]
            }
            let message: String
            if let error {
                message = "Script error: \(error[NSAppleScript.errorMessage] ?? "unknown")"
            } else {
                message = "System Dock preference updated."
            }
            DispatchQueue.main.async {
                isRunning = false
                statusMessage = message
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
            guard SystemDockPrefsBackup.ensureBackupBeforeMutation(note: note) != nil else {
                statusMessage = "Could not save a Dock preference snapshot; nothing was changed."
                return
            }
            refreshBackupSummary()
        }
        isRunning = true
        statusMessage = "Running compatibility command…"
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/zsh")
            task.arguments = ["-c", script]
            let message: String
            do {
                try task.run()
                task.waitUntilExit()
                message = task.terminationStatus == 0
                    ? "Done. System Dock restarted."
                    : "Shell exited \(task.terminationStatus). Try Copy Only and run in Terminal."
            } catch {
                message = "Could not run shell: \(error.localizedDescription)"
            }
            DispatchQueue.main.async {
                isRunning = false
                statusMessage = message
            }
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
