import Foundation

public struct ShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let command = ShortcutModifiers(rawValue: 1 << 0)
    public static let option = ShortcutModifiers(rawValue: 1 << 1)
    public static let control = ShortcutModifiers(rawValue: 1 << 2)
    public static let shift = ShortcutModifiers(rawValue: 1 << 3)
}

/// A key combination. `keyCode` is a macOS virtual key code (layout independent).
public struct Shortcut: Codable, Hashable, Sendable {
    public var keyCode: UInt32
    public var modifiers: ShortcutModifiers

    public init(keyCode: UInt32, modifiers: ShortcutModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Human-readable form such as "⌃⌥←".
    public var display: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + (Self.keyNames[keyCode] ?? "Key \(keyCode)")
    }

    private static let keyNames: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q",
        13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L", 38: "J",
        40: "K", 45: "N", 46: "M", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8",
        25: "9", 29: "0", 24: "=", 27: "-", 33: "[", 30: "]", 48: "⇥", 49: "Space", 36: "↩", 53: "⎋",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]
}

public enum ShortcutAction: String, CaseIterable, Codable, Sendable {
    case arrangeNow, toggleTiling, toggleLayout, restoreArrangement
    case swapPrevious, swapNext, moveToPreviousDisplay, moveToNextDisplay
    case focusMode, noPeek, cleanSpace, windowSwitcher
    case growTile, shrinkTile, resetSizes, cycleStack, toggleFloat
    case commandPalette
    case oneWindow, twoWindows, threeWindows, fourWindows

    public var title: String {
        switch self {
        case .arrangeNow: "Arrange Windows Now"
        case .toggleTiling: "Pause / Resume Tiling"
        case .toggleLayout: "Switch Grid / Columns"
        case .restoreArrangement: "Restore Previous Arrangement"
        case .swapPrevious: "Swap with Previous Tile"
        case .swapNext: "Swap with Next Tile"
        case .moveToPreviousDisplay: "Move to Previous Display"
        case .moveToNextDisplay: "Move to Next Display"
        case .focusMode: "Focus Mode"
        case .noPeek: "No Peek"
        case .cleanSpace: "Clean Space"
        case .windowSwitcher: "Window Switcher"
        case .growTile: "Grow Active Tile"
        case .shrinkTile: "Shrink Active Tile"
        case .resetSizes: "Reset Tile Sizes"
        case .cycleStack: "Cycle Stacked Windows"
        case .toggleFloat: "Float / Tile Active Window"
        case .commandPalette: "Command Palette"
        case .oneWindow: "Tile 1 Window per Display"
        case .twoWindows: "Tile 2 Windows per Display"
        case .threeWindows: "Tile 3 Windows per Display"
        case .fourWindows: "Tile 4 Windows per Display"
        }
    }

    private static let controlOption: ShortcutModifiers = [.control, .option]

    /// Defaults are Control + Option plus a key reachable with the *other* hand: arrows, Return, brackets
    /// and right-hand letters. Pressing both modifiers and a left-hand letter with one hand is awkward.
    /// The command palette (⌃⌥K) is the one to remember; it finds everything else.
    public var defaultShortcut: Shortcut {
        let co = Self.controlOption
        switch self {
        case .commandPalette: return Shortcut(keyCode: 40, modifiers: co)  // K
        case .oneWindow: return Shortcut(keyCode: 18, modifiers: co.union(.command))
        case .twoWindows: return Shortcut(keyCode: 19, modifiers: co.union(.command))
        case .threeWindows: return Shortcut(keyCode: 20, modifiers: co.union(.command))
        case .fourWindows: return Shortcut(keyCode: 21, modifiers: co.union(.command))
        case .arrangeNow: return Shortcut(keyCode: 36, modifiers: co)  // Return
        case .toggleTiling: return Shortcut(keyCode: 35, modifiers: co)  // P (pause)
        case .toggleLayout: return Shortcut(keyCode: 37, modifiers: co)  // L
        case .restoreArrangement: return Shortcut(keyCode: 32, modifiers: co)  // U (undo)
        case .swapPrevious: return Shortcut(keyCode: 123, modifiers: co)
        case .swapNext: return Shortcut(keyCode: 124, modifiers: co)
        case .moveToPreviousDisplay: return Shortcut(keyCode: 33, modifiers: co)  // [
        case .moveToNextDisplay: return Shortcut(keyCode: 30, modifiers: co)  // ]
        case .focusMode: return Shortcut(keyCode: 46, modifiers: co)  // M (maximize)
        case .noPeek: return Shortcut(keyCode: 45, modifiers: co)  // N
        case .cleanSpace: return Shortcut(keyCode: 4, modifiers: co)  // H (hide the rest)
        case .windowSwitcher: return Shortcut(keyCode: 48, modifiers: co)  // Tab
        case .growTile: return Shortcut(keyCode: 24, modifiers: co)  // =
        case .shrinkTile: return Shortcut(keyCode: 27, modifiers: co)  // -
        case .resetSizes: return Shortcut(keyCode: 29, modifiers: co)  // 0
        case .cycleStack: return Shortcut(keyCode: 126, modifiers: co)  // ↑
        case .toggleFloat: return Shortcut(keyCode: 125, modifiers: co)  // ↓
        }
    }

    /// Extra search words so the palette finds a command by what the user means, not only its title.
    public var keywords: [String] {
        switch self {
        case .arrangeNow: ["tidy", "organize", "tile", "fix", "layout"]
        case .toggleTiling: ["pause", "resume", "stop", "start", "enable", "disable", "automatic"]
        case .toggleLayout: ["grid", "columns", "rows", "arrangement"]
        case .restoreArrangement: ["undo", "revert", "original", "back"]
        case .swapPrevious, .swapNext: ["exchange", "reorder", "move", "tile"]
        case .moveToPreviousDisplay, .moveToNextDisplay: ["monitor", "screen", "external", "send"]
        case .focusMode: ["maximize", "fullscreen", "zoom", "expand"]
        case .noPeek: ["dim", "privacy", "hide", "highlight"]
        case .cleanSpace: ["present", "background", "distraction", "clean"]
        case .windowSwitcher: ["switch", "find", "windows", "apps", "alt tab"]
        case .growTile, .shrinkTile, .resetSizes: ["resize", "bigger", "smaller", "size", "equal"]
        case .cycleStack: ["stack", "next window", "overlap"]
        case .toggleFloat: ["float", "free", "untile", "pin"]
        case .commandPalette: ["search", "find", "commands", "help"]
        case .oneWindow, .twoWindows, .threeWindows, .fourWindows: ["layout", "count", "number", "how many", "windows per display"]
        }
    }
}

/// Resolves defaults plus user overrides and finds duplicate bindings.
public struct ShortcutMap: Equatable, Sendable {
    public private(set) var bindings: [ShortcutAction: Shortcut]

    public init(overrides: [String: Shortcut] = [:]) {
        var map: [ShortcutAction: Shortcut] = [:]
        for action in ShortcutAction.allCases {
            map[action] = overrides[action.rawValue] ?? action.defaultShortcut
        }
        bindings = map
    }

    /// Shortcuts bound to more than one action, with the actions involved.
    public var conflicts: [Shortcut: [ShortcutAction]] {
        Dictionary(grouping: ShortcutAction.allCases, by: { bindings[$0] ?? $0.defaultShortcut })
            .filter { $0.value.count > 1 }
    }

    public func conflictingActions(for action: ShortcutAction) -> [ShortcutAction] {
        guard let shortcut = bindings[action] else { return [] }
        return ShortcutAction.allCases.filter { $0 != action && bindings[$0] == shortcut }
    }
}
