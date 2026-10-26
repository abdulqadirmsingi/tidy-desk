/// Which SF Symbol the menu bar icon shows. One glance should tell the user whether tiling is working.
public enum MenuBarSymbol {
    public static func name(status: TilingStatus, isSpecialModeActive: Bool, style: MenuBarIconStyle) -> String {
        switch status {
        case .needsPermission: "exclamationmark.triangle"
        case .pausedByUser, .stageManagerOn, .asleep: "pause.rectangle"
        case .active:
            if isSpecialModeActive { "scope" } else { style == .filled ? "rectangle.split.2x2.fill" : "rectangle.split.2x2" }
        }
    }
}
