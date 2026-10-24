import Foundation
import Observation
import SwiftUI
import TidyDeskCore

/// Owns the persisted `Configuration`: validates, saves (debounced, atomic) and notifies.
@MainActor
@Observable
final class SettingsStore {
    private(set) var configuration: Configuration
    /// Set when the stored file could not be used and defaults were loaded instead.
    private(set) var loadProblem: ConfigurationError?
    private(set) var saveProblem: String?

    @ObservationIgnored var onChange: ((_ old: Configuration, _ new: Configuration) -> Void)?
    @ObservationIgnored private let store: ConfigurationStore
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    private static let saveDelay: Duration = .milliseconds(400)

    init(store: ConfigurationStore) {
        self.store = store
        let result = store.load()
        configuration = result.configuration
        loadProblem = result.problem
    }

    /// Applies a change, persists it, and notifies listeners unless `silent`.
    /// `silent` is for bookkeeping the engine itself writes (learned minimum sizes).
    func update(silent: Bool = false, _ change: (inout Configuration) -> Void) {
        let old = configuration
        var new = old
        change(&new)
        guard new != old else { return }
        configuration = new
        scheduleSave()
        if !silent { onChange?(old, new) }
    }

    func binding<Value>(_ keyPath: WritableKeyPath<Configuration, Value>) -> Binding<Value> {
        Binding(
            get: { self.configuration[keyPath: keyPath] },
            set: { value in self.update { $0[keyPath: keyPath] = value } })
    }

    func binding<Value>(for display: DisplayID?, _ keyPath: WritableKeyPath<DisplaySettings, Value>) -> Binding<Value> {
        Binding(
            get: {
                guard let display else { return self.configuration.defaultDisplay[keyPath: keyPath] }
                return self.configuration.settings(for: display)[keyPath: keyPath]
            },
            set: { value in
                self.update { config in
                    if let display {
                        config.updateSettings(for: display) { $0[keyPath: keyPath] = value }
                    } else {
                        config.defaultDisplay[keyPath: keyPath] = value
                    }
                }
            })
    }

    func resetToDefaults() {
        saveTask?.cancel()
        let old = configuration
        var fresh = Configuration()
        fresh.hasCompletedOnboarding = old.hasCompletedOnboarding
        configuration = fresh
        loadProblem = nil
        flush()
        onChange?(old, fresh)
    }

    /// Writes immediately; used on quit and after resets.
    func flush() {
        saveTask?.cancel()
        do {
            try store.save(configuration)
            saveProblem = nil
        } catch {
            saveProblem = "Settings could not be saved: \(error.localizedDescription)"
        }
    }

    func deleteStoredFile() {
        saveTask?.cancel()
        try? store.delete()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }
}
