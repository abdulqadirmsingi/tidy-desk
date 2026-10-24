public enum OnboardingStep: Int, CaseIterable, Sendable {
    case welcome, permission, grant, verify, layouts, choose, arrange
}

/// Step navigation for the first-run tour. Pure so the rules are testable.
public struct OnboardingFlow: Equatable, Sendable {
    public private(set) var current: OnboardingStep = .welcome
    /// Direction of the last move, so the view can slide steps the right way.
    public private(set) var movedForward = true

    public init() {}

    /// Steps shown for the current permission state. Explaining and requesting access is pointless
    /// once it is granted, so those two steps disappear.
    public static func steps(permissionGranted: Bool) -> [OnboardingStep] {
        OnboardingStep.allCases.filter { !permissionGranted || ($0 != .permission && $0 != .grant) }
    }

    public func isFirst(permissionGranted: Bool) -> Bool { Self.steps(permissionGranted: permissionGranted).first == current }
    public func isLast(permissionGranted: Bool) -> Bool { Self.steps(permissionGranted: permissionGranted).last == current }

    /// 1-based position and total, for "Step 2 of 5".
    public func progress(permissionGranted: Bool) -> (position: Int, total: Int) {
        let steps = Self.steps(permissionGranted: permissionGranted)
        let position = steps.lastIndex { $0.rawValue <= current.rawValue } ?? 0
        return (position + 1, steps.count)
    }

    public mutating func advance(permissionGranted: Bool) {
        let steps = Self.steps(permissionGranted: permissionGranted)
        guard let next = steps.first(where: { $0.rawValue > current.rawValue }) else { return }
        movedForward = true
        current = next
    }

    public mutating func goBack(permissionGranted: Bool) {
        let steps = Self.steps(permissionGranted: permissionGranted)
        guard let previous = steps.last(where: { $0.rawValue < current.rawValue }) else { return }
        movedForward = false
        current = previous
    }

    public mutating func jump(to step: OnboardingStep) {
        movedForward = step.rawValue >= current.rawValue
        current = step
    }
}
