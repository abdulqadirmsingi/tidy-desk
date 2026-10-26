import SwiftUI
import TidyDeskCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            LayoutSettings().tabItem { Label("Layout", systemImage: "rectangle.split.2x2") }
            DisplaysSettings().tabItem { Label("Displays", systemImage: "display.2") }
            ShortcutsSettings().tabItem { Label("Shortcuts", systemImage: "command") }
            AppearanceSettingsView().tabItem { Label("Appearance", systemImage: "paintbrush") }
            AppsSettings().tabItem { Label("Apps", systemImage: "app.badge.checkmark") }
            PrivacySettings().tabItem { Label("Privacy", systemImage: "hand.raised") }
            AboutSettings().tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 640, height: 480)
    }
}

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @State private var confirmReset = false

    var body: some View {
        let settings = model.settings
        Form {
            Section {
                Toggle(
                    "Tile windows automatically",
                    isOn: Binding(
                        get: { settings.configuration.isTilingEnabled },
                        set: { model.coordinator.setTilingEnabled($0) }))
                Text(model.ui.status.summary).font(.callout).foregroundStyle(.secondary)
            }
            Section("Startup") {
                Toggle(
                    "Start at login",
                    isOn: Binding(
                        get: { model.loginItem.state.isOn },
                        set: { model.setLaunchAtLogin($0) }))
                if model.loginItem.state == .requiresApproval {
                    Text("Approve \(Branding.name) in System Settings → General → Login Items.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Open Login Items Settings") { model.loginItem.openLoginItemsSettings() }
                }
                if let error = model.loginItemError { Text(error).font(.callout).foregroundStyle(.red) }
            }
            Section("Appearance in macOS") {
                Toggle("Also show in the Dock", isOn: settings.binding(\.showInDock))
                Text("\(Branding.name) always lives in the menu bar. Turn this on if you find the icon hard to spot; clicking the Dock icon opens Settings.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Arrangement") {
                Button("Restore Previous Arrangement") { model.coordinator.restorePreviousArrangement() }
                    .disabled(!model.ui.canRestorePreviousArrangement)
                Text("Puts windows back where they were when \(Branding.name) first saw them and pauses tiling.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Setup") {
                Button("Show Welcome Tour…") { model.showOnboarding() }
                Button("Reset All Settings…", role: .destructive) { confirmReset = true }
            }
            if let problem = settings.loadProblem {
                Text(problem.localizedDescription).font(.callout).foregroundStyle(.orange)
            }
            if let problem = settings.saveProblem { Text(problem).font(.callout).foregroundStyle(.red) }
        }
        .formStyle(.grouped)
        .confirmationDialog("Reset all settings?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { settings.resetToDefaults() }
        } message: {
            Text("Layouts, shortcuts, exclusions and learned window sizes return to their defaults.")
        }
    }
}

struct LayoutControls: View {
    @Environment(AppModel.self) private var model
    let display: DisplayID?

    var body: some View {
        let settings = model.settings
        Picker("Layout", selection: settings.binding(for: display, \.layout)) {
            ForEach(LayoutKind.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        Picker("Windows per display", selection: settings.binding(for: display, \.maxWindows)) {
            ForEach(1...LayoutDefaults.maxWindowsPerDisplay, id: \.self) { Text("\($0)").tag($0) }
        }
        .pickerStyle(.segmented)
        Picker("When there are more windows", selection: settings.binding(for: display, \.overflow)) {
            ForEach(OverflowPolicy.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        LabeledContent("Space between windows") {
            Slider(value: settings.binding(for: display, \.spacing), in: LayoutDefaults.spacingRange, step: 1)
                .frame(width: 180)
            Text("\(Int(settings.configuration.settingsOrDefault(display).spacing)) pt").monospacedDigit().frame(width: 48, alignment: .trailing)
        }
        LabeledContent("Outer margin") {
            Slider(value: settings.binding(for: display, \.margin), in: LayoutDefaults.marginRange, step: 1)
                .frame(width: 180)
            Text("\(Int(settings.configuration.settingsOrDefault(display).margin)) pt").monospacedDigit().frame(width: 48, alignment: .trailing)
        }
        Button("Reset Tile Sizes") {
            settings.update { config in
                if let display { config.updateSettings(for: display) { $0.weights = .equal } } else {
                    config.defaultDisplay.weights = .equal
                }
            }
        }
    }
}

extension Configuration {
    func settingsOrDefault(_ display: DisplayID?) -> DisplaySettings {
        display.map { settings(for: $0) } ?? defaultDisplay
    }
}

private struct LayoutSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("Defaults for new displays") {
                LayoutControls(display: nil)
                LayoutPreview(settings: model.settings.configuration.defaultDisplay)
            }
            Section {
                Text("Drag a window’s edge to resize its tile; neighbours adapt. Hold ⌘ while dragging a window onto another tile to swap them; a plain drag leaves the window floating where you drop it.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct DisplaysSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let displays = model.ui.displays
        Form {
            if displays.isEmpty {
                Text("No displays detected.").foregroundStyle(.secondary)
            }
            ForEach(displays) { display in
                Section(display.name + (display.isBuiltIn ? " (Built-in)" : "")) {
                    LayoutControls(display: display.id)
                    LayoutPreview(settings: model.settings.configuration.settings(for: display.id), aspect: display.frame.size)
                    Button("Reset This Display to Defaults") {
                        model.settings.update { $0.displays[display.id.rawValue] = nil }
                    }
                    .disabled(model.settings.configuration.displays[display.id.rawValue] == nil)
                }
            }
            if displays.count == 1 {
                Text("Connect an external display to configure it separately. Settings for displays you unplug are kept.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// Draws the real layout algorithm with placeholder windows.
struct LayoutPreview: View {
    let settings: DisplaySettings
    var aspect = CGSize(width: 1600, height: 1000)

    var body: some View {
        let area = CGRect(origin: .zero, size: aspect)
        let windows = (0..<settings.maxWindows).map { _ in PlannerWindow(id: WindowID()) }
        let plan = TilePlanner.plan(windows: windows, settings: settings, area: area)
        GeometryReader { proxy in
            let scale = min(proxy.size.width / aspect.width, proxy.size.height / aspect.height)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                ForEach(Array(plan.tileFrames.enumerated()), id: \.offset) { index, frame in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(index == 0 ? Color.accentColor.opacity(0.7) : Color.accentColor.opacity(0.35))
                        .frame(width: frame.width * scale, height: frame.height * scale)
                        .offset(x: frame.minX * scale, y: frame.minY * scale)
                }
            }
            .frame(width: aspect.width * scale, height: aspect.height * scale)
            .frame(maxWidth: .infinity)
        }
        .frame(height: 90)
        .accessibilityLabel("Preview of \(settings.layout.title) with \(settings.maxWindows) windows")
    }
}
