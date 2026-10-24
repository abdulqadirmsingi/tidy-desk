import CoreGraphics
import Foundation

/// Runtime-only identity of a window. Never persisted.
public struct WindowID: Hashable, Sendable {
    public let rawValue: UUID
    public init(rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

/// Stable display identity (CoreGraphics display UUID string).
public struct DisplayID: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public enum LayoutKind: String, Codable, CaseIterable, Sendable {
    case grid
    case columns

    public var title: String {
        switch self {
        case .grid: "Grid"
        case .columns: "Columns"
        }
    }
}

public enum OverflowPolicy: String, Codable, CaseIterable, Sendable {
    /// Extra windows share the last tile.
    case stack
    /// Extra windows stay floating until a tile frees up.
    case float

    public var title: String {
        switch self {
        case .stack: "Stack in last tile"
        case .float: "Leave floating"
        }
    }
}

/// Relative size of the primary tile (and the first row split) versus the others.
/// 1.0 means "equal share"; clamped to `LayoutDefaults.weightRange`.
public struct TileWeights: Codable, Equatable, Sendable {
    public var primary: Double
    public var secondary: Double

    public init(primary: Double = 1, secondary: Double = 1) {
        self.primary = Self.clamp(primary)
        self.secondary = Self.clamp(secondary)
    }

    public static let equal = TileWeights()

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return min(max(value, LayoutDefaults.weightRange.lowerBound), LayoutDefaults.weightRange.upperBound)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            primary: try c.value(.primary, default: 1),
            secondary: try c.value(.secondary, default: 1)
        )
    }
}

public struct DisplaySettings: Codable, Equatable, Sendable {
    public var layout: LayoutKind
    public var maxWindows: Int
    public var overflow: OverflowPolicy
    public var spacing: Double
    public var margin: Double
    public var weights: TileWeights

    public init(
        layout: LayoutKind = .grid,
        maxWindows: Int = 4,
        overflow: OverflowPolicy = .stack,
        spacing: Double = 8,
        margin: Double = 8,
        weights: TileWeights = .equal
    ) {
        self.layout = layout
        self.maxWindows = min(max(maxWindows, 1), LayoutDefaults.maxWindowsPerDisplay)
        self.overflow = overflow
        self.spacing = min(max(spacing, LayoutDefaults.spacingRange.lowerBound), LayoutDefaults.spacingRange.upperBound)
        self.margin = min(max(margin, LayoutDefaults.marginRange.lowerBound), LayoutDefaults.marginRange.upperBound)
        self.weights = weights
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = DisplaySettings()
        self.init(
            layout: try c.value(.layout, default: fallback.layout),
            maxWindows: try c.value(.maxWindows, default: fallback.maxWindows),
            overflow: try c.value(.overflow, default: fallback.overflow),
            spacing: try c.value(.spacing, default: fallback.spacing),
            margin: try c.value(.margin, default: fallback.margin),
            weights: try c.value(.weights, default: fallback.weights)
        )
    }
}

public struct LearnedMinimum: Codable, Equatable, Sendable {
    public var width: Double
    public var height: Double
    public var size: CGSize { CGSize(width: width, height: height) }
    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

extension KeyedDecodingContainer {
    /// Decodes a value, falling back to `defaultValue` when the key is absent.
    /// Lets older config files load after new fields are added.
    func value<T: Decodable>(_ key: Key, default defaultValue: T) throws -> T {
        try decodeIfPresent(T.self, forKey: key) ?? defaultValue
    }
}
