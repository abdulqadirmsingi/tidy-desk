import Foundation

/// Deterministic per-display window ordering. Index 0 of a list is the primary window.
///
/// Lists may contain windows that are alive but not currently enumerable (for example on
/// another Space); callers plan only with windows they can currently see.
public struct WindowOrder: Sendable, Equatable {
    public struct Relocation: Equatable, Sendable {
        public let window: WindowID
        public let display: DisplayID
    }

    public private(set) var lists: [DisplayID: [WindowID]] = [:]
    /// Order snapshots of displays that were disconnected, restored on reconnect.
    private var parked: [DisplayID: [WindowID]] = [:]

    public init() {}

    public func windows(on display: DisplayID) -> [WindowID] { lists[display] ?? [] }

    public func display(of window: WindowID) -> DisplayID? {
        lists.first { $0.value.contains(window) }?.key
    }

    /// Brings the order in line with what is on screen.
    ///
    /// - Parameters:
    ///   - present: Windows currently enumerated, grouped by the display they are on, in
    ///     the order unknown windows should be appended.
    ///   - alive: Windows known to still exist (including ones not currently enumerated).
    ///   - connected: Displays currently attached.
    /// - Returns: Windows that should be moved back to a reconnected display.
    @discardableResult
    public mutating func reconcile(
        present: [DisplayID: [WindowID]], alive: Set<WindowID>, connected: Set<DisplayID>
    ) -> [Relocation] {
        var present = present
        for display in lists.keys where !connected.contains(display) {
            parked[display] = lists[display]
            lists[display] = nil
        }

        var relocations: [Relocation] = []
        for display in connected {
            guard let remembered = parked.removeValue(forKey: display) else { continue }
            let restored = remembered.filter { alive.contains($0) }
            guard !restored.isEmpty else { continue }
            for list in present.keys { present[list]?.removeAll { restored.contains($0) } }
            for id in restored { removeFromLists(id) }
            let originally = Set(present[display] ?? [])
            lists[display] = restored
            for id in restored where !originally.contains(id) {
                relocations.append(Relocation(window: id, display: display))
            }
            present[display, default: []].append(contentsOf: restored)
        }

        let visible = Set(present.values.flatMap { $0 })
        for display in connected {
            var seen = Set<WindowID>()
            let here = (present[display] ?? []).filter { seen.insert($0).inserted }
            let hereSet = Set(here)
            let kept = (lists[display] ?? []).filter {
                hereSet.contains($0) || (alive.contains($0) && !visible.contains($0))
            }
            let keptSet = Set(kept)
            lists[display] = kept + here.filter { !keptSet.contains($0) }
        }
        return relocations
    }

    /// Exchanges two windows' positions. They may be on different displays.
    @discardableResult
    public mutating func swap(_ a: WindowID, _ b: WindowID) -> Bool {
        guard a != b, let da = display(of: a), let db = display(of: b),
              let ia = lists[da]?.firstIndex(of: a), let ib = lists[db]?.firstIndex(of: b)
        else { return false }
        lists[da]?[ia] = b
        lists[db]?[ib] = a
        return true
    }

    /// Moves a window to `display`, inserting at `index` (clamped) or appending.
    public mutating func move(_ window: WindowID, to display: DisplayID, at index: Int? = nil) {
        removeFromLists(window)
        var list = lists[display] ?? []
        list.insert(window, at: min(max(index ?? list.count, 0), list.count))
        lists[display] = list
    }

    public mutating func promote(_ window: WindowID) {
        guard let display = display(of: window) else { return }
        move(window, to: display, at: 0)
    }

    public mutating func remove(_ window: WindowID) { removeFromLists(window) }

    private mutating func removeFromLists(_ window: WindowID) {
        for display in lists.keys { lists[display]?.removeAll { $0 == window } }
    }
}
