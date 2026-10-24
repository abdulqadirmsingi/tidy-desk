import Foundation

/// A finite series of growing delays, so waiting for an app to become ready can never retry forever.
public struct RetrySchedule: Sendable, Equatable {
    public let delays: [TimeInterval]
    private var used = 0

    public init(delays: [TimeInterval] = [0.5, 1, 2, 4, 8]) { self.delays = delays }

    /// The next delay, or nil once the schedule is exhausted.
    public mutating func next() -> TimeInterval? {
        guard used < delays.count else { return nil }
        defer { used += 1 }
        return delays[used]
    }

    public mutating func reset() { used = 0 }
}
