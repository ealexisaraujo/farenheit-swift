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
    private let maxLogEntries = 200  // Reduced from 500 to improve performance
    private let logTTLHours: TimeInterval = 24  // Delete logs older than 24 hours

    private let osLog = Logger(subsystem: "com.alexis.farenheit", category: "SharedLogger")
    private let queue = DispatchQueue(label: "com.alexis.farenheit.logger", qos: .utility)
    
    // Batch logging to reduce file I/O
    private var pendingEntries: [LogEntry] = []
    private var writeWorkItem: DispatchWorkItem?
    private let batchWriteDelay: TimeInterval = 0.5 // Batch writes every 500ms
    private let maxBatchSize = 10 // Flush batch after 10 entries
    
    /// Disable file logging during critical operations (e.g., search)
    var fileLoggingEnabled: Bool = true

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

        // Always log to OSLog for Xcode console (fast, non-blocking)
        osLog.log(level: osLogType(for: level), "\(entry.fullDescription)")

        // Only write to file if enabled (can be disabled during critical operations)
        guard fileLoggingEnabled else { return }
        
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

    /// Append entry to batch queue (debounced writes)
    private func appendToFile(_ entry: LogEntry) {
        guard logFileURL != nil else { return }
        
        queue.async { [weak self] in
            guard let self else { return }
            
            // Add to pending batch
            self.pendingEntries.append(entry)
            
            // Cancel previous delayed write
            self.writeWorkItem?.cancel()
            
            // If batch is full, flush immediately
            if self.pendingEntries.count >= self.maxBatchSize {
                self.flushPendingEntries()
                return
            }
            
            // Otherwise, schedule delayed write
            let workItem = DispatchWorkItem { [weak self] in
                self?.flushPendingEntries()
            }
            self.writeWorkItem = workItem
            self.queue.asyncAfter(deadline: .now() + self.batchWriteDelay, execute: workItem)
        }
    }
    
    /// Flush all pending entries to file (async, non-blocking)
    private func flushPendingEntries() {
        guard !pendingEntries.isEmpty else { return }
        
        let entriesToWrite = pendingEntries
        pendingEntries.removeAll()
        
        // Perform file I/O asynchronously to avoid blocking
        queue.async { [weak self] in
            guard let self else { return }
            
            // Load existing entries (async)
            var allEntries = self.loadEntriesFromFile() ?? []
            
            // Append new entries
            allEntries.append(contentsOf: entriesToWrite)
            
            // Apply TTL: Remove entries older than logTTLHours
            let cutoffDate = Date().addingTimeInterval(-self.logTTLHours * 3600)
            allEntries = allEntries.filter { $0.timestamp >= cutoffDate }
            
            // Trim to max entries (keep newest)
            if allEntries.count > self.maxLogEntries {
                allEntries = Array(allEntries.suffix(self.maxLogEntries))
            }
            
            // Save to file (async write)
            self.saveEntriesToFileAsync(allEntries)
        }
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

    /// Save entries to file synchronously (legacy, use saveEntriesToFileAsync)
    private func saveEntriesToFile(_ entries: [LogEntry]) {
        saveEntriesToFileAsync(entries)
    }
    
    /// Save entries to file asynchronously (non-blocking)
    /// Uses FileHandle for incremental writes to avoid blocking the thread
    private func saveEntriesToFileAsync(_ entries: [LogEntry]) {
        guard let fileURL = logFileURL else { return }

        // Perform encoding and writing on background queue
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            
            do {
                // Encode entries to JSON data
                let encoder = JSONEncoder()
                encoder.outputFormatting = [] // No pretty printing for performance
                let data = try encoder.encode(entries)
                
                // Use atomic write via temporary file to prevent corruption
                // Write to temp file first, then atomically replace the original
                let tempURL = fileURL.appendingPathExtension("tmp")
                
                // Write to temporary file (non-blocking, incremental if possible)
                // For large files, use FileHandle for incremental writes
                if data.count > 100_000 { // >100KB: use FileHandle for incremental write
                    try self.writeLargeFileIncrementally(data: data, to: tempURL)
                } else {
                    // Small files: direct write is fast enough
                    try data.write(to: tempURL, options: [.completeFileProtectionNone])
                }
                
                // Atomically replace the original file with the temp file
                // This is a fast operation (just a file system move)
                let fileManager = FileManager.default
                if fileManager.fileExists(atPath: fileURL.path) {
                    try fileManager.removeItem(at: fileURL)
                }
                try fileManager.moveItem(at: tempURL, to: fileURL)
            } catch {
                self.osLog.error("Failed to save logs: \(error.localizedDescription)")
            }
        }
    }
    
    /// Write large files incrementally using FileHandle to avoid blocking
    /// This prevents loading the entire file into memory before writing
    private func writeLargeFileIncrementally(data: Data, to url: URL) throws {
        // Create file if it doesn't exist
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil, attributes: nil)
        }
        
        // Use FileHandle for incremental writes
        guard let fileHandle = FileHandle(forWritingAtPath: url.path) else {
            throw NSError(domain: "SharedLogger", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot create file handle"])
        }
        
        defer {
            fileHandle.closeFile()
        }
        
        // Truncate file to start fresh
        fileHandle.truncateFile(atOffset: 0)
        
        // Write data in chunks to avoid blocking
        let chunkSize = 64 * 1024 // 64KB chunks
        var offset = 0
        
        while offset < data.count {
            let chunkEnd = min(offset + chunkSize, data.count)
            let chunk = data.subdata(in: offset..<chunkEnd)
            fileHandle.write(chunk)
            offset = chunkEnd
            
            // Small yield to prevent blocking the queue
            if offset % (chunkSize * 4) == 0 { // Every 256KB
                Thread.sleep(forTimeInterval: 0.001) // 1ms yield
            }
        }
        
        // Ensure all data is written
        fileHandle.synchronizeFile()
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
            guard let self else { return }
            // Cancel any pending writes
            self.writeWorkItem?.cancel()
            self.pendingEntries.removeAll()
            self.saveEntriesToFile([])
        }
        osLog.info("Logs cleared")
    }
    
    /// Flush pending log entries immediately (call before app termination)
    func flushPendingLogs() {
        queue.sync { [weak self] in
            self?.writeWorkItem?.cancel()
            self?.flushPendingEntries()
        }
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

