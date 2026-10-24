import AppKit
import SwiftUI
import TidyDeskCore

struct ShortcutsSettings: View {
    @Environment(AppModel.self) private var model
    @State private var recording: ShortcutAction?

    var body: some View {
        let map = model.settings.configuration.shortcuts
        Form {
            Section {
                ForEach(ShortcutAction.allCases, id: \.self) { action in
                    HStack {
                        Text(action.title)
                        Spacer()
                        if let message = problem(for: action, in: map) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                                .help(message).accessibilityLabel(message)
                        }
                        ShortcutRecorder(
                            shortcut: map.bindings[action] ?? action.defaultShortcut,
                            isRecording: recording == action,
                            begin: { recording = action },
                            finish: { shortcut in
                                if let shortcut {
                                    model.settings.update { $0.shortcutOverrides[action.rawValue] = shortcut }
                                }
                                recording = nil
                            })
                    }
                }
            } footer: {
                Text("Shortcuts work in every app. A warning means another binding or app already uses the combination.")
            }
            Section {
                Button("Restore Default Shortcuts") { model.settings.update { $0.shortcutOverrides = [:] } }
                    .disabled(model.settings.configuration.shortcutOverrides.isEmpty)
            }
        }
        .formStyle(.grouped)
    }

    private func problem(for action: ShortcutAction, in map: ShortcutMap) -> String? {
        let others = map.conflictingActions(for: action)
        if !others.isEmpty { return "Also used by “\(others[0].title)”. Change one of them." }
        return model.shortcutFailures[action]?.explanation
    }
}

private struct ShortcutRecorder: View {
    let shortcut: Shortcut
    let isRecording: Bool
    let begin: () -> Void
    let finish: (Shortcut?) -> Void
    @State private var monitor: Any?

    var body: some View {
        Button(isRecording ? "Press keys…" : shortcut.display) { isRecording ? finish(nil) : begin() }
            .buttonStyle(.bordered)
            .monospacedDigit()
            .frame(minWidth: 96)
            .accessibilityLabel(isRecording ? "Recording shortcut" : "Shortcut \(shortcut.display)")
            .onChange(of: isRecording) { _, recording in
                recording ? startMonitoring() : stopMonitoring()
            }
            .onDisappear { stopMonitoring() }
    }

    private func startMonitoring() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {  // Escape cancels
                finish(nil)
                return nil
            }
            var modifiers: ShortcutModifiers = []
            if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
            if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
            if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
            if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
            // Global shortcuts need a modifier; a bare key would hijack typing everywhere.
            guard !modifiers.isEmpty else { NSSound.beep(); return nil }
            finish(Shortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers))
            return nil
        }
    }

    private func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

struct AppearanceSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let settings = model.settings
        Form {
            Section("Theme") {
                Picker("Appearance", selection: settings.binding(\.appearance.mode)) {
                    ForEach(AppearanceMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Menu bar icon", selection: settings.binding(\.appearance.menuBarIcon)) {
                    ForEach(MenuBarIconStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section("Window borders") {
                Toggle("Highlight the active window", isOn: settings.binding(\.appearance.showActiveBorder))
                Toggle("Show borders around all tiles", isOn: settings.binding(\.appearance.showAllBorders))
                Toggle("Glow around the active window", isOn: settings.binding(\.appearance.glow))
                ColorPicker("Highlight color", selection: colorBinding, supportsOpacity: false)
                LabeledContent("Border thickness") {
                    Slider(value: settings.binding(\.appearance.borderThickness), in: AppearanceSettings.borderThicknessRange, step: 1)
                        .frame(width: 180)
                }
            }
            Section("No Peek") {
                LabeledContent("Dimming") {
                    Slider(value: settings.binding(\.appearance.noPeekDimming), in: 0.2...0.9).frame(width: 180)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: {
                let c = model.settings.configuration.appearance.highlightColor
                return Color(.sRGB, red: c.red, green: c.green, blue: c.blue)
            },
            set: { color in
                let ns = NSColor(color).usingColorSpace(.sRGB) ?? .systemBlue
                model.settings.update {
                    $0.appearance.highlightColor = RGBColor(
                        red: Double(ns.redComponent), green: Double(ns.greenComponent), blue: Double(ns.blueComponent))
                }
            })
    }
}

struct AppsSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let config = model.settings.configuration
        Form {
            Section("Excluded apps") {
                if config.excludedBundleIDs.isEmpty {
                    Text("No apps are excluded. Excluded apps keep their windows exactly where you put them.")
                        .foregroundStyle(.secondary)
                }
                ForEach(config.excludedBundleIDs.sorted(), id: \.self) { id in
                    HStack {
                        Text(AppNames.name(for: id))
                        Spacer()
                        Button("Include Again") { model.settings.update { $0.excludedBundleIDs.remove(id) } }
                    }
                }
                Menu("Exclude a Running App") {
                    ForEach(AppNames.runningApps(), id: \.id) { app in
                        Button(app.name) { model.settings.update { $0.excludedBundleIDs.insert(app.id) } }
                            .disabled(config.excludedBundleIDs.contains(app.id))
                    }
                }
            }
            Section("Learned minimum sizes") {
                if config.learnedMinimums.isEmpty {
                    Text("None yet. When an app refuses to shrink, its minimum size is remembered here.")
                        .foregroundStyle(.secondary)
                }
                ForEach(config.learnedMinimums.keys.sorted(), id: \.self) { id in
                    if let size = config.learnedMinimums[id] {
                        LabeledContent(AppNames.name(for: id), value: "\(Int(size.width)) × \(Int(size.height))")
                    }
                }
                Button("Clear Learned Sizes") { model.settings.update { $0.learnedMinimums = [:] } }
                    .disabled(config.learnedMinimums.isEmpty)
            }
        }
        .formStyle(.grouped)
    }
}

enum AppNames {
    static func name(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    static func runningApps() -> [(id: String, name: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { app in app.bundleIdentifier.map { ($0, app.localizedName ?? $0) } }
            .sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
    }
}

struct PrivacySettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("Accessibility permission") {
                Label(
                    model.permission.isGranted ? "Access granted" : "Access not granted",
                    systemImage: model.permission.isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(model.permission.isGranted ? .green : .orange)
                Text("Accessibility access lets \(Branding.name) see which windows are open and move or resize them. Without it, nothing is arranged and the app only waits.")
                    .font(.callout).foregroundStyle(.secondary)
                if !model.permission.isGranted {
                    Button("Open Accessibility Settings") {
                        model.permission.requestPrompt()
                        model.permission.openSystemSettings()
                    }
                    Text("If you just enabled it and nothing changes, quit and reopen \(Branding.name).")
                        .font(.callout).foregroundStyle(.secondary)
                    StaleGrantHelp()
                }
            }
            Section("What \(Branding.name) never does") {
                Label("Capture your screen or record it", systemImage: "eye.slash")
                Label("Read document contents or save window titles", systemImage: "doc.text.magnifyingglass")
                Label("Send analytics, crash reports or any data over the network", systemImage: "network.slash")
            }
            Section("Local data") {
                Text("Settings are stored in ~/Library/Application Support/\(Branding.name)/config.json.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Show Settings File in Finder") {
                    let url = ConfigurationStore.defaultFileURL(appFolderName: Branding.name)
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct AboutSettings: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("Name", value: Branding.name)
                LabeledContent("Version", value: Branding.version)
                LabeledContent("Build", value: Branding.build)
                LabeledContent("Developer", value: Branding.developer)
            }
            Section {
                Text("Updates are manual: install a newer build over the old one. \(Branding.name) never checks for updates or contacts any server.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
