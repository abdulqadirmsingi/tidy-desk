import Observation
import TidyDeskCore

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
