import AppKit
import TidyDeskCore

/// User-facing commands, shared by the menu bar, shortcuts and the switcher.
extension TilingCoordinator {
    private static let resizeStep = 1.15

    // MARK: Tiling control

    func arrangeNow() {
        budget.reset()
        ui.notice = nil
        reconcile(manual: true)
    }

    func setTilingEnabled(_ enabled: Bool) {
        settings.update { $0.isTilingEnabled = enabled }
        if !enabled { exitPresentationModes() }
    }

    /// Puts every window back where it was when TidyDesk first saw it, and pauses tiling so
    /// the windows are not immediately re-tiled.
    func restorePreviousArrangement() {
        exitPresentationModes()
        settings.update(silent: true) { $0.isTilingEnabled = false }
        for (id, frame) in originalFrames {
            if let window = tracked[id] { _ = placement.place(window.element, to: frame) }
        }
        originalFrames = [:]
        ui.notice = "Previous arrangement restored. Tiling is paused."
        ui.status = currentStatus()
        syncUI()
    }

    // MARK: Active window

    func updateActiveWindow() {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ownPID else { return }
        let focused = AXElement.application(pid: app.processIdentifier).element(kAXFocusedWindowAttribute)
        lastActiveWindow = focused.flatMap { discovery.window(for: $0) }.flatMap { tracked[$0] != nil ? $0 : nil }
    }

    func activeWindow() -> TrackedWindow? {
        if tracked.isEmpty { discoverAndTrack() }
        updateActiveWindow()
        if lastActiveWindow == nil { discoverAndTrack(); updateActiveWindow() }
        return lastActiveWindow.flatMap { tracked[$0] }
    }

    func focusChanged() {
        refreshStatusIfChanged()
        updateActiveWindow()
        if let id = lastActiveWindow, focus.handle(.anotherWindowActivated(id)) {
            exitPresentationModes()
            scheduleReconcile()
        }
        refreshOverlays()
    }

    /// The tile the window currently occupies and the display it is on.
    private func tile(of id: WindowID) -> (display: DisplayID, tile: Int, plan: TilePlan)? {
        for (display, plan) in lastPlans {
            guard let item = plan.placements.first(where: { $0.id == id }) else { continue }
            switch item.role {
            case let .tile(index), let .stacked(onTile: index): return (display, index, plan)
            case .floating: return nil
            }
        }
        return nil
    }

    // MARK: Order and displays

    func swapActive(offset: Int) {
        guard let window = activeWindow(), let (_, index, plan) = tile(of: window.id), plan.tileFrames.count > 1
        else { return }
        let target = (index + offset + plan.tileFrames.count) % plan.tileFrames.count
        guard let owner = plan.placements.first(where: { $0.role == .tile(target) }) else { return }
        if order.swap(window.id, owner.id) { reconcile() }
    }

    func moveActiveToDisplay(offset: Int) {
        guard displays.count > 1 else {
            ui.notice = "Connect another display to move windows between displays."
            return
        }
        guard let window = activeWindow(),
              let current = DisplayService.display(for: window.frame, in: displays),
              let index = displays.firstIndex(where: { $0.id == current.id })
        else { return }
        let next = displays[(index + offset + displays.count) % displays.count]
        order.move(window.id, to: next.id)
        userFloating.remove(window.id)
        exitPresentationModes()
        reconcile(manual: true)
    }

    func toggleFloatActive() {
        guard let window = activeWindow() else { return }
        if userFloating.remove(window.id) == nil { userFloating.insert(window.id) }
        reconcile()
    }

    func cycleStack() {
        guard let window = activeWindow(), let (display, index, plan) = tile(of: window.id) else { return }
        let members = plan.stack(onTile: index)
        guard members.count > 1, let position = members.firstIndex(of: window.id) else {
            ui.notice = "No stacked windows on this tile."
            return
        }
        let next = members[(position + 1) % members.count]
        let key = StackKey(display: display, tile: index)
        stackActive[key] = next
        stackRaised[key] = nil
        if let target = tracked[next] { placement.raise(target.element, pid: target.pid, activate: true) }
        reconcile()
    }

    // MARK: Layout adjustments

    func toggleLayout(on display: DisplayID?) {
        guard let id = display ?? displays.first?.id else { return }
        settings.update { config in
            config.updateSettings(for: id) { $0.layout = $0.layout == .grid ? .columns : .grid }
        }
    }

    func adjustActiveTile(grow: Bool) {
        guard let window = activeWindow(), let (displayID, index, plan) = tile(of: window.id),
              let position = LayoutAlgorithms.position(
                ofTile: index, kind: settings.configuration.settings(for: displayID).layout, count: plan.tileFrames.count)
        else { return }
        let factor = grow ? Self.resizeStep : 1 / Self.resizeStep
        settings.update { config in
            config.updateSettings(for: displayID) { display in
                var primary = display.weights.primary
                var secondary = display.weights.secondary
                if position.columnCount > 1 { primary = position.column == 0 ? primary * factor : primary / factor }
                if position.rowCount == 2 { secondary = position.row == 0 ? secondary * factor : secondary / factor }
                display.weights = TileWeights(primary: primary, secondary: secondary)
            }
        }
    }

    func resetSizes(on display: DisplayID? = nil) {
        let ids = display.map { [$0] } ?? displays.map(\.id)
        settings.update { config in
            for id in ids { config.updateSettings(for: id) { $0.weights = .equal } }
        }
    }

    // MARK: Presentation modes

    func toggleFocus() {
        if focus.isActive, cleanSpaceDisplay == nil {
            exitPresentationModes()
            reconcile(manual: true, tile: currentStatus() == .active)
            return
        }
        guard let window = activeWindow() else {
            ui.notice = "Click a window first, then use Focus mode."
            return
        }
        exitPresentationModes()
        preFocusFrame = window.frame
        focus.enter(window.id)
        reconcile(manual: true, tile: currentStatus() == .active)
    }

    func toggleCleanSpace() {
        if cleanSpaceDisplay != nil {
            exitPresentationModes()
            reconcile(manual: true, tile: currentStatus() == .active)
            return
        }
        guard let window = activeWindow(), let display = DisplayService.display(for: window.frame, in: displays) else {
            ui.notice = "Click a window first, then use Clean Space."
            return
        }
        exitPresentationModes()
        preFocusFrame = window.frame
        focus.enter(window.id)
        cleanSpaceDisplay = display.id
        reconcile(manual: true, tile: currentStatus() == .active)
    }

    func toggleNoPeek() {
        noPeekActive.toggle()
        if noPeekActive, activeWindow() == nil {
            noPeekActive = false
            ui.notice = "Click a window first, then use No Peek."
        }
        syncUI()
        refreshOverlays()
    }

    // MARK: Switcher

    struct SwitcherEntry: Identifiable {
        let id: WindowID
        let appName: String
        let icon: NSImage?
        /// Read for this switcher session only and never stored.
        let title: String
    }

    struct SwitcherGroup: Identifiable {
        let id: DisplayID
        let displayName: String
        var entries: [SwitcherEntry]
    }

    func switcherGroups() -> [SwitcherGroup] {
        discoverAndTrack()
        refreshDisplays()
        var groups: [DisplayID: SwitcherGroup] = [:]
        for window in tracked.values.sorted(by: { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }) {
            guard let display = DisplayService.display(for: window.frame, in: displays) else { continue }
            let icon = NSRunningApplication(processIdentifier: window.pid)?.icon
            let entry = SwitcherEntry(
                id: window.id, appName: window.appName, icon: icon,
                title: window.element.string(kAXTitleAttribute) ?? "")
            groups[display.id, default: SwitcherGroup(id: display.id, displayName: display.name, entries: [])]
                .entries.append(entry)
        }
        return displays.compactMap { groups[$0.id] }
    }

    func activate(_ id: WindowID) {
        guard let window = tracked[id] else { return }
        placement.raise(window.element, pid: window.pid, activate: true)
        lastActiveWindow = id
        focusChanged()
    }
}
