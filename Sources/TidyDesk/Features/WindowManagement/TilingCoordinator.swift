import AppKit
import TidyDeskCore

enum TilingTuning {
    static let debounce: Duration = .milliseconds(120)
    static let wakeSettleDelay: Duration = .seconds(1)
    /// Geometry notifications this soon after our own write are treated as echoes.
    static let ownMoveSuppression: TimeInterval = 0.7
    static let maxPassesPerReconcile = 3
    static let cleanSpaceInset = CGSize(width: 0.08, height: 0.06)
}

struct StackKey: Hashable {
    let display: DisplayID
    let tile: Int
}

struct Expectation {
    var frames: [CGRect]
    var deadline: Date
}

/// The single owner of mutable tiling state. All reconciliation runs on the main actor,
/// so a plan is always applied against the state it was computed from.
@MainActor
final class TilingCoordinator {
    let ui = TilingUIState()
    let settings: SettingsStore
    let permission: AccessibilityPermission
    let discovery = WindowDiscoveryService()
    let displayService = DisplayService()
    let placement = WindowPlacementService()
    let monitor = WindowLifecycleMonitor()
    let overlays = OverlayController()
    let ownPID = ProcessInfo.processInfo.processIdentifier
    static let stageManagerNotice = "Stage Manager is on, so tiling is paused. Turn it off to resume."

    var order = WindowOrder()
    var tracked: [WindowID: TrackedWindow] = [:]
    var lastPlans: [DisplayID: TilePlan] = [:]
    var displays: [DisplayInfo] = []
    var focus = FocusModeState()
    var cleanSpaceDisplay: DisplayID?
    var noPeekActive = false
    var userFloating: Set<WindowID> = []
    /// Caps retries; stubborn windows are excluded from planning until the user intervenes.
    var budget = PlacementBudget()
    var originalFrames: [WindowID: CGRect] = [:]
    var expected: [WindowID: Expectation] = [:]
    var stackActive: [StackKey: WindowID] = [:]
    var stackRaised: [StackKey: WindowID] = [:]
    var pendingGestures: Set<WindowID> = []
    var mouseUpMonitor: Any?
    var lastActiveWindow: WindowID?
    var isAsleep = false
    var preFocusFrame: CGRect?

    private var reconcileTask: Task<Void, Never>?

    init(settings: SettingsStore, permission: AccessibilityPermission) {
        self.settings = settings
        self.permission = permission
    }

    // MARK: Lifecycle

    func start() {
        monitor.onEvent = { [weak self] in self?.handle($0) }
        monitor.start()
        reconcile()
    }

    func stop() {
        reconcileTask?.cancel()
        monitor.stop()
        removeMouseMonitor()
        overlays.removeAll()
    }

    func permissionChanged() {
        if permission.isGranted { reconcile() } else {
            overlays.removeAll()
            ui.status = .needsPermission
        }
    }

    func settingsChanged(old: Configuration, new: Configuration) {
        let layoutChanged = old.defaultDisplay.layout != new.defaultDisplay.layout
            || old.defaultDisplay.maxWindows != new.defaultDisplay.maxWindows
            || old.displays.mapValues({ [$0.layout.rawValue, "\($0.maxWindows)"] })
            != new.displays.mapValues({ [$0.layout.rawValue, "\($0.maxWindows)"] })
        if layoutChanged { exitPresentationModes() }
        budget.reset()
        scheduleReconcile(delay: .zero)
    }

    // MARK: Events

    func handle(_ event: WindowEvent) {
        switch event {
        case .structural: scheduleReconcile()
        case let .geometry(element): handleGeometry(element)
        case .focus: focusChanged()
        case .spaceChanged: scheduleReconcile()
        case .displaysChanged:
            if let id = cleanSpaceDisplay, !displayService.current().contains(where: { $0.id == id }) {
                exitPresentationModes()
            }
            scheduleReconcile()
        case .systemWillSleep, .screenLocked:
            isAsleep = true
            exitPresentationModes()
            overlays.removeAll()
            ui.status = .asleep
        case .systemDidWake, .screenUnlocked:
            isAsleep = false
            scheduleReconcile(delay: TilingTuning.wakeSettleDelay)
        }
    }

    /// Coalesces bursts of events into one reconcile; a newer request supersedes an older one.
    func scheduleReconcile(delay: Duration = TilingTuning.debounce) {
        reconcileTask?.cancel()
        reconcileTask = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled else { return }
            self?.reconcile()
        }
    }

    func currentStatus() -> TilingStatus {
        let config = settings.configuration
        return TilingStatus.resolve(
            permissionGranted: permission.isGranted, isAsleep: isAsleep, stageManagerOn: StageManagerDetector.isEnabled,
            tilingEnabled: config.isTilingEnabled, onboardingComplete: config.hasCompletedOnboarding)
    }

    /// Stage Manager has no change notification, so cheap events (focus changes) re-check it.
    func refreshStatusIfChanged() {
        if currentStatus() != ui.status { reconcile() }
    }

    // MARK: Reconciliation

    /// Brings real windows in line with the plan. `manual` runs even while paused.
    /// - Parameter tile: When false only presentation modes are applied (used by Focus while paused).
    func reconcile(manual: Bool = false, tile: Bool = true) {
        reconcileTask?.cancel()
        let status = currentStatus()
        ui.status = status
        if status == .stageManagerOn {
            ui.notice = Self.stageManagerNotice
        } else if ui.notice == Self.stageManagerNotice {
            ui.notice = nil
        }
        switch status {
        case .active: break
        case .pausedByUser where manual: break
        case .pausedByUser:
            refreshDisplays()
            syncUI()
            return
        case .needsPermission, .stageManagerOn, .asleep:
            overlays.removeAll()
            return
        }

        var passes = 0
        var needsAnotherPass = true
        while needsAnotherPass, passes < TilingTuning.maxPassesPerReconcile {
            needsAnotherPass = runPass(tile: tile)
            passes += 1
        }
        syncUI()
        refreshOverlays()
    }

    /// One discover → plan → apply cycle. Returns true if a refusal taught us something and
    /// the layout should be recomputed.
    private func runPass(tile: Bool) -> Bool {
        refreshDisplays()
        guard !displays.isEmpty else { return false }
        let config = settings.configuration
        let found = discoverAndTrack()
        for window in found.eligible where originalFrames[window.id] == nil {
            originalFrames[window.id] = window.frame
        }
        originalFrames = originalFrames.filter { found.alive.contains($0.key) }
        userFloating.formIntersection(found.alive)
        budget.retain(alive: found.alive)
        monitor.sync(windows: found.eligible)
        if let focused = focus.focusedWindow, tracked[focused] == nil {
            focus.handle(.windowClosed(focused))
            cleanSpaceDisplay = nil
        }

        var present: [DisplayID: [WindowID]] = [:]
        let candidates = found.eligible
            .filter { !userFloating.contains($0.id) && !budget.isStubborn($0.id) }
            .sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
        for window in candidates {
            if let display = DisplayService.display(for: window.frame, in: displays) {
                present[display.id, default: []].append(window.id)
            }
        }
        order.reconcile(present: present, alive: found.alive, connected: Set(displays.map(\.id)))

        var replan = false
        lastPlans = [:]
        for display in displays {
            let visible = Set(present[display.id] ?? [])
            let ids = order.windows(on: display.id).filter { visible.contains($0) }
            let windows = ids.compactMap { tracked[$0] }.map {
                PlannerWindow(id: $0.id, minimumSize: config.learnedMinimums[$0.bundleID ?? ""]?.size ?? .zero)
            }
            let displaySettings = config.settings(for: display.id)
            let plan = TilePlanner.plan(windows: windows, settings: displaySettings, area: display.usableFrame)
            lastPlans[display.id] = plan

            if let focused = focus.focusedWindow, visible.contains(focused), let window = tracked[focused] {
                replan = apply(window, to: focusFrame(on: display, margin: displaySettings.margin)) || replan
                placement.raise(window.element, pid: window.pid, activate: false)
                continue
            }
            guard tile else { continue }
            for item in plan.placements {
                guard let window = tracked[item.id] else { continue }
                if let frame = item.frame {
                    if !window.frame.isApproximatelyEqual(to: frame) { replan = apply(window, to: frame) || replan }
                } else {
                    recoverIfOffscreen(window)
                }
            }
            raiseActiveStackMembers(plan: plan, display: display.id)
        }
        return replan
    }

    /// Moves a window and learns from refusals. Returns true if the plan should be recomputed.
    private func apply(_ window: TrackedWindow, to target: CGRect) -> Bool {
        let result = placement.place(window.element, to: target)
        switch result {
        case let .success(actual):
            tracked[window.id]?.frame = actual
            expected[window.id] = Expectation(
                frames: [target, actual], deadline: Date().addingTimeInterval(TilingTuning.ownMoveSuppression))
            if ConstraintLearner.accepted(requested: target, actual: actual) {
                budget.recordSuccess(window.id)
                return false
            }
            return handleRefusal(window, requested: target, actual: actual)
        case let .failure(failure):
            Log.placement.debug("Placement failed: \(failure.localizedDescription, privacy: .public)")
            return markAttempt(window.id)
        }
    }

    private func handleRefusal(_ window: TrackedWindow, requested: CGRect, actual: CGRect) -> Bool {
        let limit = displays.first { $0.usableFrame.intersects(actual) }?.usableFrame.size ?? actual.size
        if let bundle = window.bundleID {
            let existing = settings.configuration.learnedMinimums[bundle]?.size ?? .zero
            if let learned = ConstraintLearner.learnedMinimum(
                requested: requested, actual: actual, existing: existing, plausibleLimit: limit)
            {
                settings.update(silent: true) {
                    $0.learnedMinimums[bundle] = LearnedMinimum(width: learned.width, height: learned.height)
                }
                ui.notice = "\(window.appName) needs a larger minimum size; the layout was adjusted."
                _ = markAttempt(window.id)
                return true
            }
        }
        return markAttempt(window.id)
    }

    /// Counts a failed attempt; once the budget is spent the window is left alone so we never fight it.
    private func markAttempt(_ id: WindowID) -> Bool {
        guard budget.recordRefusal(id) else { return false }
        ui.notice = "Some windows can’t be resized and were left floating."
        return true
    }

    private func recoverIfOffscreen(_ window: TrackedWindow) {
        let minimumVisible = CGSize(width: 80, height: 40)
        let isVisible = displays.contains {
            let overlap = $0.usableFrame.intersection(window.frame)
            return overlap.width >= minimumVisible.width && overlap.height >= minimumVisible.height
        }
        guard !isVisible, let display = DisplayService.display(for: window.frame, in: displays) else { return }
        let area = display.usableFrame
        let size = CGSize(width: min(window.frame.width, area.width * 0.8), height: min(window.frame.height, area.height * 0.8))
        let origin = CGPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2)
        _ = apply(window, to: CGRect(origin: origin, size: size))
    }

    private func raiseActiveStackMembers(plan: TilePlan, display: DisplayID) {
        for tile in plan.tileFrames.indices {
            let members = plan.stack(onTile: tile)
            guard members.count > 1 else { continue }
            let key = StackKey(display: display, tile: tile)
            var active = stackActive[key].flatMap { members.contains($0) ? $0 : nil } ?? members[0]
            if let focused = lastActiveWindow, members.contains(focused) { active = focused }
            stackActive[key] = active
            if stackRaised[key] != active, let window = tracked[active] {
                placement.raise(window.element, pid: window.pid, activate: false)
                stackRaised[key] = active
            }
        }
    }

    @discardableResult
    func discoverAndTrack() -> DiscoveryResult {
        let found = discovery.discover(excludedBundleIDs: settings.configuration.excludedBundleIDs)
        tracked = Dictionary(found.eligible.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return found
    }

    func focusFrame(on display: DisplayInfo, margin: Double) -> CGRect {
        let area = display.usableFrame
        if cleanSpaceDisplay != nil {
            return area.insetBy(
                dx: area.width * TilingTuning.cleanSpaceInset.width, dy: area.height * TilingTuning.cleanSpaceInset.height)
        }
        return area.insetBy(dx: margin, dy: margin)
    }

    func refreshDisplays() {
        displays = displayService.current()
        ui.displays = displays
    }

    // MARK: UI sync

    func syncUI() {
        ui.tiledCounts = lastPlans.mapValues { plan in
            plan.placements.filter { if case .tile = $0.role { true } else { false } }.count
        }
        let managedFloating = lastPlans.values.reduce(0) { $0 + $1.placements.filter { $0.role == .floating }.count }
        ui.floatingCount = managedFloating + userFloating.count + budget.stubborn.count
        ui.isFocusActive = focus.isActive && cleanSpaceDisplay == nil
        ui.isCleanSpaceActive = cleanSpaceDisplay != nil
        ui.isNoPeekActive = noPeekActive
        ui.canRestorePreviousArrangement = !originalFrames.isEmpty
    }

    func refreshOverlays() {
        var context = OverlayContext()
        context.displays = displays
        context.tiles = lastPlans.mapValues(\.tileFrames)
        context.appearance = settings.configuration.appearance
        context.noPeek = noPeekActive
        context.cleanSpaceDisplay = cleanSpaceDisplay
        if let id = lastActiveWindow, let window = tracked[id], let frame = window.element.frame {
            context.activeFrame = frame
            context.activePID = window.pid
            context.activeDisplay = DisplayService.display(for: frame, in: displays)?.id
        }
        overlays.update(context)
    }

    func exitPresentationModes() {
        if let id = focus.focusedWindow, currentStatus() != .active, let frame = preFocusFrame, let window = tracked[id] {
            _ = placement.place(window.element, to: frame)
        }
        preFocusFrame = nil
        focus.exit()
        cleanSpaceDisplay = nil
        noPeekActive = false
        syncUI()
        refreshOverlays()
    }
}

enum StageManagerDetector {
    /// Read-only check of the Window Manager preference; there is no public query API.
    /// If the key is missing or unreadable, tiling is not paused.
    static var isEnabled: Bool {
        let value = CFPreferencesCopyAppValue("GloballyEnabled" as CFString, "com.apple.WindowManager" as CFString)
        return (value as? Bool) ?? false
    }
}
