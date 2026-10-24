import Observation
import TidyDeskCore

enum TilingStatus: Equatable {
    case active
    case pausedByUser
    case needsPermission
    case stageManagerOn
    case asleep

    var summary: String {
        switch self {
        case .active: "Tiling is on"
        case .pausedByUser: "Tiling is paused"
        case .needsPermission: "Accessibility access needed"
        case .stageManagerOn: "Paused: Stage Manager is on"
        case .asleep: "Waiting for the screen to unlock"
        }
    }
}

/// What the interface shows. Written only by `TilingCoordinator`; contains no window titles.
@MainActor
@Observable
final class TilingUIState {
    var status: TilingStatus = .pausedByUser
    var displays: [DisplayInfo] = []
    var tiledCounts: [DisplayID: Int] = [:]
    var floatingCount = 0
    var isFocusActive = false
    var isCleanSpaceActive = false
    var isNoPeekActive = false
    var canRestorePreviousArrangement = false
    /// Whether the active window is floating; nil when there is no active window to act on.
    var activeWindowFloating: Bool?
    /// Short, non-blocking explanation of the last notable problem.
    var notice: String?

    var isSpecialModeActive: Bool { isFocusActive || isCleanSpaceActive || isNoPeekActive }
}
