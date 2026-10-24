import Foundation
import Testing

@testable import TidyDeskCore

@Suite("Suggestion policy")
struct SuggestionPolicyTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func suggestsTidyingWhenWindowsAppearWhileTilingIsOff() {
        var policy = SuggestionPolicy()
        let context = SuggestionPolicy.Context(status: .pausedByUser, eligibleWindowCount: 3, newWindowAppeared: true)
        #expect(policy.evaluate(context, now: t0) == .tidyUp(windowCount: 3))
    }

    @Test func staysQuietWhenTilingIsAlreadyAutomatic() {
        var policy = SuggestionPolicy()
        for status in [TilingStatus.active, .stageManagerOn, .asleep] {
            let context = SuggestionPolicy.Context(status: status, eligibleWindowCount: 4, newWindowAppeared: true)
            #expect(policy.evaluate(context, now: t0) == nil, "\(status)")
        }
    }

    @Test func needsAtLeastTwoWindowsAndANewOne() {
        var policy = SuggestionPolicy()
        #expect(policy.evaluate(.init(status: .pausedByUser, eligibleWindowCount: 1, newWindowAppeared: true), now: t0) == nil)
        #expect(policy.evaluate(.init(status: .pausedByUser, eligibleWindowCount: 3, newWindowAppeared: false), now: t0) == nil)
    }

    @Test func missingAccessIsRaisedWithoutNeedingWindows() {
        var policy = SuggestionPolicy()
        #expect(policy.evaluate(.init(status: .needsPermission), now: t0) == .grantAccess)
    }

    @Test func cooldownPreventsRepeatsAndThenAllowsAgain() {
        var policy = SuggestionPolicy()
        let context = SuggestionPolicy.Context(status: .pausedByUser, eligibleWindowCount: 2, newWindowAppeared: true)
        #expect(policy.evaluate(context, now: t0) != nil)
        #expect(policy.evaluate(context, now: t0.addingTimeInterval(10)) == nil)
        #expect(policy.evaluate(context, now: t0.addingTimeInterval(policy.tidyUpCooldown + 1)) != nil)
    }

    @Test func notNowSilencesThatSuggestionForALongTime() {
        var policy = SuggestionPolicy()
        let context = SuggestionPolicy.Context(status: .pausedByUser, eligibleWindowCount: 2, newWindowAppeared: true)
        let shown = policy.evaluate(context, now: t0)
        policy.noteDismissed(try! #require(shown), now: t0)
        #expect(policy.evaluate(context, now: t0.addingTimeInterval(300)) == nil)
        #expect(policy.evaluate(context, now: t0.addingTimeInterval(policy.dismissSilence + 60)) != nil)
    }

    @Test func accessReminderIsRareAndSilencesSeparatelyFromTidyUp() {
        var policy = SuggestionPolicy()
        #expect(policy.evaluate(.init(status: .needsPermission), now: t0) == .grantAccess)
        #expect(policy.evaluate(.init(status: .needsPermission), now: t0.addingTimeInterval(60)) == nil)
        policy.noteDismissed(.grantAccess, now: t0)
        let tidy = SuggestionPolicy.Context(status: .pausedByUser, eligibleWindowCount: 2, newWindowAppeared: true)
        #expect(policy.evaluate(tidy, now: t0.addingTimeInterval(1)) == .tidyUp(windowCount: 2))
    }
}
