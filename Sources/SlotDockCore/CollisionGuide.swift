import Foundation

/// Named collisions between Nicos Slot Dock and the native macOS Dock.
public struct CollisionTopic: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var slotDockSide: String
    public var systemDockSide: String
    public var recommendation: String

    public init(
        id: String,
        title: String,
        slotDockSide: String,
        systemDockSide: String,
        recommendation: String
    ) {
        self.id = id
        self.title = title
        self.slotDockSide = slotDockSide
        self.systemDockSide = systemDockSide
        self.recommendation = recommendation
    }
}

/// Actionable helper the UI can copy or run (user-triggered only).
public struct CollisionAction: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable {
        case openSystemSettings
        case appleScript
        case defaultsCommand
        case copyText
    }

    public var id: String
    public var title: String
    public var detail: String
    public var kind: Kind
    /// Script, shell snippet, or URL string for the helper.
    public var payload: String

    public init(id: String, title: String, detail: String, kind: Kind, payload: String) {
        self.id = id
        self.title = title
        self.detail = detail
        self.kind = kind
        self.payload = payload
    }
}

/// Full compatibility guide payload (pure content — no UI, no silent Dock mutation).
public struct CollisionGuide: Equatable, Sendable {
    public var title: String
    public var summary: String
    public var topics: [CollisionTopic]
    public var actions: [CollisionAction]

    public init(
        title: String = "Nicos Slot Dock & the system Dock",
        summary: String = """
        Nicos Slot Dock is an extra strip; it does not replace the macOS Dock. \
        “Turn Hiding On” / auto-hide only conceals the Dock until you move the pointer to the bottom edge — \
        macOS will still show it on hover. That is normal. \
        To stop brief bottom-edge hovers from summoning the system Dock while using Nicos Slot Dock, \
        raise the system Dock show-delay (autohide-delay) or turn off Nicos Slot Dock edge hover. \
        Fully removing the Dock process is unsupported. Actions below never run silently; you confirm each one.
        """,
        topics: [CollisionTopic] = CollisionGuide.defaultTopics,
        actions: [CollisionAction] = CollisionGuide.defaultActions
    ) {
        self.title = title
        self.summary = summary
        self.topics = topics
        self.actions = actions
    }

    public static let `default` = CollisionGuide()

    public static let defaultTopics: [CollisionTopic] = [
        CollisionTopic(
            id: "hide-system-dock",
            title: "Hide / “disable” the system Dock (what auto-hide really means)",
            slotDockSide: "Use Nicos Slot Dock as your everyday launcher strip.",
            systemDockSide: """
            “Turn Hiding On” only auto-hides the Dock. Moving the pointer to the bottom of the screen \
            still peeks the macOS Dock — Apple does not offer a supported “never show Dock” switch.
            """,
            recommendation: """
            1) Keep auto-hide ON. \
            2) Raise show-delay (autohide-delay) so a quick hover for Nicos Slot Dock does not pop the system Dock — \
            use “Raise Dock show-delay (5s)” or “Nearly never show Dock (1000s delay)” below. \
            3) Optional: turn off Nicos Slot Dock edge hover and open the strip from the menu-bar status item / pin. \
            4) To undo: “Reset Dock show-delay” and/or “Disable system Dock auto-hide”.
            """
        ),
        CollisionTopic(
            id: "autohide-still-on-hover",
            title: "Auto-hide still appears on bottom hover",
            slotDockSide: "Nicos Slot Dock also uses the bottom edge for reveal when edge hover is on.",
            systemDockSide: "Auto-hidden system Dock is designed to reappear when the cursor stays at the bottom edge.",
            recommendation: """
            This is expected, not a bug. Combine auto-hide + long autohide-delay, or disable one product’s edge reveal. \
            Long delay values (e.g. 5–1000 seconds) effectively stop accidental Dock peeks; holding the cursor long enough still works if you need the system Dock.
            """
        ),
        CollisionTopic(
            id: "bottom-strip",
            title: "Bottom edge strip",
            slotDockSide: "Nicos Slot Dock sits above the bottom edge (reveal / pin / auto-hide).",
            systemDockSide: "The system Dock also owns the bottom edge, icons, and magnification.",
            recommendation: "Auto-hide the system Dock and raise show-delay, or pin Nicos Slot Dock and shrink the system Dock."
        ),
        CollisionTopic(
            id: "auto-hide",
            title: "Auto-hide (two independent toggles)",
            slotDockSide: "Nicos Slot Dock can auto-hide and reappear on edge hover or the status menu.",
            systemDockSide: "System Dock auto-hide is separate (Desktop & Dock → Automatically hide and show the Dock).",
            recommendation: "Turn system Dock auto-hide ON so windows are not covered by a permanent Dock; then set a long show-delay so hover for Nicos Slot Dock does not also pull up the system Dock."
        ),
        CollisionTopic(
            id: "edge-hover",
            title: "Edge hover fight",
            slotDockSide: "Edge hover reveals Nicos Slot Dock near the bottom center/left/right.",
            systemDockSide: "The same bottom-edge gesture peeks the auto-hidden system Dock.",
            recommendation: "Either raise system Dock show-delay, or disable Nicos Slot Dock edge hover and use the status item / pin open."
        ),
        CollisionTopic(
            id: "app-list",
            title: "App list (merge / mirror)",
            slotDockSide: "Merge/Mirror reads your system Dock app list into Nicos Slot Dock.",
            systemDockSide: "The system Dock remains the source of truth for pinned apps.",
            recommendation: "Keep Merge if you want both; use Mirror for Dock-only; Off for custom-only. Changing system Dock apps updates Nicos Slot Dock on refresh/activate."
        ),
        CollisionTopic(
            id: "safe-area",
            title: "Window safe-area padding",
            slotDockSide: "Optional inset lifts windows so content clears the Nicos Slot Dock strip.",
            systemDockSide: "System Dock already reserves screen space when not auto-hidden.",
            recommendation: "Enable safe-area when Nicos Slot Dock is pinned or often expanded; disable restores only windows Nicos Slot Dock moved."
        ),
    ]

    public static let defaultActions: [CollisionAction] = [
        CollisionAction(
            id: "snapshot-dock-prefs",
            title: "0) Snapshot current Dock prefs",
            detail: "Saves autohide / show-delay / time-modifier to ~/.config/nicos-slot-dock/system-dock-prefs-backup.json so you can restore later. Safe; does not change the Dock.",
            kind: .copyText, // handled specially in UI as snapshot
            payload: "SNAPSHOT"
        ),
        CollisionAction(
            id: "apply-recommended",
            title: "Recommended for Nicos Slot Dock (snapshot + auto-hide + 5s delay)",
            detail: "One guided step: backup current Dock prefs (if none yet), enable auto-hide, set 5s show-delay, restart Dock. You confirm first.",
            kind: .defaultsCommand,
            payload: CollisionGuide.scriptRaiseDelay(seconds: 5)
        ),
        CollisionAction(
            id: "restore-dock-prefs",
            title: "Restore Dock prefs from snapshot",
            detail: "Re-applies the last Nicos Slot Dock backup of autohide/delay keys and restarts Dock. Disabled if no snapshot exists.",
            kind: .defaultsCommand,
            payload: "RESTORE_PLACEHOLDER"
        ),
        CollisionAction(
            id: "enable-system-autohide",
            title: "1) Auto-hide system Dock",
            detail: "Conceals the Dock until bottom-edge hover. Does NOT stop hover-to-show. Auto-snapshots first if no backup. Confirms before AppleScript.",
            kind: .appleScript,
            payload: """
            tell application "System Events"
              set autohide of dock preferences to true
            end tell
            """
        ),
        CollisionAction(
            id: "raise-dock-delay-5s",
            title: "2) Raise Dock show-delay (5s)",
            detail: "Keeps auto-hide ON but waits 5s at the bottom edge before the system Dock peeks — so Nicos Slot Dock edge hover usually wins. Auto-snapshots first if no backup.",
            kind: .defaultsCommand,
            payload: CollisionGuide.scriptRaiseDelay(seconds: 5)
        ),
        CollisionAction(
            id: "raise-dock-delay-never",
            title: "2b) Nearly never show system Dock (1000s delay)",
            detail: "Extreme delay: brief bottom hovers will not summon the Dock. You can still get it by holding the cursor at the bottom for a very long time, or reset delay below. Confirms + restarts Dock.",
            kind: .defaultsCommand,
            payload: CollisionGuide.scriptRaiseDelay(seconds: 1000)
        ),
        CollisionAction(
            id: "reset-dock-delay",
            title: "Reset Dock show-delay (default)",
            detail: "Removes custom autohide-delay / time-modifier so hover behaves like stock macOS again.",
            kind: .defaultsCommand,
            payload: """
            /usr/bin/defaults delete com.apple.dock autohide-delay 2>/dev/null
            /usr/bin/defaults delete com.apple.dock autohide-time-modifier 2>/dev/null
            /usr/bin/killall Dock
            """
        ),
        CollisionAction(
            id: "open-desktop-dock",
            title: "Open Desktop & Dock settings",
            detail: "System Settings → Desktop & Dock — toggle auto-hide, size, and position by hand.",
            kind: .openSystemSettings,
            payload: "x-apple.systempreferences:com.apple.Desktop-Settings.extension"
        ),
        CollisionAction(
            id: "shortcut-copy-hide-guide",
            title: "Copy full “hide Dock properly” guide",
            detail: "Explains auto-hide vs show-delay and copy-paste Terminal steps.",
            kind: .copyText,
            payload: CollisionGuide.hideDockShortcutGuide
        ),
        CollisionAction(
            id: "disable-system-autohide",
            title: "Disable system Dock auto-hide",
            detail: "User-triggered AppleScript: show the system Dock permanently again.",
            kind: .appleScript,
            payload: """
            tell application "System Events"
              set autohide of dock preferences to false
            end tell
            """
        ),
        CollisionAction(
            id: "defaults-autohide-on",
            title: "defaults: autohide on only (copy)",
            detail: "Shell: auto-hide without changing delay. Dock still appears on bottom hover.",
            kind: .defaultsCommand,
            payload: """
            /usr/bin/defaults write com.apple.dock autohide -bool true
            /usr/bin/killall Dock
            """
        ),
        CollisionAction(
            id: "defaults-autohide-off",
            title: "defaults: autohide off (copy)",
            detail: "Restores a always-visible system Dock via defaults + Dock restart.",
            kind: .defaultsCommand,
            payload: """
            /usr/bin/defaults write com.apple.dock autohide -bool false
            /usr/bin/defaults delete com.apple.dock autohide-delay 2>/dev/null
            /usr/bin/defaults delete com.apple.dock autohide-time-modifier 2>/dev/null
            /usr/bin/killall Dock
            """
        ),
        CollisionAction(
            id: "prompt-copy",
            title: "Copy full guidance",
            detail: "Plain-language summary for notes or sharing.",
            kind: .copyText,
            // Use static builder only — never CollisionGuide.default (would recurse via defaultActions).
            payload: CollisionGuide.buildGuidanceText(topics: CollisionGuide.defaultTopics)
        ),
    ]

    /// Shell to enable auto-hide + set hover delay (seconds before Dock peeks).
    public static func scriptRaiseDelay(seconds: Double) -> String {
        let safeSeconds = seconds.isFinite ? min(10_000, max(0, seconds)) : 5
        return """
        /usr/bin/defaults write com.apple.dock autohide -bool true
        /usr/bin/defaults write com.apple.dock autohide-delay -float \(safeSeconds)
        /usr/bin/defaults write com.apple.dock autohide-time-modifier -float 0.4
        /usr/bin/killall Dock
        """
    }

    /// Short copy-paste guide: auto-hide alone is not enough; need show-delay too.
    public static let hideDockShortcutGuide: String = """
        Stop the macOS Dock fighting Nicos Slot Dock
        ======================================

        Important
        ---------
        “Turn Hiding On” / auto-hide only HIDES the Dock until you move the pointer
        to the bottom of the screen. Hovering the bottom edge STILL shows the Dock.
        That is normal macOS behavior — not a Nicos Slot Dock bug.

        Recommended setup for Nicos Slot Dock
        --------------------------------
        1) Auto-hide the system Dock
           • Control-click the thin Dock separator → Turn Hiding On
           • or System Settings → Desktop & Dock → Automatically hide and show the Dock
           • or Nicos Slot Dock → “1) Auto-hide system Dock”

        2) Raise the show-delay so brief hovers do not peek the Dock
           Terminal (5 second delay — good daily default):
             defaults write com.apple.dock autohide -bool true
             defaults write com.apple.dock autohide-delay -float 5
             defaults write com.apple.dock autohide-time-modifier -float 0.4
             killall Dock

           Or use Nicos Slot Dock buttons:
             “2) Raise Dock show-delay (5s)”
             “2b) Nearly never show system Dock (1000s delay)”

        3) Optional: turn off Nicos Slot Dock “Edge hover” and open the strip from the
           menu-bar status item or Pin open — then the bottom edge is free for the
           system Dock when you really want it.

        Undo
        ----
        • Nicos Slot Dock → “Reset Dock show-delay (default)”
        • or: defaults delete com.apple.dock autohide-delay; killall Dock
        • “Disable system Dock auto-hide” to pin the stock Dock visible again.

        Unsupported
        -----------
        Fully killing/uninstalling Dock.app is not supported on modern macOS.
        """

    public static var fullGuidanceText: String {
        buildGuidanceText(topics: defaultTopics)
    }

    /// Build guidance without touching `default` / `defaultActions` (avoids static init recursion).
    public static func buildGuidanceText(topics: [CollisionTopic]) -> String {
        let summary = """
        Nicos Slot Dock is an extra strip; it does not replace the macOS Dock. \
        Auto-hide still peeks the Dock on bottom hover — raise autohide-delay to avoid that. \
        Use the actions only when you intend to change system Dock settings.
        """
        var lines: [String] = [
            "Nicos Slot Dock ↔ system Dock compatibility",
            "",
            summary,
            "",
            hideDockShortcutGuide,
            "",
        ]
        for t in topics {
            lines.append("• \(t.title)")
            lines.append("  Nicos Slot Dock: \(t.slotDockSide)")
            lines.append("  System Dock: \(t.systemDockSide)")
            lines.append("  Try: \(t.recommendation)")
            lines.append("")
        }
        lines.append("Helpers: auto-hide; raise/reset show-delay; Desktop & Dock settings; defaults + killall Dock.")
        return lines.joined(separator: "\n")
    }

    /// Whether enabling this Nicos Slot Dock mode should surface the collision prompt.
    public static func shouldPrompt(for preferences: DockPreferences) -> Bool {
        // Edge strip + auto-hide or pin stacks with system bottom Dock.
        preferences.autoHide || preferences.pinOpen || preferences.edgeHover
    }

    /// Completeness check used by tests: required topic ids and action kinds present.
    public static func isComplete(_ guide: CollisionGuide = .default) -> Bool {
        let topicIDs = Set(guide.topics.map(\.id))
        let requiredTopics: Set<String> = [
            "hide-system-dock", "autohide-still-on-hover", "bottom-strip", "auto-hide",
            "edge-hover", "app-list", "safe-area",
        ]
        let actionIDs = Set(guide.actions.map(\.id))
        let requiredActions: Set<String> = [
            "snapshot-dock-prefs", "restore-dock-prefs", "apply-recommended",
            "enable-system-autohide", "raise-dock-delay-5s", "raise-dock-delay-never", "reset-dock-delay",
        ]
        guard requiredActions.isSubset(of: actionIDs) else { return false }
        guard requiredTopics.isSubset(of: topicIDs) else { return false }
        let kinds = Set(guide.actions.map(\.kind))
        guard kinds.contains(.openSystemSettings),
              kinds.contains(.appleScript),
              kinds.contains(.defaultsCommand)
        else { return false }
        return guide.topics.allSatisfy {
            !$0.title.isEmpty && !$0.slotDockSide.isEmpty && !$0.systemDockSide.isEmpty && !$0.recommendation.isEmpty
        }
    }
}
