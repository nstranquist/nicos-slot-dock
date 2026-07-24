import AppKit
import SlotDockCore
import SwiftUI
import UniformTypeIdentifiers

/// Builds and pops a native `NSMenu` from a pure `SlotContextMenuModel`.
/// Faster than SwiftUI `.contextMenu` on a non-activating floating strip.
@MainActor
enum NativeContextMenu {
    static func popUp(
        model: SlotContextMenuModel,
        with event: NSEvent,
        for view: NSView,
        onAction: @escaping (SlotContextAction) -> Void
    ) {
        let menu = makeMenu(model: model, onAction: onAction)
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    static func makeMenu(
        model: SlotContextMenuModel,
        onAction: @escaping (SlotContextAction) -> Void
    ) -> NSMenu {
        let menu = NSMenu(title: model.title)
        menu.autoenablesItems = false
        for item in model.items {
            append(item, to: menu, onAction: onAction)
        }
        return menu
    }

    private static func append(
        _ item: SlotContextMenuItem,
        to menu: NSMenu,
        onAction: @escaping (SlotContextAction) -> Void
    ) {
        if item.isSeparator {
            menu.addItem(.separator())
            return
        }
        if item.isHeader {
            let header = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            return
        }
        if !item.children.isEmpty {
            let parent = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
            let sub = NSMenu(title: item.title)
            sub.autoenablesItems = false
            for child in item.children {
                append(child, to: sub, onAction: onAction)
            }
            menu.setSubmenu(sub, for: parent)
            menu.addItem(parent)
            return
        }

        let ns = NSMenuItem(title: item.title, action: #selector(ActionTarget.invoke(_:)), keyEquivalent: "")
        ns.isEnabled = item.enabled && item.action != nil
        // Toggle-on (e.g. Keep as Custom when already kept).
        if item.isOn {
            ns.state = .on
        }
        if let action = item.action {
            let target = ActionTarget(action: action, handler: onAction)
            ns.representedObject = target
            ns.target = target
            ns.action = #selector(ActionTarget.invoke(_:))
        }
        menu.addItem(ns)
    }

    private final class ActionTarget: NSObject {
        let action: SlotContextAction
        let handler: (SlotContextAction) -> Void

        init(action: SlotContextAction, handler: @escaping (SlotContextAction) -> Void) {
            self.action = action
            self.handler = handler
        }

        @objc func invoke(_ sender: Any?) {
            SlotDockTelemetry.menu.info("context action \(self.action.rawValue, privacy: .public)")
            handler(action)
        }
    }
}

/// Pasteboard type for strip custom-slot reorder drags.
enum StripDragPasteboard {
    static let slotIDType = NSPasteboard.PasteboardType("com.nstranquist.nicos-slot-dock.slot-id")
    static let utType = UTType(exportedAs: "com.nstranquist.nicos-slot-dock.slot-id")
}

/// Hit target over a strip icon:
/// - **Left press + release without move** → click (launch)
/// - **⌘ + left press + drag past threshold** (custom only) → AppKit drag-reorder
/// - **Right / control-click** → native menu
///
/// Uses pure `StripPressSession` so click-vs-drag is unit-testable and launch
/// never fires on mouseDown (which blocked SwiftUI `.draggable`).
/// Command must be held at mouseDown for drag; plain drag never steals launch.
final class StripIconHitView: NSView, NSDraggingSource {
    var slotID: String = ""
    var allowsDragReorder: Bool = false
    var onClick: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?
    var onReorderDrop: ((String) -> Void)? // dragged slot id dropped on this icon
    var onDragActiveChange: ((Bool) -> Void)?

    private var press = StripPressSession(dragThreshold: 4, allowsDrag: true, requiresCommand: true)
    private var didBeginDrag = false

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Keep pure session policy in sync with whether this icon can reorder.
    private func syncPressPolicy() {
        press.allowsDrag = allowsDragReorder
        press.requiresCommand = true
        press.dragThreshold = 4
    }

    override func mouseDown(with event: NSEvent) {
        guard event.buttonNumber == 0 else { return }
        let p = convert(event.locationInWindow, from: nil)
        didBeginDrag = false
        press.reset()
        syncPressPolicy()
        // Command gate is captured at press time (not mid-drag).
        press.noteCommandHeld(event.modifierFlags.contains(.command))
        _ = press.handle(.mouseDown(x: Double(p.x), y: Double(p.y)))
    }

    override func mouseDragged(with event: NSEvent) {
        guard event.buttonNumber == 0 else { return }
        // Policy already on press; non-draggable / no-Command stays .pressing → mouseUp clicks.
        let p = convert(event.locationInWindow, from: nil)
        let outcome = press.handle(.mouseDragged(x: Double(p.x), y: Double(p.y)))
        if outcome == .beginDrag, allowsDragReorder, !didBeginDrag, !slotID.isEmpty {
            didBeginDrag = true
            beginAppKitDrag(event: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard event.buttonNumber == 0 else { return }
        let p = convert(event.locationInWindow, from: nil)
        let outcome = press.handle(.mouseUp(x: Double(p.x), y: Double(p.y)))
        // Only launch on pure click; never after a real AppKit drag began.
        if outcome == .click, !didBeginDrag {
            onClick?()
        }
        press.reset()
        didBeginDrag = false
        onDragActiveChange?(false)
    }

    override func rightMouseDown(with event: NSEvent) {
        press.reset()
        didBeginDrag = false
        onRightClick?(event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        // Control-click
        press.reset()
        didBeginDrag = false
        onRightClick?(event)
        return nil
    }

    private func beginAppKitDrag(event: NSEvent) {
        let pb = NSPasteboard(name: .drag)
        pb.clearContents()
        pb.setString(slotID, forType: StripDragPasteboard.slotIDType)
        pb.setString(slotID, forType: .string)

        let item = NSDraggingItem(pasteboardWriter: SlotIDPasteboardWriter(slotID: slotID))
        let image = NSImage(size: bounds.size, flipped: false) { rect in
            NSColor.controlAccentColor.withAlphaComponent(0.35).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
            return true
        }
        item.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
        onDragActiveChange?(true)
    }

    // MARK: NSDraggingSource

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .move
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        press.reset()
        didBeginDrag = false
        onDragActiveChange?(false)
    }

    // MARK: NSDraggingDestination (drop other custom slots here)

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard allowsDragReorder, readDraggedSlotID(sender) != nil else { return [] }
        onDragActiveChange?(true)
        return .move
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard allowsDragReorder, readDraggedSlotID(sender) != nil else { return [] }
        return .move
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        onDragActiveChange?(false)
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        allowsDragReorder && readDraggedSlotID(sender) != nil
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let dragged = readDraggedSlotID(sender), dragged != slotID else { return false }
        onReorderDrop?(dragged)
        onDragActiveChange?(false)
        return true
    }

    private func readDraggedSlotID(_ sender: any NSDraggingInfo) -> String? {
        let pb = sender.draggingPasteboard
        if let s = pb.string(forType: StripDragPasteboard.slotIDType), !s.isEmpty { return s }
        if let s = pb.string(forType: .string), !s.isEmpty { return s }
        return nil
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect, .cursorUpdate],
                owner: self,
                userInfo: nil
            )
        )
        // Accept drops of custom slot IDs.
        registerForDraggedTypes([StripDragPasteboard.slotIDType, .string])
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }
}

/// Pasteboard writer for slot id drags.
private final class SlotIDPasteboardWriter: NSObject, NSPasteboardWriting {
    let slotID: String
    init(slotID: String) { self.slotID = slotID }

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        [StripDragPasteboard.slotIDType, .string]
    }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        slotID
    }
}

struct StripIconHitRepresentable: NSViewRepresentable {
    var slotID: String
    /// Empty clears tooltip (disabled). Uses AppKit toolTip for smooth system delay.
    var toolTip: String = ""
    var allowsDragReorder: Bool
    var onClick: () -> Void
    var onRightClick: (NSEvent) -> Void
    var onReorderDrop: (String) -> Void
    var onDragHighlight: ((Bool) -> Void)?

    func makeNSView(context: Context) -> StripIconHitView {
        let view = StripIconHitView()
        apply(view)
        return view
    }

    func updateNSView(_ nsView: StripIconHitView, context: Context) {
        apply(nsView)
    }

    private func apply(_ view: StripIconHitView) {
        view.slotID = slotID
        view.allowsDragReorder = allowsDragReorder
        view.onClick = onClick
        view.onRightClick = onRightClick
        view.onReorderDrop = onReorderDrop
        view.onDragActiveChange = onDragHighlight
        let trimmed = toolTip.trimmingCharacters(in: .whitespacesAndNewlines)
        // Only write when changed — avoids tooltip flicker / re-register thrash.
        let next: String? = trimmed.isEmpty ? nil : trimmed
        if view.toolTip != next {
            view.toolTip = next
        }
    }
}
