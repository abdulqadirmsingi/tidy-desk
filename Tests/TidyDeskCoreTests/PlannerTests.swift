import CoreGraphics
import Testing

@testable import TidyDeskCore

private let area = CGRect(x: 0, y: 0, width: 1600, height: 1000)

private func windows(_ count: Int, minimums: [Int: CGSize] = [:]) -> [PlannerWindow] {
    (0..<count).map { PlannerWindow(id: WindowID(), minimumSize: minimums[$0] ?? .zero) }
}

@Suite("Tile planner")
struct PlannerTests {
    @Test func tilesUpToMaxThenStacksOnLastTile() {
        let ws = windows(6)
        let plan = TilePlanner.plan(
            windows: ws, settings: DisplaySettings(layout: .grid, maxWindows: 3, overflow: .stack), area: area)
        #expect(plan.tileFrames.count == 3)
        #expect(plan.placements.prefix(3).map(\.role) == [.tile(0), .tile(1), .tile(2)])
        #expect(plan.placements.dropFirst(3).allSatisfy { $0.role == .stacked(onTile: 2) })
        #expect(plan.placements.dropFirst(3).allSatisfy { $0.frame == plan.tileFrames[2] })
        #expect(plan.stack(onTile: 2).count == 4)
    }

    @Test func floatOverflowLeavesExtrasUnmanaged() {
        let plan = TilePlanner.plan(
            windows: windows(4), settings: DisplaySettings(maxWindows: 2, overflow: .float), area: area)
        #expect(plan.placements.filter { $0.role == .floating }.count == 2)
        #expect(plan.placements.filter { $0.role == .floating }.allSatisfy { $0.frame == nil })
    }

    @Test func floatingWindowsBecomeTiledWhenRoomAppears() {
        let ws = windows(3)
        let settings = DisplaySettings(maxWindows: 2, overflow: .float)
        let before = TilePlanner.plan(windows: ws, settings: settings, area: area)
        let after = TilePlanner.plan(windows: Array(ws.dropFirst()), settings: settings, area: area)
        #expect(before.placements.last?.role == .floating)
        #expect(after.placements.allSatisfy { if case .tile = $0.role { true } else { false } })
    }

    @Test func planIsDeterministic() {
        let ws = windows(4)
        let settings = DisplaySettings(layout: .columns, maxWindows: 3)
        #expect(TilePlanner.plan(windows: ws, settings: settings, area: area)
            == TilePlanner.plan(windows: ws, settings: settings, area: area))
    }

    @Test func oversizedWindowFloatsWhileOthersStillTile() {
        let ws = windows(3, minimums: [1: CGSize(width: 5000, height: 100)])
        let plan = TilePlanner.plan(windows: ws, settings: DisplaySettings(overflow: .float), area: area)
        #expect(plan.placements[1].role == .floating)
        #expect(plan.placements[0].role == .tile(0))
        #expect(plan.placements[2].role == .tile(1))
    }

    @Test func oversizedWindowIsNotStackedIntoTileItCannotFit() {
        let ws = windows(2, minimums: [1: CGSize(width: 5000, height: 100)])
        let plan = TilePlanner.plan(windows: ws, settings: DisplaySettings(overflow: .stack), area: area)
        #expect(plan.placements[1].role == .floating)
    }

    @Test func narrowDisplayReducesColumnCount() {
        let narrow = CGRect(x: 0, y: 0, width: 800, height: 700)
        let plan = TilePlanner.plan(
            windows: windows(3), settings: DisplaySettings(layout: .columns, maxWindows: 3, overflow: .float),
            area: narrow)
        #expect(plan.tileFrames.count < 3)
        #expect(plan.tileFrames.allSatisfy { $0.width >= LayoutDefaults.minimumTileSize.width })
    }

    @Test func emptyAndUnusableAreasProduceNoTiles() {
        #expect(TilePlanner.plan(windows: [], settings: DisplaySettings(), area: area).placements.isEmpty)
        let plan = TilePlanner.plan(windows: windows(2), settings: DisplaySettings(), area: .zero)
        #expect(plan.tileFrames.isEmpty)
        #expect(plan.placements.allSatisfy { $0.role == .floating })
    }

    @Test func maxWindowsIsClamped() {
        #expect(DisplaySettings(maxWindows: 99).maxWindows == 4)
        #expect(DisplaySettings(maxWindows: 0).maxWindows == 1)
    }
}

@Suite("Ratio inference")
struct RatioInferenceTests {
    @Test func resizingPrimaryTileFeedsBackIntoLayout() throws {
        let settings = DisplaySettings(spacing: 10, margin: 10)
        let plan = TilePlanner.plan(windows: windows(2), settings: settings, area: area)
        var resized = plan.tileFrames[0]
        resized.size.width = 1000
        let weights = RatioInference.weights(
            afterResizing: 0, to: resized, oldFrames: plan.tileFrames, kind: .grid, area: area,
            margin: 10, spacing: 10, current: .equal)
        var updated = settings
        updated.weights = weights
        let next = TilePlanner.plan(windows: windows(2), settings: updated, area: area)
        #expect(abs(next.tileFrames[0].width - 1000) < 1)
        #expect(next.tileFrames[1].minX >= next.tileFrames[0].maxX)
    }

    @Test func resizingSecondaryRowAdjustsGridThree() throws {
        let settings = DisplaySettings(spacing: 10, margin: 10)
        let plan = TilePlanner.plan(windows: windows(3), settings: settings, area: area)
        var resized = plan.tileFrames[1]
        resized.size.height = 600
        let weights = RatioInference.weights(
            afterResizing: 1, to: resized, oldFrames: plan.tileFrames, kind: .grid, area: area,
            margin: 10, spacing: 10, current: .equal)
        var updated = settings
        updated.weights = weights
        let next = TilePlanner.plan(windows: windows(3), settings: updated, area: area)
        #expect(abs(next.tileFrames[1].height - 600) < 1)
    }

    @Test func unchangedFrameKeepsWeights() {
        let plan = TilePlanner.plan(windows: windows(2), settings: DisplaySettings(), area: area)
        let weights = RatioInference.weights(
            afterResizing: 0, to: plan.tileFrames[0], oldFrames: plan.tileFrames, kind: .grid, area: area,
            margin: 8, spacing: 8, current: TileWeights(primary: 1.3))
        #expect(weights == TileWeights(primary: 1.3))
    }

    @Test func weightsAreClamped() {
        #expect(TileWeights(primary: 100).primary == LayoutDefaults.weightRange.upperBound)
        #expect(TileWeights(primary: .nan).primary == 1)
    }
}

@Suite("Constraint learning")
struct ConstraintLearnerTests {
    private let limit = CGSize(width: 1600, height: 1000)

    @Test func learnsMinimumWhenWindowRefusesToShrink() {
        let requested = CGRect(x: 0, y: 0, width: 400, height: 500)
        let actual = CGRect(x: 0, y: 0, width: 640, height: 500)
        let learned = ConstraintLearner.learnedMinimum(
            requested: requested, actual: actual, existing: .zero, plausibleLimit: limit)
        #expect(learned == CGSize(width: 640, height: 0))
    }

    @Test func ignoresAcceptedAndImplausibleResults() {
        let requested = CGRect(x: 0, y: 0, width: 400, height: 500)
        #expect(ConstraintLearner.learnedMinimum(requested: requested, actual: requested, existing: .zero, plausibleLimit: limit) == nil)
        let huge = CGRect(x: 0, y: 0, width: 4000, height: 500)
        #expect(ConstraintLearner.learnedMinimum(requested: requested, actual: huge, existing: .zero, plausibleLimit: limit) == nil)
        #expect(ConstraintLearner.accepted(requested: requested, actual: requested))
    }

    @Test func neverLowersAnExistingMinimum() {
        let requested = CGRect(x: 0, y: 0, width: 400, height: 500)
        let actual = CGRect(x: 0, y: 0, width: 500, height: 500)
        let existing = CGSize(width: 700, height: 0)
        #expect(ConstraintLearner.learnedMinimum(requested: requested, actual: actual, existing: existing, plausibleLimit: limit) == nil)
    }
}

@Suite("Resizes the layout cannot express")
struct InexpressibleResizeTests {
    @Test func shrinkingASingleWindowChangesNoWeights() {
        let area = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let plan = TilePlanner.plan(windows: windows(1), settings: DisplaySettings(), area: area)
        var smaller = plan.tileFrames[0]
        smaller.size = CGSize(width: 800, height: 500)
        let weights = RatioInference.weights(
            afterResizing: 0, to: smaller, oldFrames: plan.tileFrames, kind: .grid, area: area,
            margin: 8, spacing: 8, current: .equal)
        #expect(weights == .equal)
    }

    @Test func changingTheHeightOfAFullHeightColumnTileChangesNoWeights() {
        let area = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let settings = DisplaySettings(layout: .columns, maxWindows: 3)
        let plan = TilePlanner.plan(windows: windows(3), settings: settings, area: area)
        var shorter = plan.tileFrames[1]
        shorter.size.height -= 300
        let weights = RatioInference.weights(
            afterResizing: 1, to: shorter, oldFrames: plan.tileFrames, kind: .columns, area: area,
            margin: 8, spacing: 8, current: .equal)
        #expect(weights == .equal)
    }
}


@Suite("False minimum sizes")
struct FalseMinimumTests {
    private let usable = CGSize(width: 1512, height: 920)
    private var limit: CGSize { ConstraintLearner.plausibleLimit(forUsable: usable) }

    @Test func aTerminalSnappingToWholeCellsIsNotARefusal() {
        let requested = CGRect(x: 0, y: 0, width: 744, height: 448)
        let snapped = CGRect(x: 0, y: 0, width: 749, height: 461)  // one character cell larger
        #expect(ConstraintLearner.accepted(requested: requested, actual: snapped))
        #expect(ConstraintLearner.learnedMinimum(requested: requested, actual: snapped, existing: .zero, plausibleLimit: limit) == nil)
    }

    @Test func aGenuineRefusalBeyondTheSnapAllowanceIsStillLearned() {
        let requested = CGRect(x: 0, y: 0, width: 500, height: 448)
        let actual = CGRect(x: 0, y: 0, width: 800, height: 448)
        #expect(!ConstraintLearner.accepted(requested: requested, actual: actual))
        #expect(ConstraintLearner.learnedMinimum(requested: requested, actual: actual, existing: .zero, plausibleLimit: limit)
            == CGSize(width: 800, height: 0))
    }

    @Test func aStaleFullHeightReadingIsNeverRememberedAsAMinimum() {
        // Terminal reported 861 high right after being asked for 448: the old size, not a limit.
        let requested = CGRect(x: 0, y: 0, width: 744, height: 448)
        let stale = CGRect(x: 0, y: 0, width: 744, height: 861)
        #expect(ConstraintLearner.learnedMinimum(requested: requested, actual: stale, existing: .zero, plausibleLimit: limit) == nil)
    }

    @Test func plausibleLimitIsThreeQuartersOfTheUsableArea() {
        #expect(limit == CGSize(width: 1134, height: 690))
    }

    @Test func savedImpossibleMinimumsAreIgnoredButRealOnesKept() {
        #expect(ConstraintLearner.usableMinimum(learned: CGSize(width: 0, height: 861), usable: usable) == .zero)
        #expect(ConstraintLearner.usableMinimum(learned: CGSize(width: 1026, height: 0), usable: usable)
            == CGSize(width: 1026, height: 0))
        #expect(ConstraintLearner.usableMinimum(learned: CGSize(width: 1300, height: 600), usable: usable)
            == CGSize(width: 0, height: 600))
    }

    @Test func aWindowWithARepairedMinimumTilesInATwoByTwoGrid() {
        let area = CGRect(x: 0, y: 0, width: 1512, height: 920)
        let repaired = ConstraintLearner.usableMinimum(learned: CGSize(width: 0, height: 861), usable: area.size)
        let ids = (0..<4).map { _ in WindowID() }
        let windows = ids.enumerated().map { PlannerWindow(id: $1, minimumSize: $0 == 1 ? repaired : .zero) }
        let plan = TilePlanner.plan(windows: windows, settings: DisplaySettings(maxWindows: 4, overflow: .float), area: area)
        #expect(plan.placements.allSatisfy { if case .tile = $0.role { true } else { false } })
    }

    @Test func theUnrepairedBogusMinimumLeavesOtherWindowsUntiled() {
        let area = CGRect(x: 0, y: 0, width: 1512, height: 920)
        let ids = (0..<4).map { _ in WindowID() }
        let windows = ids.enumerated().map { PlannerWindow(id: $1, minimumSize: $0 == 1 ? CGSize(width: 0, height: 861) : .zero) }
        let plan = TilePlanner.plan(windows: windows, settings: DisplaySettings(maxWindows: 4, overflow: .float), area: area)
        // A 861-high "minimum" forces Terminal into a full-height column, so a 2x2 grid cannot form and the
        // later windows are pushed out: the pile-up seen on the real machine.
        #expect(plan.placements.contains { $0.role == .floating })
        #expect(plan.tileFrames.count < 4)
    }
}
