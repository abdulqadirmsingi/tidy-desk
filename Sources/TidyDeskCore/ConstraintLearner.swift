import CoreGraphics

/// Decides whether a window refused a requested size and what that implies.
public enum ConstraintLearner {
    /// True when the window ended up at the requested size (within tolerance).
    public static func accepted(requested: CGRect, actual: CGRect) -> Bool {
        requested.hasApproximateSize(of: actual)
    }

    /// Returns an updated minimum size when `actual` is larger than `requested`, meaning the
    /// window refused to shrink. Returns nil when nothing new was learned.
    ///
    /// - Parameter plausibleLimit: Usable area of the display; larger readings are ignored
    ///   because they say nothing useful about a layout that can never fit anyway.
    public static func learnedMinimum(
        requested: CGRect, actual: CGRect, existing: CGSize, plausibleLimit: CGSize
    ) -> CGSize? {
        guard requested.isUsable, actual.isUsable else { return nil }
        let tolerance = LayoutDefaults.geometryTolerance
        var learned = existing
        if actual.width > requested.width + tolerance, actual.width <= plausibleLimit.width {
            learned.width = max(learned.width, actual.width)
        }
        if actual.height > requested.height + tolerance, actual.height <= plausibleLimit.height {
            learned.height = max(learned.height, actual.height)
        }
        return learned == existing ? nil : learned
    }
}
