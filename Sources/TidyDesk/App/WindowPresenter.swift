import AppKit
import SwiftUI

/// Opens the app's own windows on demand. The app is a menu bar agent, so nothing opens at launch
/// except onboarding on first run.
@MainActor
final class WindowPresenter {
    enum Kind: Hashable {
        case settings, onboarding

        var title: String {
            switch self {
            case .settings: "\(Branding.name) Settings"
            case .onboarding: "Welcome to \(Branding.name)"
            }
        }
    }

    private var windows: [Kind: NSWindow] = [:]

    func show(_ kind: Kind, model: AppModel) {
        if let existing = windows[kind] {
            NSApp.activate()
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let content: AnyView
        switch kind {
        case .settings: content = AnyView(SettingsView().environment(model))
        case .onboarding: content = AnyView(OnboardingView().environment(model))
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = kind.title
        if kind == .onboarding { Self.applyGlassStyle(to: window) }
        window.contentView = NSHostingView(rootView: content)
        window.isReleasedWhenClosed = false
        window.center()
        windows[kind] = window
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.windows[kind] = nil }
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Edge-to-edge frosted window: transparent title bar, no opaque background to hide the blur.
    private static func applyGlassStyle(to window: NSWindow) {
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
    }

    func close(_ kind: Kind) {
        windows[kind]?.close()
    }
}
