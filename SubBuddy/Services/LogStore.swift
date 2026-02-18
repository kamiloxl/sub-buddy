import Foundation
import os.log

// MARK: - Log Entry

struct LogEntry: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let level: Level
    let category: String
    let message: String

    enum Level: String, CaseIterable, Sendable {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"

        var emoji: String {
            switch self {
            case .debug: return "◦"
            case .info: return "●"
            case .warning: return "▲"
            case .error: return "✕"
            }
        }
    }
}

// MARK: - Log Store

@MainActor
final class LogStore: ObservableObject {
    static let shared = LogStore()

    @Published private(set) var entries: [LogEntry] = []

    private let maxEntries = 1000

    private init() {}

    func add(_ entry: LogEntry) {
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    func clear() {
        entries.removeAll()
    }
}

// MARK: - Global Logging Function

/// Logs to both os.log and the in-app LogStore console.
nonisolated func appLog(
    _ message: String,
    level: LogEntry.Level = .info,
    category: String = "App"
) {
    let osLogger = Logger(subsystem: "com.subbuddy.app", category: category)
    switch level {
    case .debug: osLogger.debug("\(message)")
    case .info: osLogger.info("\(message)")
    case .warning: osLogger.warning("\(message)")
    case .error: osLogger.error("\(message)")
    }

    let entry = LogEntry(timestamp: Date(), level: level, category: category, message: message)
    Task { @MainActor in
        LogStore.shared.add(entry)
    }
}
