public struct SwitcherPosition: Equatable, Sendable {
    public var group: Int
    public var index: Int
    public init(group: Int, index: Int) {
        self.group = group
        self.index = index
    }
}

public enum SwitcherMove: Sendable { case left, right, up, down }

/// Keyboard navigation over windows grouped by display (one row per display).
public struct SwitcherNavigation: Sendable {
    public let groupSizes: [Int]
    public init(groupSizes: [Int]) { self.groupSizes = groupSizes }

    private var nonEmptyGroups: [Int] { groupSizes.indices.filter { groupSizes[$0] > 0 } }
    public var total: Int { groupSizes.reduce(0, +) }

    public var first: SwitcherPosition? { nonEmptyGroups.first.map { SwitcherPosition(group: $0, index: 0) } }

    /// Position of the n-th window in reading order (0-based), for number-key selection.
    public func position(atFlat flat: Int) -> SwitcherPosition? {
        guard flat >= 0 else { return nil }
        var remaining = flat
        for group in nonEmptyGroups {
            if remaining < groupSizes[group] { return SwitcherPosition(group: group, index: remaining) }
            remaining -= groupSizes[group]
        }
        return nil
    }

    private func flat(_ position: SwitcherPosition) -> Int {
        groupSizes.prefix(position.group).reduce(0, +) + position.index
    }

    /// Left/right walk reading order and wrap; up/down jump between displays keeping the column.
    public func move(_ position: SwitcherPosition, _ move: SwitcherMove) -> SwitcherPosition? {
        guard total > 0, groupSizes.indices.contains(position.group) else { return first }
        switch move {
        case .left, .right:
            let step = move == .right ? 1 : -1
            return self.position(atFlat: ((flat(position) + step) % total + total) % total)
        case .up, .down:
            let groups = nonEmptyGroups
            guard let current = groups.firstIndex(of: position.group), groups.count > 1 else { return position }
            let step = move == .down ? 1 : -1
            let target = groups[((current + step) % groups.count + groups.count) % groups.count]
            return SwitcherPosition(group: target, index: min(position.index, groupSizes[target] - 1))
        }
    }
}
