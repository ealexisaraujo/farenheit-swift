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

    /// Formatted fahrenheit string
    var fahrenheitText: String {
        "\(Int(fahrenheit))°F"
    }

    /// Formatted celsius string
    var celsiusText: String {
        String(format: "%.1f°C", celsius)
    }
}

// MARK: - City Widget Data

/// Simplified city data for widget display
struct CityWidgetData: Identifiable, Codable {
    let id: UUID
    var name: String
    var countryCode: String
    var fahrenheit: Double?
    var timeZoneIdentifier: String
    var isCurrentLocation: Bool
    var lastUpdated: Date?

    var celsius: Double? {
        guard let f = fahrenheit else { return nil }
        return (f - 32) * 5 / 9
    }

    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .current
    }

    /// Get formatted local time string
    func localTimeString() -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: Date())
    }

    /// Check if it's daytime (6AM - 6PM) in this city
    var isDaytime: Bool {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let hour = calendar.component(.hour, from: Date())
        return hour >= 6 && hour < 18
    }

    static let samples: [CityWidgetData] = [
        CityWidgetData(
            id: UUID(),
            name: "Phoenix",
            countryCode: "US",
            fahrenheit: 95,
            timeZoneIdentifier: "America/Phoenix",
            isCurrentLocation: true
        ),
        CityWidgetData(
            id: UUID(),
            name: "Tokyo",
            countryCode: "JP",
            fahrenheit: 72,
            timeZoneIdentifier: "Asia/Tokyo",
            isCurrentLocation: false
        ),
        CityWidgetData(
            id: UUID(),
            name: "London",
            countryCode: "GB",
            fahrenheit: 55,
            timeZoneIdentifier: "Europe/London",
            isCurrentLocation: false
        )
    ]
}

// MARK: - Timeline Provider

/// App Group ID - must match exactly with main app
private let appGroupID = "group.alexisaraujo.alexisfarenheit"

/// Widget kind - must match Widget definition
private let widgetKind = "AlexisExtensionFarenheit"

/// Provides timeline data for the widget.
/// Fetches fresh weather via WeatherKit when cache is stale (>30 min).
/// Logs all operations for debugging via main app's Log Viewer.
struct TemperatureProvider: TimelineProvider {

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

        // Performance tracking: Start widget timeline generation
        let metadata = ["family": context.family.description, "is_preview": "\(context.isPreview)"]
        logger.startPerformanceOperation("WidgetTimeline", category: "Widget", metadata: metadata)

        // IMPORTANT: Use saved_cities as the single source of truth
        // This eliminates race conditions between widget_city and saved_cities
        let cities = loadSavedCities()
        let location = loadLastKnownLocation()

        // Get primary city from saved_cities (first city is always primary/current location)
        let primaryCity = cities.first

        // Check cache freshness based on primary city's lastUpdated
        let cacheAgeMinutes: Double
        if let primary = primaryCity, let temp = primary.fahrenheit {
            // Calculate actual age from lastUpdated
            if let lastUpdate = primary.lastUpdated {
                cacheAgeMinutes = Date().timeIntervalSince(lastUpdate) / 60
            } else {
                // No lastUpdated means data is stale
                cacheAgeMinutes = Double.infinity
            }
            logger.timeline("Primary city: \(primary.name), \(Int(temp))°F, age: \(Int(cacheAgeMinutes))m")
        } else {
            cacheAgeMinutes = Double.infinity
            logger.timeline("No primary city or temperature data")
        }

        let needsFresh = cacheAgeMinutes > maxCacheAgeMinutes

        logger.timeline("Cache age: \(Int(cacheAgeMinutes))m, needs fresh: \(needsFresh)")
        logger.timeline("Cities loaded: \(cities.count)")

        // If we have location and need fresh data, fetch from WeatherKit
        if needsFresh, let coords = location {
            logger.timeline("Fetching fresh weather from WeatherKit...")

            Task {
                let entry = await fetchFreshWeather(
                    location: coords,
                    cachedCity: primaryCity?.name ?? "Unknown",
                    cachedCountry: primaryCity?.countryCode ?? "",
                    cities: cities
                )

                // Schedule next refresh in 30 minutes
                let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
                let timeline = Timeline(entries: [entry], policy: .after(nextRefresh))

                logger.timeline("Timeline created, next refresh: \(Self.timeFormatter.string(from: nextRefresh))")
                logger.timeline("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

                // Performance tracking: End widget timeline (fresh fetch)
                var endMetadata = metadata
                endMetadata["source"] = "fresh_fetch"
                endMetadata["cities_count"] = "\(cities.count)"
                logger.endPerformanceOperation("WidgetTimeline", category: "Widget", metadata: endMetadata)

                completion(timeline)
            }
        } else {
            // Use data from saved_cities as the single source of truth
            let entry: TemperatureEntry
            if let primary = primaryCity, let temp = primary.fahrenheit {
                entry = TemperatureEntry.fromCache(
                    city: primary.name,
                    country: primary.countryCode,
                    fahrenheit: temp,
                    date: Date(),
                    cities: cities
                )
                logger.timeline("Using saved city: \(primary.name), \(Int(temp))°F")
            } else {
                entry = TemperatureEntry(
                    date: Date(),
                    cityName: "Open App",
                    countryCode: "",
                    fahrenheit: 72,
                    celsius: 22.2,
                    isPlaceholder: true,
                    cities: cities
                )
                logger.timeline("No city data - showing placeholder")
            }

            // Schedule next refresh in 15 minutes
            let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
            let timeline = Timeline(entries: [entry], policy: .after(nextRefresh))

            logger.timeline("Timeline created, next refresh: \(Self.timeFormatter.string(from: nextRefresh))")
            logger.timeline("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

            // Performance tracking: End widget timeline (cached)
            var endMetadata = metadata
            endMetadata["source"] = primaryCity != nil ? "saved_cities" : "placeholder"
            endMetadata["cities_count"] = "\(cities.count)"
            logger.endPerformanceOperation("WidgetTimeline", category: "Widget", metadata: endMetadata)

            completion(timeline)
        }
    }

    // MARK: - WeatherKit Fetch

    /// Fetch fresh weather from WeatherKit
    private func fetchFreshWeather(location: CLLocationCoordinate2D, cachedCity: String, cachedCountry: String, cities: [CityWidgetData]) async -> TemperatureEntry {
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

            // Save fresh data to cache for main app
            saveFreshTemperature(city: cachedCity, country: cachedCountry, fahrenheit: tempF)

            return TemperatureEntry.fromCache(
                city: cachedCity,
                country: cachedCountry,
                fahrenheit: tempF,
                date: Date(),
                cities: cities
            )
        } catch {
            logger.error("WeatherKit error: \(error.localizedDescription)")

            // Performance tracking: End widget weather fetch (error)
            var errorMetadata = metadata
            errorMetadata["error"] = error.localizedDescription
            logger.endPerformanceOperation("WidgetWeatherFetch", category: "Widget", metadata: errorMetadata, forceLog: true)

            // Fall back to cached data on error
            if let cached = loadCachedData() {
                return TemperatureEntry.fromCache(
                    city: cached.city,
                    country: cached.country,
                    fahrenheit: cached.fahrenheit,
                    date: Date(),
                    cities: cities
                )
            }

            return .placeholder
        }
    }

    /// Save fresh temperature to App Group (so main app sees it too)
    private func saveFreshTemperature(city: String, country: String, fahrenheit: Double) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }

        defaults.set(city, forKey: "widget_city")
        defaults.set(country, forKey: "widget_country")
        defaults.set(fahrenheit, forKey: "widget_fahrenheit")
        defaults.set(Date().timeIntervalSince1970, forKey: "widget_last_update")
        defaults.synchronize()

        logger.data("Saved fresh data: \(city), \(Int(fahrenheit))°F")
    }

    // MARK: - Data Loading

    private func loadCachedData() -> (city: String, country: String, fahrenheit: Double, lastUpdate: Date)? {
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            logger.error("Cannot access App Group: \(appGroupID)")
            return nil
        }

        defaults.synchronize()

        let city = defaults.string(forKey: "widget_city")
        let country = defaults.string(forKey: "widget_country") ?? ""
        let fahrenheit = defaults.double(forKey: "widget_fahrenheit")
        let lastUpdate = defaults.double(forKey: "widget_last_update")

        guard let cityName = city, !cityName.isEmpty, lastUpdate > 0 else {
            logger.data("No cached data found")
            return nil
        }

        let updateDate = Date(timeIntervalSince1970: lastUpdate)
        return (cityName, country, fahrenheit, updateDate)
    }

    private func loadLastKnownLocation() -> CLLocationCoordinate2D? {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return nil }

        defaults.synchronize()

        let lat = defaults.double(forKey: "last_latitude")
        let lon = defaults.double(forKey: "last_longitude")

        guard lat != 0 && lon != 0 else {
            logger.data("No location saved")
            return nil
        }

        logger.data("Location: \(lat), \(lon)")
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Load saved cities from App Group
    /// This is the SINGLE SOURCE OF TRUTH for widget data
    private func loadSavedCities() -> [CityWidgetData] {
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            logger.error("Cannot access App Group: \(appGroupID)")
            return []
        }

        // CRITICAL: Synchronize to get the latest data from the main app
        // This ensures we read the most recent changes, especially after city changes
        defaults.synchronize()

        guard let data = defaults.data(forKey: "saved_cities") else {
            logger.data("No saved_cities data found")
            return []
        }

        do {
            // Decode full CityModel array
            let decoder = JSONDecoder()
            let cityModels = try decoder.decode([SavedCityModel].self, from: data)

            // Convert to widget data (take first 3)
            let widgetCities = cityModels.prefix(3).map { model in
                CityWidgetData(
                    id: model.id,
                    name: model.name,
                    countryCode: model.countryCode,
                    fahrenheit: model.fahrenheit,
                    timeZoneIdentifier: model.timeZoneIdentifier,
                    isCurrentLocation: model.isCurrentLocation,
                    lastUpdated: model.lastUpdated
                )
            }

            logger.data("Loaded \(widgetCities.count) cities for widget")
            return Array(widgetCities)
        } catch {
            logger.error("Failed to decode cities: \(error.localizedDescription)")
            return []
        }
    }

    private func loadCachedEntry() -> TemperatureEntry {
        let cities = loadSavedCities()
        // Use saved_cities as single source of truth
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

// MARK: - Saved City Model (for decoding from main app)

/// Mirrors CityModel from main app for decoding
private struct SavedCityModel: Codable {
    let id: UUID
    var name: String
    var countryCode: String
    var latitude: Double
    var longitude: Double
    var timeZoneIdentifier: String
    var fahrenheit: Double?
    var lastUpdated: Date?
    var isCurrentLocation: Bool
    var sortOrder: Int
}

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
                secondaryCityView(secondCity)
            } else {
                conversionView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
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
                Text("\(Int(entry.fahrenheit))")
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
    private func secondaryCityView(_ city: CityWidgetData) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // City name
            HStack(spacing: 4) {
                Image(systemName: city.isDaytime ? "sun.max.fill" : "moon.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(city.isDaytime ? .yellow : .white.opacity(0.7))

                Text(city.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            Spacer()

            // Temperature
            if let temp = city.fahrenheit {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(Int(temp))")
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

            // Local time
            Text(city.localTimeString())
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
                        cityRow(city)
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
                Text(entry.date, style: .time)
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
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
                Text("\(Int(entry.fahrenheit))")
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
    private func cityRow(_ city: CityWidgetData) -> some View {
        HStack(spacing: 12) {
            // Day/night indicator
            Image(systemName: city.isDaytime ? "sun.max.fill" : "moon.fill")
                .font(.system(size: 16))
                .foregroundStyle(city.isDaytime ? .yellow : .white.opacity(0.7))
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

                Text(city.localTimeString())
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer()

            // Temperature
            if let temp = city.fahrenheit {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(temp))°")
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
            Text("\(Int(entry.fahrenheit))°")
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
                Text("\(Int(entry.fahrenheit))")
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
