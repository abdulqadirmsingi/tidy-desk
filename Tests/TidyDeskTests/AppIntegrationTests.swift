import AppKit
import ApplicationServices
import Foundation
import Testing
import TidyDeskCore

@testable import TidyDesk

/// Tests that run without Accessibility permission and without touching other apps' windows.
@Suite("App integration", .serialized)
@MainActor
struct AppIntegrationTests {
    @Test func permissionServiceMatchesSystemState() {
        #expect(AccessibilityPermission().isGranted == AXIsProcessTrusted())
    }

    @Test func displayServiceReportsConsistentGeometry() throws {
        let displays = DisplayService().current()
        try #require(!displays.isEmpty, "No display attached (headless environment)")
        for display in displays {
            #expect(display.frame.isUsable)
            #expect(display.frame.insetBy(dx: -1, dy: -1).contains(display.usableFrame))
        }
        #expect(Set(displays.map(\.id)).count == displays.count)
    }

    @Test func settingsStorePersistsAndNotifiesOnlyForUserChanges() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("TidyDeskIT-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.json")
        let store = SettingsStore(store: ConfigurationStore(fileURL: url))
        var notifications = 0
        store.onChange = { _, _ in notifications += 1 }

        store.update { $0.defaultDisplay.layout = .columns }
        store.update(silent: true) { $0.learnedMinimums["x"] = LearnedMinimum(width: 1, height: 1) }
        store.update { $0.defaultDisplay.layout = .columns }  // no-op
        #expect(notifications == 1)

        store.flush()
        let reloaded = SettingsStore(store: ConfigurationStore(fileURL: url))
        #expect(reloaded.configuration.defaultDisplay.layout == .columns)
        #expect(reloaded.configuration.learnedMinimums["x"] != nil)
    }

    @Test func resetKeepsOnboardingFlagAndClearsRest() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("TidyDeskIT-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SettingsStore(store: ConfigurationStore(fileURL: dir.appendingPathComponent("config.json")))
        store.update { $0.hasCompletedOnboarding = true; $0.excludedBundleIDs = ["a"] }
        store.resetToDefaults()
        #expect(store.configuration.hasCompletedOnboarding)
        #expect(store.configuration.excludedBundleIDs.isEmpty)
    }

    @Test func shortcutCenterRegistersDefaultsWithoutConflicts() {
        let center = GlobalShortcutCenter()
        defer { center.stop() }
        let failures = center.register(ShortcutMap())
        // Another app may legitimately own a combination; conflicts inside our own map must not occur.
        #expect(failures.values.allSatisfy { $0 != .other(-1) })
        #expect(ShortcutMap().conflicts.isEmpty)
    }

    @Test func discoveryReturnsPromptlyAndSafelyWithoutPermission() throws {
        try #require(!AXIsProcessTrusted(), "Only meaningful when Accessibility is not granted")
        let started = Date()
        let result = WindowDiscoveryService().discover(excludedBundleIDs: [])
        #expect(result.eligible.isEmpty)
        #expect(Date().timeIntervalSince(started) < 5)
    }

    @Test func wrappedElementsAreMessagingTimeoutBounded() {
        // The timeout has no public getter, so this guards the constant that every wrapper applies.
        #expect(AXElement.messagingTimeout > 0 && AXElement.messagingTimeout <= 1)
    }

    @Test func loginItemServiceReportsAState() {
        _ = LoginItemService().state
    }
}

/// Requires Accessibility permission for the test host. Run with `TIDYDESK_AX_TESTS=1 swift test`.
/// Uses a window created by the test itself; never touches other applications.
@Suite("Accessibility integration (opt-in)", .serialized)
@MainActor
struct AccessibilityIntegrationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TIDYDESK_AX_TESTS"] == "1" && AXIsProcessTrusted()))
    func movesAndResizesOwnWindow() throws {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 600, height: 400),
            styleMask: [.titled, .resizable, .closable], backing: .buffered, defer: false)
        window.title = "TidyDesk AX Test"
        window.makeKeyAndOrderFront(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        defer { window.close() }

        let app = AXElement.application(pid: ProcessInfo.processInfo.processIdentifier)
        let element = try #require(app.elements(kAXWindowsAttribute).first)
        let target = CGRect(x: 120, y: 160, width: 700, height: 450)
        let actual = try #require(try? WindowPlacementService().place(element, to: target).get())
        #expect(actual.isApproximatelyEqual(to: target, tolerance: 4))
    }
}

/// Exercises coordinator state without Accessibility by injecting a tracked window.
@Suite("Float toggle", .serialized)
@MainActor
struct FloatToggleTests {
    private func makeCoordinator() -> TilingCoordinator {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TidyDeskFloat-\(UUID().uuidString)/config.json")
        let settings = SettingsStore(store: ConfigurationStore(fileURL: url))
        return TilingCoordinator(settings: settings, permission: AccessibilityPermission())
    }

    private func inject(_ coordinator: TilingCoordinator) -> WindowID {
        let id = WindowID()
        coordinator.tracked[id] = TrackedWindow(
            id: id, element: AXElement(raw: AXUIElementCreateSystemWide()), pid: 1, bundleID: nil,
            appName: "Test", frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        coordinator.lastActiveWindow = id
        return id
    }

    @Test func togglingFloatsAndTilesTheWindowAndUpdatesUIState() {
        let coordinator = makeCoordinator()
        let id = inject(coordinator)
        coordinator.syncUI()
        #expect(coordinator.ui.activeWindowFloating == false)

        coordinator.toggleFloat(id)
        #expect(coordinator.userFloating.contains(id))
        #expect(coordinator.ui.activeWindowFloating == true)
        #expect(coordinator.ui.floatingCount == 1)

        coordinator.toggleFloat(id)
        #expect(!coordinator.userFloating.contains(id))
        #expect(coordinator.ui.activeWindowFloating == false)
    }

    @Test func noActiveWindowDisablesTheToggle() {
        let coordinator = makeCoordinator()
        coordinator.syncUI()
        #expect(coordinator.ui.activeWindowFloating == nil)
    }
}

@Suite("Newer config protection (app)", .serialized)
@MainActor
struct NewerConfigAppTests {
    @Test func settingsChangesDoNotClobberANewerFileAndResetBacksItUp() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("TidyDeskNewer-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("config.json")
        let future = Data(#"{"schemaVersion":99}"#.utf8)
        try future.write(to: url)

        let store = SettingsStore(store: ConfigurationStore(fileURL: url))
        #expect(store.loadProblem != nil)
        store.update { $0.isTilingEnabled = false }
        store.flush()
        #expect(try Data(contentsOf: url) == future)
        #expect(store.saveProblem?.contains("will not be saved") == true)

        store.resetToDefaults()
        #expect(store.saveProblem == nil)
        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.contains("newer-") }
        #expect(backups.count == 1)
    }
}

@Suite("Stale Accessibility grant")
@MainActor
struct StaleGrantTests {
    @Test func resetTargetsOnlyAccessibilityForTheGivenApp() {
        #expect(AccessibilityPermission.resetArguments(bundleID: "com.example.app") == ["reset", "Accessibility", "com.example.app"])
    }
}
