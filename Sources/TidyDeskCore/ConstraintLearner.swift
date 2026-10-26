import CoreGraphics

/// Decides whether a window refused a requested size and what that implies.
public enum ConstraintLearner {
    /// Apps that size in steps (terminals snap to whole character cells) overshoot by up to one step.
    /// Anything within this allowance is a rounding artefact, not a minimum size.
    public static let snapAllowance: CGFloat = 24
    /// A "minimum" larger than this share of the display is not useful: it would exclude the window from
    /// every layout, and in practice comes from a stale reading rather than a real limit.
    public static let maxPlausibleFraction: CGFloat = 0.75

    /// True when the window ended up at the requested size, allowing for rounding up to whole steps.
    public static func accepted(requested: CGRect, actual: CGRect) -> Bool {
        let tolerance = LayoutDefaults.geometryTolerance
        return actual.width >= requested.width - tolerance && actual.width <= requested.width + snapAllowance
            && actual.height >= requested.height - tolerance && actual.height <= requested.height + snapAllowance
    }

    /// The largest minimum worth remembering on a display with this usable size.
    public static func plausibleLimit(forUsable usable: CGSize) -> CGSize {
        CGSize(width: usable.width * maxPlausibleFraction, height: usable.height * maxPlausibleFraction)
    }

    /// A stored minimum made safe for planning: dimensions beyond the plausible limit are treated as
    /// unknown. This repairs values saved before this check existed.
    public static func usableMinimum(learned: CGSize, usable: CGSize) -> CGSize {
        let limit = plausibleLimit(forUsable: usable)
        return CGSize(
            width: learned.width <= limit.width ? learned.width : 0,
            height: learned.height <= limit.height ? learned.height : 0)
    }

    /// Returns an updated minimum size when `actual` is clearly larger than `requested` and has had time
    /// to settle, meaning the window refused to shrink. Returns nil when nothing new was learned.
    ///
    /// - Parameter plausibleLimit: Largest minimum worth remembering (see `plausibleLimit(forUsable:)`).
    public static func learnedMinimum(
        requested: CGRect, actual: CGRect, existing: CGSize, plausibleLimit: CGSize
    ) -> CGSize? {
        guard requested.isUsable, actual.isUsable else { return nil }
        var learned = existing
        if actual.width > requested.width + snapAllowance, actual.width <= plausibleLimit.width {
            learned.width = max(learned.width, actual.width)
        }
        if actual.height > requested.height + snapAllowance, actual.height <= plausibleLimit.height {
            learned.height = max(learned.height, actual.height)
        }
        return learned == existing ? nil : learned
    }
}
