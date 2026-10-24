import CoreGraphics

/// Input for a single layout computation. `minimums.count` is the number of tiles.
public struct LayoutRequest: Sendable {
    public var area: CGRect
    public var kind: LayoutKind
    public var spacing: CGFloat
    public var margin: CGFloat
    public var weights: TileWeights
    public var minimums: [CGSize]

    public init(
        area: CGRect, kind: LayoutKind, spacing: CGFloat, margin: CGFloat,
        weights: TileWeights, minimums: [CGSize]
    ) {
        self.area = area
        self.kind = kind
        self.spacing = spacing
        self.margin = margin
        self.weights = weights
        self.minimums = minimums
    }
}

/// Pure tile geometry for Grid and Columns.
///
/// Tiles are described as columns of stacked tiles in a "landscape" frame. Portrait
/// displays transpose that frame (columns become rows) except for the 2×2 grid, which is
/// already symmetric. Tile 0 is always the primary tile.
public enum LayoutAlgorithms {
    struct Shape {
        var columns: [[Int]]
        var columnWeights: [Double]
        var rowWeights: [Double]
        var alignRows = false
    }

    /// Where a tile sits in the column/row structure; used to decide which weight a resize changes.
    public struct TilePosition: Equatable, Sendable {
        public let column: Int
        public let columnCount: Int
        public let row: Int
        public let rowCount: Int
    }

    public static func position(ofTile tile: Int, kind: LayoutKind, count: Int) -> TilePosition? {
        guard (1...LayoutDefaults.maxWindowsPerDisplay).contains(count) else { return nil }
        let shape = makeShape(kind: kind, count: count, weights: .equal)
        guard let column = shape.columns.firstIndex(where: { $0.contains(tile) }),
              let row = shape.columns[column].firstIndex(of: tile)
        else { return nil }
        return TilePosition(
            column: column, columnCount: shape.columns.count, row: row, rowCount: shape.columns[column].count)
    }

    /// Returns one frame per requested tile, or nil if the minimum sizes cannot fit.
    public static func frames(_ request: LayoutRequest) -> [CGRect]? {
        let count = request.minimums.count
        guard (1...LayoutDefaults.maxWindowsPerDisplay).contains(count) else { return nil }
        let inner = request.area.insetBy(dx: request.margin, dy: request.margin)
        guard inner.isUsable else { return nil }

        let transposed = isTransposed(kind: request.kind, count: count, inner: inner)
        let space = transposed ? CGSize(width: inner.height, height: inner.width) : inner.size
        let minimums = transposed
            ? request.minimums.map { CGSize(width: $0.height, height: $0.width) } : request.minimums

        let shape = makeShape(kind: request.kind, count: count, weights: request.weights)
        guard let local = place(shape, in: space, gap: request.spacing, minimums: minimums) else { return nil }

        return local.map { rect in
            transposed
                ? CGRect(x: inner.minX + rect.minY, y: inner.minY + rect.minX, width: rect.height, height: rect.width)
                : rect.offsetBy(dx: inner.minX, dy: inner.minY)
        }
    }

    /// Portrait areas swap rows and columns, except the symmetric 2×2 grid.
    static func isTransposed(kind: LayoutKind, count: Int, inner: CGRect) -> Bool {
        count > 1 && inner.height > inner.width && !(kind == .grid && count == 4)
    }

    static func makeShape(kind: LayoutKind, count: Int, weights: TileWeights) -> Shape {
        let rows = [weights.secondary, 1]
        switch kind {
        case .columns:
            return Shape(
                columns: (0..<count).map { [$0] },
                columnWeights: [weights.primary] + [Double](repeating: 1, count: count - 1),
                rowWeights: [1])
        case .grid:
            switch count {
            case 1: return Shape(columns: [[0]], columnWeights: [1], rowWeights: [1])
            case 2: return Shape(columns: [[0], [1]], columnWeights: [weights.primary, 1], rowWeights: [1])
            case 3: return Shape(columns: [[0], [1, 2]], columnWeights: [weights.primary, 1], rowWeights: rows)
            default:
                return Shape(
                    columns: [[0, 2], [1, 3]], columnWeights: [weights.primary, 1], rowWeights: rows,
                    alignRows: true)
            }
        }
    }

    private static func place(_ shape: Shape, in space: CGSize, gap: CGFloat, minimums: [CGSize]) -> [CGRect]? {
        let columnMinimums = shape.columns.map { tiles in tiles.map { minimums[$0].width }.max() ?? 0 }
        guard let widths = AxisSplitter.split(
            length: space.width, gap: gap, weights: shape.columnWeights, minimums: columnMinimums)
        else { return nil }
        let columnSpans = AxisSplitter.spans(origin: 0, sizes: widths, gap: gap)

        let alignedRowMinimums = (0..<2).map { row in
            shape.columns.compactMap { $0.indices.contains(row) ? minimums[$0[row]].height : nil }.max() ?? 0
        }

        var frames = [CGRect](repeating: .zero, count: minimums.count)
        for (columnIndex, tiles) in shape.columns.enumerated() {
            let rowMinimums = shape.alignRows ? alignedRowMinimums : tiles.map { minimums[$0].height }
            let rowWeights = Array(shape.rowWeights.prefix(tiles.count))
            guard let heights = AxisSplitter.split(
                length: space.height, gap: gap, weights: rowWeights, minimums: rowMinimums)
            else { return nil }
            let rowSpans = AxisSplitter.spans(origin: 0, sizes: heights, gap: gap)
            for (row, tile) in tiles.enumerated() {
                frames[tile] = CGRect(
                    x: columnSpans[columnIndex].start, y: rowSpans[row].start,
                    width: columnSpans[columnIndex].length, height: rowSpans[row].length)
            }
        }
        return frames
    }
}
