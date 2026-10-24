import Foundation

public enum ConfigurationError: Error, Equatable, LocalizedError {
    /// The file was written by a newer TidyDesk; it is left untouched.
    case newerSchema(found: Int, supported: Int)
    /// `backedUp` says whether the unusable file was set aside intact (true) or left in place (false).
    case corrupt(backedUp: Bool)

    public var errorDescription: String? {
        switch self {
        case let .newerSchema(found, supported):
            "Settings were saved by a newer version of the app (format \(found), this version supports \(supported)). They were left untouched and defaults are in use."
        case .corrupt(backedUp: true):
            "The settings file could not be read. It was set aside as a backup and defaults are in use."
        case .corrupt(backedUp: false):
            "The settings file could not be read and could not be backed up. Defaults are in use."
        }
    }
}

/// Upgrades stored JSON to `Configuration.currentSchemaVersion`.
/// Add one step per schema bump; each step transforms the raw JSON object.
public enum ConfigurationMigration {
    typealias Step = @Sendable (inout [String: Any]) -> Void

    /// `steps[n]` upgrades version `n + 1` to `n + 2`. Empty until schema 2 exists.
    static let steps: [Step] = []

    public static func decode(_ data: Data) throws -> Configuration {
        guard var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConfigurationError.corrupt(backedUp: false)
        }
        let version = object["schemaVersion"] as? Int ?? 1
        guard version <= Configuration.currentSchemaVersion else {
            throw ConfigurationError.newerSchema(found: version, supported: Configuration.currentSchemaVersion)
        }
        for index in max(version - 1, 0)..<steps.count { steps[index](&object) }
        object["schemaVersion"] = Configuration.currentSchemaVersion
        do {
            let upgraded = try JSONSerialization.data(withJSONObject: object)
            return try JSONDecoder().decode(Configuration.self, from: upgraded)
        } catch {
            throw ConfigurationError.corrupt(backedUp: false)
        }
    }
}

/// Atomic JSON persistence for `Configuration`.
public struct ConfigurationStore: Sendable {
    public struct LoadResult: Sendable {
        public let configuration: Configuration
        /// Set when defaults were used because the stored file was unusable.
        public let problem: ConfigurationError?
    }

    public let fileURL: URL

    public init(fileURL: URL) { self.fileURL = fileURL }

    public static func defaultFileURL(appFolderName: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(appFolderName, isDirectory: true).appendingPathComponent("config.json")
    }

    public func load() -> LoadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return LoadResult(configuration: Configuration(), problem: nil)
        }
        do {
            let data = try Data(contentsOf: fileURL)
            return LoadResult(configuration: try ConfigurationMigration.decode(data), problem: nil)
        } catch let error as ConfigurationError {
            if case .corrupt = error { return unusable() }
            return LoadResult(configuration: Configuration(), problem: error)
        } catch {
            // The file exists but could not be read (permissions, I/O): never treat it as absent.
            return unusable()
        }
    }

    public func save(_ configuration: Configuration) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(configuration).write(to: fileURL, options: .atomic)
    }

    public func delete() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    private func unusable() -> LoadResult {
        let backedUp = backUpCorruptFile()
        return LoadResult(configuration: Configuration(), problem: .corrupt(backedUp: backedUp))
    }

    /// Moves the unusable file aside under a unique name so it is never overwritten by a later save.
    private func backUpCorruptFile() -> Bool {
        let fileManager = FileManager.default
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        var backup = fileURL.appendingPathExtension("\(Self.backupMarker)\(stamp)")
        var suffix = 1
        while fileManager.fileExists(atPath: backup.path) {
            backup = fileURL.appendingPathExtension("\(Self.backupMarker)\(stamp)-\(suffix)")
            suffix += 1
        }
        do {
            try fileManager.moveItem(at: fileURL, to: backup)
        } catch {
            return false
        }
        pruneBackups()
        return true
    }

    /// Keeps the newest few backups so repeated corruption cannot fill the disk.
    private func pruneBackups() {
        let directory = fileURL.deletingLastPathComponent()
        let prefix = fileURL.lastPathComponent + "." + Self.backupMarker
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        let backups = names.filter { $0.hasPrefix(prefix) }.sorted { lhs, rhs in
            (Self.backupStamp(lhs, prefix), lhs) < (Self.backupStamp(rhs, prefix), rhs)
        }
        for name in backups.dropLast(Self.maxBackups) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    private static func backupStamp(_ name: String, _ prefix: String) -> Int {
        Int(name.dropFirst(prefix.count).prefix { $0.isNumber }) ?? 0
    }

    static let backupMarker = "corrupt-"
    static let maxBackups = 5
}
