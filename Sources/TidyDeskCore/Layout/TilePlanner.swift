import CoreGraphics

public struct PlannerWindow: Sendable, Equatable {
    public var id: WindowID
    /// Largest known minimum (reported or learned). `.zero` when unknown.
    public var minimumSize: CGSize

    public init(id: WindowID, minimumSize: CGSize = .zero) {
        self.id = id
        self.minimumSize = minimumSize
    }
}

public enum PlacementRole: Equatable, Sendable {
    case tile(Int)
    /// Shares the frame of the given tile with other windows.
    case stacked(onTile: Int)
    /// Not managed; left where the user has it.
    case floating
}

public struct Placement: Equatable, Sendable {
    public var id: WindowID
    public var role: PlacementRole
    /// Target frame. Nil for floating windows.
    public var frame: CGRect?
}

public struct TilePlan: Equatable, Sendable {
    public var placements: [Placement]
    public var tileFrames: [CGRect]

    /// Windows sharing one tile, tile owner first.
    public func stack(onTile tile: Int) -> [WindowID] {
        placements.compactMap { placement in
            switch placement.role {
            case .tile(tile), .stacked(onTile: tile): placement.id
            default: nil
            }
        }
    }
}

public enum TilePlanner {
    /// Plans placements for `windows` (already in display order, primary first).
    /// Placements are returned in the same order as `windows`.
    ///
    /// Windows are admitted greedily: a window joins the tiled set only if the layout still
    /// satisfies every admitted window's minimum size. Rejected or surplus windows follow
    /// the overflow policy, so the result is deterministic and does not flap.
    public static func plan(windows: [PlannerWindow], settings: DisplaySettings, area: CGRect) -> TilePlan {
        var admitted: [PlannerWindow] = []
        var rejected: [PlannerWindow] = []
        var frames: [CGRect] = []

        for window in windows {
            guard admitted.count < settings.maxWindows else {
                rejected.append(window)
                continue
            }
            let candidate = admitted + [window]
            if let candidateFrames = layout(candidate, settings: settings, area: area) {
                admitted = candidate
                frames = candidateFrames
            } else {
                rejected.append(window)
            }
        }

        var roles: [WindowID: Placement] = [:]
        for (index, window) in admitted.enumerated() {
            roles[window.id] = Placement(id: window.id, role: .tile(index), frame: frames[index])
        }
        for window in rejected {
            // A window rejected for size reasons cannot share a tile it does not fit in.
            if settings.overflow == .stack, fitsAsStack(window, frames: frames) {
                let tile = frames.count - 1
                roles[window.id] = Placement(id: window.id, role: .stacked(onTile: tile), frame: frames[tile])
            } else {
                roles[window.id] = Placement(id: window.id, role: .floating, frame: nil)
            }
        }
        let placements = windows.compactMap { roles[$0.id] }
        return TilePlan(placements: placements, tileFrames: frames)
    }

    private static func layout(_ windows: [PlannerWindow], settings: DisplaySettings, area: CGRect) -> [CGRect]? {
        let minimums = windows.map { window in
            CGSize(
                width: max(window.minimumSize.width, LayoutDefaults.minimumTileSize.width),
                height: max(window.minimumSize.height, LayoutDefaults.minimumTileSize.height))
        }
        return LayoutAlgorithms.frames(
            LayoutRequest(
                area: area, kind: settings.layout, spacing: settings.spacing, margin: settings.margin,
                weights: settings.weights, minimums: minimums))
    }

    private static func fitsAsStack(_ window: PlannerWindow, frames: [CGRect]) -> Bool {
        guard let last = frames.last else { return false }
        return window.minimumSize.width <= last.width + LayoutDefaults.geometryTolerance
            && window.minimumSize.height <= last.height + LayoutDefaults.geometryTolerance
    }
}
