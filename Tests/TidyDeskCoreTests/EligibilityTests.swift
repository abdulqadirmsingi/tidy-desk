import Foundation
import CoreGraphics
import Testing

@testable import TidyDeskCore

@Suite("Window eligibility")
struct EligibilityTests {
    @Test func ordinaryWindowIsEligible() { #expect(WindowEligibility.evaluate(WindowTraits()) == nil) }

    @Test func eachDisqualifierIsReported() {
        #expect(WindowEligibility.evaluate(WindowTraits(subrole: "AXDialog")) == .notAStandardWindow)
        #expect(WindowEligibility.evaluate(WindowTraits(role: "AXSheet")) == .notAStandardWindow)
        #expect(WindowEligibility.evaluate(WindowTraits(isMinimized: true)) == .minimized)
        #expect(WindowEligibility.evaluate(WindowTraits(isFullScreen: true)) == .fullScreen)
        #expect(WindowEligibility.evaluate(WindowTraits(isModal: true)) == .modal)
        #expect(WindowEligibility.evaluate(WindowTraits(canMove: false)) == .notMovable)
        #expect(WindowEligibility.evaluate(WindowTraits(canResize: false)) == .notResizable)
        #expect(WindowEligibility.evaluate(WindowTraits(hasUsableFrame: false)) == .noGeometry)
    }

    @Test func missingOptionalAttributesAreTolerated() {
        let traits = WindowTraits(isMinimized: nil, isFullScreen: nil, isModal: nil)
        #expect(WindowEligibility.evaluate(traits) == nil)
    }

    @Test func missingRoleOrSubroleIsNotAStandardWindow() {
        #expect(WindowEligibility.evaluate(WindowTraits(role: nil)) == .notAStandardWindow)
        #expect(WindowEligibility.evaluate(WindowTraits(subrole: nil)) == .notAStandardWindow)
    }
}

@Suite("Window explanation")
struct ExplanationTests {
    private func text(
        _ ineligibility: Ineligibility? = nil, excluded: Bool = false, floating: Bool = false, stubborn: Bool = false,
        minimum: CGSize? = nil, role: PlacementRole? = .tile(0)
    ) -> String {
        WindowExplanation.describe(
            appName: "Prime", ineligibility: ineligibility, isExcluded: excluded, isUserFloating: floating,
            isStubborn: stubborn, learnedMinimum: minimum, role: role)
    }

    @Test func ineligibleWindowsSayWhy() {
        #expect(text(.notResizable).contains("does not allow it to be resized"))
    }

    @Test func eachFloatingCauseIsDistinct() {
        let all = [text(excluded: true), text(floating: true), text(stubborn: true), text(role: .floating)]
        #expect(Set(all).count == 4)
    }

    @Test func nonFittingWindowMentionsItsLearnedMinimum() {
        #expect(text(minimum: CGSize(width: 1400, height: 900), role: .floating).contains("1400 × 900"))
    }

    @Test func tiledStackedAndUnknownAreDescribed() {
        #expect(text(role: .tile(1)).contains("tile 2"))
        #expect(text(role: .stacked(onTile: 0)).contains("stacked"))
        #expect(text(role: nil).contains("not found"))
    }

    @Test func neverIncludesAWindowTitle() {
        // The API has no title parameter; this documents that the text only uses the app name.
        #expect(text().contains("Prime"))
    }
}

@Suite("Retry schedule")
struct RetryScheduleTests {
    @Test func yieldsEachDelayOnceThenStops() {
        var schedule = RetrySchedule(delays: [1, 2])
        #expect(schedule.next() == 1)
        #expect(schedule.next() == 2)
        #expect(schedule.next() == nil)
        #expect(schedule.next() == nil)
    }

    @Test func resetStartsOver() {
        var schedule = RetrySchedule(delays: [1])
        _ = schedule.next()
        schedule.reset()
        #expect(schedule.next() == 1)
    }

    @Test func defaultScheduleIsFiniteAndGrowing() {
        var schedule = RetrySchedule()
        var delays: [TimeInterval] = []
        while let delay = schedule.next(), delays.count < 100 { delays.append(delay) }
        #expect(delays.count == 5)
        #expect(delays == delays.sorted())
    }
}
