import AppKit
import SlotDockCore
import SwiftUI
import UniformTypeIdentifiers

/// Tabbed settings: Slots editor + Options/controls.
struct SettingsView: View {
    @ObservedObject var store: SlotDockStore
    @State private var draftLabel = ""
    @State private var draftTarget = ""
    @State private var draftIcon = ""
    @State private var editingID: String?
    @State private var showFileImporter = false
    @State private var importFor: ImportKind = .target
    @State private var lastImportNote: String?
    @State private var isTargetedDrop = false

    private enum ImportKind {
        case target
        case icon
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Picker("", selection: $store.settingsTab) {
                ForEach(SlotDockStore.SettingsTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Group {
                switch store.settingsTab {
                case .slots:
                    slotsPane
                case .options:
                    OptionsView(store: store)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 560, minHeight: 700)
        .background(Color(nsColor: .windowBackgroundColor))
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: importFor == .target
                ? [.application, .item, .folder]
                : [.image, .icns],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                let path = url.path
                switch importFor {
                case .target:
                    draftTarget = path
                    if draftLabel.isEmpty {
                        draftLabel = url.deletingPathExtension().lastPathComponent
                    }
                case .icon:
                    draftIcon = path
                }
            }
        }
        .onAppear {
            if store.settingsTab == .slots {
                _ = store.refreshSystemDock()
            }
            consumePendingEditIfNeeded()
        }
        .onChange(of: store.settingsTab) { _, tab in
            if tab == .slots {
                _ = store.refreshSystemDock()
                consumePendingEditIfNeeded()
            }
        }
        .onChange(of: store.pendingEditSlotID) { _, _ in
            consumePendingEditIfNeeded()
        }
    }

    private func consumePendingEditIfNeeded() {
        guard store.settingsTab == .slots,
              let id = store.consumePendingEditSlotID(),
              let slot = store.slots.first(where: { $0.id == id })
        else { return }
        beginEdit(slot)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Slot Dock")
                    .font(.system(size: 15, weight: .semibold))
                Text(store.settingsTab == .slots
                    ? "Custom slots + import from your system Dock"
                    : "Behavior, appearance, and Dock compatibility")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done") {
                store.closeSettings()
                NSApp.keyWindow?.close()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var slotsPane: some View {
        VStack(spacing: 0) {
            dockConflictBanner
            HStack(alignment: .top, spacing: 0) {
                systemDockSourcePane
                    .frame(minWidth: 220, maxWidth: 280)
                Divider()
                VStack(spacing: 0) {
                    if store.slots.isEmpty {
                        emptyState
                    } else {
                        slotList
                    }
                    Divider()
                    editor
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// Quick path to hide the stock Dock so two strips don’t fight.
    private var dockConflictBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "dock.rectangle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Two docks fighting?")
                    .font(.system(size: 12, weight: .semibold))
                Text("Hide the macOS Dock (auto-hide): Control-click the thin Dock separator → Turn Hiding On. Or open the full guide under Options.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("Hide Mac Dock…") {
                        runHideSystemDock()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    Button("Open guide") {
                        store.settingsTab = .options
                        NotificationCenter.default.post(name: .slotDockOpenCollisionGuide, object: nil)
                    }
                    .controlSize(.small)
                    Button("Copy shortcut steps") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(CollisionGuide.hideDockShortcutGuide, forType: .string)
                        lastImportNote = "Copied hide-Dock shortcut guide."
                    }
                    .controlSize(.small)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.orange.opacity(0.08))
        .overlay(alignment: .bottom) { Divider() }
    }

    /// Live system Dock apps already read/merged for the strip — drag or + into custom slots.
    private var systemDockSourcePane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("System Dock")
                        .font(.system(size: 12, weight: .semibold))
                    Text("\(store.systemDockEntries.count) apps · live from macOS")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    _ = store.refreshSystemDock()
                    lastImportNote = "Refreshed system Dock (\(store.systemDockEntries.count) apps)."
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Re-read com.apple.dock")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if store.importableSystemDockEntries.isEmpty == false {
                Button {
                    let n = store.importSystemDockAsCustomSlots()
                    lastImportNote = n == 0
                        ? "Nothing new to import."
                        : "Imported \(n) Dock app\(n == 1 ? "" : "s") as custom slots."
                } label: {
                    Label(
                        "Import all (\(store.importableSystemDockEntries.count))",
                        systemImage: "square.and.arrow.down.on.square"
                    )
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            }

            Text("Drag an app onto Custom slots, or click +")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)

            if store.systemDockEntries.isEmpty {
                VStack(spacing: 6) {
                    Text("No Dock apps found")
                        .font(.system(size: 12, weight: .medium))
                    Text("Open a few apps on the macOS Dock, then refresh.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List {
                    ForEach(store.systemDockEntries) { entry in
                        systemDockRow(entry)
                    }
                }
                .listStyle(.inset)
            }

            if let lastImportNote {
                Text(lastImportNote)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }

    private func systemDockRow(_ entry: SystemDockEntry) -> some View {
        let already = store.isSystemEntryAlreadyCustom(entry)
        let payload = SystemDockDragPayload.encode(entry)
        return HStack(spacing: 8) {
            SlotIconImage(slot: SystemDockReader.slot(from: entry), size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.label)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(already ? "Already a custom slot" : "Drag or + to add")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button {
                if store.importSystemDockEntry(entry) != nil {
                    lastImportNote = "Added “\(entry.label)”."
                } else {
                    lastImportNote = "“\(entry.label)” is already a custom slot."
                }
            } label: {
                Image(systemName: already ? "checkmark.circle.fill" : "plus.circle.fill")
                    .foregroundStyle(already ? Color.secondary : Color.accentColor)
            }
            .buttonStyle(.borderless)
            .disabled(already)
            .help(already ? "Already imported" : "Add as custom slot")
        }
        .padding(.vertical, 2)
        .opacity(already ? 0.55 : 1)
        .draggable(payload)
        .listRowInsets(EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 10))
        .contextMenu {
            Button("Add as custom slot") {
                _ = store.importSystemDockEntry(entry)
            }
            .disabled(already)
            Button("Copy path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.path, forType: .string)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text("No custom slots yet")
                .font(.system(size: 13, weight: .medium))
            Text("Drag apps from System Dock on the left, or add a path below.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(isTargetedDrop ? Color.accentColor.opacity(0.08) : Color.clear)
        .dropDestination(for: String.self) { items, _ in
            importDroppedPayloads(items)
        } isTargeted: { isTargetedDrop = $0 }
    }

    private var slotList: some View {
        List {
            Section {
                ForEach(Array(store.slots.enumerated()), id: \.element.id) { index, slot in
                    HStack(spacing: 10) {
                        SlotIconImage(slot: slot, size: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(slot.label)
                                .font(.system(size: 13, weight: .medium))
                            Text(slot.target)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Button {
                            beginEdit(slot)
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.borderless)
                        .help("Edit")

                        Button(role: .destructive) {
                            _ = store.removeSlot(id: slot.id)
                            if editingID == slot.id { clearEditor() }
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.borderless)
                        .help("Remove")
                    }
                    .padding(.vertical, 2)
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    .contextMenu {
                        Button("Move Up") { store.reorder(from: index, to: index - 1) }
                            .disabled(index == 0)
                        Button("Move Down") { store.reorder(from: index, to: index + 1) }
                            .disabled(index >= store.slots.count - 1)
                        Divider()
                        Button("Edit") { beginEdit(slot) }
                        Button("Remove", role: .destructive) {
                            _ = store.removeSlot(id: slot.id)
                        }
                    }
                }
                .onMove { indices, newOffset in
                    guard let from = indices.first else { return }
                    var to = newOffset
                    if from < to { to -= 1 }
                    store.reorder(from: from, to: to)
                }
            } header: {
                Text("Custom slots — drop Dock apps here")
            }
        }
        .listStyle(.inset)
        .frame(maxHeight: .infinity)
        .scrollContentBackground(.hidden)
        .background(isTargetedDrop ? Color.accentColor.opacity(0.08) : Color.clear)
        .dropDestination(for: String.self) { items, _ in
            importDroppedPayloads(items)
        } isTargeted: { isTargetedDrop = $0 }
    }

    @discardableResult
    private func importDroppedPayloads(_ items: [String]) -> Bool {
        var added = 0
        for raw in items {
            if store.importFromDockDragPayload(raw) != nil {
                added += 1
            }
        }
        if added > 0 {
            lastImportNote = "Imported \(added) item\(added == 1 ? "" : "s") from drag."
            return true
        }
        lastImportNote = "Drop ignored (already present or invalid)."
        return false
    }

    private func runHideSystemDock() {
        guard let action = CollisionGuide.default.actions.first(where: { $0.id == "enable-system-autohide" }) else {
            return
        }
        let alert = NSAlert()
        alert.messageText = action.title
        alert.informativeText = """
        This turns on system Dock auto-hide so the stock Dock stays out of the way while you use Slot Dock.

        \(action.payload)
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Run")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        var error: NSDictionary?
        if let script = NSAppleScript(source: action.payload) {
            _ = script.executeAndReturnError(&error)
            lastImportNote = error == nil
                ? "System Dock auto-hide enabled."
                : "Could not change Dock preference (check Automation for System Events)."
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(editingID == nil ? "Add slot" : "Edit slot")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("Label", text: $draftLabel)
                    .textFieldStyle(.roundedBorder)
                TextField("App path, file, or URL", text: $draftTarget)
                    .textFieldStyle(.roundedBorder)
                Button {
                    importFor = .target
                    showFileImporter = true
                } label: {
                    Image(systemName: "folder")
                }
                .help("Browse for app or file")
            }

            HStack(spacing: 8) {
                TextField("Icon path (optional)", text: $draftIcon)
                    .textFieldStyle(.roundedBorder)
                Button {
                    importFor = .icon
                    showFileImporter = true
                } label: {
                    Image(systemName: "photo")
                }
                .help("Browse for custom icon")
            }

            HStack {
                if editingID != nil {
                    Button("Cancel") { clearEditor() }
                }
                Spacer()
                Button(editingID == nil ? "Add" : "Save") {
                    commitEditor()
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(draftLabel.trimmingCharacters(in: .whitespaces).isEmpty
                    || draftTarget.trimmingCharacters(in: .whitespaces).isEmpty)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
    }

    private func beginEdit(_ slot: Slot) {
        editingID = slot.id
        draftLabel = slot.label
        draftTarget = slot.target
        draftIcon = slot.iconPath ?? ""
    }

    private func clearEditor() {
        editingID = nil
        draftLabel = ""
        draftTarget = ""
        draftIcon = ""
    }

    private func commitEditor() {
        let label = draftLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = draftTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        let icon = draftIcon.trimmingCharacters(in: .whitespacesAndNewlines)
        let iconValue: String? = icon.isEmpty ? nil : icon
        guard !label.isEmpty, !target.isEmpty else { return }

        if let id = editingID {
            _ = store.updateSlot(id: id, label: label, target: target, iconPath: .some(iconValue))
        } else {
            _ = store.addSlot(label: label, target: target, iconPath: iconValue)
        }
        clearEditor()
    }
}

/// Single Form row: title · slider · live value (avoids label row + slider row stacking).
private struct OptionsSliderRow: View {
    let title: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var disabled: Bool = false
    var helpText: String = ""

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                Slider(value: $value, in: range, step: step)
                    .controlSize(.small)
                    .frame(minWidth: 120, maxWidth: 220)
                    .disabled(disabled)
                Text(valueText)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
        }
        .disabled(disabled)
        .help(helpText)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(valueText)")
    }
}

/// Full options / controls pane.
struct OptionsView: View {
    @ObservedObject var store: SlotDockStore

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { store.preferences.launchAtLogin },
                    set: { on in
                        if let msg = store.setLaunchAtLogin(on), !msg.isEmpty {
                            store.lastLaunchError = msg
                        }
                    }
                ))
                .help("Opt-in: open Slot Dock when you log in (default off). Requires installed .app.")

                Text(LaunchAtLogin.status.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Toggle("Pin open", isOn: Binding(
                    get: { store.preferences.pinOpen },
                    set: { store.setPinOpen($0) }
                ))
                .help("Keep the strip expanded until you hide it")

                Toggle("Auto-hide", isOn: Binding(
                    get: { store.preferences.autoHide },
                    set: { store.setAutoHide($0) }
                ))
                .disabled(store.preferences.pinOpen)
                .help("Collapse when the pointer leaves the strip")

                OptionsSliderRow(
                    title: "Hide delay",
                    valueText: String(format: "%.1fs", store.preferences.autoHideDelay),
                    value: Binding(
                        get: { store.preferences.autoHideDelay },
                        set: { store.setAutoHideDelay($0) }
                    ),
                    range: DockPreferences.minAutoHideDelay...DockPreferences.maxAutoHideDelay,
                    step: 0.05,
                    disabled: store.preferences.pinOpen || !store.preferences.autoHide,
                    helpText:
                        "How long to wait after the pointer leaves before collapsing "
                        + "(\(String(format: "%.1f", DockPreferences.minAutoHideDelay))–"
                        + "\(String(format: "%.1f", DockPreferences.maxAutoHideDelay))s). "
                        + "At 0.3s or less, a click outside the strip also collapses it."
                )

                OptionsSliderRow(
                    title: "Leave margin",
                    valueText: "\(Int(store.preferences.autoHideLeaveMargin.rounded())) pt",
                    value: Binding(
                        get: { store.preferences.autoHideLeaveMargin },
                        set: { store.setAutoHideLeaveMargin($0) }
                    ),
                    range: DockPreferences.minAutoHideLeaveMargin...DockPreferences.maxAutoHideLeaveMargin,
                    step: 1,
                    disabled: store.preferences.pinOpen || !store.preferences.autoHide,
                    helpText:
                        "How far outside the strip (including above it) the cursor may travel "
                        + "before the hide-delay timer starts "
                        + "(\(Int(DockPreferences.minAutoHideLeaveMargin))–"
                        + "\(Int(DockPreferences.maxAutoHideLeaveMargin)) pt). "
                        + "Default \(Int(DockPreferences.defaultAutoHideLeaveMargin)) pt."
                )

                Toggle("Edge hover to reveal", isOn: Binding(
                    get: { store.preferences.edgeHover },
                    set: { store.setEdgeHover($0) }
                ))
                .help("Move the pointer to the bottom edge to expand")

                OptionsSliderRow(
                    title: "Edge trigger height",
                    valueText: "\(Int(store.preferences.edgeTriggerHeight.rounded())) pt",
                    value: Binding(
                        get: { store.preferences.edgeTriggerHeight },
                        set: { store.setEdgeTriggerHeight($0) }
                    ),
                    range: DockPreferences.minEdgeTriggerHeight...DockPreferences.maxEdgeTriggerHeight,
                    step: 1,
                    disabled: !store.preferences.edgeHover,
                    helpText:
                        "How tall the bottom-edge hit zone is when the strip is collapsed or auto-hidden "
                        + "(\(Int(DockPreferences.minEdgeTriggerHeight))–\(Int(DockPreferences.maxEdgeTriggerHeight)) pt). "
                        + "Default \(Int(DockPreferences.defaultEdgeTriggerHeight)) pt. Also sizes the thin collapsed tab."
                )

                OptionsSliderRow(
                    title: "Edge lateral overshoot",
                    valueText: "\(Int(store.preferences.edgeHorizontalOvershoot.rounded())) pt",
                    value: Binding(
                        get: { store.preferences.edgeHorizontalOvershoot },
                        set: { store.setEdgeHorizontalOvershoot($0) }
                    ),
                    range: DockPreferences.minEdgeHorizontalOvershoot...DockPreferences.maxEdgeHorizontalOvershoot,
                    step: 1,
                    disabled: !store.preferences.edgeHover,
                    helpText:
                        "Extra width beyond half the strip for bottom-edge hover "
                        + "(\(Int(DockPreferences.minEdgeHorizontalOvershoot))–\(Int(DockPreferences.maxEdgeHorizontalOvershoot)) pt). "
                        + "Default \(Int(DockPreferences.defaultEdgeHorizontalOvershoot)) pt."
                )

                OptionsSliderRow(
                    title: "Reveal animation",
                    valueText: String(format: "%.2fs", store.preferences.revealBaseDuration),
                    value: Binding(
                        get: { store.preferences.revealBaseDuration },
                        set: { store.setRevealBaseDuration($0) }
                    ),
                    range: DockPreferences.minRevealBaseDuration...DockPreferences.maxRevealBaseDuration,
                    step: 0.01,
                    helpText:
                        "Full expand/collapse travel time "
                        + "(\(String(format: "%.2f", DockPreferences.minRevealBaseDuration))–"
                        + "\(String(format: "%.2f", DockPreferences.maxRevealBaseDuration))s). "
                        + "Default \(String(format: "%.2f", DockPreferences.defaultRevealBaseDuration))s. "
                        + "Shorter remaining distance still scales down."
                )
            } header: {
                Text("Behavior")
            } footer: {
                Text("Pin open disables auto-hide. You can still hide via the controls menu or status item.")
                    .font(.system(size: 10))
            }

            Section {
                Picker("System Dock", selection: Binding(
                    get: { store.preferences.systemDockIntegration },
                    set: { store.setSystemDockIntegration($0) }
                )) {
                    ForEach(SystemDockIntegration.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .help(store.preferences.systemDockIntegration.helpText)

                Text(store.preferences.systemDockIntegration.helpText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                LabeledContent("Apps on system Dock") {
                    Text("\(store.systemDockEntries.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Toggle("Divider between Dock & custom", isOn: Binding(
                    get: { store.preferences.showSystemDockDivider },
                    set: { store.setShowSystemDockDivider($0) }
                ))
                .disabled(store.preferences.systemDockIntegration != .merge)

                Button("Refresh from system Dock") {
                    _ = store.refreshSystemDock()
                }
                Button("Import Dock apps as custom slots") {
                    _ = store.importSystemDockAsCustomSlots()
                }
                .help("Copy system Dock apps into your custom list (skips duplicates)")
            } header: {
                Text("System Dock apps")
            } footer: {
                Text("Merge: custom slots left, system Dock apps next (live), open apps on the right. Mirror is Dock-only. Off is custom-only.")
                    .font(.system(size: 10))
            }

            Section {
                Toggle("Running-app dots", isOn: Binding(
                    get: { store.preferences.showRunningDots },
                    set: { store.setShowRunningDots($0) }
                ))
                .help("Small indicator under apps that are already open")

                Toggle("Window safe-area padding", isOn: Binding(
                    get: { store.preferences.safeAreaPadding },
                    set: { store.setSafeAreaPadding($0) }
                ))
                .help("When the strip is open, lift overlapping windows so content stays visible. Off restores only windows Slot Dock moved.")

                if store.preferences.safeAreaPadding {
                    OptionsSliderRow(
                        title: "Extra gap",
                        valueText: "\(Int(store.preferences.safeAreaExtraGap)) pt",
                        value: Binding(
                            get: { store.preferences.safeAreaExtraGap },
                            set: { store.setSafeAreaExtraGap($0) }
                        ),
                        range: 0...24,
                        step: 1,
                        helpText: "Extra points above the strip when safe-area padding is active."
                    )
                    Button("Request Accessibility…") {
                        NotificationCenter.default.post(name: .slotDockRequestAccessibility, object: nil)
                    }
                    .help("Required for live window padding")
                }
            } header: {
                Text("Strip & windows")
            } footer: {
                Text("Safe-area applies when the strip is pinned or expanded; turning it off restores only tracked windows.")
                    .font(.system(size: 10))
            }

            Section("Appearance") {
                Picker("Icon size", selection: Binding(
                    get: { store.preferences.iconSize },
                    set: { store.setIconSize($0) }
                )) {
                    ForEach(DockPreferences.IconSize.allCases, id: \.self) { size in
                        Text(size.displayName).tag(size)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Position", selection: Binding(
                    get: { store.preferences.alignment },
                    set: { store.setAlignment($0) }
                )) {
                    ForEach(DockPreferences.Alignment.allCases, id: \.self) { align in
                        Text(align.displayName).tag(align)
                    }
                }
                .pickerStyle(.segmented)

                OptionsSliderRow(
                    title: "Icon spacing",
                    valueText: "\(Int(store.preferences.iconSpacing.rounded())) pt",
                    value: Binding(
                        get: { store.preferences.iconSpacing },
                        set: { store.setIconSpacing($0) }
                    ),
                    range: DockPreferences.minIconSpacing...DockPreferences.maxIconSpacing,
                    step: 1,
                    helpText:
                        "Space between strip icons when labels are off "
                        + "(\(Int(DockPreferences.minIconSpacing))–\(Int(DockPreferences.maxIconSpacing)) pt). "
                        + "Default \(Int(DockPreferences.defaultIconSpacing)) pt; labels add "
                        + "\(Int(DockPreferences.iconSpacingLabelsExtra)) pt (prior 10 when base is 8)."
                )

                Toggle("Show labels under icons", isOn: Binding(
                    get: { store.preferences.showLabels },
                    set: { store.setShowLabels($0) }
                ))

                Toggle("Icon hover tooltips", isOn: Binding(
                    get: { store.preferences.showIconTooltips },
                    set: { store.setShowIconTooltips($0) }
                ))
                .help("Native tooltips on strip icons (name · open). Off disables all icon tooltips.")

                Toggle("Show running apps not on strip", isOn: Binding(
                    get: { store.preferences.showTransientRunningApps },
                    set: { store.setShowTransientRunningApps($0) }
                ))
                .help("Append open apps that aren’t pinned/custom (event-driven; no polling). Ephemeral icons vanish when the app quits.")

                Toggle("Launch press feedback", isOn: Binding(
                    get: { store.preferences.launchFeedback },
                    set: { store.setLaunchFeedback($0) }
                ))

                Toggle("Menu bar status item", isOn: Binding(
                    get: { store.preferences.showStatusItem },
                    set: { store.setShowStatusItem($0) }
                ))
                .help("Icon on the right side of the menu bar. Off = bottom strip only.")
            }

            Section {
                Toggle("Global shortcuts (system-wide)", isOn: Binding(
                    get: { store.preferences.hotkeys.globalEnabled },
                    set: { store.setHotkeysGlobal($0) }
                ))
                .help("When on, shortcuts work even while typing in other apps. Leave off unless you need them.")

                if store.hotkeyReport.hasProblems {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Hotkey registration problem", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.orange)
                        Text(store.hotkeyReport.userSummary)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Pick a free key combo, or turn Global shortcuts off. Conflicts often mean another app already owns that Carbon hotkey.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityIdentifier("hotkey-registration-failure")
                }

                KeyBindingRow(
                    title: "Show / hide dock",
                    help: "Toggle the bottom strip",
                    binding: hotkeyBinding(\.toggleDock)
                ) { store.notifyHotkeysChanged() }

                KeyBindingRow(
                    title: "Open settings",
                    help: "Slots & options window",
                    binding: hotkeyBinding(\.openSettings)
                ) { store.notifyHotkeysChanged() }

                KeyBindingRow(
                    title: "Pin open",
                    help: "Keep strip expanded",
                    binding: hotkeyBinding(\.pinOpen)
                ) { store.notifyHotkeysChanged() }

                KeyBindingRow(
                    title: "Quit Slot Dock",
                    help: "Exit the app",
                    binding: hotkeyBinding(\.quit)
                ) { store.notifyHotkeysChanged() }

                KeyBindingRow(
                    title: "Launch slots 1–9",
                    help: "Modifiers + digit launches that slot (key shown is slot 1)",
                    binding: hotkeyBinding(\.launchSlotDigits)
                ) { store.notifyHotkeysChanged() }

                HStack {
                    Button("Apply classic shortcuts") {
                        store.setHotkeys(.classicEnabled)
                    }
                    Button("Disable all") {
                        store.setHotkeys(.default)
                    }
                }
            } header: {
                Text("Keyboard shortcuts")
            } footer: {
                Text("Shortcuts are off by default so they never eat everyday typing. Click a binding, then press ⌘/⌃/⌥ + key. Esc cancels recording. Global mode uses Carbon hotkeys. Registration failures appear above when Global is on.")
                    .font(.system(size: 10))
            }

            Section("Config") {
                LabeledContent("Slots file") {
                    Text(store.core.fileURL.path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .frame(maxWidth: 260, alignment: .trailing)
                }
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([store.core.fileURL])
                }
                Button("Reset options to defaults") {
                    store.resetPreferences()
                }
            }

            // Last on Options: System Dock resolution / collision guide (after all product controls).
            Section {
                CollisionGuideView(store: store)
            } header: {
                Text("System Dock compatibility")
            }
        }
        .formStyle(.grouped)
        .padding(.bottom, 8)
    }

    private func hotkeyBinding(_ keyPath: WritableKeyPath<DockHotkeys, KeyBinding>) -> Binding<KeyBinding> {
        Binding(
            get: { store.preferences.hotkeys[keyPath: keyPath] },
            set: { newValue in
                store.updatePreferences { $0.hotkeys[keyPath: keyPath] = newValue }
            }
        )
    }
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private weak var store: SlotDockStore?

    convenience init(store: SlotDockStore) {
        let view = SettingsView(store: store)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 560),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Slot Dock Settings"
        window.titlebarAppearsTransparent = true
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: 640, height: 720))
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)
        self.store = store
        window.delegate = self
    }

    func show(tab: SlotDockStore.SettingsTab? = nil) {
        if let tab {
            store?.settingsTab = tab
        }
        // Refresh root so tab binding is current
        if let store {
            window?.contentViewController = NSHostingController(rootView: SettingsView(store: store))
        }
        SlotDockHeadless.surface(window!)
        window?.makeKeyAndOrderFront(nil)
        if !SlotDockHeadless.isHeadless {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func windowWillClose(_ notification: Notification) {
        store?.closeSettings()
    }
}
