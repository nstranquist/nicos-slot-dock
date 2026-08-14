import AppKit
import SlotDockCore
import SwiftUI

/// Minimal edge dock strip: icons + gear + options control.
struct DockView: View {
    @ObservedObject var store: SlotDockStore
    @ObservedObject var runningApps: RunningAppsMonitor
    @ObservedObject var badges: DockBadgeMonitor
    var onHoverChange: ((Bool) -> Void)?
    var onOpenSettings: ((SlotDockStore.SettingsTab) -> Void)?
    var onShowControlsMenu: ((NSView?) -> Void)?

    private var iconSize: CGFloat { store.preferences.iconSize.pointSize }
    /// Outer chrome pad — same pure source as window `expandedStripHeight`.
    private var pad: CGFloat { store.preferences.chromeVerticalPad() }
    private var barHeight: CGFloat {
        // Content height only (window adds expandedChromeExtra); keep in sync with prefs helpers.
        let base = iconSize + pad * 2
        let labels: CGFloat = store.preferences.showLabels ? CGFloat(DockPreferences.labelRowHeight) : 0
        let dots: CGFloat = store.preferences.showRunningDots ? CGFloat(DockPreferences.runningDotRowHeight) : 0
        return base + labels + dots
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: barHeight * 0.32, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: barHeight * 0.32, style: .continuous)
                        .fill(Color.primary.opacity(0.035))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: barHeight * 0.32, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.32),
                                    Color.white.opacity(0.08),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.6
                        )
                )
                .shadow(color: .black.opacity(0.26 * contentOpacity), radius: 16, y: 7)

            HStack(spacing: store.preferences.effectiveIconSpacing()) {
                if store.displayItems.isEmpty {
                    Text("Add apps…")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .opacity(contentOpacity)
                        .padding(.horizontal, 6)
                } else {
                    ForEach(Array(store.displayItems.enumerated()), id: \.element.id) { index, item in
                        if shouldShowDivider(before: index) {
                            controlDivider
                                .opacity(0.55 * contentOpacity)
                        }
                        let mark = runningApps.presentation(for: item.slot)
                        SlotIconButton(
                            store: store,
                            item: item,
                            size: iconSize,
                            showLabel: store.preferences.showLabels,
                            showTooltip: store.preferences.showIconTooltips,
                            isFlashing: store.launchFlashSlotID == item.slot.id,
                            // Dot visibility can be off; right-click still needs true running state.
                            isRunning: mark.isRunning,
                            instanceCount: mark.instanceCount,
                            showRunningDot: store.preferences.showRunningDots,
                            badge: store.preferences.showNotificationBadges
                                ? badges.badge(for: item.slot)
                                : nil,
                            liveIconToken: badges.liveIconToken(for: item.slot),
                            progress: badges.progress(for: item.slot),
                            customIndex: item.origin == .custom
                                ? store.customIndex(of: item.slot.id)
                                : nil,
                            customCount: store.slots.count,
                            canImportAsCustom: (item.origin == .systemDock || item.origin == .running)
                                && !store.isSystemEntryAlreadyCustom(
                                    SystemDockEntry(label: item.slot.label, path: item.slot.target)
                                )
                        )
                        .opacity(contentOpacity)
                        .scaleEffect(0.94 + 0.06 * contentOpacity)
                    }
                }

                controlDivider

                // Gear → slot editor
                controlButton(
                    systemName: "gearshape",
                    help: "Edit slots",
                    action: { onOpenSettings?(.slots) ?? store.openSettings(tab: .slots) }
                )

                // Ellipsis → options / controls menu
                ControlsMenuButton(store: store, onOpenOptions: {
                    onOpenSettings?(.options) ?? store.openSettings(tab: .options)
                })
                .opacity(max(0.55, contentOpacity))
            }
            .padding(.horizontal, pad + 6)
            .padding(.vertical, pad)
        }
        .frame(height: barHeight)
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL, .url, .plainText], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
        .overlay(alignment: .top) {
            if let err = store.lastLaunchError {
                Text(err)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.red.opacity(0.85)))
                    .offset(y: -22)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .onTapGesture { store.lastLaunchError = nil }
            }
        }
        .animation(.easeOut(duration: 0.2), value: store.lastLaunchError)
        .onHover { hovering in
            onHoverChange?(hovering)
        }
    }

    private var controlDivider: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.primary.opacity(0.18))
            .frame(width: 1, height: iconSize * 0.55)
            .opacity(0.9 * contentOpacity)
            .padding(.horizontal, 2)
    }

    private func controlButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary.opacity(0.78))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .opacity(max(0.55, contentOpacity))
    }

    private var contentOpacity: Double {
        // Keep full opacity while collapsing — dimming mid-travel re-renders the material
        // stack and reads as a stutter halfway through close.
        switch store.reveal.phase {
        case .collapsed: return 0
        case .expanding, .expanded, .collapsing: return 1
        }
    }

    /// Divider between custom → system Dock, and pinned strip → transient running (merge mode).
    private func shouldShowDivider(before index: Int) -> Bool {
        guard store.preferences.systemDockIntegration == .merge,
              store.preferences.showSystemDockDivider,
              index > 0
        else { return false }
        let prev = store.displayItems[index - 1].origin
        let cur = store.displayItems[index].origin
        // Group boundaries: custom → system Dock, and pinned strip → transient running.
        if prev == .custom && cur == .systemDock { return true }
        if prev != .running && cur == .running { return true }
        return false
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var claimed = false
        let dockStore = store
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                claimed = true
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
                    let raw: String? = {
                        if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                            return url.path
                        }
                        if let url = item as? URL { return url.path }
                        if let str = item as? String { return str }
                        return nil
                    }()
                    let errorMessage = error?.localizedDescription
                    Task { @MainActor [dockStore] in
                        guard let raw else {
                            dockStore.lastLaunchError = errorMessage ?? "Could not read the dropped item."
                            return
                        }
                        if case .reject(let reason) = dockStore.addSlotFromDrop(raw) {
                            dockStore.lastLaunchError = reason
                        }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier("public.url") {
                claimed = true
                provider.loadItem(forTypeIdentifier: "public.url", options: nil) { item, error in
                    let raw: String? = {
                        if let url = item as? URL { return url.absoluteString }
                        if let data = item as? Data, let s = String(data: data, encoding: .utf8) { return s }
                        if let s = item as? String { return s }
                        return nil
                    }()
                    let errorMessage = error?.localizedDescription
                    Task { @MainActor [dockStore] in
                        guard let raw else {
                            dockStore.lastLaunchError = errorMessage ?? "Could not read the dropped item."
                            return
                        }
                        if case .reject(let reason) = dockStore.addSlotFromDrop(raw) {
                            dockStore.lastLaunchError = reason
                        }
                    }
                }
            } else if provider.canLoadObject(ofClass: String.self) {
                claimed = true
                _ = provider.loadObject(ofClass: String.self) { str, error in
                    let errorMessage = error?.localizedDescription
                    Task { @MainActor [dockStore] in
                        guard let str else {
                            dockStore.lastLaunchError = errorMessage ?? "Could not read the dropped item."
                            return
                        }
                        if case .reject(let reason) = dockStore.addSlotFromDrop(str) {
                            dockStore.lastLaunchError = reason
                        }
                    }
                }
            }
        }
        return claimed
    }
}

/// Ellipsis control with native menu for dock options.
struct ControlsMenuButton: View {
    @ObservedObject var store: SlotDockStore
    var onOpenOptions: () -> Void

    var body: some View {
        Menu {
            Section("Dock") {
                Button(store.reveal.isRevealed ? "Hide Dock" : "Show Dock") {
                    store.toggleReveal()
                }
                Toggle("Pin Open", isOn: Binding(
                    get: { store.preferences.pinOpen },
                    set: { store.setPinOpen($0) }
                ))
                Toggle("Auto-Hide", isOn: Binding(
                    get: { store.preferences.autoHide },
                    set: { store.setAutoHide($0) }
                ))
                .disabled(store.preferences.pinOpen)
                Toggle("Edge Hover", isOn: Binding(
                    get: { store.preferences.edgeHover },
                    set: { store.setEdgeHover($0) }
                ))
            }
            Section("System Dock") {
                Button("Mac Dock Settings…") {
                    store.openMacDockSettings()
                }
                .help("Open System Settings → Desktop & Dock")
                Picker("Integration", selection: Binding(
                    get: { store.preferences.systemDockIntegration },
                    set: { store.setSystemDockIntegration($0) }
                )) {
                    ForEach(SystemDockIntegration.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Button("Refresh from Dock") { _ = store.refreshSystemDock() }
                Button("Import Dock apps as custom…") {
                    _ = store.importSystemDockAsCustomSlots()
                }
            }
            Section("Appearance") {
                Picker("Icon Size", selection: Binding(
                    get: { store.preferences.iconSize },
                    set: { store.setIconSize($0) }
                )) {
                    ForEach(DockPreferences.IconSize.allCases, id: \.self) { size in
                        Text(size.displayName).tag(size)
                    }
                }
                Picker("Position", selection: Binding(
                    get: { store.preferences.alignment },
                    set: { store.setAlignment($0) }
                )) {
                    ForEach(DockPreferences.Alignment.allCases, id: \.self) { align in
                        Text(align.displayName).tag(align)
                    }
                }
                Toggle("Show Labels", isOn: Binding(
                    get: { store.preferences.showLabels },
                    set: { store.setShowLabels($0) }
                ))
                Toggle("Icon Tooltips", isOn: Binding(
                    get: { store.preferences.showIconTooltips },
                    set: { store.setShowIconTooltips($0) }
                ))
                Toggle("Show Running Apps", isOn: Binding(
                    get: { store.preferences.showTransientRunningApps },
                    set: { store.setShowTransientRunningApps($0) }
                ))
                Toggle("Notification Badges", isOn: Binding(
                    get: { store.preferences.showNotificationBadges },
                    set: { store.setShowNotificationBadges($0) }
                ))
            }
            Section {
                Button("All Options…") { onOpenOptions() }
                Button("Edit Slots…") { store.openSettings(tab: .slots) }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary.opacity(0.78))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
                .accessibilityLabel("Options and controls")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help(store.preferences.showIconTooltips ? "Options & controls" : "")
    }
}

struct SlotIconButton: View {
    @ObservedObject var store: SlotDockStore
    let item: SlotComposer.Item
    let size: CGFloat
    var showLabel: Bool = false
    var showTooltip: Bool = true
    var isFlashing: Bool = false
    var isRunning: Bool = false
    var instanceCount: Int = 0
    var showRunningDot: Bool = true
    var badge: DockBadge?
    var liveIconToken: String = ""
    var progress: Double?
    var customIndex: Int?
    var customCount: Int = 0
    var canImportAsCustom: Bool = false

    @State private var hovered = false
    @State private var dragHighlight = false

    private var slot: Slot { item.slot }
    private var isCustom: Bool { item.origin == .custom }

    /// Short native tooltip (AppKit toolTip — delayed & cheap).
    private var tooltipText: String {
        guard showTooltip else { return "" }
        var parts = [slot.label]
        switch item.origin {
        case .systemDock: parts.append("system Dock")
        case .running: parts.append("running")
        case .custom: break
        }
        if isRunning, item.origin != .running { parts.append("open") }
        if let badge {
            let text = DockBadgeFormatting.displayText(badge)
            parts.append(text.isEmpty ? "unread" : text)
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(Color.primary.opacity(hovered || isFlashing || dragHighlight ? 0.12 : 0))
                SlotIconImage(slot: slot, size: size - 6, liveToken: liveIconToken)
                    .frame(width: size - 6, height: size - 6)
                    .allowsHitTesting(false)
                if let progress, progress > 0, progress < 1 {
                    DockProgressRing(progress: progress)
                        .frame(width: size - 4, height: size - 4)
                        .allowsHitTesting(false)
                }
                if let badge {
                    NotificationBadgeView(badge: badge, iconSize: size)
                        .offset(x: 3, y: -2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .allowsHitTesting(false)
                }
                // Native hit target owns click/drag/right-click so launch never
                // races strip reorder (mouseUp click vs threshold drag).
                StripIconHitRepresentable(
                    slotID: slot.id,
                    toolTip: tooltipText,
                    // ⌘+drag reorders custom slots only (gate is also in StripPressSession).
                    allowsDragReorder: isCustom,
                    onClick: {
                        _ = store.launch(slotID: slot.id)
                    },
                    onRightClick: { event in
                        presentNativeMenu(with: event)
                    },
                    onReorderDrop: { draggedID in
                        _ = store.reorderCustomSlot(draggedID: draggedID, beforeID: slot.id)
                    },
                    onDragHighlight: { dragHighlight = $0 }
                )
            }
            .frame(width: size, height: size)
            .scaleEffect(isFlashing ? 0.88 : (hovered ? 1.1 : 1.0))
            .animation(.spring(response: 0.26, dampingFraction: 0.68), value: hovered)
            .animation(.spring(response: 0.18, dampingFraction: 0.55), value: isFlashing)

            HStack(spacing: -1) {
                Circle()
                    .fill(Color.primary.opacity(showRunningDot && isRunning ? 0.75 : 0))
                    .frame(width: 4, height: 4)
                if showRunningDot, instanceCount > 1 {
                    Circle()
                        .fill(Color.primary.opacity(0.55))
                        .frame(width: 4, height: 4)
                }
            }
            .overlay(alignment: .trailing) {
                if showRunningDot, instanceCount > 2 {
                    Text("\(instanceCount)")
                        .font(.system(size: 6, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .offset(x: 7, y: 0)
                }
            }
            .padding(.top, 1)
            .allowsHitTesting(false)

            if showLabel {
                Text(slot.label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: size + 12)
                    .allowsHitTesting(false)
            }
        }
        .onHover { hovering in
            hovered = hovering
            if hovering {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .onDisappear { NSCursor.arrow.set() }
        .accessibilityLabel(accessibilityName)
        .accessibilityHint(
            isCustom
                ? "Click to open. Command-drag to reorder. Right-click for more."
                : "Click to open. Right-click for Options (Keep as Custom Slot)."
        )
    }

    private var accessibilityName: String {
        var parts = [slot.label]
        if let badge {
            parts.append(DockBadgeFormatting.accessibilityText(badge))
        }
        if isRunning {
            parts.append(instanceCount > 1 ? "\(instanceCount) running" : "running")
        }
        return parts.joined(separator: ", ")
    }

    private func presentNativeMenu(with event: NSEvent) {
        guard let view = event.window?.contentView else { return }
        let request = LaunchResolver.resolve(slot: slot)
        let loginEligible = AppOpenAtLoginPolicy.isEligible(
            kind: request.kind,
            path: request.resolvedTarget
        )
        let loginEnabled = loginEligible ? store.openAtLoginState(slotID: slot.id) : nil
        // Keep/unkeep toggle: path already present as a durable custom slot.
        let keptAsCustom = item.origin != .custom
            && KeepAsCustomPolicy.state(
                origin: item.origin,
                path: slot.target,
                customSlots: store.slots
            ) == .kept
        let model = SlotContextMenuBuilder.buildSlotMenu(
            input: SlotContextMenuInput(
                label: slot.label,
                origin: item.origin,
                kind: request.kind,
                isRunning: isRunning,
                canOpenNewInstance: SlotContextMenuBuilder.canOpenNewInstance(
                    kind: request.kind,
                    path: request.resolvedTarget
                ),
                canImportAsCustom: canImportAsCustom && !keptAsCustom,
                isKeptAsCustom: keptAsCustom,
                customIndex: customIndex,
                customCount: customCount,
                openAtLoginEligible: loginEligible,
                openAtLoginEnabled: loginEnabled,
                instances: store.runningInstances(for: slot.id)
            )
        )
        NativeContextMenu.popUp(model: model, with: event, for: view) { action, instance in
            _ = store.performContextAction(action, slotID: slot.id, instance: instance)
        }
    }
}

struct SlotIconImage: View {
    let slot: Slot
    let size: CGFloat
    var liveToken: String = ""

    var body: some View {
        Group {
            if let resolved = SlotIconCache.resolved(for: slot, pointSize: size, liveToken: liveToken) {
                Image(nsImage: resolved.image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fit)
                    .modifier(OptionalIconMask(enabled: resolved.appliesMask, cornerRadius: size * 0.2))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.2))
                    Text(String(slot.label.prefix(1)).uppercased())
                        .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary.opacity(0.8))
                }
            }
        }
        .frame(width: size, height: size)
    }
}

private struct OptionalIconMask: ViewModifier {
    let enabled: Bool
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if enabled {
            content.clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            content
        }
    }
}

private struct DockProgressRing: View {
    let progress: Double

    var body: some View {
        Circle()
            .trim(from: 0, to: max(0.02, min(1, progress)))
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            .rotationEffect(.degrees(-90))
    }
}

struct NotificationBadgeView: View {
    let badge: DockBadge
    let iconSize: CGFloat

    var body: some View {
        let text = DockBadgeFormatting.displayText(badge)
        let diameter = max(12, iconSize * 0.36)
        if text.isEmpty {
            Circle()
                .fill(Color(nsColor: .systemRed))
                .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.2))
                .frame(width: diameter * 0.62, height: diameter * 0.62)
                .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
        } else {
            Text(text)
                .font(.system(size: max(8, iconSize * 0.22), weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .padding(.horizontal, text.count > 1 ? 4 : 0)
                .frame(minWidth: diameter, minHeight: diameter)
                .background(Capsule(style: .continuous).fill(Color(nsColor: .systemRed)))
                .overlay(Capsule(style: .continuous).strokeBorder(Color.white, lineWidth: 1.2))
                .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
        }
    }
}

/// Collapsed edge tab — discoverable hit target when dock is hidden.
struct CollapsedTabView: View {
    var body: some View {
        VStack(spacing: 0) {
            Capsule(style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5)
                )
                .frame(width: 96, height: 11)
                .shadow(color: .black.opacity(0.2), radius: 6, y: 1)
            Image(systemName: "chevron.compact.up")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary.opacity(0.75))
                .padding(.top, 1)
        }
        .padding(.bottom, 2)
        .help("Show Nicos Slot Dock")
    }
}
