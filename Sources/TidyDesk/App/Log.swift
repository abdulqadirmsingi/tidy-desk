import Foundation
import os

/// Loggers never receive window titles or document names; keep messages to events and counts.
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "TidyDesk"
    static let placement = Logger(subsystem: subsystem, category: "placement")
    static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
    static let shortcuts = Logger(subsystem: subsystem, category: "shortcuts")
}
