import Foundation
import os.log
import os.signpost

/// Performance monitoring service for tracking latency, timing, and metrics.
/// Integrates with Instruments (signposts), SharedLogger, and NSLog for comprehensive performance analysis.
///
/// Usage:
/// ```swift
/// let monitor = PerformanceMonitor.shared
/// monitor.startOperation("WeatherFetch", category: "Network")
/// // ... perform work ...
/// monitor.endOperation("WeatherFetch", category: "Network")
/// ```
final class PerformanceMonitor {

    // MARK: - Singleton

    static let shared = PerformanceMonitor()

    // MARK: - Operation Tracking

    /// Tracks active operations with start times and signpost IDs
    private struct ActiveOperation {
        let startTime: Date
        let signpostID: OSSignpostID
    }

    private var activeOperations: [String: ActiveOperation] = [:]
    private let operationsQueue = DispatchQueue(label: "com.alexis.farenheit.performance", qos: .utility)

    /// Maximum time before considering an operation orphaned (5 minutes)
    private let orphanTimeout: TimeInterval = 5 * 60

    /// Timer to clean up orphaned operations
    private var orphanCleanupTimer: Timer?

    /// Performance metrics storage
    struct PerformanceMetric: Codable {
        let operation: String
        let category: String
        let duration: TimeInterval
        let timestamp: Date
        let metadata: [String: String]?

        var formattedDuration: String {
            if duration < 0.001 {
                return String(format: "%.3fms", duration * 1000)
            } else if duration < 1.0 {
                return String(format: "%.1fms", duration * 1000)
            } else {
                return String(format: "%.2fs", duration)
            }
        }
    }

    private var metrics: [PerformanceMetric] = []
    private let maxMetrics = 200 // Keep last 200 metrics

    // MARK: - Logging

    private let osLog = Logger(subsystem: "com.alexis.farenheit", category: "Performance")
    private let signpostLog = OSLog(subsystem: "com.alexis.farenheit", category: "Performance")

    /// Minimum duration to log (operations faster than this are ignored unless forced)
    var minimumLogDuration: TimeInterval = 0.01 // 10ms

    /// Whether to log all operations regardless of duration
    var logAllOperations: Bool = false

    // MARK: - Init

    private init() {
        osLog.info("PerformanceMonitor initialized")
        print("PerformanceMonitor initialized")

        // Start orphan cleanup timer
        startOrphanCleanupTimer()
    }

    /// Start timer to clean up orphaned operations
    private func startOrphanCleanupTimer() {
        orphanCleanupTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.cleanupOrphanedOperations()
        }
    }

    /// Clean up operations that started but never ended (orphaned)
    private func cleanupOrphanedOperations() {
        operationsQueue.async { [weak self] in
            guard let self else { return }

            let now = Date()
            let orphanedKeys = self.activeOperations.compactMap { key, operation -> String? in
                if now.timeIntervalSince(operation.startTime) > self.orphanTimeout {
                    return key
                }
                return nil
            }

            for key in orphanedKeys {
                if let operation = self.activeOperations[key] {
                    // Close signpost
                    os_signpost(.end, log: self.signpostLog, name: "Operation", signpostID: operation.signpostID)

                    // Log warning
                    let components = key.split(separator: ".")
                    if components.count == 2 {
                        let category = String(components[0])
                        let opName = String(components[1])
                        NSLog("⚠️ [PERF] Orphaned operation cleaned: \(category)/\(opName)")
                        self.osLog.warning("Orphaned operation cleaned: \(category)/\(opName)")
                    }

                    // Remove from active operations
                    self.activeOperations.removeValue(forKey: key)
                }
            }
        }
    }

    // MARK: - Operation Tracking

    /// Start tracking an operation
    /// - Parameters:
    ///   - operation: Name of the operation (e.g., "WeatherFetch", "LocationUpdate")
    ///   - category: Category for grouping (e.g., "Network", "Location", "FileIO")
    ///   - metadata: Optional metadata to include in logs
    func startOperation(_ operation: String, category: String, metadata: [String: String]? = nil) {
        let key = "\(category).\(operation)"
        let startTime = Date()

        // Create signpost ID
        let signpostID = OSSignpostID(log: signpostLog)

        // Log start with NSLog for easy debugging
        NSLog("⏱️ [PERF] START: \(category)/\(operation)")

        // OSLog for Instruments
        osLog.debug("⏱️ START: \(category)/\(operation)")

        // Signpost for Instruments timeline
        os_signpost(.begin, log: signpostLog, name: "Operation", signpostID: signpostID, "%{public}s.%{public}s", category, operation)

        // Store operation with signpost ID for proper cleanup
        operationsQueue.async { [weak self] in
            self?.activeOperations[key] = ActiveOperation(startTime: startTime, signpostID: signpostID)
        }
    }

    /// End tracking an operation and record metrics
    /// - Parameters:
    ///   - operation: Name of the operation (must match startOperation)
    ///   - category: Category (must match startOperation)
    ///   - metadata: Optional metadata to include
    ///   - forceLog: Force logging even if duration is below minimum
    func endOperation(_ operation: String, category: String, metadata: [String: String]? = nil, forceLog: Bool = false) {
        let key = "\(category).\(operation)"

        operationsQueue.async { [weak self] in
            guard let self else { return }

            guard let activeOp = self.activeOperations[key] else {
                NSLog("⚠️ [PERF] END without START: \(category)/\(operation)")
                self.osLog.warning("END without START: \(category)/\(operation)")
                return
            }

            let duration = Date().timeIntervalSince(activeOp.startTime)
            self.activeOperations.removeValue(forKey: key)

            // Create metric
            let metric = PerformanceMetric(
                operation: operation,
                category: category,
                duration: duration,
                timestamp: Date(),
                metadata: metadata
            )

            // Store metric
            self.metrics.append(metric)
            if self.metrics.count > self.maxMetrics {
                self.metrics.removeFirst()
            }

            // Log if duration exceeds threshold or forced
            let shouldLog = forceLog || self.logAllOperations || duration >= self.minimumLogDuration

            if shouldLog {
                self.logMetric(metric)
            }

            // Signpost end (use the stored signpost ID)
            os_signpost(.end, log: self.signpostLog, name: "Operation", signpostID: activeOp.signpostID, "%{public}s.%{public}s", category, operation)
        }
    }

    /// Measure a block of code synchronously
    /// - Parameters:
    ///   - operation: Name of the operation
    ///   - category: Category for grouping
    ///   - metadata: Optional metadata
    ///   - block: Code block to measure
    /// - Returns: Duration in seconds
    @discardableResult
    func measure<T>(_ operation: String, category: String, metadata: [String: String]? = nil, block: () throws -> T) rethrows -> (result: T, duration: TimeInterval) {
        startOperation(operation, category: category, metadata: metadata)
        let startTime = Date()
        defer {
            endOperation(operation, category: category, metadata: metadata, forceLog: true)
        }
        let result = try block()
        let duration = Date().timeIntervalSince(startTime)
        return (result, duration)
    }

    /// Measure an async block
    /// - Parameters:
    ///   - operation: Name of the operation
    ///   - category: Category for grouping
    ///   - metadata: Optional metadata
    ///   - block: Async code block to measure
    /// - Returns: Duration in seconds
    @discardableResult
    func measureAsync<T>(_ operation: String, category: String, metadata: [String: String]? = nil, block: () async throws -> T) async rethrows -> (result: T, duration: TimeInterval) {
        startOperation(operation, category: category, metadata: metadata)
        let startTime = Date()
        defer {
            endOperation(operation, category: category, metadata: metadata, forceLog: true)
        }
        let result = try await block()
        let duration = Date().timeIntervalSince(startTime)
        return (result, duration)
    }

    // MARK: - Logging

    private func logMetric(_ metric: PerformanceMetric) {
        // NSLog for easy console viewing (no file I/O)
        let metadataStr = metric.metadata.map { " | \($0.map { "\($0.key):\($0.value)" }.joined(separator: ", "))" } ?? ""
        NSLog("⏱️ \(metric.category)/\(metric.operation): \(metric.formattedDuration)")

        // OSLog for Instruments (no file I/O)
        osLog.info("⏱️ \(metric.category)/\(metric.operation): \(metric.formattedDuration)")

        // Skip file logging to prevent I/O during performance-sensitive operations
        // Console logs (NSLog + OSLog) are sufficient for debugging
    }

    // MARK: - Metrics Retrieval

    /// Get all metrics for a specific category
    func metrics(for category: String) -> [PerformanceMetric] {
        operationsQueue.sync {
            metrics.filter { $0.category == category }
        }
    }

    /// Get all metrics for a specific operation
    func metrics(for operation: String, category: String) -> [PerformanceMetric] {
        operationsQueue.sync {
            metrics.filter { $0.operation == operation && $0.category == category }
        }
    }

    /// Get average duration for an operation
    func averageDuration(for operation: String, category: String) -> TimeInterval? {
        let operationMetrics = metrics(for: operation, category: category)
        guard !operationMetrics.isEmpty else { return nil }

        let total = operationMetrics.reduce(0.0) { $0 + $1.duration }
        return total / Double(operationMetrics.count)
    }

    /// Get all metrics (sorted by timestamp, newest first)
    func allMetrics() -> [PerformanceMetric] {
        operationsQueue.sync {
            metrics.sorted { $0.timestamp > $1.timestamp }
        }
    }

    /// Get summary statistics for a category
    func summary(for category: String) -> (count: Int, avg: TimeInterval, min: TimeInterval, max: TimeInterval)? {
        let categoryMetrics = metrics(for: category)
        guard !categoryMetrics.isEmpty else { return nil }

        let durations = categoryMetrics.map { $0.duration }
        let avg = durations.reduce(0.0, +) / Double(durations.count)
        let min = durations.min() ?? 0
        let max = durations.max() ?? 0

        return (categoryMetrics.count, avg, min, max)
    }

    // MARK: - Memory Tracking

    /// Get current memory usage
    func currentMemoryUsage() -> (used: Int64, total: Int64) {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }

        guard kerr == KERN_SUCCESS else {
            return (0, 0)
        }

        let usedBytes = Int64(info.resident_size)
        let totalBytes = Int64(ProcessInfo.processInfo.physicalMemory)

        return (usedBytes, totalBytes)
    }

    /// Log current memory usage (console only, no file I/O)
    func logMemoryUsage(context: String = "") {
        let (used, total) = currentMemoryUsage()
        let usedMB = Double(used) / 1024 / 1024
        let totalMB = Double(total) / 1024 / 1024
        let percentage = (Double(used) / Double(total)) * 100

        let message = "Memory\(context.isEmpty ? "" : " (\(context))"): \(String(format: "%.1f", usedMB))MB / \(String(format: "%.1f", totalMB))MB (\(String(format: "%.1f", percentage))%)"

        NSLog("💾 \(message)")
        osLog.info("💾 \(message)")
        // Skip file logging to prevent I/O blocking
    }

    // MARK: - File I/O Tracking

    /// Track file read operation
    func trackFileRead(_ filePath: String, size: Int64) {
        let sizeKB = Double(size) / 1024
        let metadata = ["file": filePath, "size_bytes": "\(size)", "size_kb": String(format: "%.1f", sizeKB)]

        startOperation("FileRead", category: "FileIO", metadata: metadata)
        // Note: This is a simplified tracking - in production you'd measure actual I/O time
    }

    /// Track file write operation
    func trackFileWrite(_ filePath: String, size: Int64) {
        let sizeKB = Double(size) / 1024
        let metadata = ["file": filePath, "size_bytes": "\(size)", "size_kb": String(format: "%.1f", sizeKB)]

        startOperation("FileWrite", category: "FileIO", metadata: metadata)
    }

    // MARK: - Cleanup

    /// Clear all metrics
    func clearMetrics() {
        operationsQueue.async { [weak self] in
            self?.metrics.removeAll()
            self?.activeOperations.removeAll()
        }
        osLog.info("Performance metrics cleared")
    }

    /// Export metrics as JSON for analysis
    func exportMetrics() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(allMetrics())
    }
}

// MARK: - Convenience Global Functions

/// Quick performance tracking functions
func perfStart(_ operation: String, category: String, metadata: [String: String]? = nil) {
    PerformanceMonitor.shared.startOperation(operation, category: category, metadata: metadata)
}

func perfEnd(_ operation: String, category: String, metadata: [String: String]? = nil, forceLog: Bool = false) {
    PerformanceMonitor.shared.endOperation(operation, category: category, metadata: metadata, forceLog: forceLog)
}

func perfMeasure<T>(_ operation: String, category: String, block: () throws -> T) rethrows -> T {
    let (result, _) = try PerformanceMonitor.shared.measure(operation, category: category, block: block)
    return result
}

func perfMeasureAsync<T>(_ operation: String, category: String, block: () async throws -> T) async rethrows -> T {
    let (result, _) = try await PerformanceMonitor.shared.measureAsync(operation, category: category, block: block)
    return result
}

