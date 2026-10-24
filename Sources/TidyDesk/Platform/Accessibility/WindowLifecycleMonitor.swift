import AppKit

enum WindowEvent {
    case structural
    case geometry(AXElement)
    case focus
    case spaceChanged
    case displaysChanged
    case systemWillSleep
    case systemDidWake
    case screenLocked
    case screenUnlocked
}

/// Turns Accessibility notifications and workspace/system notifications into `WindowEvent`s.
/// Event-driven only: nothing here polls.
@MainActor
final class WindowLifecycleMonitor {
    private final class AppWatch {
        let observer: AXObserver
        let pid: pid_t
        var windows: [AXElement] = []
        /// App-level notifications that failed because the app was not ready; retried on `sync`.
        var pendingApp: [String] = []
        init(observer: AXObserver, pid: pid_t) {
            self.observer = observer
            self.pid = pid
        }
    }

    var onEvent: ((WindowEvent) -> Void)?

    private var watches: [pid_t: AppWatch] = [:]
    private var tokens: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var distributedTokens: [NSObjectProtocol] = []
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    private static let appNotifications = [
        kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification,
    ]
    private static let windowNotifications = [
        kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification,
        kAXWindowMovedNotification, kAXWindowResizedNotification,
    ]

    func start() {
        guard tokens.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        let structural: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification,
        ]
        for name in structural {
            observe(workspace, name) { [weak self] note in
                let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                    .processIdentifier
                MainActor.assumeIsolated {
                    if name == NSWorkspace.didTerminateApplicationNotification, let pid { self?.detach(pid: pid) }
                    self?.onEvent?(.structural)
                }
            }
        }
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { [weak self] _ in
            MainActor.assumeIsolated { self?.onEvent?(.focus) }
        }
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { [weak self] _ in
            MainActor.assumeIsolated { self?.onEvent?(.spaceChanged) }
        }
        observe(workspace, NSWorkspace.willSleepNotification) { [weak self] _ in
            MainActor.assumeIsolated { self?.onEvent?(.systemWillSleep) }
        }
        observe(workspace, NSWorkspace.didWakeNotification) { [weak self] _ in
            MainActor.assumeIsolated { self?.onEvent?(.systemDidWake) }
        }
        observe(.default, NSApplication.didChangeScreenParametersNotification) { [weak self] _ in
            MainActor.assumeIsolated { self?.onEvent?(.displaysChanged) }
        }
        let distributed = DistributedNotificationCenter.default()
        distributedTokens.append(
            distributed.addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated { self?.onEvent?(.screenLocked) }
            })
        distributedTokens.append(
            distributed.addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated { self?.onEvent?(.screenUnlocked) }
            })
    }

    func stop() {
        tokens.forEach { $0.center.removeObserver($0.token) }
        tokens = []
        distributedTokens.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        distributedTokens = []
        for pid in Array(watches.keys) { detach(pid: pid) }
    }

    /// Ensures every regular app and each given window is observed. Safe to call repeatedly.
    /// Returns true while some registrations are still pending because an app was not ready yet,
    /// so the caller can try again later instead of silently missing that app's new windows.
    @discardableResult
    func sync(windows: [TrackedWindow]) -> Bool {
        var hasPending = false
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && app.processIdentifier != ownPID && !app.isTerminated {
            guard let watch = watch(for: app.processIdentifier) else { continue }
            if !watch.pendingApp.isEmpty { registerAppNotifications(watch) }
            if !watch.pendingApp.isEmpty { hasPending = true }
        }
        for window in windows {
            guard let watch = watches[window.pid], !watch.windows.contains(window.element) else { continue }
            let results = Self.windowNotifications.map {
                AXObserverAddNotification(watch.observer, window.element.raw, $0 as CFString, refcon)
            }
            // Only a not-ready app is worth retrying; other errors (unsupported) will never succeed.
            if results.contains(.cannotComplete) {
                hasPending = true
            } else {
                watch.windows.append(window.element)
            }
        }
        return hasPending
    }

    private func registerAppNotifications(_ watch: AppWatch) {
        let app = AXElement.application(pid: watch.pid)
        watch.pendingApp = watch.pendingApp.filter {
            AXObserverAddNotification(watch.observer, app.raw, $0 as CFString, refcon) == .cannotComplete
        }
    }

    fileprivate func receive(notification: String, element: AXElement) {
        switch notification {
        case kAXWindowMovedNotification, kAXWindowResizedNotification: onEvent?(.geometry(element))
        case kAXFocusedWindowChangedNotification: onEvent?(.focus)
        default: onEvent?(.structural)
        }
    }

    private var refcon: UnsafeMutableRawPointer { Unmanaged.passUnretained(self).toOpaque() }

    private func watch(for pid: pid_t) -> AppWatch? {
        if let existing = watches[pid] { return existing }
        var observer: AXObserver?
        let callback: AXObserverCallback = { _, element, notification, refcon in
            guard let refcon else { return }
            let monitor = Unmanaged<WindowLifecycleMonitor>.fromOpaque(refcon).takeUnretainedValue()
            let name = notification as String
            // The observer's run loop source is on the main run loop.
            MainActor.assumeIsolated { monitor.receive(notification: name, element: AXElement(raw: element)) }
        }
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return nil }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        let watch = AppWatch(observer: observer, pid: pid)
        watch.pendingApp = Self.appNotifications
        registerAppNotifications(watch)
        watches[pid] = watch
        return watch
    }

    private func detach(pid: pid_t) {
        guard let watch = watches.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(watch.observer), .defaultMode)
    }

    private func observe(
        _ center: NotificationCenter, _ name: Notification.Name, _ handler: @escaping @Sendable (Notification) -> Void
    ) {
        tokens.append((center, center.addObserver(forName: name, object: nil, queue: .main, using: handler)))
    }
}
