import AppKit
import TidyDeskCore

struct OverlayContext {
    var displays: [DisplayInfo] = []
    /// Tile rectangles per display in Accessibility coordinates.
    var tiles: [DisplayID: [CGRect]] = [:]
    var activeFrame: CGRect?
    var activePID: pid_t?
    var activeDisplay: DisplayID?
    var appearance = AppearanceSettings()
    var noPeek = false
    var cleanSpaceDisplay: DisplayID?
}

/// Owns every click-through overlay window (borders, No Peek dimming, Clean Space backdrop).
/// Overlays never take focus, never capture content, and are all removed by `removeAll()`.
@MainActor
final class OverlayController {
    private var borderWindows: [DisplayID: NSWindow] = [:]
    private var backdropWindows: [DisplayID: NSWindow] = [:]

    func update(_ context: OverlayContext) {
        updateBorders(context)
        updateBackdrop(context)
    }

    func removeAll() {
        (Array(borderWindows.values) + Array(backdropWindows.values)).forEach { $0.orderOut(nil); $0.close() }
        borderWindows = [:]
        backdropWindows = [:]
    }

    // MARK: Borders

    private func updateBorders(_ context: OverlayContext) {
        let appearance = context.appearance
        let wantsBorders = appearance.showActiveBorder || appearance.showAllBorders
        let connected = Set(context.displays.map(\.id))
        for id in borderWindows.keys where !connected.contains(id) || !wantsBorders {
            borderWindows.removeValue(forKey: id)?.close()
        }
        guard wantsBorders else { return }

        for display in context.displays {
            guard let screen = NSScreen.screen(withNumber: display.backingScreenNumber) else { continue }
            let tiles = context.tiles[display.id] ?? []
            let window = borderWindows[display.id] ?? makeBorderWindow()
            borderWindows[display.id] = window
            if window.frame != screen.frame { window.setFrame(screen.frame, display: false) }

            var rects: [BorderView.Item] = []
            let activeOnThisDisplay = context.activeDisplay == display.id ? context.activeFrame : nil
            if appearance.showAllBorders {
                rects += tiles.map { BorderView.Item(rect: local($0, in: display), isActive: false) }
            }
            if appearance.showActiveBorder, let active = activeOnThisDisplay {
                rects.removeAll { $0.rect.isApproximatelyEqual(to: local(active, in: display), tolerance: 6) }
                rects.append(BorderView.Item(rect: local(active, in: display), isActive: true))
            }
            if let view = window.contentView as? BorderView {
                view.items = rects
                view.style = appearance
            }
            if rects.isEmpty { window.orderOut(nil) } else { window.orderFrontRegardless() }
        }
    }

    private func makeBorderWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.contentView = BorderView()
        return window
    }

    private func local(_ rect: CGRect, in display: DisplayInfo) -> CGRect {
        let relative = rect.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
        return ScreenCoordinates.flip(relative, primaryHeight: display.frame.height)
    }

    // MARK: Backdrop (No Peek / Clean Space)

    private func updateBackdrop(_ context: OverlayContext) {
        var target: (display: DisplayInfo, color: NSColor)?
        if let cleanID = context.cleanSpaceDisplay, let display = context.displays.first(where: { $0.id == cleanID }) {
            target = (display, NSColor.underPageBackgroundColor)
        } else if context.noPeek, let activeID = context.activeDisplay,
                  let display = context.displays.first(where: { $0.id == activeID })
        {
            target = (display, NSColor.black.withAlphaComponent(context.appearance.noPeekDimming))
        }

        for id in backdropWindows.keys where id != target?.display.id {
            backdropWindows.removeValue(forKey: id)?.close()
        }
        guard let target, let pid = context.activePID, let frame = context.activeFrame,
              let screen = NSScreen.screen(withNumber: target.display.backingScreenNumber),
              let reference = Self.windowNumber(pid: pid, frame: frame)
        else {
            // Without a window to sit beneath, showing the backdrop would cover everything.
            backdropWindows.values.forEach { $0.orderOut(nil) }
            return
        }
        let window = backdropWindows[target.display.id] ?? makeBackdropWindow()
        backdropWindows[target.display.id] = window
        window.backgroundColor = target.color
        if window.frame != screen.frame { window.setFrame(screen.frame, display: false) }
        window.order(.below, relativeTo: reference)
    }

    private func makeBackdropWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .normal
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.stationary, .ignoresCycle]
        return window
    }

    /// Finds the window-server number of another app's window by owner and bounds. Reading
    /// numbers and bounds needs no Screen Recording permission; titles are never requested.
    private static func windowNumber(pid: pid_t, frame: CGRect) -> Int? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
        for info in list {
            guard info[kCGWindowOwnerPID as String] as? pid_t == pid,
                  info[kCGWindowLayer as String] as? Int == 0,
                  let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
                  bounds.isApproximatelyEqual(to: frame, tolerance: 8),
                  let number = info[kCGWindowNumber as String] as? Int
            else { continue }
            return number
        }
        return nil
    }
}

extension NSScreen {
    static func screen(withNumber number: CGDirectDisplayID) -> NSScreen? {
        screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == number }
    }
}

final class BorderView: NSView {
    struct Item {
        var rect: CGRect
        var isActive: Bool
    }

    var items: [Item] = [] { didSet { needsDisplay = true } }
    var style = AppearanceSettings() { didSet { needsDisplay = true } }

    override var isFlipped: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let color = NSColor(
            srgbRed: style.highlightColor.red, green: style.highlightColor.green,
            blue: style.highlightColor.blue, alpha: 1)
        let highContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let thickness = style.borderThickness + (highContrast ? 1 : 0)
        let cornerRadius: CGFloat = 12

        for item in items {
            let path = NSBezierPath(
                roundedRect: item.rect.insetBy(dx: -thickness / 2, dy: -thickness / 2),
                xRadius: cornerRadius + thickness / 2, yRadius: cornerRadius + thickness / 2)
            path.lineWidth = thickness
            NSGraphicsContext.saveGraphicsState()
            if item.isActive, style.glow {
                let shadow = NSShadow()
                shadow.shadowColor = color.withAlphaComponent(0.8)
                shadow.shadowBlurRadius = 14
                shadow.set()
            }
            color.withAlphaComponent(item.isActive ? 1 : 0.45).setStroke()
            path.stroke()
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}
