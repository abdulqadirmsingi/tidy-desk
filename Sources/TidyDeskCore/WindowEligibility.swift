import CoreGraphics

/// What Accessibility reported about a window. Nil means the attribute was unavailable.
public struct WindowTraits: Equatable, Sendable {
    public var role: String?
    public var subrole: String?
    public var isMinimized: Bool?
    public var isFullScreen: Bool?
    public var isModal: Bool?
    public var canMove: Bool
    public var canResize: Bool
    public var hasUsableFrame: Bool

    public init(
        role: String? = "AXWindow", subrole: String? = "AXStandardWindow", isMinimized: Bool? = false,
        isFullScreen: Bool? = false, isModal: Bool? = false, canMove: Bool = true, canResize: Bool = true,
        hasUsableFrame: Bool = true
    ) {
        self.role = role
        self.subrole = subrole
        self.isMinimized = isMinimized
        self.isFullScreen = isFullScreen
        self.isModal = isModal
        self.canMove = canMove
        self.canResize = canResize
        self.hasUsableFrame = hasUsableFrame
    }
}

public enum Ineligibility: Equatable, Sendable {
    case notAStandardWindow
    case minimized
    case fullScreen
    case modal
    case notMovable
    case notResizable
    case noGeometry

    public var explanation: String {
        switch self {
        case .notAStandardWindow: "it is a panel, dialog or utility window rather than a normal window"
        case .minimized: "it is minimized"
        case .fullScreen: "it is in macOS full-screen mode"
        case .modal: "it is a modal dialog"
        case .notMovable: "the app does not allow it to be moved"
        case .notResizable: "the app does not allow it to be resized"
        case .noGeometry: "the app did not report its position and size"
        }
    }
}

/// The single definition of which windows may be tiled.
public enum WindowEligibility {
    public static func evaluate(_ traits: WindowTraits) -> Ineligibility? {
        guard traits.role == "AXWindow", traits.subrole == "AXStandardWindow" else { return .notAStandardWindow }
        if traits.isMinimized == true { return .minimized }
        if traits.isFullScreen == true { return .fullScreen }
        if traits.isModal == true { return .modal }
        if !traits.canMove { return .notMovable }
        if !traits.canResize { return .notResizable }
        if !traits.hasUsableFrame { return .noGeometry }
        return nil
    }
}

/// Plain-language answer to "why isn't this window tiled?". Contains no window titles.
public enum WindowExplanation {
    public static func describe(
        appName: String, ineligibility: Ineligibility?, isExcluded: Bool, isUserFloating: Bool, isStubborn: Bool,
        learnedMinimum: CGSize?, role: PlacementRole?
    ) -> String {
        if let ineligibility {
            return "\(appName) is not tiled because \(ineligibility.explanation)."
        }
        if isExcluded { return "\(appName) is excluded. Re-enable it in Settings → Apps to tile its windows." }
        if isUserFloating { return "This \(appName) window is floating because you chose Float. Turn that off in the menu to tile it." }
        if isStubborn {
            return "This \(appName) window kept refusing the size it was given, so it is left floating. “Arrange Windows Now” tries again."
        }
        switch role {
        case .tile(let index)?: return "This \(appName) window is tiled (tile \(index + 1))."
        case .stacked(onTile: let index)?:
            return "This \(appName) window is stacked behind another window in tile \(index + 1). Use Cycle Stacked Windows to switch."
        case .floating?:
            let size = learnedMinimum.map { " It needs at least \(Int($0.width)) × \(Int($0.height)) points," } ?? ""
            return "This \(appName) window is floating because it does not fit in the layout." + size
                + " Try fewer windows on this display or the Float overflow setting."
        case nil: return "\(appName) was not found in the current layout yet. Try “Arrange Windows Now”."
        }
    }
}
