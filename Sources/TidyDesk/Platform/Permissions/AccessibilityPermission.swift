import AppKit
import ApplicationServices
import Observation

/// Tracks the Accessibility permission without ever bypassing macOS controls.
@MainActor
@Observable
final class AccessibilityPermission {
    private(set) var isGranted: Bool
    @ObservationIgnored var onChange: ((Bool) -> Void)?
    @ObservationIgnored private var tokens: [NSObjectProtocol] = []

    /// Grants and revocations are posted system-wide; the value updates a moment later.
    private static let settleDelay: Duration = .milliseconds(400)

    init() {
        isGranted = AXIsProcessTrusted()
    }

    func startObserving() {
        guard tokens.isEmpty else { return }
        let distributed = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                try? await Task.sleep(for: Self.settleDelay)
                self.refresh()
            }
        }
        let activation = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        tokens = [distributed, activation]
    }

    func stopObserving() {
        tokens.forEach {
            DistributedNotificationCenter.default().removeObserver($0)
            NotificationCenter.default.removeObserver($0)
        }
        tokens = []
    }

    func refresh() {
        let trusted = AXIsProcessTrusted()
        guard trusted != isGranted else { return }
        isGranted = trusted
        onChange?(trusted)
    }

    /// Shows the system prompt once. Subsequent calls should use `openSystemSettings()`.
    func requestPrompt() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }
}
