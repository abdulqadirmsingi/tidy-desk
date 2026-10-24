import Foundation

public enum SuggestionKind: Equatable, Sendable {
    /// Accessibility access is missing, so nothing can be arranged.
    case grantAccess
    /// Automatic tiling is off and several windows are open.
    case tidyUp(windowCount: Int)

    fileprivate var key: Key {
        switch self {
        case .grantAccess: .grantAccess
        case .tidyUp: .tidyUp
        }
    }

    fileprivate enum Key: Hashable { case grantAccess, tidyUp }
}

/// Decides when a non-intrusive suggestion may appear, so help never turns into nagging.
public struct SuggestionPolicy: Sendable {
    public struct Context: Sendable {
        public var status: TilingStatus
        public var eligibleWindowCount: Int
        /// A window appeared since the last check (not merely the first scan after launch).
        public var newWindowAppeared: Bool

        public init(status: TilingStatus, eligibleWindowCount: Int = 0, newWindowAppeared: Bool = false) {
            self.status = status
            self.eligibleWindowCount = eligibleWindowCount
            self.newWindowAppeared = newWindowAppeared
        }
    }

    /// Minimum gap between two "tidy up" suggestions.
    public var tidyUpCooldown: TimeInterval = 45
    /// Minimum gap between two reminders about missing access.
    public var accessCooldown: TimeInterval = 600
    /// Silence after the user answers "Not now".
    public var dismissSilence: TimeInterval = 900

    private var lastShown: [SuggestionKind.Key: Date] = [:]
    private var silencedUntil: [SuggestionKind.Key: Date] = [:]

    public init() {}

    /// Returns a suggestion to show now, if any, and records that it was shown.
    public mutating func evaluate(_ context: Context, now: Date = Date()) -> SuggestionKind? {
        let candidate: SuggestionKind
        let cooldown: TimeInterval
        switch context.status {
        case .needsPermission:
            candidate = .grantAccess
            cooldown = accessCooldown
        case .pausedByUser:
            guard context.newWindowAppeared, context.eligibleWindowCount >= 2 else { return nil }
            candidate = .tidyUp(windowCount: context.eligibleWindowCount)
            cooldown = tidyUpCooldown
        case .active, .stageManagerOn, .asleep:
            return nil
        }
        let key = candidate.key
        if let until = silencedUntil[key], now < until { return nil }
        if let last = lastShown[key], now.timeIntervalSince(last) < cooldown { return nil }
        lastShown[key] = now
        return candidate
    }

    /// The user chose "Not now" (or "Later"): stay quiet for a while.
    public mutating func noteDismissed(_ kind: SuggestionKind, now: Date = Date()) {
        silencedUntil[kind.key] = now.addingTimeInterval(dismissSilence)
    }
}
