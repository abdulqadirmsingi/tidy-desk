import Carbon.HIToolbox
import TidyDeskCore

/// Registers system-wide hot keys with Carbon `RegisterEventHotKey`, which is public and needs
/// no extra privacy permission.
@MainActor
final class GlobalShortcutCenter {
    enum Failure: Equatable {
        /// Another app or macOS already owns this combination.
        case unavailable
        case other(Int32)

        var explanation: String {
            switch self {
            case .unavailable:
                "Another app or macOS already uses this shortcut. Choose a different one in Settings → Shortcuts."
            case let .other(code): "The shortcut could not be registered (error \(code))."
            }
        }
    }

    var onAction: ((ShortcutAction) -> Void)?

    private static let signature: OSType = 0x5444_534B  // 'TDSK'
    private var handlerRef: EventHandlerRef?
    private var hotKeys: [UInt32: (action: ShortcutAction, ref: EventHotKeyRef)] = [:]
    private let actions = ShortcutAction.allCases

    /// Replaces all registrations and reports the ones that failed.
    func register(_ map: ShortcutMap) -> [ShortcutAction: Failure] {
        installHandlerIfNeeded()
        unregisterAll()
        var failures: [ShortcutAction: Failure] = [:]
        let conflicted = Set(map.conflicts.values.flatMap { $0 })
        for (index, action) in actions.enumerated() {
            guard let shortcut = map.bindings[action], !conflicted.contains(action) else { continue }
            let id = EventHotKeyID(signature: Self.signature, id: UInt32(index))
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                shortcut.keyCode, Self.carbonModifiers(shortcut.modifiers), id, GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                hotKeys[id.id] = (action, ref)
            } else {
                failures[action] = status == OSStatus(eventHotKeyExistsErr) ? .unavailable : .other(status)
            }
        }
        return failures
    }

    func unregisterAll() {
        hotKeys.values.forEach { UnregisterEventHotKey($0.ref) }
        hotKeys = [:]
    }

    func stop() {
        unregisterAll()
        if let handlerRef { RemoveEventHandler(handlerRef) }
        handlerRef = nil
    }

    fileprivate func handle(hotKeyID: UInt32) {
        guard let action = hotKeys[hotKeyID]?.action else { return }
        onAction?(action)
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr else { return status }
            let center = Unmanaged<GlobalShortcutCenter>.fromOpaque(userData).takeUnretainedValue()
            // Hot key events are delivered on the main thread's event loop.
            MainActor.assumeIsolated { center.handle(hotKeyID: id.id) }
            return noErr
        }
        InstallEventHandler(
            GetApplicationEventTarget(), callback, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    private static func carbonModifiers(_ modifiers: ShortcutModifiers) -> UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }
}
