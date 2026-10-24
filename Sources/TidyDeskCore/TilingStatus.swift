public enum TilingStatus: Equatable, Sendable {
    case active
    case pausedByUser
    case needsPermission
    case stageManagerOn
    case asleep

    public var summary: String {
        switch self {
        case .active: "Tiling is on"
        case .pausedByUser: "Tiling is paused"
        case .needsPermission: "Accessibility access needed"
        case .stageManagerOn: "Paused: Stage Manager is on"
        case .asleep: "Waiting for the screen to unlock"
        }
    }

    /// Decides whether windows may be touched. Earlier reasons take priority: without permission
    /// nothing can be done at all, and Stage Manager pauses tiling even if the user wants it on.
    public static func resolve(
        permissionGranted: Bool, isAsleep: Bool, stageManagerOn: Bool, tilingEnabled: Bool, onboardingComplete: Bool
    ) -> TilingStatus {
        if !permissionGranted { return .needsPermission }
        if isAsleep { return .asleep }
        if stageManagerOn { return .stageManagerOn }
        return tilingEnabled && onboardingComplete ? .active : .pausedByUser
    }
}
