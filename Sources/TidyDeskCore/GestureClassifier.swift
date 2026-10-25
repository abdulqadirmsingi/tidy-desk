import CoreGraphics

public enum GestureOutcome: Equatable, Sendable {
    /// The window ended where the layout put it.
    case unchanged
    /// A move too small to be deliberate; the window returns to its tile.
    case snapBack
    /// The window was resized.
    case resize
    /// Dragged with the swap modifier held: swap with the tile dropped on, or move to that display.
    case swapOrMove
    /// Dragged without the modifier: the user placed it, so leave it where it is.
    case float
}

/// Interprets what a finished mouse gesture on a tiled window meant.
public enum GestureClassifier {
    /// Moves shorter than this many points are treated as accidents.
    public static let nudgeThreshold: CGFloat = 24

    public static func classify(target: CGRect, final: CGRect, swapModifierHeld: Bool) -> GestureOutcome {
        if final.isApproximatelyEqual(to: target) { return .unchanged }
        if !final.hasApproximateSize(of: target) { return .resize }
        let distance = hypot(final.minX - target.minX, final.minY - target.minY)
        if distance <= nudgeThreshold { return .snapBack }
        return swapModifierHeld ? .swapOrMove : .float
    }
}

public enum FloatingPlacement {
    /// Top-left origin that centres a window of `size` in `area`, never pushing it past the area's
    /// top-left corner when it is larger than the area.
    public static func centeredOrigin(size: CGSize, in area: CGRect) -> CGPoint {
        CGPoint(
            x: area.minX + max((area.width - size.width) / 2, 0),
            y: area.minY + max((area.height - size.height) / 2, 0))
    }
}
