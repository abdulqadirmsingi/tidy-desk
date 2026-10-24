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

    /// Arguments for `tccutil`, which removes this app's Accessibility entry so macOS asks again.
    /// Needed when System Settings shows the app switched on but the grant belongs to an older build:
    /// macOS ties the permission to the code signature, which changes with every ad-hoc rebuild.
    nonisolated static func resetArguments(bundleID: String) -> [String] { ["reset", "Accessibility", bundleID] }

    /// Clears a stale grant for this app only, then asks again. Returns false if it could not be cleared.
    func resetStaleGrant() async -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let succeeded = await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = Self.resetArguments(bundleID: bundleID)
            process.standardOutput = nil
            process.standardError = nil
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus == 0) }
            do { try process.run() } catch { continuation.resume(returning: false) }
        }
        if succeeded {
            requestPrompt()
            openSystemSettings()
        }
        return succeeded
    }

    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }
}
