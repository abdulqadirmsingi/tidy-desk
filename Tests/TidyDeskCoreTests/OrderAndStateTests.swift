import Foundation
import Testing

@testable import TidyDeskCore

private let a = DisplayID(rawValue: "A")
private let b = DisplayID(rawValue: "B")

@Suite("Window order")
struct WindowOrderTests {
    @Test func firstSeenWindowIsPrimaryAndNewOnesAppend() {
        let w1 = WindowID(), w2 = WindowID(), w3 = WindowID()
        var order = WindowOrder()
        order.reconcile(present: [a: [w1, w2]], alive: [w1, w2], connected: [a])
        order.reconcile(present: [a: [w2, w1, w3]], alive: [w1, w2, w3], connected: [a])
        #expect(order.windows(on: a) == [w1, w2, w3])
    }

    @Test func removalKeepsRelativeOrderAndPromotesNext() {
        let ws = (0..<4).map { _ in WindowID() }
        var order = WindowOrder()
        order.reconcile(present: [a: ws], alive: Set(ws), connected: [a])
        order.reconcile(present: [a: Array(ws.dropFirst())], alive: Set(ws.dropFirst()), connected: [a])
        #expect(order.windows(on: a) == Array(ws.dropFirst()))
    }

    @Test func duplicateEventsDoNotDuplicateEntries() {
        let w = WindowID()
        var order = WindowOrder()
        for _ in 0..<3 { order.reconcile(present: [a: [w, w]], alive: [w], connected: [a]) }
        #expect(order.windows(on: a) == [w])
    }

    @Test func aliveButUnlistedWindowsKeepTheirSlot() {
        let w1 = WindowID(), w2 = WindowID(), w3 = WindowID()
        var order = WindowOrder()
        order.reconcile(present: [a: [w1, w2, w3]], alive: [w1, w2, w3], connected: [a])
        order.reconcile(present: [a: [w1, w3]], alive: [w1, w2, w3], connected: [a])
        #expect(order.windows(on: a) == [w1, w2, w3])
        order.reconcile(present: [a: [w1, w3]], alive: [w1, w3], connected: [a])
        #expect(order.windows(on: a) == [w1, w3])
    }

    @Test func swapChangesOccupantsAcrossDisplays() {
        let w1 = WindowID(), w2 = WindowID(), w3 = WindowID()
        var order = WindowOrder()
        order.reconcile(present: [a: [w1, w2], b: [w3]], alive: [w1, w2, w3], connected: [a, b])
        let swapped_w1w2 = order.swap(w1, w2)
        #expect(swapped_w1w2)
        #expect(order.windows(on: a) == [w2, w1])
        let swapped_w1w3 = order.swap(w1, w3)
        #expect(swapped_w1w3)
        #expect(order.windows(on: a) == [w2, w3])
        #expect(order.windows(on: b) == [w1])
        let swapped_w1w1 = order.swap(w1, w1)
        #expect(!swapped_w1w1)
    }

    @Test func moveAndPromote() {
        let w1 = WindowID(), w2 = WindowID(), w3 = WindowID()
        var order = WindowOrder()
        order.reconcile(present: [a: [w1, w2, w3]], alive: [w1, w2, w3], connected: [a, b])
        order.move(w2, to: b)
        #expect(order.windows(on: a) == [w1, w3] && order.windows(on: b) == [w2])
        order.promote(w3)
        #expect(order.windows(on: a) == [w3, w1])
        order.move(w1, to: b, at: 0)
        #expect(order.windows(on: b) == [w1, w2])
    }

    @Test func disconnectedDisplayOrderIsRestoredOnReconnect() {
        let w1 = WindowID(), w2 = WindowID(), w3 = WindowID()
        var order = WindowOrder()
        order.reconcile(present: [a: [w1], b: [w2, w3]], alive: [w1, w2, w3], connected: [a, b])

        // Display B unplugged: macOS pulls its windows onto A.
        order.reconcile(present: [a: [w1, w2, w3]], alive: [w1, w2, w3], connected: [a])
        #expect(order.windows(on: a) == [w1, w2, w3])
        #expect(order.windows(on: b).isEmpty)

        // Display B returns: its windows are sent back in their old order.
        let relocations = order.reconcile(
            present: [a: [w1, w2, w3]], alive: [w1, w2, w3], connected: [a, b])
        #expect(order.windows(on: b) == [w2, w3])
        #expect(order.windows(on: a) == [w1])
        #expect(Set(relocations.map(\.window)) == [w2, w3])
        #expect(relocations.allSatisfy { $0.display == b })

        // Once they physically moved, nothing more is requested.
        let again = order.reconcile(present: [a: [w1], b: [w2, w3]], alive: [w1, w2, w3], connected: [a, b])
        #expect(again.isEmpty)
        #expect(order.windows(on: b) == [w2, w3])
    }

    @Test func windowsClosedWhileDisplayAbsentAreNotRestored() {
        let w1 = WindowID(), w2 = WindowID()
        var order = WindowOrder()
        order.reconcile(present: [a: [w1], b: [w2]], alive: [w1, w2], connected: [a, b])
        order.reconcile(present: [a: [w1]], alive: [w1], connected: [a])
        let relocations = order.reconcile(present: [a: [w1]], alive: [w1], connected: [a, b])
        #expect(relocations.isEmpty)
        #expect(order.windows(on: b).isEmpty)
    }
}

@Suite("Focus mode")
struct FocusModeTests {
    @Test func entersAndExits() {
        var state = FocusModeState()
        let w = WindowID()
        state.enter(w)
        #expect(state.isActive && state.focusedWindow == w)
        state.exit()
        #expect(!state.isActive)
    }

    @Test(arguments: [
        FocusModeState.Event.layoutChanged, .displayLost,
    ])
    func layoutAndDisplayEventsExit(event: FocusModeState.Event) {
        var state = FocusModeState()
        state.enter(WindowID())
        let result1 = state.handle(event)
        #expect(result1)
        #expect(!state.isActive)
    }

    @Test func onlyRelevantWindowEventsExit() {
        var state = FocusModeState()
        let focused = WindowID(), other = WindowID()
        state.enter(focused)
        let result2 = state.handle(.windowClosed(other))
        #expect(!result2)
        let result3 = state.handle(.anotherWindowActivated(focused))
        #expect(!result3)
        #expect(state.isActive)
        let result4 = state.handle(.anotherWindowActivated(other))
        #expect(result4)
    }

    @Test func eventsWhenInactiveAreIgnored() {
        var state = FocusModeState()
        let result5 = state.handle(.layoutChanged)
        #expect(!result5)
    }
}
