import CoreGraphics

/// Tuning constants shared by the layout engine and the coordinator.
public enum LayoutDefaults {
    /// Smallest tile we consider usable when an app reports nothing.
    public static let minimumTileSize = CGSize(width: 320, height: 220)
    public static let maxWindowsPerDisplay = 4
    public static let weightRange: ClosedRange<Double> = 0.25...4.0
    public static let spacingRange: ClosedRange<Double> = 0...40
    public static let marginRange: ClosedRange<Double> = 0...80
    /// Geometry differences below this many points are treated as equal.
    public static let geometryTolerance: CGFloat = 2
}

public enum ScreenCoordinates {
    /// Converts between AppKit (bottom-left origin) and Accessibility/CoreGraphics
    /// (top-left origin) space. Both origins are anchored to the primary display,
    /// and the flip is its own inverse.
    public static func flip(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    public static func flip(_ point: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }
}

extension CGRect {
    public func isApproximatelyEqual(to other: CGRect, tolerance: CGFloat = LayoutDefaults.geometryTolerance) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }

    public func hasApproximateSize(of other: CGRect, tolerance: CGFloat = LayoutDefaults.geometryTolerance) -> Bool {
        abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }

    /// True for finite, positive-area rectangles; guards against bad AX reads.
    public var isUsable: Bool {
        origin.x.isFinite && origin.y.isFinite && width.isFinite && height.isFinite && width > 0 && height > 0
    }
}
