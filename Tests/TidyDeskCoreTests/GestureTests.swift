import CoreGraphics
import Testing

@testable import TidyDeskCore

@Suite("Gesture classification")
struct GestureTests {
    private let target = CGRect(x: 100, y: 100, width: 800, height: 600)

    private func classify(_ final: CGRect, command: Bool = false) -> GestureOutcome {
        GestureClassifier.classify(target: target, final: final, swapModifierHeld: command)
    }

    @Test func staying_put_is_unchanged() { #expect(classify(target) == .unchanged) }

    @Test func tinyMovesSnapBack() {
        #expect(classify(target.offsetBy(dx: 10, dy: 8)) == .snapBack)
        #expect(classify(target.offsetBy(dx: 10, dy: 8), command: true) == .snapBack)
    }

    @Test func plainDragFloatsTheWindowWhereItWasPlaced() {
        #expect(classify(target.offsetBy(dx: 300, dy: 40)) == .float)
    }

    @Test func commandDragSwapsOrMoves() {
        #expect(classify(target.offsetBy(dx: 300, dy: 40), command: true) == .swapOrMove)
    }

    @Test func sizeChangesAreResizesRegardlessOfModifier() {
        var bigger = target
        bigger.size.width += 200
        #expect(classify(bigger) == .resize)
        #expect(classify(bigger, command: true) == .resize)
    }

    @Test func resizeFromTheLeftEdgeIsStillAResize() {
        var final = target
        final.origin.x += 150
        final.size.width -= 150
        #expect(classify(final) == .resize)
    }
}

@Suite("Floating placement and layout shortcuts")
struct FloatingPlacementTests {
    private let area = CGRect(x: 1512, y: 38, width: 1440, height: 875)

    @Test func centresASmallerWindow() {
        #expect(FloatingPlacement.centeredOrigin(size: CGSize(width: 1000, height: 600), in: area)
            == CGPoint(x: 1512 + 220, y: 38 + 137.5))
    }

    @Test func aWindowLargerThanTheAreaAnchorsToItsTopLeft() {
        #expect(FloatingPlacement.centeredOrigin(size: CGSize(width: 2000, height: 1200), in: area)
            == CGPoint(x: 1512, y: 38))
    }

    @Test func windowCountShortcutsAreCommandControlOptionDigits() {
        let displays = [ShortcutAction.oneWindow, .twoWindows, .threeWindows, .fourWindows].map(\.defaultShortcut.display)
        #expect(displays == ["⌃⌥⌘1", "⌃⌥⌘2", "⌃⌥⌘3", "⌃⌥⌘4"])
    }
}
