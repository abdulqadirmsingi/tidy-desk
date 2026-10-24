import AppKit
import TidyDeskCore

/// A window found through Accessibility. Runtime-only; titles are never stored here.
struct TrackedWindow {
    let id: WindowID
    let element: AXElement
    let pid: pid_t
    let bundleID: String?
    let appName: String
    var frame: CGRect
}

struct DiscoveryResult {
    /// Windows eligible for tiling on the current Space.
    var eligible: [TrackedWindow] = []
    /// Every window known to still exist, including minimized or off-Space ones.
    var alive: Set<WindowID> = []
}

/// Enumerates application windows and decides which ones may be tiled.
@MainActor
final class WindowDiscoveryService {
    private struct Entry {
        let id: WindowID
        let element: AXElement
        let pid: pid_t
    }

    private var registry: [Entry] = []
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    func window(for element: AXElement) -> WindowID? {
        registry.first { $0.element == element }?.id
    }

    func element(for id: WindowID) -> AXElement? {
        registry.first { $0.id == id }?.element
    }

    func discover(excludedBundleIDs: Set<String>) -> DiscoveryResult {
        var result = DiscoveryResult()
        var seenThisPass: Set<WindowID> = []
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated && $0.processIdentifier != ownPID
        }
        let runningPIDs = Set(apps.map(\.processIdentifier))
        registry.removeAll { !runningPIDs.contains($0.pid) }

        for app in apps where !app.isHidden {
            let appElement = AXElement.application(pid: app.processIdentifier)
            for element in appElement.elements(kAXWindowsAttribute) {
                // One timed-out read means the app is hung; skip its remaining windows this pass
                // instead of paying the timeout for every attribute of every window.
                if element.probe() == .cannotComplete {
                    Log.lifecycle.debug("App not responding; skipped for this pass")
                    break
                }
                let id = identity(for: element, pid: app.processIdentifier)
                seenThisPass.insert(id)
                result.alive.insert(id)
                guard !excludedBundleIDs.contains(app.bundleIdentifier ?? ""),
                      let frame = eligibleFrame(of: element)
                else { continue }
                result.eligible.append(
                    TrackedWindow(
                        id: id, element: element, pid: app.processIdentifier, bundleID: app.bundleIdentifier,
                        appName: app.localizedName ?? "App", frame: frame))
            }
        }

        // Windows we know about but did not list (hidden app, other Space, minimized) stay alive
        // only while the element still answers.
        for entry in registry where !seenThisPass.contains(entry.id) {
            if entry.element.probe() != .invalidUIElement { result.alive.insert(entry.id) }
        }
        registry.removeAll { !result.alive.contains($0.id) }
        return result
    }

    /// Frame of a window if it may be tiled, nil otherwise.
    private func eligibleFrame(of element: AXElement) -> CGRect? {
        guard element.string(kAXRoleAttribute) == kAXWindowRole,
              element.string(kAXSubroleAttribute) == kAXStandardWindowSubrole,
              element.bool(kAXMinimizedAttribute) != true,
              element.bool("AXFullScreen") != true,
              element.bool(kAXModalAttribute) != true,
              element.isSettable(kAXPositionAttribute),
              element.isSettable(kAXSizeAttribute)
        else { return nil }
        return element.frame
    }

    private func identity(for element: AXElement, pid: pid_t) -> WindowID {
        if let existing = registry.first(where: { $0.element == element }) { return existing.id }
        let entry = Entry(id: WindowID(), element: element, pid: pid)
        registry.append(entry)
        return entry.id
    }
}
