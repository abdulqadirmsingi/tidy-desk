import AppKit
import SwiftUI

/// A panel that can take key events without activating the app, so the previously active window
/// stays active and commands act on it.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Shows one transient glass panel (switcher, command palette) and removes it when it loses focus.
@MainActor
final class FloatingPanelPresenter {
    enum Anchor {
        case center
        /// Near the top, where search launchers conventionally appear.
        case upper
        /// Just below a status item, given by its rectangle in screen coordinates.
        case below(CGRect)
    }

    private var panel: KeyablePanel?
    private var resignToken: NSObjectProtocol?

    var isPresented: Bool { panel != nil }
    /// Called whenever a presented panel goes away (focus loss, action, or explicit dismiss).
    var onDismiss: (() -> Void)?

    func present<Content: View>(_ content: Content, size: NSSize? = nil, anchor: Anchor) {
        dismiss()
        let host = NSHostingView(rootView: content)
        let panelSize = size ?? host.fittingSize
        host.setFrameSize(panelSize)

        let panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .modalPanel
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        if case let .below(anchorRect) = anchor {
            let screen = NSScreen.screens.first { $0.frame.intersects(anchorRect) } ?? NSScreen.main
            let visible = screen?.visibleFrame ?? anchorRect
            let x = min(max(anchorRect.midX - panelSize.width / 2, visible.minX + 8), visible.maxX - panelSize.width - 8)
            panel.setFrameOrigin(NSPoint(x: x, y: anchorRect.minY - panelSize.height - 6))
        } else if let screen = Self.screenUnderMouse() {
            let y: CGFloat = switch anchor {
            case .center: screen.frame.midY - panelSize.height / 2
            default: screen.frame.maxY - screen.frame.height * 0.26 - panelSize.height
            }
            panel.setFrameOrigin(NSPoint(x: screen.frame.midX - panelSize.width / 2, y: y))
        }
        panel.makeKeyAndOrderFront(nil)
        resignToken = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
        self.panel = panel
    }

    func dismiss() {
        if let resignToken { NotificationCenter.default.removeObserver(resignToken) }
        resignToken = nil
        guard let panel else { return }
        panel.orderOut(nil)
        panel.close()
        self.panel = nil
        onDismiss?()
    }

    private static func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
    }
}
