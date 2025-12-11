import Foundation
import os.log
import os.signpost

/// Lightweight logger for Widget Extension
/// Writes to shared App Group file so main app can read widget logs
/// Includes performance tracking capabilities for latency investigation
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

    // Performance tracking
    private var activeOperations: [String: Date] = [:]
    private let osLog = Logger(subsystem: "com.alexis.farenheit", category: "Performance")
    private let signpostLog = OSLog(subsystem: "com.alexis.farenheit", category: "Performance")

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

    func warning(_ message: String) {
        log(message, category: "Warning", level: "⚠️ WARN")
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

    // MARK: - Performance Tracking

    /// Start tracking an operation for performance monitoring
    /// - Parameters:
    ///   - operation: Name of the operation (e.g., "WidgetTimeline", "WeatherFetch")
    ///   - category: Category for grouping (e.g., "Widget", "Network")
    ///   - metadata: Optional metadata to include in logs
    func startPerformanceOperation(_ operation: String, category: String, metadata: [String: String]? = nil) {
        let key = "\(category).\(operation)"
        let startTime = Date()
        activeOperations[key] = startTime

        // Log start with NSLog for console
        NSLog("⏱️ [PERF] START: \(category)/\(operation)")

        // OSLog for Instruments
        osLog.debug("⏱️ START: \(category)/\(operation)")

        // Signpost for Instruments timeline
        let signpostID = OSSignpostID(log: signpostLog)
        os_signpost(.begin, log: signpostLog, name: "Operation", signpostID: signpostID, "%{public}s.%{public}s", category, operation)
    }

    /// End tracking an operation and log performance metrics
    /// - Parameters:
    ///   - operation: Name of the operation (must match startPerformanceOperation)
    ///   - category: Category (must match startPerformanceOperation)
    ///   - metadata: Optional metadata to include
    ///   - forceLog: Force logging even if duration is very short
    func endPerformanceOperation(_ operation: String, category: String, metadata: [String: String]? = nil, forceLog: Bool = false) {
        let key = "\(category).\(operation)"

        guard let startTime = activeOperations[key] else {
            NSLog("⚠️ [PERF] END without START: \(category)/\(operation)")
            osLog.warning("END without START: \(category)/\(operation)")
            return
        }

        let duration = Date().timeIntervalSince(startTime)
        activeOperations.removeValue(forKey: key)

        // Format duration
        let formattedDuration: String
        if duration < 0.001 {
            formattedDuration = String(format: "%.3fms", duration * 1000)
        } else if duration < 1.0 {
            formattedDuration = String(format: "%.1fms", duration * 1000)
        } else {
            formattedDuration = String(format: "%.2fs", duration)
        }

        // Log performance metric
        let metadataStr = metadata.map { " | \($0.map { "\($0.key):\($0.value)" }.joined(separator: ", "))" } ?? ""
        NSLog("⏱️ [PERF] END: \(category)/\(operation) | Duration: \(formattedDuration)\(metadataStr)")

        // OSLog for Instruments
        osLog.info("⏱️ \(category)/\(operation): \(formattedDuration)")

        // Log to file with WidgetLogger
        let message = "\(operation): \(formattedDuration)\(metadataStr)"
        self.log(message, category: "Performance.\(category)")

        // Log warning if operation is slow (>1 second)
        if duration > 1.0 {
            self.log("Slow operation: \(operation) took \(formattedDuration)", category: "Performance.\(category)", level: "⚠️ WARN")
        }

        // Signpost end
        let signpostID = OSSignpostID(log: signpostLog)
        os_signpost(.end, log: signpostLog, name: "Operation", signpostID: signpostID, "%{public}s.%{public}s", category, operation)
    }

    // MARK: - Helpers

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        return df
    }()
}

