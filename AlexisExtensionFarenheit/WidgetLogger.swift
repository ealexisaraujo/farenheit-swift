import Foundation

/// Lightweight logger for Widget Extension
/// Writes to shared App Group file so main app can read widget logs
final class WidgetLogger {

    // MARK: - Log Entry (must match SharedLogger.LogEntry)

    struct LogEntry: Codable {
        let id: UUID
        let timestamp: Date
        let level: String
        let source: String
        let category: String
        let message: String
    }

    // MARK: - Singleton

    static let shared = WidgetLogger()

    // MARK: - Properties

    private let appGroupID = "group.alexisaraujo.alexisfarenheit"
    private let logFileName = "app_logs.json"
    private let maxLogEntries = 500
    private let source = "Widget"

    // MARK: - File Path

    private var logFileURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        )?.appendingPathComponent(logFileName)
    }

    // MARK: - Logging Methods

    func log(_ message: String, category: String = "Timeline", level: String = "📱 WIDGET") {
        // Print to console (visible in Xcode when debugging widget)
        let timestamp = Self.dateFormatter.string(from: Date())
        print("[\(timestamp)] \(level) [Widget/\(category)] \(message)")

        // Write to shared file
        appendToFile(message: message, category: category, level: level)
    }

    func timeline(_ message: String) {
        log(message, category: "Timeline")
    }

    func data(_ message: String) {
        log(message, category: "Data")
    }

    func error(_ message: String) {
        log(message, category: "Error", level: "❌ ERROR")
    }

    // MARK: - File Operations

    private func appendToFile(message: String, category: String, level: String) {
        guard logFileURL != nil else {
            print("[WidgetLogger] Cannot access App Group")
            return
        }

        let entry = LogEntry(
            id: UUID(),
            timestamp: Date(),
            level: level,
            source: source,
            category: category,
            message: message
        )

        var entries = loadEntries() ?? []
        entries.append(entry)

        // Trim to max
        if entries.count > maxLogEntries {
            entries = Array(entries.suffix(maxLogEntries))
        }

        saveEntries(entries)
    }

    private func loadEntries() -> [LogEntry]? {
        guard let fileURL = logFileURL else { return nil }

        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([LogEntry].self, from: data)
        } catch {
            return []
        }
    }

    private func saveEntries(_ entries: [LogEntry]) {
        guard let fileURL = logFileURL else { return }

        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[WidgetLogger] Save failed: \(error)")
        }
    }

    // MARK: - Helpers

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        return df
    }()
}

