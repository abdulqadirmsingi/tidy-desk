import SwiftUI
import TidyDeskCore

struct MenuBarIcon: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Image(systemName: symbol)
            .accessibilityLabel("\(Branding.name): \(model.ui.status.summary)")
    }

    private var symbol: String {
        let filled = model.settings.configuration.appearance.menuBarIcon == .filled
        switch model.ui.status {
        case .needsPermission: return "exclamationmark.triangle"
        case .pausedByUser, .stageManagerOn, .asleep: return "pause.rectangle"
        case .active:
            if model.ui.isSpecialModeActive { return "scope" }
            return filled ? "rectangle.split.2x2.fill" : "rectangle.split.2x2"
        }
    }
}

struct MenuBarContent: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let ui = model.ui
        let settings = model.settings
        let display = model.currentDisplay?.id

        Text(statusLine)
        if let notice = ui.notice { Text(notice) }
        if ui.status == .needsPermission {
            Button("Grant Accessibility Access…") { model.showOnboarding() }
        }

        Divider()

        Toggle(
            "Automatic Tiling",
            isOn: Binding(
                get: { settings.configuration.isTilingEnabled },
                set: { model.coordinator.setTilingEnabled($0) }))

        if ui.displays.count > 1 {
            Picker("Display", selection: Binding(get: { model.currentDisplay?.id }, set: { model.selectedDisplayID = $0 })) {
                ForEach(ui.displays) { Text($0.name).tag(Optional($0.id)) }
            }
        }
        Picker("Layout", selection: settings.binding(for: display, \.layout)) {
            ForEach(LayoutKind.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        Picker("Windows on This Display", selection: settings.binding(for: display, \.maxWindows)) {
            ForEach(1...LayoutDefaults.maxWindowsPerDisplay, id: \.self) { Text("\($0)").tag($0) }
        }
        Picker("Extra Windows", selection: settings.binding(for: display, \.overflow)) {
            ForEach(OverflowPolicy.allCases, id: \.self) { Text($0.title).tag($0) }
        }

        Divider()

        Button("Arrange Windows Now") { model.coordinator.arrangeNow() }
        Button("Restore Previous Arrangement") { model.coordinator.restorePreviousArrangement() }
            .disabled(!ui.canRestorePreviousArrangement)
        Button("Command Palette…") { model.showCommandPalette() }
        Button("Window Switcher…") { model.showSwitcher() }
        Toggle(
            "Float Active Window",
            isOn: Binding(get: { ui.activeWindowFloating ?? false }, set: { _ in model.coordinator.toggleFloatActive() })
        )
        .disabled(ui.activeWindowFloating == nil)

        Divider()

        Toggle("Focus Mode", isOn: Binding(get: { ui.isFocusActive }, set: { _ in model.coordinator.toggleFocus() }))
        Toggle("No Peek", isOn: Binding(get: { ui.isNoPeekActive }, set: { _ in model.coordinator.toggleNoPeek() }))
        Toggle("Clean Space", isOn: Binding(get: { ui.isCleanSpaceActive }, set: { _ in model.coordinator.toggleCleanSpace() }))

        Divider()

        Button("Settings…") { model.showSettings() }.keyboardShortcut(",")
        Button("Quit \(Branding.name)") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
    }

    private var statusLine: String {
        let ui = model.ui
        switch ui.status {
        case .active:
            let tiled = ui.tiledCounts.values.reduce(0, +)
            let mode = ui.isFocusActive ? " · Focus" : ui.isCleanSpaceActive ? " · Clean Space" : ui.isNoPeekActive ? " · No Peek" : ""
            return "Tiling \(tiled) window\(tiled == 1 ? "" : "s")" + (ui.floatingCount > 0 ? ", \(ui.floatingCount) floating" : "") + mode
        default: return ui.status.summary
        }
    }
}
