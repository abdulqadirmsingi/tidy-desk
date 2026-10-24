import ApplicationServices
import Foundation

enum AXFailure: Error, LocalizedError, Equatable {
    case invalidElement
    case notSettable
    case timedOut
    case unsupported
    case other(Int32)

    init(_ error: AXError) {
        switch error {
        case .invalidUIElement: self = .invalidElement
        case .cannotComplete: self = .timedOut
        case .attributeUnsupported, .actionUnsupported, .noValue: self = .unsupported
        default: self = .other(error.rawValue)
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidElement: "The window no longer exists."
        case .notSettable: "The window does not allow this change."
        case .timedOut: "The app did not respond in time."
        case .unsupported: "The app does not support this operation."
        case let .other(code): "Accessibility error \(code)."
        }
    }
}

/// Thin value wrapper over `AXUIElement`. Equality uses `CFEqual`, which is how a window is
/// recognised across separate enumerations without private window-number APIs.
struct AXElement: Equatable {
    let raw: AXUIElement

    /// Seconds before an unresponsive app stops blocking us. The timeout is per element, so it
    /// is applied here for every element we wrap, not just the application element.
    static let messagingTimeout: Float = 0.5

    init(raw: AXUIElement) {
        AXUIElementSetMessagingTimeout(raw, Self.messagingTimeout)
        self.raw = raw
    }

    static func == (lhs: AXElement, rhs: AXElement) -> Bool { CFEqual(lhs.raw, rhs.raw) }

    static func application(pid: pid_t) -> AXElement {
        AXElement(raw: AXUIElementCreateApplication(pid))
    }

    var pid: pid_t? {
        var pid: pid_t = 0
        return AXUIElementGetPid(raw, &pid) == .success ? pid : nil
    }

    func value(_ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(raw, attribute as CFString, &result) == .success else { return nil }
        return result
    }

    /// Distinguishes "attribute missing" from "element is gone" or "app not responding".
    func probe() -> AXError {
        var result: CFTypeRef?
        return AXUIElementCopyAttributeValue(raw, kAXRoleAttribute as CFString, &result)
    }

    func string(_ attribute: String) -> String? { value(attribute) as? String }

    func bool(_ attribute: String) -> Bool? { (value(attribute) as? NSNumber)?.boolValue }

    func element(_ attribute: String) -> AXElement? {
        guard let found = value(attribute), CFGetTypeID(found) == AXUIElementGetTypeID() else { return nil }
        return AXElement(raw: unsafeDowncast(found, to: AXUIElement.self))
    }

    func elements(_ attribute: String) -> [AXElement] {
        guard let array = value(attribute) as? [AnyObject] else { return [] }
        return array.compactMap { object in
            let cf = object as CFTypeRef
            guard CFGetTypeID(cf) == AXUIElementGetTypeID() else { return nil }
            return AXElement(raw: unsafeDowncast(cf, to: AXUIElement.self))
        }
    }

    func point(_ attribute: String) -> CGPoint? {
        guard let found = value(attribute), CFGetTypeID(found) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        // The CFGetTypeID check above guarantees this bridge is valid.
        return AXValueGetValue(unsafeDowncast(found, to: AXValue.self), .cgPoint, &point) ? point : nil
    }

    func size(_ attribute: String) -> CGSize? {
        guard let found = value(attribute), CFGetTypeID(found) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(unsafeDowncast(found, to: AXValue.self), .cgSize, &size) ? size : nil
    }

    func isSettable(_ attribute: String) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(raw, attribute as CFString, &settable) == .success && settable.boolValue
    }

    var frame: CGRect? {
        guard let origin = point(kAXPositionAttribute), let size = size(kAXSizeAttribute) else { return nil }
        let rect = CGRect(origin: origin, size: size)
        return rect.isUsable ? rect : nil
    }

    func setPosition(_ point: CGPoint) throws {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { throw AXFailure.unsupported }
        try check(AXUIElementSetAttributeValue(raw, kAXPositionAttribute as CFString, value))
    }

    func setSize(_ size: CGSize) throws {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { throw AXFailure.unsupported }
        try check(AXUIElementSetAttributeValue(raw, kAXSizeAttribute as CFString, value))
    }

    func perform(_ action: String) {
        AXUIElementPerformAction(raw, action as CFString)
    }

    private func check(_ error: AXError) throws {
        if error != .success { throw AXFailure(error) }
    }
}
