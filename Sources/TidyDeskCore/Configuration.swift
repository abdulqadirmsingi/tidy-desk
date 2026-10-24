import Foundation

public enum AppearanceMode: String, Codable, CaseIterable, Sendable {
    case system, light, dark
    public var title: String { rawValue.capitalized }
}

public enum MenuBarIconStyle: String, Codable, CaseIterable, Sendable {
    case outline, filled
    public var title: String { rawValue.capitalized }
}

/// sRGB color stored as components so Core stays free of AppKit.
public struct RGBColor: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
    public static let defaultHighlight = RGBColor(red: 0.04, green: 0.52, blue: 1.0)
}

public struct AppearanceSettings: Codable, Equatable, Sendable {
    public var mode: AppearanceMode = .system
    public var menuBarIcon: MenuBarIconStyle = .outline
    public var showActiveBorder = true
    public var showAllBorders = false
    public var glow = false
    public var highlightColor: RGBColor = .defaultHighlight
    public var borderThickness: Double = 3
    /// 0...1 darkness applied by No Peek.
    public var noPeekDimming: Double = 0.55

    public static let borderThicknessRange: ClosedRange<Double> = 1...8

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppearanceSettings()
        mode = try c.value(.mode, default: d.mode)
        menuBarIcon = try c.value(.menuBarIcon, default: d.menuBarIcon)
        showActiveBorder = try c.value(.showActiveBorder, default: d.showActiveBorder)
        showAllBorders = try c.value(.showAllBorders, default: d.showAllBorders)
        glow = try c.value(.glow, default: d.glow)
        highlightColor = try c.value(.highlightColor, default: d.highlightColor)
        borderThickness = try c.value(.borderThickness, default: d.borderThickness)
        noPeekDimming = try c.value(.noPeekDimming, default: d.noPeekDimming)
    }
}

/// Everything TidyDesk persists. Contains no window titles or live references.
public struct Configuration: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion = Configuration.currentSchemaVersion
    public var isTilingEnabled = true
    public var hasCompletedOnboarding = false
    /// Settings applied to displays without their own entry in `displays`.
    public var defaultDisplay = DisplaySettings()
    /// Per-display overrides keyed by `DisplayID.rawValue`. Kept while a display is unplugged.
    public var displays: [String: DisplaySettings] = [:]
    public var excludedBundleIDs: Set<String> = []
    /// Minimum sizes learned from refused resizes, keyed by bundle identifier.
    public var learnedMinimums: [String: LearnedMinimum] = [:]
    /// User shortcut overrides keyed by `ShortcutAction.rawValue`.
    public var shortcutOverrides: [String: Shortcut] = [:]
    public var appearance = AppearanceSettings()
    /// Also show the app in the Dock (it is a menu bar app by default).
    public var showInDock = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Configuration()
        schemaVersion = try c.value(.schemaVersion, default: d.schemaVersion)
        isTilingEnabled = try c.value(.isTilingEnabled, default: d.isTilingEnabled)
        hasCompletedOnboarding = try c.value(.hasCompletedOnboarding, default: d.hasCompletedOnboarding)
        defaultDisplay = try c.value(.defaultDisplay, default: d.defaultDisplay)
        displays = try c.value(.displays, default: d.displays)
        excludedBundleIDs = try c.value(.excludedBundleIDs, default: d.excludedBundleIDs)
        learnedMinimums = try c.value(.learnedMinimums, default: d.learnedMinimums)
        shortcutOverrides = try c.value(.shortcutOverrides, default: d.shortcutOverrides)
        appearance = try c.value(.appearance, default: d.appearance)
        showInDock = try c.value(.showInDock, default: d.showInDock)
    }

    public func settings(for display: DisplayID) -> DisplaySettings {
        displays[display.rawValue] ?? defaultDisplay
    }

    public mutating func updateSettings(for display: DisplayID, _ change: (inout DisplaySettings) -> Void) {
        var settings = settings(for: display)
        change(&settings)
        displays[display.rawValue] = settings
    }

    public var shortcuts: ShortcutMap { ShortcutMap(overrides: shortcutOverrides) }
}
