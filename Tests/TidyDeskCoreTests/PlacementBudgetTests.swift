import Foundation
import Testing

@testable import TidyDeskCore

@Suite("Placement budget")
struct PlacementBudgetTests {
    @Test func windowBecomesStubbornAfterRepeatedRefusals() {
        var budget = PlacementBudget(maxRefusals: 2)
        let w = WindowID()
        let r1 = budget.recordRefusal(w)
        #expect(!r1)
        #expect(!budget.isStubborn(w))
        let r2 = budget.recordRefusal(w)
        #expect(r2)
        #expect(budget.isStubborn(w))
    }

    @Test func becomingStubbornIsReportedOnlyOnce() {
        var budget = PlacementBudget(maxRefusals: 1)
        let w = WindowID()
        let r3 = budget.recordRefusal(w)
        #expect(r3)
        let r4 = budget.recordRefusal(w)
        #expect(!r4)
    }

    @Test func successForgivesEarlierRefusals() {
        var budget = PlacementBudget(maxRefusals: 2)
        let w = WindowID()
        budget.recordRefusal(w)
        budget.recordSuccess(w)
        let r5 = budget.recordRefusal(w)
        #expect(!r5)
        #expect(!budget.isStubborn(w))
    }

    @Test func refusalsArePerWindow() {
        var budget = PlacementBudget(maxRefusals: 2)
        let a = WindowID(), b = WindowID()
        budget.recordRefusal(a)
        let r6 = budget.recordRefusal(b)
        #expect(!r6)
        #expect(!budget.isStubborn(a) && !budget.isStubborn(b))
    }

    @Test func selfMovingWindowIsStoppedAfterTooManyEventsInTheWindow() {
        var budget = PlacementBudget(maxUnsolicited: 4, unsolicitedWindow: 10)
        let w = WindowID()
        let start = Date()
        for i in 0..<4 {
            let tripped = budget.recordUnsolicited(w, at: start.addingTimeInterval(Double(i)))
            #expect(!tripped)
        }
        let r7 = budget.recordUnsolicited(w, at: start.addingTimeInterval(5))
        #expect(r7)
        #expect(budget.isStubborn(w))
    }

    @Test func slowCorrectionsNeverAccumulate() {
        var budget = PlacementBudget(maxUnsolicited: 2, unsolicitedWindow: 10)
        let w = WindowID()
        let start = Date()
        for i in 0..<20 { budget.recordUnsolicited(w, at: start.addingTimeInterval(Double(i) * 11)) }
        #expect(!budget.isStubborn(w))
    }

    @Test func resetClearsEverything() {
        var budget = PlacementBudget(maxRefusals: 1)
        let w = WindowID()
        budget.recordRefusal(w)
        budget.reset()
        #expect(!budget.isStubborn(w))
        #expect(budget == PlacementBudget(maxRefusals: 1))
    }

    @Test func retainDropsClosedWindows() {
        var budget = PlacementBudget(maxRefusals: 1)
        let kept = WindowID(), gone = WindowID()
        budget.recordRefusal(kept)
        budget.recordRefusal(gone)
        budget.retain(alive: [kept])
        #expect(budget.stubborn == [kept])
    }

    @Test func retriesAreBoundedForAnAlwaysRefusingApp() {
        var budget = PlacementBudget()
        let w = WindowID()
        var attempts = 0
        while !budget.isStubborn(w) && attempts < 1000 {
            attempts += 1
            budget.recordRefusal(w)
        }
        #expect(attempts == budget.maxRefusals)
    }
}
