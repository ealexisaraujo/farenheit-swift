import Foundation
import os.log

/// Shared file-based logger for both main app and widget extension.
/// Writes logs to App Group container so both processes can access them.
/// Inspired by CocoaLumberjack but lightweight and native.
final class SharedLogger {

    // MARK: - Log Level

    enum Level: String, CaseIterable, Codable {
        case debug = "🔍 DEBUG"
        case info = "ℹ️ INFO"
        case warning = "⚠️ WARN"
        case error = "❌ ERROR"
        case widget = "📱 WIDGET"

        var priority: Int {
            switch self {
            case .debug: return 0
            case .info: return 1
            case .warning: return 2
            case .error: return 3
            case .widget: return 1
            }
        }
    }

    // MARK: - Log Entry

    struct LogEntry: Identifiable, Codable {
        let id: UUID
        let timestamp: Date
        let level: Level
        let source: String  // "App" or "Widget"
        let category: String
        let message: String

        var formattedTimestamp: String {
            Self.dateFormatter.string(from: timestamp)
        }

        var fullDescription: String {
            "[\(formattedTimestamp)] \(level.rawValue) [\(source)/\(category)] \(message)"
        }

        private static let dateFormatter: DateFormatter = {
            let df = DateFormatter()
            df.dateFormat = "HH:mm:ss.SSS"
            return df
        }()
    }

    // MARK: - Singleton

    static let shared = SharedLogger()

    // MARK: - Properties

    private let appGroupID = "group.alexisaraujo.alexisfarenheit"
    private let logFileName = "app_logs.json"
    private let maxLogEntries = 500  // Keep last 500 entries

    private let osLog = Logger(subsystem: "com.alexis.farenheit", category: "SharedLogger")
    private let queue = DispatchQueue(label: "com.alexis.farenheit.logger", qos: .utility)

    /// Current source identifier
    var source: String = "App"

    /// Minimum log level to record (default: debug = all logs)
    var minimumLevel: Level = .debug

    // MARK: - File Path

    private var logFileURL: URL? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else {
            osLog.error("SharedLogger: Cannot access App Group container")
            return nil
        }
        return containerURL.appendingPathComponent(logFileName)
    }

    // MARK: - Init

    private init() {
        osLog.debug("SharedLogger initialized for source: \(self.source)")
    }

    // MARK: - Public Logging Methods

    func debug(_ message: String, category: String = "General") {
        log(level: .debug, category: category, message: message)
    }

    func info(_ message: String, category: String = "General") {
        log(level: .info, category: category, message: message)
    }

    func warning(_ message: String, category: String = "General") {
        log(level: .warning, category: category, message: message)
    }

    func error(_ message: String, category: String = "General") {
        log(level: .error, category: category, message: message)
    }

    func widget(_ message: String, category: String = "Timeline") {
        log(level: .widget, category: category, message: message)
    }

    // MARK: - Core Logging

    private func log(level: Level, category: String, message: String) {
        // Check minimum level
        guard level.priority >= minimumLevel.priority else { return }

        let entry = LogEntry(
            id: UUID(),
            timestamp: Date(),
            level: level,
            source: source,
            category: category,
            message: message
        )

        // Also log to OSLog for Xcode console
        osLog.log(level: osLogType(for: level), "\(entry.fullDescription)")

        // Write to shared file asynchronously
        queue.async { [weak self] in
            self?.appendToFile(entry)
        }
    }

    private func osLogType(for level: Level) -> OSLogType {
        switch level {
        case .debug: return .debug
        case .info, .widget: return .info
        case .warning: return .default
        case .error: return .error
        }
    }

    // MARK: - File Operations

    private func appendToFile(_ entry: LogEntry) {
        guard logFileURL != nil else { return }

        var entries = loadEntriesFromFile() ?? []
        entries.append(entry)

        // Trim to max entries
        if entries.count > maxLogEntries {
            entries = Array(entries.suffix(maxLogEntries))
        }

        saveEntriesToFile(entries)
    }

    private func loadEntriesFromFile() -> [LogEntry]? {
        guard let fileURL = logFileURL else { return nil }

        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([LogEntry].self, from: data)
        } catch {
            // File doesn't exist or is corrupted - return empty
            return []
        }
    }

    private func saveEntriesToFile(_ entries: [LogEntry]) {
        guard let fileURL = logFileURL else { return }

        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            osLog.error("Failed to save logs: \(error.localizedDescription)")
        }
    }

    // MARK: - Public Read Methods

    /// Load all log entries from shared file
    func loadLogs() -> [LogEntry] {
        var result: [LogEntry] = []
        queue.sync {
            result = loadEntriesFromFile() ?? []
        }
        return result.sorted { $0.timestamp > $1.timestamp }  // Newest first
    }

    /// Load logs filtered by level
    func loadLogs(minimumLevel: Level) -> [LogEntry] {
        loadLogs().filter { $0.level.priority >= minimumLevel.priority }
    }

    /// Load logs filtered by source
    func loadLogs(source: String) -> [LogEntry] {
        loadLogs().filter { $0.source == source }
    }

    /// Clear all logs
    func clearLogs() {
        queue.async { [weak self] in
            self?.saveEntriesToFile([])
        }
        osLog.info("Logs cleared")
    }

    // MARK: - Export

    /// Export logs as formatted text for sharing
    func exportAsText() -> String {
        let logs = loadLogs().reversed()  // Oldest first for export
        var output = """
        ═══════════════════════════════════════════════════════
        📋 ALEXIS FARENHEIT - LOG EXPORT
        📅 Exported: \(Date())
        📊 Total entries: \(logs.count)
        ═══════════════════════════════════════════════════════

        """

        for entry in logs {
            output += entry.fullDescription + "\n"
        }

        output += "\n═══════════════════════════════════════════════════════\n"
        output += "END OF LOG\n"

        return output
    }

    /// Export logs as JSON for programmatic analysis
    func exportAsJSON() -> Data? {
        let logs = loadLogs().reversed()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(Array(logs))
    }

    /// Get temporary file URL for sharing
    func createExportFile(format: ExportFormat) -> URL? {
        let fileName: String
        let data: Data?

        switch format {
        case .text:
            fileName = "alexis_farenheit_logs_\(exportTimestamp()).txt"
            data = exportAsText().data(using: .utf8)
        case .json:
            fileName = "alexis_farenheit_logs_\(exportTimestamp()).json"
            data = exportAsJSON()
        }

        guard let exportData = data else { return nil }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try exportData.write(to: tempURL)
            return tempURL
        } catch {
            osLog.error("Failed to create export file: \(error.localizedDescription)")
            return nil
        }
    }

    enum ExportFormat {
        case text
        case json
    }

    private func exportTimestamp() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd_HHmmss"
        return df.string(from: Date())
    }
}

// MARK: - Convenience Global Functions

/// Quick logging functions for easy use throughout the app
func logDebug(_ message: String, category: String = "General") {
    SharedLogger.shared.debug(message, category: category)
}

func logInfo(_ message: String, category: String = "General") {
    SharedLogger.shared.info(message, category: category)
}

func logWarning(_ message: String, category: String = "General") {
    SharedLogger.shared.warning(message, category: category)
}

func logError(_ message: String, category: String = "General") {
    SharedLogger.shared.error(message, category: category)
}

func logWidget(_ message: String, category: String = "Timeline") {
    SharedLogger.shared.widget(message, category: category)
}

