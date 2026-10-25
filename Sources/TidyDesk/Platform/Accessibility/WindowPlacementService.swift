import AppKit
import TidyDeskCore

/// Applies geometry to other apps' windows through Accessibility.
@MainActor
struct WindowPlacementService {
    /// Moves and resizes `element`, then reads back what the app actually accepted.
    ///
    /// Position is set again after the resize because many apps shift origin when their
    /// size changes, especially when crossing displays.
    func place(_ element: AXElement, to target: CGRect) -> Result<CGRect, AXFailure> {
        do {
            try element.setPosition(target.origin)
            try element.setSize(target.size)
            guard var actual = element.frame else { return .failure(.unsupported) }
            if abs(actual.minX - target.minX) > LayoutDefaults.geometryTolerance
                || abs(actual.minY - target.minY) > LayoutDefaults.geometryTolerance
            {
                try element.setPosition(target.origin)
                actual = element.frame ?? actual
            }
            return .success(actual)
        } catch let failure as AXFailure {
            return .failure(failure)
        } catch {
            return .failure(.unsupported)
        }
    }

    /// Moves a window without touching its size. Returns the position the app accepted, or nil on failure.
    func move(_ element: AXElement, to origin: CGPoint) -> CGPoint? {
        do { try element.setPosition(origin) } catch { return nil }
        return element.frame?.origin
    }

    func raise(_ element: AXElement, pid: pid_t, activate: Bool) {
        element.perform(kAXRaiseAction)
        if activate { NSRunningApplication(processIdentifier: pid)?.activate() }
    }
}
