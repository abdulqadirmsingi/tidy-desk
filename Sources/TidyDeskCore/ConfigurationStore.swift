import Foundation

public enum ConfigurationError: Error, Equatable, LocalizedError {
    /// The file was written by a newer TidyDesk; it is left untouched.
    case newerSchema(found: Int, supported: Int)
    case corrupt

    public var errorDescription: String? {
        switch self {
        case let .newerSchema(found, supported):
            "Settings were saved by a newer version of the app (format \(found), this version supports \(supported)). They were left untouched and defaults are in use."
        case .corrupt:
            "The settings file could not be read. A backup was kept and defaults are in use."
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
            throw ConfigurationError.corrupt
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
            throw ConfigurationError.corrupt
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
        guard let data = try? Data(contentsOf: fileURL) else {
            return LoadResult(configuration: Configuration(), problem: nil)
        }
        do {
            return LoadResult(configuration: try ConfigurationMigration.decode(data), problem: nil)
        } catch let error as ConfigurationError {
            if error == .corrupt { backUpCorruptFile() }
            return LoadResult(configuration: Configuration(), problem: error)
        } catch {
            return LoadResult(configuration: Configuration(), problem: .corrupt)
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

    private func backUpCorruptFile() {
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = fileURL.appendingPathExtension("corrupt-\(stamp)")
        try? FileManager.default.moveItem(at: fileURL, to: backup)
    }
}
