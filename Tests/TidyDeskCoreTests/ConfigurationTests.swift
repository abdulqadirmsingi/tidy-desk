import Foundation
import Testing

@testable import TidyDeskCore

private func makeStore() -> (ConfigurationStore, URL) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("TidyDeskTests-\(UUID().uuidString)")
    return (ConfigurationStore(fileURL: dir.appendingPathComponent("config.json")), dir)
}

@Suite("Configuration persistence")
struct ConfigurationTests {
    @Test func roundTripPreservesEverything() throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        var config = Configuration()
        config.isTilingEnabled = false
        config.hasCompletedOnboarding = true
        config.excludedBundleIDs = ["com.example.app"]
        config.learnedMinimums["com.example.app"] = LearnedMinimum(width: 640, height: 480)
        config.updateSettings(for: DisplayID(rawValue: "X")) { $0.layout = .columns; $0.maxWindows = 2 }
        config.shortcutOverrides[ShortcutAction.arrangeNow.rawValue] = Shortcut(keyCode: 9, modifiers: [.command])
        config.appearance.glow = true
        try store.save(config)
        let loaded = store.load()
        #expect(loaded.problem == nil)
        #expect(loaded.configuration == config)
    }

    @Test func missingFileYieldsDefaults() {
        let (store, _) = makeStore()
        let result = store.load()
        #expect(result.configuration == Configuration())
        #expect(result.problem == nil)
    }

    @Test func olderFilesMissingNewFieldsStillLoad() throws {
        let json = #"{"schemaVersion":1,"isTilingEnabled":false}"#
        let config = try ConfigurationMigration.decode(Data(json.utf8))
        #expect(!config.isTilingEnabled)
        #expect(config.defaultDisplay == DisplaySettings())
        #expect(config.appearance == AppearanceSettings())
    }

    @Test func filesWithoutVersionAreTreatedAsVersionOne() throws {
        let config = try ConfigurationMigration.decode(Data(#"{"hasCompletedOnboarding":true}"#.utf8))
        #expect(config.hasCompletedOnboarding)
        #expect(config.schemaVersion == Configuration.currentSchemaVersion)
    }

    @Test func newerSchemaIsRejectedAndNotOverwritten() throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let future = Data(#"{"schemaVersion":99}"#.utf8)
        try future.write(to: store.fileURL)
        let result = store.load()
        #expect(result.problem == .newerSchema(found: 99, supported: Configuration.currentSchemaVersion))
        #expect(try Data(contentsOf: store.fileURL) == future)
    }

    @Test func corruptFileIsBackedUpAndDefaultsUsed() throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.fileURL)
        let result = store.load()
        #expect(result.problem == .corrupt)
        #expect(result.configuration == Configuration())
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(files.contains { $0.contains("corrupt") })
    }

    @Test func displayOverridesAreIndependentAndRestorable() {
        var config = Configuration()
        let x = DisplayID(rawValue: "X"), y = DisplayID(rawValue: "Y")
        config.updateSettings(for: x) { $0.layout = .columns }
        #expect(config.settings(for: x).layout == .columns)
        #expect(config.settings(for: y).layout == .grid)
        config.displays[x.rawValue] = nil
        #expect(config.settings(for: x).layout == .grid)
    }

    @Test func decodedSettingsAreClamped() throws {
        let json = #"{"defaultDisplay":{"maxWindows":12,"spacing":900,"weights":{"primary":50}}}"#
        let config = try ConfigurationMigration.decode(Data(json.utf8))
        #expect(config.defaultDisplay.maxWindows == 4)
        #expect(config.defaultDisplay.spacing == LayoutDefaults.spacingRange.upperBound)
        #expect(config.defaultDisplay.weights.primary == LayoutDefaults.weightRange.upperBound)
    }

    @Test func deleteRemovesFile() throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try store.save(Configuration())
        try store.delete()
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
        try store.delete()
    }
}

@Suite("Shortcuts")
struct ShortcutTests {
    @Test func defaultsHaveNoConflicts() {
        #expect(ShortcutMap().conflicts.isEmpty)
    }

    @Test func detectsDuplicateBindings() {
        let map = ShortcutMap(overrides: [
            ShortcutAction.focusMode.rawValue: ShortcutAction.noPeek.defaultShortcut
        ])
        #expect(map.conflicts[ShortcutAction.noPeek.defaultShortcut]?.count == 2)
        #expect(map.conflictingActions(for: .focusMode) == [.noPeek])
    }

    @Test func displayStringUsesSymbols() {
        #expect(ShortcutAction.swapPrevious.defaultShortcut.display == "⌃⌥←")
        #expect(ShortcutAction.moveToPreviousDisplay.defaultShortcut.display == "⌃⌥⇧D")
    }

    @Test func everyActionHasADistinctDefault() {
        let defaults = ShortcutAction.allCases.map(\.defaultShortcut)
        #expect(Set(defaults).count == defaults.count)
    }
}
