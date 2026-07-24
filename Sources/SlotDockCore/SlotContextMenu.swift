import Foundation

/// Actions a slot (or strip chrome) context menu can request.
public enum SlotContextAction: String, Equatable, Sendable {
    case open
    case openNewInstance
    case showInFinder
    case copyPath
    case copyLabel
    case hideApplication
    case quitApplication
    case forceQuitApplication
    case removeFromSlotDock
    case importAsCustomSlot
    /// Reverse of Keep as Custom Slot (remove the durable custom keep for this path).
    case unkeepCustomSlot
    case editSlot
    case moveLeft
    case moveRight
    case openSlotsSettings
    case openOptionsSettings
    case pinOpen
    case unpinOpen
    case hideStrip
    case showStrip
    case refreshSystemDock
    /// Enable login-item for this `.app` target (fail-closed at runtime).
    case enableOpenAtLogin
    /// Remove login-item for this `.app` target.
    case disableOpenAtLogin
}

/// One row in a context menu (pure model — no AppKit).
public struct SlotContextMenuItem: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var action: SlotContextAction?
    public var enabled: Bool
    public var isDestructive: Bool
    /// When true, native menu shows a checkmark (toggle-on state).
    public var isOn: Bool
    public var isSeparator: Bool
    public var isHeader: Bool
    public var children: [SlotContextMenuItem]

    public init(
        id: String,
        title: String,
        action: SlotContextAction? = nil,
        enabled: Bool = true,
        isDestructive: Bool = false,
        isOn: Bool = false,
        isSeparator: Bool = false,
        isHeader: Bool = false,
        children: [SlotContextMenuItem] = []
    ) {
        self.id = id
        self.title = title
        self.action = action
        self.enabled = enabled
        self.isDestructive = isDestructive
        self.isOn = isOn
        self.isSeparator = isSeparator
        self.isHeader = isHeader
        self.children = children
    }

    public static func separator(id: String = UUID().uuidString) -> SlotContextMenuItem {
        SlotContextMenuItem(
            id: id,
            title: "",
            action: nil,
            enabled: false,
            isDestructive: false,
            isOn: false,
            isSeparator: true,
            isHeader: false,
            children: []
        )
    }

    public static func header(_ title: String, id: String = UUID().uuidString) -> SlotContextMenuItem {
        SlotContextMenuItem(
            id: id,
            title: title,
            action: nil,
            enabled: false,
            isDestructive: false,
            isOn: false,
            isSeparator: false,
            isHeader: true,
            children: []
        )
    }
}

/// Built menu for a strip item or chrome.
public struct SlotContextMenuModel: Equatable, Sendable {
    public var title: String
    public var items: [SlotContextMenuItem]

    public init(title: String, items: [SlotContextMenuItem]) {
        self.title = title
        self.items = items
    }

    /// Flat action list (non-separator, with action) for tests / keybinding maps.
    public var actionableItems: [SlotContextMenuItem] {
        items.flatMap { item -> [SlotContextMenuItem] in
            if item.isSeparator || item.isHeader { return [] }
            if !item.children.isEmpty {
                return item.children.filter { $0.action != nil }
            }
            return item.action != nil ? [item] : []
        }
    }
}

/// Inputs for building a per-slot menu (pure).
public struct SlotContextMenuInput: Equatable, Sendable {
    public var label: String
    public var origin: SlotComposer.Item.Origin
    public var kind: LaunchRequest.Kind
    public var isRunning: Bool
    public var canOpenNewInstance: Bool
    public var canImportAsCustom: Bool
    /// True when this strip item’s path is already a durable custom slot (Keep applied).
    public var isKeptAsCustom: Bool
    public var customIndex: Int?
    public var customCount: Int
    /// Eligible for Open at Login (`.application` + `.app` path).
    public var openAtLoginEligible: Bool
    /// Current login-item state when known; `nil` → show enable entry only.
    public var openAtLoginEnabled: Bool?

    public init(
        label: String,
        origin: SlotComposer.Item.Origin,
        kind: LaunchRequest.Kind,
        isRunning: Bool,
        canOpenNewInstance: Bool,
        canImportAsCustom: Bool,
        isKeptAsCustom: Bool = false,
        customIndex: Int?,
        customCount: Int,
        openAtLoginEligible: Bool = false,
        openAtLoginEnabled: Bool? = nil
    ) {
        self.label = label
        self.origin = origin
        self.kind = kind
        self.isRunning = isRunning
        self.canOpenNewInstance = canOpenNewInstance
        self.canImportAsCustom = canImportAsCustom
        self.isKeptAsCustom = isKeptAsCustom
        self.customIndex = customIndex
        self.customCount = customCount
        self.openAtLoginEligible = openAtLoginEligible
        self.openAtLoginEnabled = openAtLoginEnabled
    }
}

/// Pure builder for Dock-like + Slot Dock–specific right-click menus.
public enum SlotContextMenuBuilder {
    public static func buildSlotMenu(input: SlotContextMenuInput) -> SlotContextMenuModel {
        var items: [SlotContextMenuItem] = []

        items.append(
            SlotContextMenuItem(id: "open", title: "Open", action: .open)
        )
        if input.canOpenNewInstance {
            items.append(
                SlotContextMenuItem(
                    id: "open-new",
                    title: "Open New Instance",
                    action: .openNewInstance,
                    enabled: true
                )
            )
        }

        items.append(.separator(id: "sep-reveal"))
        items.append(
            SlotContextMenuItem(id: "finder", title: "Show in Finder", action: .showInFinder)
        )
        items.append(
            SlotContextMenuItem(id: "copy-path", title: "Copy Path", action: .copyPath)
        )
        items.append(
            SlotContextMenuItem(id: "copy-label", title: "Copy Name", action: .copyLabel)
        )

        // Options submenu (Dock-like)
        var options: [SlotContextMenuItem] = []
        if input.origin == .custom {
            options.append(
                SlotContextMenuItem(
                    id: "remove",
                    title: "Remove from Slot Dock",
                    action: .removeFromSlotDock,
                    isDestructive: true
                )
            )
            options.append(
                SlotContextMenuItem(id: "edit", title: "Edit Slot…", action: .editSlot)
            )
            if let idx = input.customIndex {
                options.append(
                    SlotContextMenuItem(
                        id: "move-left",
                        title: "Move Left",
                        action: .moveLeft,
                        enabled: idx > 0
                    )
                )
                options.append(
                    SlotContextMenuItem(
                        id: "move-right",
                        title: "Move Right",
                        action: .moveRight,
                        enabled: idx < input.customCount - 1
                    )
                )
            }
        } else {
            // System / running: reversible Keep as Custom toggle (check when kept; never dead-disabled).
            if input.isKeptAsCustom {
                options.append(
                    SlotContextMenuItem(
                        id: "unkeep",
                        title: "Keep as Custom Slot",
                        action: .unkeepCustomSlot,
                        enabled: true,
                        isOn: true
                    )
                )
            } else {
                options.append(
                    SlotContextMenuItem(
                        id: "import",
                        title: "Keep as Custom Slot",
                        action: .importAsCustomSlot,
                        enabled: input.canImportAsCustom,
                        isOn: false
                    )
                )
            }
            if input.origin == .systemDock {
                options.append(
                    SlotContextMenuItem(
                        id: "from-dock",
                        title: "Live from system Dock",
                        enabled: false
                    )
                )
            } else if input.origin == .running {
                options.append(
                    SlotContextMenuItem(
                        id: "from-running",
                        title: "Live running app",
                        enabled: false
                    )
                )
            }
        }
        if input.openAtLoginEligible {
            if input.openAtLoginEnabled == true {
                options.append(
                    SlotContextMenuItem(
                        id: "open-at-login-off",
                        title: "Remove from Open at Login",
                        action: .disableOpenAtLogin
                    )
                )
            } else {
                options.append(
                    SlotContextMenuItem(
                        id: "open-at-login-on",
                        title: "Open at Login",
                        action: .enableOpenAtLogin,
                        // Unknown state still offers enable; OS may prompt/fail closed.
                        enabled: true
                    )
                )
            }
        }
        items.append(.separator(id: "sep-options"))
        items.append(
            SlotContextMenuItem(
                id: "options",
                title: "Options",
                children: options
            )
        )

        if input.isRunning {
            items.append(.separator(id: "sep-running"))
            items.append(
                SlotContextMenuItem(id: "hide", title: "Hide", action: .hideApplication)
            )
            items.append(
                SlotContextMenuItem(id: "quit", title: "Quit", action: .quitApplication)
            )
            items.append(
                SlotContextMenuItem(
                    id: "force-quit",
                    title: "Force Quit",
                    action: .forceQuitApplication,
                    isDestructive: true
                )
            )
        }

        items.append(.separator(id: "sep-settings"))
        items.append(
            SlotContextMenuItem(id: "edit-slots", title: "Edit Slots…", action: .openSlotsSettings)
        )

        return SlotContextMenuModel(title: input.label, items: items)
    }

    /// Right-click on strip chrome (not a specific icon).
    public static func buildChromeMenu(
        isPinned: Bool,
        isRevealed: Bool,
        systemDockCount: Int
    ) -> SlotContextMenuModel {
        var items: [SlotContextMenuItem] = [
            SlotContextMenuItem(id: "edit-slots", title: "Edit Slots…", action: .openSlotsSettings),
            SlotContextMenuItem(id: "options", title: "All Options…", action: .openOptionsSettings),
            .separator(id: "sep-1"),
        ]
        if isPinned {
            items.append(SlotContextMenuItem(id: "unpin", title: "Unpin", action: .unpinOpen))
        } else {
            items.append(SlotContextMenuItem(id: "pin", title: "Pin Open", action: .pinOpen))
        }
        if isRevealed {
            items.append(SlotContextMenuItem(id: "hide-strip", title: "Hide Strip", action: .hideStrip))
        } else {
            items.append(SlotContextMenuItem(id: "show-strip", title: "Show Strip", action: .showStrip))
        }
        items.append(.separator(id: "sep-2"))
        items.append(
            SlotContextMenuItem(
                id: "refresh",
                title: systemDockCount > 0
                    ? "Refresh System Dock (\(systemDockCount))"
                    : "Refresh System Dock",
                action: .refreshSystemDock
            )
        )
        return SlotContextMenuModel(title: "Slot Dock", items: items)
    }

    /// Whether an app path supports “Open New Instance”.
    public static func canOpenNewInstance(kind: LaunchRequest.Kind, path: String) -> Bool {
        kind == .application && path.hasSuffix(".app") && !path.isEmpty
    }
}

// MARK: - Open at Login policy (pure)

/// Pure eligibility / path helpers for per-app Open at Login (no SM/AppKit).
public enum AppOpenAtLoginPolicy {
    /// Apple Event not permitted / System Events Automation denied (-1743).
    public static func isAutomationDenialMessage(_ message: String) -> Bool {
        let m = message.lowercased()
        if m.contains("-1743") { return true }
        if m.contains("not authorized to send apple events") { return true }
        if m.contains("not authorized"), m.contains("system events") { return true }
        return false
    }

    /// Only real application bundles are eligible.
    public static func isEligible(kind: LaunchRequest.Kind, path: String) -> Bool {
        guard kind == .application else { return false }
        let normalized = SystemDockEntry.normalizePath(path)
        guard !normalized.isEmpty else { return false }
        // Reject bare URLs mistaken as paths.
        if normalized.contains("://") { return false }
        if !normalized.hasSuffix(".app") { return false }
        return true
    }

    public static func isEligible(slot: Slot) -> Bool {
        let request = LaunchResolver.resolve(slot: slot)
        return isEligible(kind: request.kind, path: request.resolvedTarget)
    }

    /// Display name used by System Events login items (last path component without `.app`).
    public static func loginItemDisplayName(path: String) -> String {
        let base = URL(fileURLWithPath: path).lastPathComponent
        if base.hasSuffix(".app") {
            return String(base.dropLast(4))
        }
        return base
    }

    /// Match a login-item path list against a target app path (normalized).
    public static func isEnabled(targetPath: String, loginItemPaths: [String]) -> Bool {
        let key = SystemDockEntry.normalizePath(targetPath).lowercased()
        return loginItemPaths.contains { SystemDockEntry.normalizePath($0).lowercased() == key }
    }
}

// MARK: - Strip custom reorder (pure)

/// Reorder only custom slots; system Dock items are never reordered via strip drag.
public enum StripCustomReorder {
    /// Move custom slot `draggedID` so it lands at `toIndex` within the custom list.
    /// Returns new custom list or `nil` if drag is invalid (unknown id / no-op bounds).
    public static func move(
        customSlots: [Slot],
        draggedID: String,
        toIndex: Int
    ) -> [Slot]? {
        var ordered = customSlots.sorted { $0.sortOrder < $1.sortOrder }
        guard let from = ordered.firstIndex(where: { $0.id == draggedID }) else { return nil }
        let clamped = min(max(toIndex, 0), ordered.count - 1)
        guard from != clamped else { return ordered }
        let item = ordered.remove(at: from)
        ordered.insert(item, at: clamped)
        for i in ordered.indices {
            ordered[i].sortOrder = i
        }
        return ordered
    }

    /// Drop `draggedID` before `beforeID` (or at end if `beforeID` is nil / missing).
    public static func move(
        customSlots: [Slot],
        draggedID: String,
        beforeID: String?
    ) -> [Slot]? {
        let ordered = customSlots.sorted { $0.sortOrder < $1.sortOrder }
        guard ordered.contains(where: { $0.id == draggedID }) else { return nil }
        if draggedID == beforeID { return ordered }
        var toIndex = ordered.count - 1
        if let beforeID, let idx = ordered.firstIndex(where: { $0.id == beforeID }) {
            toIndex = idx
            // If removing from before the target, insertion index shifts left after remove.
            if let from = ordered.firstIndex(where: { $0.id == draggedID }), from < idx {
                toIndex = idx - 1
            }
        }
        return move(customSlots: ordered, draggedID: draggedID, toIndex: toIndex)
    }

    /// Whether a strip display item may start a strip drag-reorder.
    public static func isDraggable(origin: SlotComposer.Item.Origin) -> Bool {
        origin == .custom
    }
}

// MARK: - Press → click vs drag (pure)

/// Pure state machine: left-button press either becomes a **click** (launch) or a
/// **drag** (reorder) once movement exceeds a threshold. Used by the strip hit
/// view so mouseDown never launches while still allowing drag-reorder.
public struct StripPressSession: Equatable, Sendable {
    public enum Phase: String, Equatable, Sendable {
        case idle
        case pressing
        case dragging
        case clicked
        case cancelled
    }

    public enum Event: Equatable, Sendable {
        case mouseDown(x: Double, y: Double)
        case mouseDragged(x: Double, y: Double)
        case mouseUp(x: Double, y: Double)
        case cancel
    }

    public enum Outcome: Equatable, Sendable {
        case none
        /// Begin AppKit/dragging session for reorder.
        case beginDrag
        /// Treat as icon click (launch). Only after mouseUp without drag.
        case click
    }

    public var phase: Phase = .idle
    public var originX: Double = 0
    public var originY: Double = 0
    /// Pixel distance (points) before press becomes a drag.
    public var dragThreshold: Double = 4
    /// When false (system Dock icons / no Command), movement never enters `.dragging` —
    /// mouseUp always yields `.click` so micro-moves still launch.
    public var allowsDrag: Bool = true
    /// When true, drag only begins if Command was held at mouseDown (user-requested move).
    public var requiresCommand: Bool = true
    /// Captured at mouseDown from the event’s Command flag.
    public var commandHeldAtDown: Bool = false

    public init(
        dragThreshold: Double = 4,
        allowsDrag: Bool = true,
        requiresCommand: Bool = true
    ) {
        self.dragThreshold = dragThreshold
        self.allowsDrag = allowsDrag
        self.requiresCommand = requiresCommand
    }

    public mutating func handle(_ event: Event) -> Outcome {
        switch event {
        case .mouseDown(let x, let y):
            phase = .pressing
            originX = x
            originY = y
            // commandHeldAtDown set by caller before/after via noteCommand(_:)
            return .none

        case .mouseDragged(let x, let y):
            // Must be allowed and (if required) Command was held at press.
            guard allowsDrag else { return .none }
            if requiresCommand, !commandHeldAtDown { return .none }
            guard phase == .pressing else {
                return .none
            }
            let dx = x - originX
            let dy = y - originY
            let dist = (dx * dx + dy * dy).squareRoot()
            if dist >= dragThreshold {
                phase = .dragging
                return .beginDrag
            }
            return .none

        case .mouseUp:
            switch phase {
            case .pressing:
                phase = .clicked
                return .click
            case .dragging:
                phase = .idle
                return .none
            default:
                phase = .idle
                return .none
            }

        case .cancel:
            phase = .cancelled
            return .none
        }
    }

    public mutating func noteCommandHeld(_ held: Bool) {
        commandHeldAtDown = held
    }

    /// Reset after click/drag fully finished.
    public mutating func reset() {
        phase = .idle
        originX = 0
        originY = 0
        commandHeldAtDown = false
    }
}

// MARK: - Keep as Custom policy (pure)

/// Two-state Keep-as-Custom for non-custom strip origins.
public enum KeepAsCustomPolicy {
    public enum State: String, Equatable, Sendable {
        /// Not yet a durable custom slot — offer Keep.
        case available
        /// Path already exists as custom — offer Unkeep.
        case kept
        /// Cannot keep (no path / invalid).
        case unavailable
    }

    public static func state(
        origin: SlotComposer.Item.Origin,
        path: String,
        customSlots: [Slot]
    ) -> State {
        guard origin != .custom else { return .unavailable }
        let key = SystemDockEntry.normalizePath(path).lowercased()
        guard !key.isEmpty else { return .unavailable }
        let kept = customSlots.contains {
            SystemDockEntry.normalizePath($0.target).lowercased() == key
        }
        return kept ? .kept : .available
    }

    /// Custom slot id matching path, if any (for unkeep).
    public static func customSlotID(matchingPath path: String, customSlots: [Slot]) -> String? {
        let key = SystemDockEntry.normalizePath(path).lowercased()
        return customSlots.first {
            SystemDockEntry.normalizePath($0.target).lowercased() == key
        }?.id
    }
}
