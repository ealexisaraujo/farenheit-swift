//
//  AlexisExtensionFarenheit.swift
//  Temperature Converter Widget
//
//  Displays temperature in °F and °C with automatic updates.
//  Uses App Group to share data with main app.
//  Fetches fresh weather data via WeatherKit when cache is stale.
//  Logs are written to shared file for debugging via main app.
//

import WidgetKit
import SwiftUI
import WeatherKit
import CoreLocation

// MARK: - Temperature Rounding

/// Extension for consistent temperature rounding across app and widgets
/// Uses standard rounding (0.5 rounds up) to match app behavior
extension Double {
    /// Rounds to nearest integer using standard rounding rules
    /// Example: 57.85 → 58, 57.49 → 57
    var roundedInt: Int {
        Int(self.rounded())
    }
}

// MARK: - Timeline Entry

/// Data model for widget timeline entry
struct TemperatureEntry: TimelineEntry {
    let date: Date
    let cityName: String
    let countryCode: String
    let fahrenheit: Double
    let celsius: Double
    let isPlaceholder: Bool

    // Multi-city support for large widget
    let cities: [CityWidgetData]

    /// Placeholder entry for widget preview
    static var placeholder: TemperatureEntry {
        TemperatureEntry(
            date: Date(),
            cityName: "Los Angeles",
            countryCode: "US",
            fahrenheit: 72,
            celsius: 22.2,
            isPlaceholder: true,
            cities: CityWidgetData.samples
        )
    }

    /// Create entry from cached data
    static func fromCache(city: String, country: String, fahrenheit: Double, date: Date = Date(), cities: [CityWidgetData] = []) -> TemperatureEntry {
        TemperatureEntry(
            date: date,
            cityName: city,
            countryCode: country,
            fahrenheit: fahrenheit,
            celsius: (fahrenheit - 32) * 5 / 9,
            isPlaceholder: false,
            cities: cities
        )
    }

    /// Formatted fahrenheit string (uses consistent rounding)
    var fahrenheitText: String {
        "\(fahrenheit.roundedInt)°F"
    }

    /// Formatted celsius string
    var celsiusText: String {
        String(format: "%.1f°C", celsius)
    }
}

// MARK: - City Widget Data
// NOTE: CityWidgetData is now defined in WidgetRepository.swift
// This provides a SINGLE SOURCE OF TRUTH for all data structures
// The type alias below maintains backwards compatibility with existing views

/// Type alias for backwards compatibility - actual definition in WidgetRepository.swift
typealias CityWidgetData = WidgetCityData

// MARK: - Time Formatting Helper

/// Helper for formatting time in different timezones
/// Used by widget views to display local time for each city
enum WidgetTimeFormatter {
    /// Format a date in a specific timezone.
    ///
    /// NOTE:
    /// - We avoid a shared `DateFormatter` because it is not thread-safe and requires mutating `timeZone`.
    /// - We intentionally create a formatter per call: only a few cities are rendered, once per minute.
    ///   This keeps the code correct and avoids cross-thread/shared-mutable-state issues inside WidgetKit.
    ///
    /// - Parameters:
    ///   - date: The date to format (typically "now" from TimelineView)
    ///   - timeZone: The timezone to display the time in
    /// - Returns: Formatted time string (e.g., "2:30 PM")
    static func formatTime(_ date: Date, in timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = timeZone
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - Timeline Provider

/// Widget kind - must match Widget definition
private let widgetKind = "AlexisExtensionFarenheit"

/// Number of timeline entries to create (one per minute)
/// 15 minutes provides good balance between accuracy and memory usage
private let timelineEntriesCount = 15

/// Provides timeline data for the widget.
/// Uses WidgetRepository as SINGLE SOURCE OF TRUTH (Repository Pattern).
/// Creates minute-by-minute entries for accurate timezone display.
/// Fetches fresh weather via WeatherKit when cache is stale (>30 min).
struct TemperatureProvider: TimelineProvider {

    // MARK: - Dependencies (Repository Pattern)

    /// Single source of truth for all widget data
    private let repository = WidgetRepository.shared
    private let logger = WidgetLogger.shared
    private let weatherService = WeatherKit.WeatherService.shared

    /// Cache is considered stale after 30 minutes
    private let maxCacheAgeMinutes: Double = 30

    // MARK: - TimelineProvider Protocol

    func placeholder(in context: Context) -> TemperatureEntry {
        logger.timeline("placeholder() called")
        return .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (TemperatureEntry) -> Void) {
        logger.timeline("getSnapshot() called (isPreview: \(context.isPreview))")

        if context.isPreview {
            completion(.placeholder)
        } else {
            let entry = loadCachedEntry()
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TemperatureEntry>) -> Void) {
        logger.timeline("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        logger.timeline("getTimeline() CALLED")
        logger.timeline("Family: \(context.family.description)")
        // Debug note:
        // The widget UI uses `TimelineView(.periodic...)` for a live clock (time-of-day),
        // because iOS may delay timeline reloads after the last entry expires.
        logger.timeline("Clock UI: TimelineView periodic (1m) to avoid stale time after last entry")

        // Performance tracking: Start widget timeline generation
        let metadata = ["family": context.family.description, "is_preview": "\(context.isPreview)"]
        logger.startPerformanceOperation("WidgetTimeline", category: "Widget", metadata: metadata)

        // REPOSITORY PATTERN: Single source of truth for all data
        // All data access goes through repository - no scattered keys
        let cities = repository.getCities()
        let location = repository.getLocation()
        let primaryCity = repository.getPrimaryCity()
        let cacheAgeMinutes = repository.getPrimaryCacheAgeMinutes()

        // Log current state
        if let primary = primaryCity, let temp = primary.fahrenheit {
            logger.timeline("Primary city: \(primary.name), \(Int(temp))°F, age: \(Int(cacheAgeMinutes))m")
        } else {
            logger.timeline("No primary city or temperature data")
        }

        let needsFresh = cacheAgeMinutes > maxCacheAgeMinutes

        logger.timeline("Cache age: \(Int(cacheAgeMinutes))m, needs fresh: \(needsFresh)")
        logger.timeline("Cities loaded: \(cities.count)")

        // If we have location and need fresh data, fetch from WeatherKit
        if needsFresh, let coords = location, coords.isValid {
            logger.timeline("Fetching fresh weather from WeatherKit...")

            Task {
                let freshTemp = await fetchFreshTemperature(
                    location: coords.coordinate,
                    cachedCity: primaryCity?.name ?? "Unknown"
                )

                // Create updated primary city with fresh temperature
                var updatedPrimaryCity = primaryCity
                if let temp = freshTemp {
                    updatedPrimaryCity?.fahrenheit = temp
                    updatedPrimaryCity?.lastUpdated = Date()
                }

                // Create minute-by-minute entries with fresh data
                let entries = createMinuteEntries(
                    primaryCity: updatedPrimaryCity,
                    cities: cities
                )

                // Schedule next refresh after the last entry
                let lastEntryDate = entries.last?.date ?? Date()
                let timeline = Timeline(entries: entries, policy: .after(lastEntryDate))

                logger.timeline("Timeline created with \(entries.count) entries (fresh), next refresh: \(Self.timeFormatter.string(from: lastEntryDate))")
                logger.timeline("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

                // Performance tracking: End widget timeline (fresh fetch)
                var endMetadata = metadata
                endMetadata["source"] = "fresh_fetch"
                endMetadata["cities_count"] = "\(cities.count)"
                endMetadata["entries_count"] = "\(entries.count)"
                logger.endPerformanceOperation("WidgetTimeline", category: "Widget", metadata: endMetadata)

                completion(timeline)
            }
        } else {
            // Use data from repository (single source of truth)
            // Create minute-by-minute entries for accurate timezone display
            let entries = createMinuteEntries(
                primaryCity: primaryCity,
                cities: cities
            )

            if let primary = primaryCity, let temp = primary.fahrenheit {
                logger.timeline("Using saved city: \(primary.name), \(Int(temp))°F")
            } else {
                logger.timeline("No city data - showing placeholder")
            }

            // Schedule next refresh after the last entry
            let lastEntryDate = entries.last?.date ?? Date()
            let timeline = Timeline(entries: entries, policy: .after(lastEntryDate))

            logger.timeline("Timeline created with \(entries.count) entries, next refresh: \(Self.timeFormatter.string(from: lastEntryDate))")
            logger.timeline("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

            // Performance tracking: End widget timeline (cached)
            var endMetadata = metadata
            endMetadata["source"] = primaryCity != nil ? "repository" : "placeholder"
            endMetadata["cities_count"] = "\(cities.count)"
            endMetadata["entries_count"] = "\(entries.count)"
            logger.endPerformanceOperation("WidgetTimeline", category: "Widget", metadata: endMetadata)

            completion(timeline)
        }
    }

    // MARK: - Timeline Entry Creation

    /// Create minute-by-minute entries for accurate timezone display
    /// Each entry represents one minute, allowing iOS to show the correct time
    /// - Parameters:
    ///   - primaryCity: The primary city data (current location)
    ///   - cities: All cities to display
    /// - Returns: Array of timeline entries, one per minute
    private func createMinuteEntries(
        primaryCity: WidgetCityData?,
        cities: [WidgetCityData]
    ) -> [TemperatureEntry] {
        var entries: [TemperatureEntry] = []
        let currentDate = Date()

        // Round to the start of the current minute for cleaner times
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: currentDate)
        let startOfMinute = calendar.date(from: components) ?? currentDate

        for minuteOffset in 0..<timelineEntriesCount {
            guard let entryDate = calendar.date(byAdding: .minute, value: minuteOffset, to: startOfMinute) else {
                continue
            }

            let entry: TemperatureEntry
            if let primary = primaryCity, let temp = primary.fahrenheit {
                entry = TemperatureEntry.fromCache(
                    city: primary.name,
                    country: primary.countryCode,
                    fahrenheit: temp,
                    date: entryDate,
                    cities: cities
                )
            } else {
                entry = TemperatureEntry(
                    date: entryDate,
                    cityName: "Open App",
                    countryCode: "",
                    fahrenheit: 72,
                    celsius: 22.2,
                    isPlaceholder: true,
                    cities: cities
                )
            }

            entries.append(entry)
        }

        return entries
    }

    // MARK: - WeatherKit Fetch

    /// Fetch fresh temperature from WeatherKit
    /// Returns nil if fetch fails, allowing caller to use cached data
    private func fetchFreshTemperature(location: CLLocationCoordinate2D, cachedCity: String) async -> Double? {
        // Performance tracking: Start widget weather fetch
        let metadata = [
            "latitude": String(format: "%.4f", location.latitude),
            "longitude": String(format: "%.4f", location.longitude),
            "city": cachedCity
        ]
        logger.startPerformanceOperation("WidgetWeatherFetch", category: "Widget", metadata: metadata)

        let clLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)

        do {
            let weather = try await weatherService.weather(for: clLocation, including: .current)
            let tempF = weather.temperature.converted(to: .fahrenheit).value

            logger.timeline("WeatherKit success: \(Int(tempF))°F")

            // Performance tracking: End widget weather fetch (success)
            var successMetadata = metadata
            successMetadata["temperature"] = String(format: "%.1f", tempF)
            logger.endPerformanceOperation("WidgetWeatherFetch", category: "Widget", metadata: successMetadata)

            // REPOSITORY PATTERN: Save via repository (single source of truth)
            // This updates saved_cities array, eliminating race conditions
            repository.updatePrimaryTemperature(fahrenheit: tempF)
            logger.data("Saved fresh data via repository: \(cachedCity), \(Int(tempF))°F")

            return tempF
        } catch {
            logger.error("WeatherKit error: \(error.localizedDescription)")

            // Performance tracking: End widget weather fetch (error)
            var errorMetadata = metadata
            errorMetadata["error"] = error.localizedDescription
            logger.endPerformanceOperation("WidgetWeatherFetch", category: "Widget", metadata: errorMetadata, forceLog: true)

            return nil
        }
    }

    // MARK: - Data Loading (via Repository)

    /// Load cached entry from repository (used by getSnapshot)
    /// All data access goes through WidgetRepository - SINGLE SOURCE OF TRUTH
    private func loadCachedEntry() -> TemperatureEntry {
        let cities = repository.getCities()

        // Use repository as single source of truth
        if let primary = cities.first, let temp = primary.fahrenheit {
            return TemperatureEntry.fromCache(
                city: primary.name,
                country: primary.countryCode,
                fahrenheit: temp,
                cities: cities
            )
        }
        return .placeholder
    }

    // MARK: - Helpers

    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        return df
    }()
}

// NOTE: SavedCityModel has been REMOVED
// All data structures are now in WidgetRepository.swift
// This eliminates code duplication and ensures single source of truth

// MARK: - Conversion Data

struct ConversionItem: Identifiable {
    let id: Int
    let fahrenheit: Int
    let celsius: Int

    var fText: String { "\(fahrenheit)°F" }
    var cText: String { "\(celsius)°C" }
}

let conversionScale: [ConversionItem] = [
    ConversionItem(id: 0, fahrenheit: 32, celsius: 0),
    ConversionItem(id: 1, fahrenheit: 50, celsius: 10),
    ConversionItem(id: 2, fahrenheit: 68, celsius: 20),
    ConversionItem(id: 3, fahrenheit: 86, celsius: 30),
    ConversionItem(id: 4, fahrenheit: 104, celsius: 40)
]

let conversionTable: [ConversionItem] = [
    ConversionItem(id: 0, fahrenheit: 0, celsius: -18),
    ConversionItem(id: 1, fahrenheit: 32, celsius: 0),
    ConversionItem(id: 2, fahrenheit: 50, celsius: 10),
    ConversionItem(id: 3, fahrenheit: 68, celsius: 20),
    ConversionItem(id: 4, fahrenheit: 86, celsius: 30),
    ConversionItem(id: 5, fahrenheit: 100, celsius: 38)
]

// MARK: - Widget Views

struct SmallWidgetView: View {
    let entry: TemperatureEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "location.fill")
                    .font(.caption2)
                Text(entry.cityName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
            .foregroundStyle(Color.white.opacity(0.9))

            Spacer()

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.fahrenheitText)
                    .font(.system(size: 42, weight: .thin, design: .rounded))
                    .foregroundStyle(Color.white)

                Text(entry.celsiusText)
                    .font(.title3)
                    .foregroundStyle(Color.white.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding()
    }
}

/// Medium Widget - Clean 2025 Design
/// Simple, readable, high contrast - shows 2 cities
struct MediumWidgetView: View {
    let entry: TemperatureEntry

    var body: some View {
        // IMPORTANT (WidgetKit limitation):
        // Widget timelines are best-effort. When the last timeline entry expires, iOS may delay calling `getTimeline()`.
        // If we render time based on `entry.date`, the UI can get "stuck" (e.g., device 4:30, widget 4:19).
        //
        // `TimelineView(.periodic...)` lets the widget re-render periodically WITHOUT network and WITHOUT needing a new timeline,
        // so the displayed "clock" stays aligned with the OS time.
        TimelineView(.periodic(from: Date(), by: 60)) { context in
            let now = context.date

            HStack(spacing: 16) {
                // Primary city (left side - larger)
                primaryCityView

                // Divider
                Rectangle()
                    .fill(.white.opacity(0.2))
                    .frame(width: 1)
                    .padding(.vertical, 8)

                // Secondary city or conversion table (right side)
                if let secondCity = entry.cities.dropFirst().first {
                    secondaryCityView(secondCity, now: now)
                } else {
                    conversionView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(16)
        }
    }

    // MARK: - Primary City View
    private var primaryCityView: some View {
        VStack(alignment: .leading, spacing: 4) {
            // City name with location icon
            HStack(spacing: 4) {
                Image(systemName: "location.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.cyan)

                Text(entry.cityName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            Spacer()

            // Large temperature
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(entry.fahrenheit.roundedInt)")
                    .font(.system(size: 52, weight: .thin, design: .rounded))
                    .foregroundStyle(.white)

                Text("°F")
                    .font(.system(size: 20, weight: .light, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }

            // Celsius
            Text(entry.celsiusText)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Secondary City View
    private func secondaryCityView(_ city: CityWidgetData, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // City name
            HStack(spacing: 4) {
                Image(systemName: city.isDaytime(at: now) ? "sun.max.fill" : "moon.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(city.isDaytime(at: now) ? .yellow : .white.opacity(0.7))

                Text(city.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            Spacer()

            // Temperature
            if let temp = city.fahrenheit {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(temp.roundedInt)")
                        .font(.system(size: 36, weight: .light, design: .rounded))
                        .foregroundStyle(.white)

                    Text("°F")
                        .font(.system(size: 14, weight: .light, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }

                if let celsius = city.celsius {
                    Text("\(Int(celsius))°C")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }
            } else {
                Text("--°")
                    .font(.system(size: 36, weight: .light, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }

            // Local time - uses "now" from TimelineView for live clock behavior.
            Text(WidgetTimeFormatter.formatTime(now, in: city.timeZone))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Conversion View (fallback when no second city)
    private var conversionView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("F° → C°")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))
                .textCase(.uppercase)

            Spacer()

            VStack(alignment: .leading, spacing: 4) {
                conversionRow(32, 0)
                conversionRow(50, 10)
                conversionRow(68, 20)
                conversionRow(86, 30)
                conversionRow(100, 38)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func conversionRow(_ f: Int, _ c: Int) -> some View {
        let isNear = abs(Int(entry.fahrenheit) - f) <= 8

        return HStack(spacing: 4) {
            Text("\(f)°")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(isNear ? .cyan : .white.opacity(0.7))
                .frame(width: 36, alignment: .trailing)

            Text("→")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.4))

            Text("\(c)°")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(isNear ? .cyan : .white.opacity(0.7))
                .frame(width: 30, alignment: .leading)
        }
    }
}

// MARK: - Large Widget with Multi-City Support

struct LargeWidgetView: View {
    let entry: TemperatureEntry

    var body: some View {
        // Same reasoning as MediumWidgetView: keep the clock live even if iOS delays timeline reloads.
        TimelineView(.periodic(from: Date(), by: 60)) { context in
            let now = context.date

            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    Text("Tiempo Mundial")
                        .font(.headline)
                        .foregroundStyle(Color.white)
                    Spacer()
                    Image(systemName: "globe.americas.fill")
                        .font(.title2)
                        .foregroundStyle(Color.cyan)
                }

                // City cards (up to 3)
                if entry.cities.isEmpty {
                    // Fallback to single city display
                    singleCityView
                } else {
                    // Multi-city display
                    VStack(spacing: 8) {
                        ForEach(entry.cities.prefix(3)) { city in
                            cityRow(city, now: now)
                        }
                    }
                }

                Spacer()

                // Footer with conversion hint
                HStack {
                    Text("Desliza en la app para cambiar hora")
                        .font(.caption2)
                        .foregroundStyle(Color.white.opacity(0.5))
                    Spacer()
                    Text(now, style: .time)
                        .font(.caption2)
                        .foregroundStyle(Color.white.opacity(0.5))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }

    // Single city fallback
    private var singleCityView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "location.fill")
                    .font(.caption)
                Text(entry.cityName)
                    .font(.headline)
                if !entry.countryCode.isEmpty {
                    Text(entry.countryCode)
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                }
            }
            .foregroundStyle(Color.white)

            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("\(entry.fahrenheit.roundedInt)")
                    .font(.system(size: 64, weight: .ultraLight, design: .rounded))
                Text("°F")
                    .font(.system(size: 24, weight: .light))
            }
            .foregroundStyle(Color.white)

            Text(entry.celsiusText)
                .font(.title2)
                .foregroundStyle(Color.white.opacity(0.7))
        }
    }

    // City row for multi-city display
    private func cityRow(_ city: CityWidgetData, now: Date) -> some View {
        HStack(spacing: 12) {
            // Day/night indicator
            Image(systemName: city.isDaytime(at: now) ? "sun.max.fill" : "moon.fill")
                .font(.system(size: 16))
                .foregroundStyle(city.isDaytime(at: now) ? .yellow : .white.opacity(0.7))
                .frame(width: 24)

            // City info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if city.isCurrentLocation {
                        Image(systemName: "location.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.blue)
                    }
                    Text(city.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if !city.countryCode.isEmpty {
                        Text(city.countryCode)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }

                // Uses "now" from TimelineView for live clock behavior
                Text(WidgetTimeFormatter.formatTime(now, in: city.timeZone))
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer()

            // Temperature
            if let temp = city.fahrenheit {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(temp.roundedInt)°")
                        .font(.system(size: 28, weight: .light, design: .rounded))
                        .foregroundStyle(.white)

                    if let celsius = city.celsius {
                        Text("\(Int(celsius))°C")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            } else {
                Text("--°")
                    .font(.system(size: 28, weight: .light, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(city.isCurrentLocation
                    ? Color.white.opacity(0.15)
                    : Color.white.opacity(0.08))
        )
    }
}

// MARK: - WidgetCityData Helpers (Widget Extension)

extension WidgetCityData {
    /// Determine day/night state at a specific moment for this city's timezone.
    ///
    /// We pass `now` from `TimelineView` so the icon can update even if iOS delays the next widget timeline.
    func isDaytime(at date: Date) -> Bool {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let hour = calendar.component(.hour, from: date)
        return hour >= 6 && hour < 18
    }
}

// MARK: - Lock Screen Widget Views (iOS 16+)

/// Circular widget for Lock Screen - shows temperature prominently
/// Optimized for glanceability - one number that matters most
struct AccessoryCircularView: View {
    let entry: TemperatureEntry

    var body: some View {
        Gauge(value: normalizedTemp, in: 0...1) {
            Text("°F")
                .font(.system(size: 8))
        } currentValueLabel: {
            Text("\(entry.fahrenheit.roundedInt)°")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
        } minimumValueLabel: {
            Text("\(Int(entry.celsius))°")
                .font(.system(size: 9, weight: .medium))
        } maximumValueLabel: {
            Text("C")
                .font(.system(size: 9, weight: .medium))
        }
        .gaugeStyle(.accessoryCircular)
        .widgetAccentable()
    }

    /// Normalize temperature for gauge display (0°F to 120°F range)
    private var normalizedTemp: Double {
        let clamped = min(max(entry.fahrenheit, 0), 120)
        return clamped / 120
    }
}

/// Rectangular widget for Lock Screen - shows city and both temperatures
/// Design follows Apple HIG: clear hierarchy, instant readability, compact layout
struct AccessoryRectangularView: View {
    let entry: TemperatureEntry

    var body: some View {
        HStack(spacing: 12) {
            // Temperature hero - the star of the show
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(entry.fahrenheit.roundedInt)")
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                Text("°F")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
            }

            // Divider line for visual separation
            Rectangle()
                .fill(.secondary.opacity(0.4))
                .frame(width: 1, height: 32)

            // Secondary info - city and celsius
            VStack(alignment: .leading, spacing: 2) {
                // City with location pin
                HStack(spacing: 3) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 8))
                    Text(entry.cityName)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                }

                // Celsius conversion
                Text(entry.celsiusText)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetAccentable()
    }
}

/// Inline widget for Lock Screen - single line text
struct AccessoryInlineView: View {
    let entry: TemperatureEntry

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "thermometer.medium")
            Text("\(entry.cityName): \(entry.fahrenheitText) / \(entry.celsiusText)")
        }
    }
}

// MARK: - Widget Definition

struct AlexisExtensionFarenheit: Widget {
    let kind: String = "AlexisExtensionFarenheit"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TemperatureProvider()) { entry in
            WidgetContentView(entry: entry)
                .containerBackground(for: .widget) {
                    gradientBackground(for: entry.fahrenheit)
                }
        }
        .configurationDisplayName("Temp Converter")
        .description("Muestra temperatura en °F y °C. Widget grande muestra 3 ciudades.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

private func gradientBackground(for fahrenheit: Double) -> LinearGradient {
    let colors: [Color]

    switch fahrenheit {
    case ..<32:
        colors = [Color(hex: "1a237e"), Color(hex: "0d47a1")]
    case 32..<50:
        colors = [Color(hex: "0288d1"), Color(hex: "03a9f4")]
    case 50..<68:
        colors = [Color(hex: "00897b"), Color(hex: "26a69a")]
    case 68..<86:
        colors = [Color(hex: "ff7043"), Color(hex: "ff5722")]
    default:
        colors = [Color(hex: "d32f2f"), Color(hex: "f44336")]
    }

    return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
}

struct WidgetContentView: View {
    @Environment(\.widgetFamily) var family
    let entry: TemperatureEntry

    var body: some View {
        switch family {
        // Home Screen widgets
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .systemLarge:
            LargeWidgetView(entry: entry)
        // Lock Screen widgets (iOS 16+)
        case .accessoryCircular:
            AccessoryCircularView(entry: entry)
        case .accessoryRectangular:
            AccessoryRectangularView(entry: entry)
        case .accessoryInline:
            AccessoryInlineView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    AlexisExtensionFarenheit()
} timeline: {
    TemperatureEntry.placeholder
    TemperatureEntry.fromCache(city: "Chandler", country: "US", fahrenheit: 69)
}

#Preview("Medium", as: .systemMedium) {
    AlexisExtensionFarenheit()
} timeline: {
    TemperatureEntry.fromCache(city: "Detroit", country: "US", fahrenheit: 62)
}

#Preview("Large - Multi City", as: .systemLarge) {
    AlexisExtensionFarenheit()
} timeline: {
    TemperatureEntry.fromCache(
        city: "Phoenix",
        country: "US",
        fahrenheit: 95,
        cities: CityWidgetData.samples
    )
}

#Preview("Large - Single City", as: .systemLarge) {
    AlexisExtensionFarenheit()
} timeline: {
    TemperatureEntry.placeholder
}

// MARK: - Lock Screen Widget Previews

#Preview("Lock Screen - Circular", as: .accessoryCircular) {
    AlexisExtensionFarenheit()
} timeline: {
    TemperatureEntry.fromCache(city: "Chandler", country: "US", fahrenheit: 72)
}

#Preview("Lock Screen - Rectangular", as: .accessoryRectangular) {
    AlexisExtensionFarenheit()
} timeline: {
    TemperatureEntry.fromCache(city: "Chandler", country: "US", fahrenheit: 72)
}

#Preview("Lock Screen - Inline", as: .accessoryInline) {
    AlexisExtensionFarenheit()
} timeline: {
    TemperatureEntry.fromCache(city: "Chandler", country: "US", fahrenheit: 72)
}
