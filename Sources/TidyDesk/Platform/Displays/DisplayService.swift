import AppKit
import TidyDeskCore

struct DisplayInfo: Identifiable, Equatable {
    let id: DisplayID
    let name: String
    let isBuiltIn: Bool
    /// Full and usable (menu bar and Dock excluded) frames in Accessibility coordinates.
    let frame: CGRect
    let usableFrame: CGRect
    let backingScreenNumber: CGDirectDisplayID
}

/// Reads display geometry from `NSScreen`, converted to the top-left coordinate space that
/// Accessibility uses.
@MainActor
struct DisplayService {
    /// Displays ordered left-to-right then top-to-bottom, matching System Settings arrangement.
    func current() -> [DisplayInfo] {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return [] }
        return NSScreen.screens.compactMap { screen -> DisplayInfo? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                  let id = Self.identifier(for: number)
            else { return nil }
            return DisplayInfo(
                id: id, name: screen.localizedName, isBuiltIn: CGDisplayIsBuiltin(number) != 0,
                frame: ScreenCoordinates.flip(screen.frame, primaryHeight: primaryHeight),
                usableFrame: ScreenCoordinates.flip(screen.visibleFrame, primaryHeight: primaryHeight),
                backingScreenNumber: number)
        }
        .sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
    }

    /// Display with the largest overlap with `rect`, or the nearest one for off-screen windows.
    static func display(for rect: CGRect, in displays: [DisplayInfo]) -> DisplayInfo? {
        let overlapping = displays.max {
            area(of: $0.frame.intersection(rect)) < area(of: $1.frame.intersection(rect))
        }
        if let overlapping, area(of: overlapping.frame.intersection(rect)) > 0 { return overlapping }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return displays.min { distance(from: center, to: $0.frame) < distance(from: center, to: $1.frame) }
    }

    static func display(at point: CGPoint, in displays: [DisplayInfo]) -> DisplayInfo? {
        displays.first { $0.frame.contains(point) }
            ?? displays.min { distance(from: point, to: $0.frame) < distance(from: point, to: $1.frame) }
    }

    private static func identifier(for number: CGDirectDisplayID) -> DisplayID? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue(),
              let string = CFUUIDCreateString(nil, uuid) as String?
        else { return nil }
        return DisplayID(rawValue: string)
    }

    private static func area(of rect: CGRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }
}
