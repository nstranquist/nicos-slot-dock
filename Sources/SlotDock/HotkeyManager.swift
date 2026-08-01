import AppKit
import Carbon
import SlotDockCore

/// Registers optional system-wide hotkeys (Carbon) and maps menu key equivalents.
@MainActor
final class HotkeyManager {
    enum Action: UInt32, CaseIterable {
        case toggleDock = 1
        case openSettings = 2
        case pinOpen = 3
        case quit = 4
        // 11…19 reserved for slot digits 1…9
        case slot1 = 11
        case slot2 = 12
        case slot3 = 13
        case slot4 = 14
        case slot5 = 15
        case slot6 = 16
        case slot7 = 17
        case slot8 = 18
        case slot9 = 19
    }

    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var handlerRef: EventHandlerRef?
    private var handlers: [UInt32: () -> Void] = [:]

    /// Last apply result (for Settings UI + telemetry).
    private(set) var lastReport = HotkeyRegistrationReport()

    /// Optional hook when registration fails (store publishes to Settings).
    var onReportChange: ((HotkeyRegistrationReport) -> Void)?

    deinit {
        // Best-effort; MainActor deinit may not run on main in all paths.
    }

    func invalidate() {
        unregisterAll()
        removeHandler()
        handlers.removeAll()
        lastReport = HotkeyRegistrationReport()
        onReportChange?(lastReport)
    }

    func apply(hotkeys: DockHotkeys, handlers: [Action: () -> Void]) {
        unregisterAll()
        self.handlers = Dictionary(uniqueKeysWithValues: handlers.map { ($0.key.rawValue, $0.value) })
        var report = HotkeyRegistrationReport(globalEnabled: hotkeys.globalEnabled)

        guard hotkeys.globalEnabled else {
            // Do not install a Carbon handler for an explicitly disabled feature.
            removeHandler()
            SlotDockTelemetry.hotkey.info("global hotkeys disabled")
            lastReport = report
            onReportChange?(report)
            return
        }

        let handlerOK = ensureHandlerInstalled()
        if !handlerOK {
            report.handlerInstallFailed = true
            report.handlerStatusCode = lastHandlerStatus
            lastReport = report
            onReportChange?(report)
            return
        }

        var claimed = Set<String>()

        register(hotkeys.toggleDock, id: Action.toggleDock.rawValue, report: &report, claimed: &claimed)
        register(hotkeys.openSettings, id: Action.openSettings.rawValue, report: &report, claimed: &claimed)
        register(hotkeys.pinOpen, id: Action.pinOpen.rawValue, report: &report, claimed: &claimed)
        register(hotkeys.quit, id: Action.quit.rawValue, report: &report, claimed: &claimed)

        if hotkeys.launchSlotDigits.isBound {
            for digit in 1...9 {
                var binding = hotkeys.launchSlotDigits
                binding.keyEquivalent = "\(digit)"
                register(binding, id: Action.slot1.rawValue + UInt32(digit - 1), report: &report, claimed: &claimed)
            }
        }
        report.registeredCount = hotKeyRefs.count
        lastReport = report
        onReportChange?(report)
        SlotDockTelemetry.hotkey.info(
            "global hotkeys applied refs=\(self.hotKeyRefs.count, privacy: .public) failures=\(report.failures.count, privacy: .public) digits=\(hotkeys.launchSlotDigits.isBound, privacy: .public)"
        )
        if report.hasProblems {
            SlotDockTelemetry.hotkey.warning("hotkey problems: \(report.userSummary, privacy: .private)")
        }
    }

    /// AppKit menu equivalent string + modifier mask for a binding (empty if off).
    static func menuKey(for binding: KeyBinding) -> (key: String, mask: NSEvent.ModifierFlags) {
        guard binding.isBound else { return ("", []) }
        var mask: NSEvent.ModifierFlags = []
        if binding.command { mask.insert(.command) }
        if binding.option { mask.insert(.option) }
        if binding.shift { mask.insert(.shift) }
        if binding.control { mask.insert(.control) }
        if mask.isEmpty { mask = .command }
        return (appKitKeyEquivalent(for: binding.keyEquivalent), mask)
    }

    // MARK: - Carbon

    private var lastHandlerStatus: Int32 = 0

    @discardableResult
    private func ensureHandlerInstalled() -> Bool {
        guard handlerRef == nil else { return true }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                let parameterStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard parameterStatus == noErr else { return OSStatus(eventNotHandledErr) }
                Task { @MainActor in
                    SlotDockTelemetry.hotkey.info("hotkey fire id=\(hotKeyID.id, privacy: .public)")
                    manager.handlers[hotKeyID.id]?()
                }
                return noErr
            },
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &handlerRef
        )
        lastHandlerStatus = status
        if status != noErr {
            SlotDockTelemetry.hotkey.error("hotkey handler install failed status=\(status, privacy: .public)")
            fputs("slot-dock: hotkey handler install failed status=\(status)\n", stderr)
            return false
        }
        return true
    }

    private func register(
        _ binding: KeyBinding,
        id: UInt32,
        report: inout HotkeyRegistrationReport,
        claimed: inout Set<String>
    ) {
        guard binding.isBound else { return }
        guard let keyCode = Self.carbonKeyCode(for: binding.keyEquivalent) else {
            report.failures.append(
                HotkeyRegistrationFailure(
                    actionID: id,
                    actionLabel: HotkeyRegistrationReport.label(forActionID: id),
                    statusCode: -10001,
                    message: HotkeyRegistrationReport.explainStatus(-10001)
                )
            )
            return
        }
        let modifiers = Self.carbonModifiers(for: binding)
        let claim = "\(keyCode):\(modifiers)"
        guard claimed.insert(claim).inserted else {
            report.failures.append(
                HotkeyRegistrationFailure(
                    actionID: id,
                    actionLabel: HotkeyRegistrationReport.label(forActionID: id),
                    statusCode: -10002,
                    message: HotkeyRegistrationReport.explainStatus(-10002)
                )
            )
            return
        }
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x534C444B), id: id) // 'SLDK'
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status == noErr {
            hotKeyRefs.append(hotKeyRef)
            SlotDockTelemetry.hotkey.debug("hotkey registered id=\(id, privacy: .public)")
        } else {
            let label = HotkeyRegistrationReport.label(forActionID: id)
            let message = HotkeyRegistrationReport.explainStatus(status)
            report.failures.append(
                HotkeyRegistrationFailure(
                    actionID: id,
                    actionLabel: label,
                    statusCode: status,
                    message: message
                )
            )
            SlotDockTelemetry.hotkey.warning(
                "RegisterEventHotKey id=\(id, privacy: .public) status=\(status, privacy: .public)"
            )
            fputs("slot-dock: RegisterEventHotKey id=\(id) status=\(status)\n", stderr)
        }
    }

    private func unregisterAll() {
        for ref in hotKeyRefs {
            if let ref { UnregisterEventHotKey(ref) }
        }
        hotKeyRefs.removeAll()
    }

    private func removeHandler() {
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    private static func carbonModifiers(for binding: KeyBinding) -> UInt32 {
        var mods: UInt32 = 0
        if binding.command { mods |= UInt32(cmdKey) }
        if binding.option { mods |= UInt32(optionKey) }
        if binding.shift { mods |= UInt32(shiftKey) }
        if binding.control { mods |= UInt32(controlKey) }
        if mods == 0 { mods = UInt32(cmdKey) }
        return mods
    }

    static func carbonKeyCode(for key: String) -> UInt32? {
        switch key.lowercased() {
        case "<f1>": return UInt32(kVK_F1)
        case "<f2>": return UInt32(kVK_F2)
        case "<f3>": return UInt32(kVK_F3)
        case "<f4>": return UInt32(kVK_F4)
        case "<f5>": return UInt32(kVK_F5)
        case "<f6>": return UInt32(kVK_F6)
        case "<f7>": return UInt32(kVK_F7)
        case "<f8>": return UInt32(kVK_F8)
        case "<f9>": return UInt32(kVK_F9)
        case "<f10>": return UInt32(kVK_F10)
        case "<f11>": return UInt32(kVK_F11)
        case "<f12>": return UInt32(kVK_F12)
        case "<up>": return UInt32(kVK_UpArrow)
        case "<down>": return UInt32(kVK_DownArrow)
        case "<left>": return UInt32(kVK_LeftArrow)
        case "<right>": return UInt32(kVK_RightArrow)
        case "<home>": return UInt32(kVK_Home)
        case "<end>": return UInt32(kVK_End)
        case "<pageup>": return UInt32(kVK_PageUp)
        case "<pagedown>": return UInt32(kVK_PageDown)
        case "<return>": return UInt32(kVK_Return)
        case "<tab>": return UInt32(kVK_Tab)
        case "<space>": return UInt32(kVK_Space)
        case "<delete>": return UInt32(kVK_Delete)
        case "<forwarddelete>": return UInt32(kVK_ForwardDelete)
        case "<escape>": return UInt32(kVK_Escape)
        default: break
        }
        guard let ch = key.lowercased().first else { return nil }
        switch ch {
        case "a": return UInt32(kVK_ANSI_A)
        case "b": return UInt32(kVK_ANSI_B)
        case "c": return UInt32(kVK_ANSI_C)
        case "d": return UInt32(kVK_ANSI_D)
        case "e": return UInt32(kVK_ANSI_E)
        case "f": return UInt32(kVK_ANSI_F)
        case "g": return UInt32(kVK_ANSI_G)
        case "h": return UInt32(kVK_ANSI_H)
        case "i": return UInt32(kVK_ANSI_I)
        case "j": return UInt32(kVK_ANSI_J)
        case "k": return UInt32(kVK_ANSI_K)
        case "l": return UInt32(kVK_ANSI_L)
        case "m": return UInt32(kVK_ANSI_M)
        case "n": return UInt32(kVK_ANSI_N)
        case "o": return UInt32(kVK_ANSI_O)
        case "p": return UInt32(kVK_ANSI_P)
        case "q": return UInt32(kVK_ANSI_Q)
        case "r": return UInt32(kVK_ANSI_R)
        case "s": return UInt32(kVK_ANSI_S)
        case "t": return UInt32(kVK_ANSI_T)
        case "u": return UInt32(kVK_ANSI_U)
        case "v": return UInt32(kVK_ANSI_V)
        case "w": return UInt32(kVK_ANSI_W)
        case "x": return UInt32(kVK_ANSI_X)
        case "y": return UInt32(kVK_ANSI_Y)
        case "z": return UInt32(kVK_ANSI_Z)
        case "0": return UInt32(kVK_ANSI_0)
        case "1": return UInt32(kVK_ANSI_1)
        case "2": return UInt32(kVK_ANSI_2)
        case "3": return UInt32(kVK_ANSI_3)
        case "4": return UInt32(kVK_ANSI_4)
        case "5": return UInt32(kVK_ANSI_5)
        case "6": return UInt32(kVK_ANSI_6)
        case "7": return UInt32(kVK_ANSI_7)
        case "8": return UInt32(kVK_ANSI_8)
        case "9": return UInt32(kVK_ANSI_9)
        case ",": return UInt32(kVK_ANSI_Comma)
        case ".": return UInt32(kVK_ANSI_Period)
        case "/": return UInt32(kVK_ANSI_Slash)
        case ";": return UInt32(kVK_ANSI_Semicolon)
        case "'": return UInt32(kVK_ANSI_Quote)
        case "[": return UInt32(kVK_ANSI_LeftBracket)
        case "]": return UInt32(kVK_ANSI_RightBracket)
        case "\\": return UInt32(kVK_ANSI_Backslash)
        case "-": return UInt32(kVK_ANSI_Minus)
        case "=": return UInt32(kVK_ANSI_Equal)
        case " ": return UInt32(kVK_Space)
        default: return nil
        }
    }

    private static func appKitKeyEquivalent(for key: String) -> String {
        let scalar: UInt32?
        switch key.lowercased() {
        case "<up>": scalar = 0xF700
        case "<down>": scalar = 0xF701
        case "<left>": scalar = 0xF702
        case "<right>": scalar = 0xF703
        case "<f1>": scalar = 0xF704
        case "<f2>": scalar = 0xF705
        case "<f3>": scalar = 0xF706
        case "<f4>": scalar = 0xF707
        case "<f5>": scalar = 0xF708
        case "<f6>": scalar = 0xF709
        case "<f7>": scalar = 0xF70A
        case "<f8>": scalar = 0xF70B
        case "<f9>": scalar = 0xF70C
        case "<f10>": scalar = 0xF70D
        case "<f11>": scalar = 0xF70E
        case "<f12>": scalar = 0xF70F
        case "<home>": scalar = 0xF729
        case "<end>": scalar = 0xF72B
        case "<pageup>": scalar = 0xF72C
        case "<pagedown>": scalar = 0xF72D
        case "<delete>": scalar = 0xF728
        case "<forwarddelete>": scalar = 0xF728
        case "<return>": scalar = 0x000D
        case "<tab>": scalar = 0x0009
        case "<space>": scalar = 0x0020
        case "<escape>": scalar = 0x001B
        default: scalar = nil
        }
        guard let scalar, let value = UnicodeScalar(scalar) else { return key }
        return String(value)
    }
}
