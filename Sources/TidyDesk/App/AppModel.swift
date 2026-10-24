import AppKit
import Observation
import SwiftUI
import TidyDeskCore

enum Branding {
    static var name: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "TidyDesk" }
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1" }
    static var developer: String {
        Bundle.main.object(forInfoDictionaryKey: "TDDeveloperName") as? String ?? "Niajiri"
    }
}

/// Composition root: wires services together and exposes what the interface needs.
@MainActor
@Observable
final class AppModel {
    let settings: SettingsStore
    let permission = AccessibilityPermission()
    let coordinator: TilingCoordinator
    let loginItem = LoginItemService()
    let presenter = WindowPresenter()

    private(set) var shortcutFailures: [ShortcutAction: GlobalShortcutCenter.Failure] = [:]
    private(set) var loginItemError: String?
    var selectedDisplayID: DisplayID?

    @ObservationIgnored private let shortcutCenter = GlobalShortcutCenter()
    @ObservationIgnored private let switcher = SwitcherController()
    @ObservationIgnored private let palettePresenter = FloatingPanelPresenter()
    @ObservationIgnored private let toast = ToastPresenter()

    init() {
        let url = ConfigurationStore.defaultFileURL(appFolderName: Branding.name)
        settings = SettingsStore(store: ConfigurationStore(fileURL: url))
        coordinator = TilingCoordinator(settings: settings, permission: permission)
    }

    var ui: TilingUIState { coordinator.ui }

    /// Display the menu and per-display controls act on.
    var currentDisplay: DisplayInfo? {
        ui.displays.first { $0.id == selectedDisplayID } ?? ui.displays.first
    }

    func start() {
        permission.onChange = { [weak self] _ in self?.coordinator.permissionChanged() }
        permission.startObserving()
        settings.onChange = { [weak self] old, new in
            self?.coordinator.settingsChanged(old: old, new: new)
            if old.shortcutOverrides != new.shortcutOverrides { self?.registerShortcuts() }
            if old.appearance.mode != new.appearance.mode { Self.applyAppearance(new.appearance.mode) }
        }
        Self.applyAppearance(settings.configuration.appearance.mode)
        coordinator.onSuggestion = { [weak self] in self?.present($0) }
        shortcutCenter.onAction = { [weak self] in self?.perform($0) }
        registerShortcuts()
        coordinator.start()
        coordinator.refreshDisplays()
        if !settings.configuration.hasCompletedOnboarding || !permission.isGranted { showOnboarding() }
    }

    func stop() {
        settings.flush()
        shortcutCenter.stop()
        coordinator.stop()
        permission.stopObserving()
    }

    // MARK: Windows

    func showSettings() { presenter.show(.settings, model: self) }
    func showOnboarding() { presenter.show(.onboarding, model: self) }

    func showSwitcher() {
        let groups = coordinator.switcherGroups()
        switcher.show(groups: groups) { [weak self] id in self?.coordinator.activate(id) }
    }

    /// Shows a suggestion unless the welcome tour is open, which already covers the same ground.
    private func present(_ suggestion: SuggestionKind) {
        guard !presenter.isShown(.onboarding) else { return }
        let dismiss = { [weak self] in
            self?.toast.dismiss()
            self?.coordinator.suggestionDismissed(suggestion)
        }
        let actions: SuggestionActions
        switch suggestion {
        case .grantAccess:
            actions = SuggestionActions(
                primary: { [weak self] in
                    guard let self else { return }
                    toast.dismiss()
                    presenter.show(.onboarding, model: self, startAt: .grant)
                },
                secondary: nil, dismiss: dismiss)
        case .tidyUp:
            actions = SuggestionActions(
                primary: { [weak self] in
                    self?.toast.dismiss()
                    self?.settings.update { $0.hasCompletedOnboarding = true; $0.isTilingEnabled = true }
                    self?.coordinator.arrangeNow()
                },
                secondary: { [weak self] in
                    self?.toast.dismiss()
                    self?.coordinator.arrangeNow()
                },
                dismiss: dismiss)
        }
        toast.show(SuggestionToastView(kind: suggestion, actions: actions), onTimeout: {})
    }

    func showCommandPalette() {
        let shortcuts = settings.configuration.shortcuts
        var commands = ShortcutAction.allCases.map { action in
            PaletteCommand(
                item: CommandItem(
                    id: action.rawValue, title: action.title, keywords: action.keywords,
                    shortcutText: shortcuts.bindings[action]?.display),
                run: { [weak self] in self?.perform(action) })
        }
        commands += [
            PaletteCommand(
                item: CommandItem(id: "settings", title: "Open Settings", keywords: ["preferences", "options", "configure"]),
                run: { [weak self] in self?.showSettings() }),
            PaletteCommand(
                item: CommandItem(
                    id: "explain", title: "Explain Active Window", keywords: ["why", "not tiled", "floating", "debug"]),
                run: { [weak self] in self?.showWindowExplanation() }),
            PaletteCommand(
                item: CommandItem(id: "tour", title: "Show Welcome Tour", keywords: ["onboarding", "help", "intro"]),
                run: { [weak self] in self?.showOnboarding() }),
        ]
        let model = PaletteModel(commands: commands)
        palettePresenter.present(
            CommandPaletteView(
                model: model,
                onRun: { [weak self] command in
                    // Close first so the previously active window is the target again.
                    self?.palettePresenter.dismiss()
                    Task { @MainActor in command.run() }
                },
                onDismiss: { [weak self] in self?.palettePresenter.dismiss() }),
            size: NSSize(width: 560, height: 400), anchor: .upper)
    }

    func showWindowExplanation() {
        let alert = NSAlert()
        alert.messageText = "Why isn’t this window tiled?"
        alert.informativeText = coordinator.explainActiveWindow()
        alert.addButton(withTitle: "OK")
        NSApp.activate()
        alert.runModal()
    }

    func completeOnboarding() {
        settings.update { $0.hasCompletedOnboarding = true }
        presenter.close(.onboarding)
    }

    // MARK: Shortcuts

    func registerShortcuts() {
        shortcutFailures = shortcutCenter.register(settings.configuration.shortcuts)
        for (action, failure) in shortcutFailures {
            Log.shortcuts.error("Shortcut \(action.rawValue, privacy: .public) unavailable: \(failure.explanation, privacy: .public)")
        }
    }

    func perform(_ action: ShortcutAction) {
        switch action {
        case .arrangeNow: coordinator.arrangeNow()
        case .toggleTiling: coordinator.setTilingEnabled(!settings.configuration.isTilingEnabled)
        case .toggleLayout: coordinator.toggleLayout(on: coordinator.activeWindow().flatMap {
            DisplayService.display(for: $0.frame, in: coordinator.displays)?.id
        } ?? currentDisplay?.id)
        case .restoreArrangement: coordinator.restorePreviousArrangement()
        case .swapPrevious: coordinator.swapActive(offset: -1)
        case .swapNext: coordinator.swapActive(offset: 1)
        case .moveToPreviousDisplay: coordinator.moveActiveToDisplay(offset: -1)
        case .moveToNextDisplay: coordinator.moveActiveToDisplay(offset: 1)
        case .focusMode: coordinator.toggleFocus()
        case .noPeek: coordinator.toggleNoPeek()
        case .cleanSpace: coordinator.toggleCleanSpace()
        case .windowSwitcher: showSwitcher()
        case .commandPalette: showCommandPalette()
        case .growTile: coordinator.adjustActiveTile(grow: true)
        case .shrinkTile: coordinator.adjustActiveTile(grow: false)
        case .resetSizes: coordinator.resetSizes()
        case .cycleStack: coordinator.cycleStack()
        case .toggleFloat: coordinator.toggleFloatActive()
        }
    }

    // MARK: Login item

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try loginItem.setEnabled(enabled)
            loginItemError = nil
        } catch {
            loginItemError = "Start at Login could not be changed: \(error.localizedDescription)"
        }
    }

    // MARK: Appearance

    private static func applyAppearance(_ mode: AppearanceMode) {
        switch mode {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
