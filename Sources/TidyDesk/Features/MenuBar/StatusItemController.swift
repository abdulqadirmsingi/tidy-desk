import AppKit
import Observation
import SwiftUI
import TidyDeskCore

/// The menu bar icon. Click opens the glass panel; right-click (or Control-click) opens a small menu.
@MainActor
final class StatusItemController {
    /// A click this soon after the panel closed itself is the same click that closed it.
    private static let reclickWindow: TimeInterval = 0.25

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let presenter = FloatingPanelPresenter()
    private unowned let model: AppModel
    private var lastClosed = Date.distantPast

    init(model: AppModel) {
        self.model = model
        presenter.onDismiss = { [weak self] in self?.lastClosed = Date() }
        item.button?.target = self
        item.button?.action = #selector(clicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        refreshIcon()
        observe()
    }

    deinit { MainActor.assumeIsolated { NSStatusBar.system.removeStatusItem(item) } }

    private func refreshIcon() {
        let config = model.settings.configuration
        let ui = model.ui
        let symbol = MenuBarSymbol.name(
            status: ui.status, isSpecialModeActive: ui.isSpecialModeActive, style: config.appearance.menuBarIcon)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "\(Branding.name): \(ui.status.summary)")
        image?.isTemplate = true
        item.button?.image = image
        item.button?.toolTip = "\(Branding.name) — \(ui.status.summary)"
    }

    /// Re-reads the icon whenever the status or style changes (Observation fires once per registration).
    private func observe() {
        withObservationTracking {
            let ui = model.ui
            _ = (ui.status, ui.isSpecialModeActive, model.settings.configuration.appearance.menuBarIcon)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.refreshIcon()
                self?.observe()
            }
        }
    }

    @objc private func clicked() {
        let event = NSApp.currentEvent
        let isSecondary = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if isSecondary { showContextMenu(); return }
        if presenter.isPresented {
            presenter.dismiss()
        } else if Date().timeIntervalSince(lastClosed) > Self.reclickWindow {
            showPanel()
        }
    }

    private func showPanel() {
        guard let button = item.button, let window = button.window else { return }
        model.captureFrontmostApp()
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        presenter.present(
            MenuPanelView(close: { [weak self] in self?.presenter.dismiss() }).environment(model), anchor: .below(anchor))
    }

    private func showContextMenu() {
        presenter.dismiss()
        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Quit \(Branding.name)", action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func openSettings() { model.showSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
}
