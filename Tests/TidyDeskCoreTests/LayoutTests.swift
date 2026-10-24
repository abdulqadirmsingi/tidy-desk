import CoreGraphics
import Testing

@testable import TidyDeskCore

private let landscape = CGRect(x: 0, y: 0, width: 1600, height: 1000)
private let portrait = CGRect(x: 0, y: 0, width: 1000, height: 1600)

private func request(
    _ kind: LayoutKind, count: Int, area: CGRect = landscape, spacing: CGFloat = 10, margin: CGFloat = 10,
    weights: TileWeights = .equal, minimums: [CGSize]? = nil
) -> LayoutRequest {
    LayoutRequest(
        area: area, kind: kind, spacing: spacing, margin: margin, weights: weights,
        minimums: minimums ?? [CGSize](repeating: .zero, count: count))
}

private func noOverlap(_ frames: [CGRect]) -> Bool {
    for i in frames.indices {
        for j in frames.indices where j > i && !frames[i].intersection(frames[j]).isNull {
            let overlap = frames[i].intersection(frames[j])
            if overlap.width > 0.001 && overlap.height > 0.001 { return false }
        }
    }
    return true
}

@Suite("Grid layout")
struct GridLayoutTests {
    @Test func oneWindowFillsInnerArea() throws {
        let frames = try #require(LayoutAlgorithms.frames(request(.grid, count: 1)))
        #expect(frames == [CGRect(x: 10, y: 10, width: 1580, height: 980)])
    }

    @Test func twoWindowsSplitLeftRight() throws {
        let f = try #require(LayoutAlgorithms.frames(request(.grid, count: 2)))
        #expect(f[0].minX == 10)
        #expect(f[1].maxX == 1590)
        #expect(f[0].height == 980 && f[1].height == 980)
        #expect(f[1].minX - f[0].maxX == 10)
        #expect(f[0].width == f[1].width)
    }

    @Test func threeWindowsPrimaryLeftRightSplit() throws {
        let f = try #require(LayoutAlgorithms.frames(request(.grid, count: 3)))
        #expect(f[0].height == 980)
        #expect(f[1].minX == f[2].minX)
        #expect(f[1].minX > f[0].maxX)
        #expect(f[2].minY - f[1].maxY == 10)
        #expect(f[1].maxX == 1590 && f[2].maxX == 1590)
        #expect(noOverlap(f))
    }

    @Test func fourWindowsFormTwoByTwoRowMajor() throws {
        let f = try #require(LayoutAlgorithms.frames(request(.grid, count: 4)))
        #expect(f[0].minY == f[1].minY)
        #expect(f[2].minY == f[3].minY)
        #expect(f[0].minX == f[2].minX)
        #expect(f[1].minX == f[3].minX)
        #expect(f[0].minX < f[1].minX)
        #expect(f[0].minY < f[2].minY)
        #expect(noOverlap(f))
    }

    @Test func portraitTwoWindowsStackVertically() throws {
        let f = try #require(LayoutAlgorithms.frames(request(.grid, count: 2, area: portrait)))
        #expect(f[0].minY < f[1].minY)
        #expect(f[0].width == f[1].width)
    }

    @Test func portraitThreeWindowsPrimaryOnTop() throws {
        let f = try #require(LayoutAlgorithms.frames(request(.grid, count: 3, area: portrait)))
        #expect(f[0].width == 980)
        #expect(f[1].minY == f[2].minY)
        #expect(f[1].minY > f[0].maxY)
        #expect(f[1].minX < f[2].minX)
    }

    @Test func tilesStayInsideAreaWithMarginAndOffsetOrigin() throws {
        let area = CGRect(x: 1600, y: 25, width: 1440, height: 875)
        for count in 1...4 {
            let f = try #require(LayoutAlgorithms.frames(request(.grid, count: count, area: area, margin: 20)))
            let inner = area.insetBy(dx: 20, dy: 20)
            #expect(f.allSatisfy { inner.insetBy(dx: -0.001, dy: -0.001).contains($0) })
        }
    }

    @Test func primaryWeightWidensPrimaryTile() throws {
        let f = try #require(LayoutAlgorithms.frames(request(.grid, count: 2, weights: TileWeights(primary: 2))))
        #expect(abs(f[0].width / f[1].width - 2) < 0.01)
    }

    @Test func spacingAndMarginAreApplied() throws {
        let f = try #require(LayoutAlgorithms.frames(request(.grid, count: 2, spacing: 30, margin: 50)))
        #expect(f[0].minX == 50)
        #expect(f[1].minX - f[0].maxX == 30)
        #expect(f[1].maxX == 1550)
    }
}

@Suite("Columns layout")
struct ColumnsLayoutTests {
    @Test(arguments: 1...4)
    func columnsShareWidthAndUseFullHeight(count: Int) throws {
        let f = try #require(LayoutAlgorithms.frames(request(.columns, count: count)))
        #expect(f.count == count)
        #expect(f.allSatisfy { $0.height == 980 })
        #expect(zip(f, f.dropFirst()).allSatisfy { $0.minX < $1.minX })
        #expect(abs(f.map(\.width).max()! - f.map(\.width).min()!) < 0.001)
    }

    @Test func differsFromGridForThreeWindows() throws {
        let columns = try #require(LayoutAlgorithms.frames(request(.columns, count: 3)))
        let grid = try #require(LayoutAlgorithms.frames(request(.grid, count: 3)))
        #expect(columns != grid)
    }

    @Test func portraitUsesRows() throws {
        let f = try #require(LayoutAlgorithms.frames(request(.columns, count: 3, area: portrait)))
        #expect(f.allSatisfy { $0.width == 980 })
        #expect(zip(f, f.dropFirst()).allSatisfy { $0.minY < $1.minY })
    }

    @Test func minimumWidthsAreHonoured() throws {
        let mins = [CGSize(width: 800, height: 0), .zero, .zero]
        let f = try #require(LayoutAlgorithms.frames(request(.columns, count: 3, minimums: mins)))
        #expect(f[0].width >= 800)
        #expect(noOverlap(f))
        #expect(f[2].maxX <= 1590.001)
    }

    @Test func infeasibleMinimumsReturnNil() {
        let mins = [CGSize(width: 1000, height: 0), CGSize(width: 1000, height: 0)]
        #expect(LayoutAlgorithms.frames(request(.columns, count: 2, minimums: mins)) == nil)
    }

    @Test func minimumHeightTooTallReturnsNil() {
        let mins = [CGSize(width: 0, height: 2000)]
        #expect(LayoutAlgorithms.frames(request(.columns, count: 1, minimums: mins)) == nil)
    }
}

@Suite("Layout edge cases")
struct LayoutEdgeCaseTests {
    @Test func invalidCountsAndAreasReturnNil() {
        #expect(LayoutAlgorithms.frames(request(.grid, count: 0)) == nil)
        #expect(LayoutAlgorithms.frames(request(.grid, count: 5, minimums: [CGSize](repeating: .zero, count: 5))) == nil)
        #expect(LayoutAlgorithms.frames(request(.grid, count: 1, area: .zero)) == nil)
        #expect(LayoutAlgorithms.frames(request(.grid, count: 1, area: CGRect(x: 0, y: 0, width: 15, height: 15), margin: 10)) == nil)
        #expect(LayoutAlgorithms.frames(request(.grid, count: 1, area: CGRect(x: CGFloat.nan, y: 0, width: 100, height: 100))) == nil)
    }

    @Test func gridFourAlignsRowsWhenOneColumnNeedsTallerRow() throws {
        let mins = [CGSize.zero, .zero, CGSize(width: 0, height: 700), .zero]
        let f = try #require(LayoutAlgorithms.frames(request(.grid, count: 4, minimums: mins)))
        #expect(f[2].minY == f[3].minY)
        #expect(f[2].height >= 700)
    }

    @Test func splitterPinsConstrainedSegmentsAndKeepsTotal() throws {
        let sizes = try #require(AxisSplitter.split(length: 1000, gap: 0, weights: [1, 1, 1], minimums: [600, 0, 0]))
        #expect(sizes[0] == 600)
        #expect(abs(sizes.reduce(0, +) - 1000) < 0.001)
        #expect(abs(sizes[1] - 200) < 0.001)
    }
}

@Suite("Coordinates")
struct CoordinateTests {
    @Test func flipIsItsOwnInverse() {
        let rect = CGRect(x: 100, y: 50, width: 300, height: 200)
        let flipped = ScreenCoordinates.flip(rect, primaryHeight: 900)
        #expect(flipped == CGRect(x: 100, y: 650, width: 300, height: 200))
        #expect(ScreenCoordinates.flip(flipped, primaryHeight: 900) == rect)
    }
}

@Suite("Tile positions")
struct TilePositionTests {
    @Test func gridThreeHasSplitRightColumn() {
        #expect(LayoutAlgorithms.position(ofTile: 0, kind: .grid, count: 3)
            == .init(column: 0, columnCount: 2, row: 0, rowCount: 1))
        #expect(LayoutAlgorithms.position(ofTile: 2, kind: .grid, count: 3)
            == .init(column: 1, columnCount: 2, row: 1, rowCount: 2))
    }

    @Test func columnsAreSingleRow() {
        #expect(LayoutAlgorithms.position(ofTile: 2, kind: .columns, count: 4)
            == .init(column: 2, columnCount: 4, row: 0, rowCount: 1))
        #expect(LayoutAlgorithms.position(ofTile: 9, kind: .columns, count: 4) == nil)
    }
}
