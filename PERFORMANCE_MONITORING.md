# Performance Monitoring Guide

## Overview

The app now includes comprehensive performance monitoring to help investigate latency issues. The system tracks timing, memory usage, and file I/O operations across all critical paths.

## Components

### 1. PerformanceMonitor Service

Located at: `Core/Services/PerformanceMonitor.swift`

**Features:**
- Operation timing (start/end tracking)
- OSLog integration for Instruments
- Signposts for Instruments timeline visualization
- NSLog output for easy console debugging
- SharedLogger integration for file-based logging
- Memory usage tracking
- Metrics collection and analysis

### 2. Integrated Services

Performance tracking has been added to:

- **WeatherService**: Tracks weather API calls
- **LocationService**: Tracks location requests and reverse geocoding
- **SharedLogger**: Tracks file I/O operations (read/write)
- **Widget Timeline Provider**: Tracks widget timeline generation
- **HomeViewModel**: Tracks city weather fetching
- **WidgetDataService**: Tracks widget data saves and reloads

## Usage

### Viewing Performance Data

#### 1. Console (NSLog)
All performance operations are logged to console with `⏱️ [PERF]` prefix:
```
⏱️ [PERF] START: Network/WeatherFetch
⏱️ [PERF] END: Network/WeatherFetch | Duration: 1.23s | latitude:33.3062, longitude:-111.8412, temperature:72.5
```

#### 2. SharedLogger (File-based)
Performance logs are written to the shared log file with category `Performance.*`:
- `Performance.Network` - Network operations
- `Performance.Location` - Location operations
- `Performance.FileIO` - File I/O operations
- `Performance.Widget` - Widget operations
- `Performance.Memory` - Memory usage

View logs in the app's Log Viewer or export them.

#### 3. Instruments

**Using Signposts:**
1. Open Instruments in Xcode
2. Select "Time Profiler" or "System Trace"
3. Filter by subsystem: `com.alexis.farenheit`
4. Look for "Performance" category
5. Operations appear as intervals on the timeline

**Using OSLog:**
1. In Instruments, select "Logging" instrument
2. Filter by subsystem: `com.alexis.farenheit`
3. Category: `Performance`
4. View all performance log entries

#### 4. Metrics Tab (Programmatic)

Access metrics programmatically:
```swift
let monitor = PerformanceMonitor.shared

// Get all metrics for a category
let networkMetrics = monitor.metrics(for: "Network")

// Get average duration for an operation
if let avgDuration = monitor.averageDuration(for: "WeatherFetch", category: "Network") {
    print("Average weather fetch: \(avgDuration)s")
}

// Get summary statistics
if let summary = monitor.summary(for: "Network") {
    print("Network operations: \(summary.count)")
    print("Average: \(summary.avg)s")
    print("Min: \(summary.min)s")
    print("Max: \(summary.max)s")
}
```

### Memory Tracking

Memory usage is automatically logged:
- On app initialization
- When app becomes active

Manual memory tracking:
```swift
PerformanceMonitor.shared.logMemoryUsage(context: "After Weather Fetch")
```

Output:
```
💾 [MEM] Memory (After Weather Fetch): 45.2MB / 4096.0MB (1.1%)
```

## Performance Categories

### Network
- `WeatherFetch` - WeatherKit API calls
- `CityWeatherFetch` - City-specific weather fetches
- `WidgetWeatherFetch` - Widget weather fetches

### Location
- `LocationRequest` - CoreLocation requests
- `ReverseGeocode` - Reverse geocoding operations

### FileIO
- `LogFileRead` - Reading log files
- `LogFileWrite` - Writing log files

### Widget
- `WidgetTimeline` - Widget timeline generation
- `WidgetDataSave` - Saving widget data
- `WidgetReload` - Reloading widget timelines

## Configuration

### Minimum Log Duration

By default, operations faster than 10ms are not logged (unless forced):
```swift
PerformanceMonitor.shared.minimumLogDuration = 0.05 // 50ms
```

### Log All Operations

Force logging of all operations regardless of duration:
```swift
PerformanceMonitor.shared.logAllOperations = true
```

## Analyzing Latency Issues

### Step 1: Check Console Logs
Look for operations with long durations:
```
⏱️ [PERF] END: Network/WeatherFetch | Duration: 5.23s
```

### Step 2: Use Instruments
1. Profile the app with Instruments
2. Look for long-running operations in the timeline
3. Check for memory spikes during slow operations
4. Identify blocking operations on main thread

### Step 3: Review Metrics
Export metrics for analysis:
```swift
if let metricsData = PerformanceMonitor.shared.exportMetrics() {
    // Save to file or send to analytics
}
```

### Step 4: Check Memory Usage
Look for memory warnings in logs:
```
💾 [MEM] Memory: 250.5MB / 4096.0MB (6.1%)
```

High memory usage can cause performance degradation.

## Common Latency Sources

### 1. Network Operations
- WeatherKit API calls can be slow on poor connections
- Check `Network/WeatherFetch` metrics
- Look for timeouts or retries

### 2. Location Services
- GPS acquisition can take time
- Reverse geocoding adds latency
- Check `Location/LocationRequest` and `Location/ReverseGeocode` metrics

### 3. File I/O
- Log file writes can block if file is large
- Check `FileIO/LogFileWrite` metrics
- Consider async file operations

### 4. Widget Operations
- Widget timeline generation happens in background
- Multiple widget updates can cause delays
- Check `Widget/WidgetTimeline` metrics

## Debugging Tips

### Enable Verbose Logging
```swift
PerformanceMonitor.shared.logAllOperations = true
PerformanceMonitor.shared.minimumLogDuration = 0.0
```

### Track Custom Operations
```swift
// Start tracking
PerformanceMonitor.shared.startOperation("CustomOp", category: "Custom", metadata: ["key": "value"])

// ... perform work ...

// End tracking
PerformanceMonitor.shared.endOperation("CustomOp", category: "Custom", metadata: ["result": "success"])
```

### Measure Code Blocks
```swift
let (result, duration) = PerformanceMonitor.shared.measure("ProcessData", category: "Processing") {
    // Your code here
    return processedData
}
print("Processing took: \(duration)s")
```

## Integration with Existing Logging

All performance metrics are automatically:
1. Logged to NSLog (console)
2. Written to SharedLogger (file-based)
3. Sent to OSLog (Instruments)
4. Tracked with signposts (Instruments timeline)

No additional configuration needed - it works out of the box!

## Best Practices

1. **Monitor in Production**: Performance data helps identify real-world issues
2. **Set Thresholds**: Configure `minimumLogDuration` based on your needs
3. **Review Regularly**: Check metrics periodically to catch regressions
4. **Use Instruments**: Visual timeline helps identify bottlenecks
5. **Track Memory**: High memory usage can cause performance issues

## Troubleshooting

### No Performance Logs Appearing
- Check that `minimumLogDuration` is not too high
- Verify `logAllOperations` is enabled if needed
- Ensure operations are properly started/ended

### Instruments Not Showing Signposts
- Verify subsystem: `com.alexis.farenheit`
- Check category: `Performance`
- Ensure app is running with Instruments attached

### High Memory Usage
- Check for memory leaks in Instruments
- Review memory logs for patterns
- Consider reducing log file size limits

