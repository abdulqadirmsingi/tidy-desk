import AppKit
import TidyDeskCore

/// Distinguishing the user's mouse gestures from our own writes and from app-driven changes.
extension TilingCoordinator {
    private static let gestureSettleDelay: Duration = .milliseconds(80)

    func handleGeometry(_ element: AXElement) {
        guard let id = discovery.window(for: element), tracked[id] != nil, let frame = element.frame else {
            scheduleReconcile()
            return
        }
        if let echo = expected[id], Date() < echo.deadline,
           echo.frames.contains(where: { $0.isApproximatelyEqual(to: frame, tolerance: 4) })
        {
            return
        }
        if NSEvent.pressedMouseButtons & 1 != 0 {
            pendingGestures.insert(id)
            if NSEvent.modifierFlags.contains(.command) { swapGestures.insert(id) }
            installMouseMonitor()
            return
        }
        // Not our write and not a mouse gesture: an app moved itself. Allow a few corrections,
        // then stop so we never fight it.
        if budget.recordUnsolicited(id) {
            ui.notice = "A window keeps moving itself and was left floating."
        }
        scheduleReconcile()
    }

    private func installMouseMonitor() {
        guard mouseUpMonitor == nil else { return }
        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            MainActor.assumeIsolated { self?.gestureEnded() }
        }
    }

    func removeMouseMonitor() {
        if let monitor = mouseUpMonitor { NSEvent.removeMonitor(monitor) }
        mouseUpMonitor = nil
    }

    private func gestureEnded() {
        removeMouseMonitor()
        Task { [weak self] in
            try? await Task.sleep(for: Self.gestureSettleDelay)
            self?.finishGestures()
        }
    }

    private func finishGestures() {
        let ids = pendingGestures
        let swapIDs = swapGestures
        let commandHeldNow = NSEvent.modifierFlags.contains(.command)
        pendingGestures = []
        swapGestures = []
        for id in ids { _ = finishGesture(id, swapHeld: swapIDs.contains(id) || commandHeldNow) }
        reconcile()
    }

    /// Plain drag places a window freely (it floats); ⌘-drag swaps or moves it between tiles/displays;
    /// resizing an edge adapts the neighbours; tiny nudges snap back.
    /// Returns true if order or settings changed.
    private func finishGesture(_ id: WindowID, swapHeld: Bool) -> Bool {
        guard let window = tracked[id], let frame = window.element.frame,
              let (displayID, item) = placement(of: id),
              let target = item.frame, case let .tile(currentTile) = item.role,
              let plan = lastPlans[displayID], let display = displays.first(where: { $0.id == displayID })
        else { return false }

        let current = settings.configuration.settings(for: displayID)
        switch GestureClassifier.classify(target: target, final: frame, swapModifierHeld: swapHeld) {
        case .unchanged, .snapBack:
            return false
        case .float:
            userFloating.insert(id)
            ui.notice = "\(window.appName) now floats where you put it. Hold ⌘ while dragging to swap tiles, or use Float Active Window to tile it again."
            return true
        case .resize:
            let weights = RatioInference.weights(
                afterResizing: currentTile, to: frame, oldFrames: plan.tileFrames, kind: current.layout,
                area: display.usableFrame, margin: current.margin, spacing: current.spacing, current: current.weights)
            guard weights != current.weights else {
                // The neighbours cannot absorb this resize (single window, or an edge nothing shares).
                // Snapping back would feel like the window can't be resized; float it instead.
                let change = max(abs(frame.width - target.width), abs(frame.height - target.height))
                guard change > TilingTuning.floatOnResizeThreshold else { return false }
                userFloating.insert(id)
                ui.notice = "\(window.appName) is now floating because the layout can’t take that size. Use Float Active Window to tile it again."
                return true
            }
            settings.update(silent: true) { $0.updateSettings(for: displayID) { $0.weights = weights } }
            return true
        case .swapOrMove:
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            let cursor = ScreenCoordinates.flip(NSEvent.mouseLocation, primaryHeight: primaryHeight)
            guard let dropDisplay = DisplayService.display(at: cursor, in: displays) else { return false }
            let dropTile = lastPlans[dropDisplay.id].flatMap { tileIndex(containing: cursor, in: $0.tileFrames) }
            if dropDisplay.id == displayID {
                guard let dropTile, dropTile != currentTile,
                      let owner = plan.placements.first(where: { $0.role == .tile(dropTile) })
                else { return false }
                return order.swap(id, owner.id)
            }
            order.move(id, to: dropDisplay.id, at: dropTile)
            return true
        }
    }

    private func placement(of id: WindowID) -> (DisplayID, Placement)? {
        for (display, plan) in lastPlans {
            if let item = plan.placements.first(where: { $0.id == id }) { return (display, item) }
        }
        return nil
    }

    private func tileIndex(containing point: CGPoint, in frames: [CGRect]) -> Int? {
        if let hit = frames.firstIndex(where: { $0.insetBy(dx: -8, dy: -8).contains(point) }) { return hit }
        return frames.indices.min {
            hypot(frames[$0].midX - point.x, frames[$0].midY - point.y)
                < hypot(frames[$1].midX - point.x, frames[$1].midY - point.y)
        }
    }
}
