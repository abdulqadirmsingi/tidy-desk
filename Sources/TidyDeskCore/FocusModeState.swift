/// Tracks which window, if any, is expanded by Focus mode.
///
/// The tiled arrangement is not stored: order and weights are untouched while focused, so
/// leaving Focus mode simply re-plans and restores every tile.
public struct FocusModeState: Equatable, Sendable {
    public enum Event: Equatable, Sendable {
        case windowClosed(WindowID)
        case anotherWindowActivated(WindowID)
        case layoutChanged
        case displayLost
    }

    public private(set) var focusedWindow: WindowID?

    public init() {}

    public var isActive: Bool { focusedWindow != nil }

    public mutating func enter(_ window: WindowID) { focusedWindow = window }
    public mutating func exit() { focusedWindow = nil }

    /// Applies an event; returns true if it ended Focus mode.
    @discardableResult
    public mutating func handle(_ event: Event) -> Bool {
        guard let current = focusedWindow else { return false }
        let invalidates: Bool
        switch event {
        case let .windowClosed(id): invalidates = id == current
        case let .anotherWindowActivated(id): invalidates = id != current
        case .layoutChanged, .displayLost: invalidates = true
        }
        if invalidates { focusedWindow = nil }
        return invalidates
    }
}
