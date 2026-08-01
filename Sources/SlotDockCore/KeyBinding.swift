import Foundation

/// Remappable keyboard shortcut stored with dock preferences.
/// `keyEquivalent` is a lowercase character or a canonical special token such
/// as `<f1>`, `<up>`, `<return>`, or `<escape>`.
public struct KeyBinding: Codable, Equatable, Sendable {
    /// Empty string = unbound.
    public var keyEquivalent: String
    public var command: Bool
    public var option: Bool
    public var shift: Bool
    public var control: Bool
    /// When false, neither menu nor global hotkey fires.
    public var enabled: Bool

    public init(
        keyEquivalent: String = "",
        command: Bool = true,
        option: Bool = false,
        shift: Bool = false,
        control: Bool = false,
        enabled: Bool = false
    ) {
        self.keyEquivalent = Self.normalizeKey(keyEquivalent)
        self.command = command
        self.option = option
        self.shift = shift
        self.control = control
        self.enabled = enabled
    }

    public static let unbound = KeyBinding(keyEquivalent: "", command: true, enabled: false)

    public var isBound: Bool { enabled && !keyEquivalent.isEmpty }

    /// Human-readable form e.g. `⌘⇧D` or `Off`.
    public var displayString: String {
        guard enabled, !keyEquivalent.isEmpty else { return "Off" }
        var parts = ""
        if control { parts += "⌃" }
        if option { parts += "⌥" }
        if shift { parts += "⇧" }
        if command { parts += "⌘" }
        parts += Self.displayKey(keyEquivalent)
        return parts
    }

    public static func normalizeKey(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        if specialKeys.contains(lowered) {
            return lowered
        }
        guard let first = trimmed.first else { return "" }
        // Single character only; lowercase for AppKit menu equivalents.
        return String(first).lowercased()
    }

    private static let specialKeys: Set<String> = [
        "<f1>", "<f2>", "<f3>", "<f4>", "<f5>", "<f6>",
        "<f7>", "<f8>", "<f9>", "<f10>", "<f11>", "<f12>",
        "<up>", "<down>", "<left>", "<right>",
        "<home>", "<end>", "<pageup>", "<pagedown>",
        "<return>", "<tab>", "<space>", "<delete>", "<forwarddelete>", "<escape>",
    ]

    public static func displayKey(_ key: String) -> String {
        switch key.lowercased() {
        case "<up>": return "↑"
        case "<down>": return "↓"
        case "<left>": return "←"
        case "<right>": return "→"
        case "<return>": return "↩"
        case "<tab>": return "⇥"
        case "<space>": return "Space"
        case "<delete>": return "⌫"
        case "<forwarddelete>": return "⌦"
        case "<escape>": return "Esc"
        case "<pageup>": return "Page Up"
        case "<pagedown>": return "Page Down"
        default: return key.uppercased()
        }
    }

    /// Build from an `NSEvent`-like character + modifier flags (bit layout free of AppKit).
    public static func fromCapture(
        characters: String,
        command: Bool,
        option: Bool,
        shift: Bool,
        control: Bool
    ) -> KeyBinding {
        KeyBinding(
            keyEquivalent: characters,
            command: command,
            option: option,
            shift: shift,
            control: control,
            enabled: true
        )
    }
}

/// Named shortcuts for Slot Dock actions.
public struct DockHotkeys: Codable, Equatable, Sendable {
    public var toggleDock: KeyBinding
    public var openSettings: KeyBinding
    public var pinOpen: KeyBinding
    public var quit: KeyBinding
    /// When enabled, ⌘1…⌘9 (or configured modifiers + digit) launch slots 1–9.
    public var launchSlotDigits: KeyBinding
    /// Register system-wide hotkeys (Carbon) so shortcuts work while other apps are focused.
    public var globalEnabled: Bool

    public init(
        toggleDock: KeyBinding = KeyBinding(keyEquivalent: "d", command: true, enabled: false),
        openSettings: KeyBinding = KeyBinding(keyEquivalent: ",", command: true, enabled: false),
        pinOpen: KeyBinding = KeyBinding(keyEquivalent: "p", command: true, enabled: false),
        quit: KeyBinding = KeyBinding(keyEquivalent: "q", command: true, enabled: false),
        launchSlotDigits: KeyBinding = KeyBinding(keyEquivalent: "1", command: true, enabled: false),
        globalEnabled: Bool = false
    ) {
        self.toggleDock = toggleDock
        self.openSettings = openSettings
        self.pinOpen = pinOpen
        self.quit = quit
        self.launchSlotDigits = launchSlotDigits
        self.globalEnabled = globalEnabled
    }

    public static let `default` = DockHotkeys()

    /// Whether at least one shortcut remains available as a recovery path when
    /// the strip is auto-hidden and edge/status affordances are disabled.
    public var hasEnabledBinding: Bool {
        [toggleDock, openSettings, pinOpen, quit, launchSlotDigits].contains(where: \.isBound)
    }

    /// Sensible “classic” set (matches earlier hardcoded menu keys) — still opt-in via enabled flags.
    public static let classicEnabled = DockHotkeys(
        toggleDock: KeyBinding(keyEquivalent: "d", command: true, enabled: true),
        openSettings: KeyBinding(keyEquivalent: ",", command: true, enabled: true),
        pinOpen: KeyBinding(keyEquivalent: "p", command: true, enabled: true),
        quit: KeyBinding(keyEquivalent: "q", command: true, enabled: true),
        launchSlotDigits: KeyBinding(keyEquivalent: "1", command: true, enabled: true),
        globalEnabled: false
    )

    public mutating func sanitize() {
        toggleDock.keyEquivalent = KeyBinding.normalizeKey(toggleDock.keyEquivalent)
        openSettings.keyEquivalent = KeyBinding.normalizeKey(openSettings.keyEquivalent)
        pinOpen.keyEquivalent = KeyBinding.normalizeKey(pinOpen.keyEquivalent)
        quit.keyEquivalent = KeyBinding.normalizeKey(quit.keyEquivalent)
        launchSlotDigits.keyEquivalent = KeyBinding.normalizeKey(launchSlotDigits.keyEquivalent)
        // Digits binding uses modifiers from launchSlotDigits; key char is illustrative.
        if launchSlotDigits.enabled, launchSlotDigits.keyEquivalent.isEmpty {
            launchSlotDigits.keyEquivalent = "1"
        }
    }
}
