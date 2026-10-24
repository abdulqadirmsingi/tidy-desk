import ServiceManagement

/// Start-at-login through `SMAppService`, the supported mechanism for the main app.
@MainActor
struct LoginItemService {
    enum State: Equatable {
        case enabled
        case disabled
        /// The user turned the item off (or it needs approval) in System Settings → Login Items.
        case requiresApproval
        case unavailable

        var isOn: Bool { self == .enabled || self == .requiresApproval }
    }

    var state: State {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .notRegistered: .disabled
        case .requiresApproval: .requiresApproval
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            guard service.status != .enabled else { return }
            try service.register()
        } else {
            guard service.status != .notRegistered else { return }
            try service.unregister()
        }
    }

    func openLoginItemsSettings() { SMAppService.openSystemSettingsLoginItems() }
}
