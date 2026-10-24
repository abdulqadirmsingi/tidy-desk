import Testing

@testable import TidyDeskCore

private let items = [
    CommandItem(id: "arrange", title: "Arrange Windows Now", keywords: ["tidy", "organize"]),
    CommandItem(id: "pause", title: "Pause / Resume Tiling", keywords: ["stop", "disable"]),
    CommandItem(id: "layout", title: "Switch Grid / Columns", keywords: ["rows"]),
    CommandItem(id: "focus", title: "Focus Mode", keywords: ["maximize", "fullscreen"]),
    CommandItem(id: "float", title: "Float / Tile Active Window", keywords: ["untile"]),
]

private func ids(_ query: String) -> [String] { CommandSearch.rank(query, in: items).map(\.id) }

@Suite("Command search")
struct CommandSearchTests {
    @Test func emptyQueryKeepsOriginalOrder() { #expect(ids("") == items.map(\.id)) }

    @Test func prefixBeatsWordStartBeatsSubstring() {
        #expect(ids("fo").first == "focus")
        #expect(ids("tiling") == ["pause"])
        #expect(ids("win").first == "arrange")
    }

    @Test func keywordsFindCommandsByMeaning() {
        #expect(ids("maximize") == ["focus"])
        #expect(ids("tidy") == ["arrange"])
        #expect(ids("stop") == ["pause"])
    }

    @Test func everyWordMustMatch() {
        #expect(ids("float window") == ["float"])
        #expect(ids("float nothing").isEmpty)
    }

    @Test func caseAndSpacingAreForgiving() {
        #expect(ids("  FOCUS  ") == ["focus"])
    }

    @Test func lettersInOrderStillMatchAsALastResort() {
        #expect(ids("fcs") == ["focus"])
        #expect(ids("zzz").isEmpty)
    }

    @Test func equalScoresKeepOriginalOrder() {
        let tied = [CommandItem(id: "a", title: "Alpha Tool"), CommandItem(id: "b", title: "Beta Tool")]
        #expect(CommandSearch.rank("tool", in: tied).map(\.id) == ["a", "b"])
    }

    @Test func everyShortcutActionIsFindableByItsOwnTitle() {
        let all = ShortcutAction.allCases.map { CommandItem(id: $0.rawValue, title: $0.title, keywords: $0.keywords) }
        for action in ShortcutAction.allCases {
            #expect(CommandSearch.rank(action.title, in: all).first?.id == action.rawValue, "\(action)")
        }
    }
}

@Suite("Default shortcuts")
struct DefaultShortcutTests {
    @Test func paletteIsBoundAndEveryDefaultIsUniqueWithControlOption() {
        #expect(ShortcutAction.commandPalette.defaultShortcut.display == "⌃⌥K")
        let defaults = ShortcutAction.allCases.map(\.defaultShortcut)
        #expect(Set(defaults).count == defaults.count)
        #expect(defaults.allSatisfy { $0.modifiers.isSuperset(of: [.control, .option]) })
    }

    @Test func commonActionsUseTheEasierKeys() {
        #expect(ShortcutAction.arrangeNow.defaultShortcut.display == "⌃⌥↩")
        #expect(ShortcutAction.moveToNextDisplay.defaultShortcut.display == "⌃⌥]")
    }

    @Test func everyDefaultHasAReadableKeyName() {
        for action in ShortcutAction.allCases {
            #expect(!action.defaultShortcut.display.contains("Key "), "\(action) shows a raw key code")
        }
    }

    @Test func everyActionHasKeywords() {
        #expect(ShortcutAction.allCases.allSatisfy { !$0.keywords.isEmpty })
    }
}

@Suite("Switcher navigation")
struct SwitcherNavigationTests {
    private let nav = SwitcherNavigation(groupSizes: [3, 2])

    @Test func leftRightWalkReadingOrderAndWrap() {
        #expect(nav.move(.init(group: 0, index: 2), .right) == .init(group: 1, index: 0))
        #expect(nav.move(.init(group: 1, index: 1), .right) == .init(group: 0, index: 0))
        #expect(nav.move(.init(group: 0, index: 0), .left) == .init(group: 1, index: 1))
    }

    @Test func upDownSwitchDisplayKeepingTheColumnClamped() {
        #expect(nav.move(.init(group: 0, index: 2), .down) == .init(group: 1, index: 1))
        #expect(nav.move(.init(group: 1, index: 1), .up) == .init(group: 0, index: 1))
        #expect(nav.move(.init(group: 1, index: 0), .down) == .init(group: 0, index: 0))
    }

    @Test func singleDisplayIgnoresUpDown() {
        let single = SwitcherNavigation(groupSizes: [3])
        #expect(single.move(.init(group: 0, index: 1), .down) == .init(group: 0, index: 1))
    }

    @Test func emptyGroupsAreSkipped() {
        let sparse = SwitcherNavigation(groupSizes: [0, 2, 0, 1])
        #expect(sparse.first == .init(group: 1, index: 0))
        #expect(sparse.move(.init(group: 1, index: 1), .right) == .init(group: 3, index: 0))
        #expect(sparse.move(.init(group: 1, index: 0), .down) == .init(group: 3, index: 0))
    }

    @Test func numberKeysMapToReadingOrder() {
        #expect(nav.position(atFlat: 0) == .init(group: 0, index: 0))
        #expect(nav.position(atFlat: 3) == .init(group: 1, index: 0))
        #expect(nav.position(atFlat: 5) == nil)
        #expect(nav.position(atFlat: -1) == nil)
    }

    @Test func nothingToSelectWhenThereAreNoWindows() {
        let none = SwitcherNavigation(groupSizes: [])
        #expect(none.first == nil)
        #expect(none.total == 0)
    }
}
