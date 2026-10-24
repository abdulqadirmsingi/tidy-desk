import CoreGraphics

/// Turns a user's manual resize of one tile into new `TileWeights`, so neighbouring tiles
/// adapt instead of overlapping.
public enum RatioInference {
    public static func weights(
        afterResizing tile: Int, to newFrame: CGRect, oldFrames: [CGRect],
        kind: LayoutKind, area: CGRect, margin: CGFloat, spacing: CGFloat, current: TileWeights
    ) -> TileWeights {
        let count = oldFrames.count
        guard oldFrames.indices.contains(tile), newFrame.isUsable else { return current }
        let inner = area.insetBy(dx: margin, dy: margin)
        let transposed = LayoutAlgorithms.isTransposed(kind: kind, count: count, inner: inner)
        let space = transposed ? CGSize(width: inner.height, height: inner.width) : inner.size
        let shape = LayoutAlgorithms.makeShape(kind: kind, count: count, weights: current)
        guard let column = shape.columns.firstIndex(where: { $0.contains(tile) }),
              let row = shape.columns[column].firstIndex(of: tile)
        else { return current }

        func abstractSize(_ rect: CGRect) -> CGSize {
            transposed ? CGSize(width: rect.height, height: rect.width) : rect.size
        }
        let old = abstractSize(oldFrames[tile])
        let new = abstractSize(newFrame)
        let tolerance = LayoutDefaults.geometryTolerance
        var result = current

        let columnCount = CGFloat(shape.columns.count)
        if columnCount > 1, abs(new.width - old.width) > tolerance {
            let available = space.width - spacing * (columnCount - 1)
            let others = columnCount - 1
            // Primary width P and equal remaining width u satisfy P + others·u = available.
            let ratio: CGFloat
            if column == 0 {
                ratio = available - new.width > 1 ? new.width * others / (available - new.width) : 0
            } else {
                let primary = available - others * new.width
                ratio = new.width > 1 && primary > 1 ? primary / new.width : 0
            }
            if ratio > 0 { result.primary = Double(ratio) }
        }

        if shape.columns[column].count == 2, abs(new.height - old.height) > tolerance {
            let available = space.height - spacing
            let other = available - new.height
            if new.height > 1, other > 1 {
                result.secondary = Double(row == 0 ? new.height / other : other / new.height)
            }
        }
        return TileWeights(primary: result.primary, secondary: result.secondary)
    }
}
