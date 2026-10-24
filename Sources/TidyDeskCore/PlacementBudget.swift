import Foundation

/// Bounds how often TidyDesk will try to place a window that resists, so it never fights an app.
///
/// Two independent triggers mark a window *stubborn* (left floating until the user intervenes):
/// repeated refusals of our own placement, and an app that keeps moving itself without any
/// mouse gesture from the user.
public struct PlacementBudget: Sendable, Equatable {
    public let maxRefusals: Int
    public let maxUnsolicited: Int
    public let unsolicitedWindow: TimeInterval

    public private(set) var stubborn: Set<WindowID> = []
    private var refusals: [WindowID: Int] = [:]
    private var unsolicited: [WindowID: [Date]] = [:]

    public init(maxRefusals: Int = 2, maxUnsolicited: Int = 4, unsolicitedWindow: TimeInterval = 10) {
        self.maxRefusals = maxRefusals
        self.maxUnsolicited = maxUnsolicited
        self.unsolicitedWindow = unsolicitedWindow
    }

    public func isStubborn(_ window: WindowID) -> Bool { stubborn.contains(window) }

    /// Records a placement the app did not honour. Returns true when this call made the window stubborn.
    @discardableResult
    public mutating func recordRefusal(_ window: WindowID) -> Bool {
        guard !stubborn.contains(window) else { return false }
        let count = (refusals[window] ?? 0) + 1
        refusals[window] = count
        guard count >= maxRefusals else { return false }
        stubborn.insert(window)
        return true
    }

    /// A placement was honoured; earlier refusals no longer count against the window.
    public mutating func recordSuccess(_ window: WindowID) { refusals[window] = nil }

    /// Records a geometry change the user did not cause. Returns true when this call made the window stubborn.
    @discardableResult
    public mutating func recordUnsolicited(_ window: WindowID, at now: Date = Date()) -> Bool {
        guard !stubborn.contains(window) else { return false }
        var recent = (unsolicited[window] ?? []).filter { now.timeIntervalSince($0) < unsolicitedWindow }
        recent.append(now)
        unsolicited[window] = recent
        guard recent.count > maxUnsolicited else { return false }
        stubborn.insert(window)
        return true
    }

    /// Forgets everything; used when the user changes settings or asks to arrange again.
    public mutating func reset() {
        stubborn = []
        refusals = [:]
        unsolicited = [:]
    }

    /// Drops state for windows that no longer exist.
    public mutating func retain(alive: Set<WindowID>) {
        stubborn.formIntersection(alive)
        refusals = refusals.filter { alive.contains($0.key) }
        unsolicited = unsolicited.filter { alive.contains($0.key) }
    }
}
