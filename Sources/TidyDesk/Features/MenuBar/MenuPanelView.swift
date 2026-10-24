import SwiftUI
import TidyDeskCore

/// The panel under the menu bar icon: status first, the one switch most people need, then the rest.
struct MenuPanelView: View {
    @Environment(AppModel.self) private var model
    let close: () -> Void

    private var ui: TilingUIState { model.ui }
    private var settings: SettingsStore { model.settings }
    private var display: DisplayID? { model.currentDisplay?.id }

    var body: some View {
        VStack(spacing: 12) {
            header
            if ui.status == .needsPermission { fixAccess }
            tilingSwitch
            if let notice = ui.notice { Text(notice).font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
            layoutSection
            if model.frontApp != nil { appSection }
            actions
            modes
            footer
        }
        .padding(16)
        .frame(width: 340)
        .glassPanel(cornerRadius: 22)
    }

    // MARK: Header and switch

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: MenuBarSymbol.name(status: ui.status, isSpecialModeActive: ui.isSpecialModeActive, style: .filled))
                .font(.system(size: 22)).foregroundStyle(statusColor).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(Branding.name).font(.headline)
                HStack(spacing: 6) {
                    Circle().fill(statusColor).frame(width: 7, height: 7)
                    Text(statusLine).font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private var statusColor: Color {
        switch ui.status {
        case .active: .green
        case .needsPermission: .orange
        case .pausedByUser, .stageManagerOn, .asleep: .secondary
        }
    }

    private var statusLine: String {
        guard ui.status == .active else { return ui.status.summary }
        let tiled = ui.tiledCounts.values.reduce(0, +)
        var text = "Tiling \(tiled) window\(tiled == 1 ? "" : "s")"
        if ui.floatingCount > 0 { text += ", \(ui.floatingCount) floating" }
        return text
    }

    private var fixAccess: some View {
        Button { run { model.showOnboarding(at: .grant) } } label: {
            Label("Allow Accessibility access to start", systemImage: "hand.raised.fill").frame(maxWidth: .infinity)
        }
        .glassButton(prominent: true)
    }

    private var tilingSwitch: some View {
        HStack {
            Text("Automatic tiling").font(.body.weight(.semibold))
            Spacer()
            Toggle("Automatic tiling", isOn: Binding(
                get: { settings.configuration.isTilingEnabled && settings.configuration.hasCompletedOnboarding },
                set: { on in
                    if on { settings.update { $0.hasCompletedOnboarding = true } }
                    model.coordinator.setTilingEnabled(on)
                }))
            .toggleStyle(.switch).labelsHidden()
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Layout

    private var layoutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if ui.displays.count > 1 {
                Picker("Display", selection: Binding(get: { model.currentDisplay?.id }, set: { model.selectedDisplayID = $0 })) {
                    ForEach(ui.displays) { Text($0.name).tag(Optional($0.id)) }
                }
                .pickerStyle(.menu)
            }
            Picker("Layout", selection: settings.binding(for: display, \.layout)) {
                ForEach(LayoutKind.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            .accessibilityLabel("Layout")
            HStack {
                Text("Windows").font(.callout).foregroundStyle(.secondary)
                Picker("Windows on this display", selection: settings.binding(for: display, \.maxWindows)) {
                    ForEach(1...LayoutDefaults.maxWindowsPerDisplay, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
            }
            HStack {
                Text("When full").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Picker("When full", selection: settings.binding(for: display, \.overflow)) {
                    ForEach(OverflowPolicy.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu).labelsHidden().fixedSize()
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Active app

    @ViewBuilder private var appSection: some View {
        if let app = model.frontApp {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    if let icon = app.icon { Image(nsImage: icon).resizable().frame(width: 20, height: 20) }
                    Text("Tile \(app.name)").lineLimit(1)
                    Spacer()
                    Toggle("Tile \(app.name)", isOn: Binding(
                        get: { app.bundleID.map { !settings.configuration.excludedBundleIDs.contains($0) } ?? true },
                        set: { tile in
                            guard let id = app.bundleID else { return }
                            settings.update { config in
                                if tile { config.excludedBundleIDs.remove(id) } else { config.excludedBundleIDs.insert(id) }
                            }
                        }))
                    .toggleStyle(.switch).labelsHidden().disabled(app.bundleID == nil)
                }
                HStack {
                    Text("Float this window").foregroundStyle(ui.activeWindowFloating == nil ? .tertiary : .primary)
                    Spacer()
                    Toggle("Float this window", isOn: Binding(
                        get: { ui.activeWindowFloating ?? false }, set: { _ in model.coordinator.toggleFloatActive() }))
                    .toggleStyle(.switch).labelsHidden().disabled(ui.activeWindowFloating == nil)
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: Actions and modes

    private var actions: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                actionButton("Arrange Now", "rectangle.split.2x2") { model.coordinator.arrangeNow() }
                actionButton("Undo", "arrow.uturn.backward", disabled: !ui.canRestorePreviousArrangement) {
                    model.coordinator.restorePreviousArrangement()
                }
            }
            GridRow {
                actionButton("Switcher", "square.on.square") { model.showSwitcher() }
                actionButton("Commands", "magnifyingglass") { model.showCommandPalette() }
            }
        }
    }

    private func actionButton(_ title: String, _ symbol: String, disabled: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button { run(action) } label: { Label(title, systemImage: symbol).frame(maxWidth: .infinity) }
            .glassButton().disabled(disabled)
    }

    private var modes: some View {
        HStack(spacing: 8) {
            modeChip("Focus", ui.isFocusActive) { model.coordinator.toggleFocus() }
            modeChip("No Peek", ui.isNoPeekActive) { model.coordinator.toggleNoPeek() }
            modeChip("Clean Space", ui.isCleanSpaceActive) { model.coordinator.toggleCleanSpace() }
        }
    }

    private func modeChip(_ title: String, _ isOn: Bool, _ action: @escaping () -> Void) -> some View {
        Toggle(title, isOn: Binding(get: { isOn }, set: { _ in action() })).toggleStyle(.button).frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack {
            Button("Settings…") { run { model.showSettings() } }.buttonStyle(.plain)
            Spacer()
            Text("⌃⌥K for commands").font(.caption).foregroundStyle(.tertiary)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.plain)
        }
        .font(.callout)
    }

    /// Closes the panel first so the action sees the app the user was working in, then runs it.
    private func run(_ action: @escaping () -> Void) {
        close()
        Task { @MainActor in action() }
    }
}
