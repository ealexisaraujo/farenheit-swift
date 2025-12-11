//
//  WidgetRepository.swift
//  AlexisExtensionFarenheit (Widget Extension)
//
//  Single source of truth for widget data - Widget Extension version.
//  This is a lightweight copy of the main app's WidgetRepository.
//
//  WHY DUPLICATE?
//  - Widget Extension runs in a separate process from the main app
//  - Cannot share code directly without a shared framework
//  - App Group (UserDefaults) is the bridge between processes
//  - Both use identical keys and data structures for compatibility
//
//  TODO: Consider creating a shared framework (e.g., AlexisShared.framework)
//  to eliminate this duplication and ensure both targets use the same code.
//
//  SYNC MECHANISM:
//  ┌──────────────┐                    ┌──────────────────────┐
//  │   Main App   │──── UserDefaults ──│   Widget Extension   │
//  │ WidgetRepo   │◀─── (App Group) ──▶│   WidgetRepo         │
//  └──────────────┘                    └──────────────────────┘
//

import Foundation
import CoreLocation
import WidgetKit

// MARK: - Shared Data Models (Must match main app exactly)

/// Unified location data for widget sharing
/// NOTE: No 'public' modifiers needed - this is an app extension, not a framework
struct SharedLocation: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date

    init(latitude: Double, longitude: Double, timestamp: Date = Date()) {
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var isValid: Bool {
        latitude != 0 && longitude != 0
    }
}

/// Lightweight city data for widget display
/// Structure MUST match main app's WidgetCityData exactly
struct WidgetCityData: Codable, Identifiable, Equatable {
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

    // MARK: - Memberwise Initializer
    init(
        id: UUID = UUID(),
        name: String,
        countryCode: String,
        latitude: Double,
        longitude: Double,
        timeZoneIdentifier: String,
        fahrenheit: Double? = nil,
        lastUpdated: Date? = nil,
        isCurrentLocation: Bool = false,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.countryCode = countryCode
        self.latitude = latitude
        self.longitude = longitude
        self.timeZoneIdentifier = timeZoneIdentifier
        self.fahrenheit = fahrenheit
        self.lastUpdated = lastUpdated
        self.isCurrentLocation = isCurrentLocation
        self.sortOrder = sortOrder
    }

    var celsius: Double? {
        guard let f = fahrenheit else { return nil }
        return (f - 32) * 5 / 9
    }

    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .current
    }

    /// Check if it's daytime (6AM - 6PM) in this city
    var isDaytime: Bool {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let hour = calendar.component(.hour, from: Date())
        return hour >= 6 && hour < 18
    }

    /// Get formatted local time string
    func localTimeString() -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: Date())
    }

    /// Sample data for previews
    static let samples: [WidgetCityData] = [
        WidgetCityData(
            id: UUID(),
            name: "Phoenix",
            countryCode: "US",
            latitude: 33.4484,
            longitude: -112.0740,
            timeZoneIdentifier: "America/Phoenix",
            fahrenheit: 95,
            lastUpdated: Date(),
            isCurrentLocation: true,
            sortOrder: 0
        ),
        WidgetCityData(
            id: UUID(),
            name: "Tokyo",
            countryCode: "JP",
            latitude: 35.6762,
            longitude: 139.6503,
            timeZoneIdentifier: "Asia/Tokyo",
            fahrenheit: 72,
            lastUpdated: Date(),
            isCurrentLocation: false,
            sortOrder: 1
        ),
        WidgetCityData(
            id: UUID(),
            name: "London",
            countryCode: "GB",
            latitude: 51.5074,
            longitude: -0.1278,
            timeZoneIdentifier: "Europe/London",
            fahrenheit: 55,
            lastUpdated: Date(),
            isCurrentLocation: false,
            sortOrder: 2
        )
    ]
}

// MARK: - Widget Repository (Widget Extension Version)

/// Widget-side repository for reading/writing shared data
/// Provides single point of access to App Group data
final class WidgetRepository {

    // MARK: - Constants (Must match main app)

    /// App Group ID - MUST match in both targets' entitlements
    static let appGroupID = "group.alexisaraujo.alexisfarenheit"

    /// UserDefaults keys - Single source of truth
    private enum Keys {
        static let cities = "saved_cities"
        static let location = "widget_location"

        // Legacy keys for backwards compatibility
        static let legacyLatitude = "last_latitude"
        static let legacyLongitude = "last_longitude"
    }

    // MARK: - Singleton

    static let shared = WidgetRepository()

    // MARK: - Properties

    private let defaults: UserDefaults?
    private let logger = WidgetLogger.shared

    // MARK: - Init

    private init() {
        defaults = UserDefaults(suiteName: Self.appGroupID)

        if defaults == nil {
            logger.error("WidgetRepository: Cannot access App Group")
        }
    }

    // MARK: - Read Operations

    /// Get all saved cities (sorted by sortOrder)
    /// This is the SINGLE SOURCE OF TRUTH for widget data
    func getCities() -> [WidgetCityData] {
        guard let defaults = defaults else {
            logger.error("getCities: App Group not available")
            return []
        }

        // CRITICAL: Synchronize to get latest data from main app
        defaults.synchronize()

        guard let data = defaults.data(forKey: Keys.cities) else {
            logger.data("getCities: No data found")
            return []
        }

        do {
            let cities = try JSONDecoder().decode([WidgetCityData].self, from: data)
            logger.data("getCities: Loaded \(cities.count) cities")
            return cities.sorted { $0.sortOrder < $1.sortOrder }
        } catch {
            logger.error("getCities: Decode error - \(error.localizedDescription)")
            return []
        }
    }

    /// Get the primary city (first city, usually current location)
    func getPrimaryCity() -> WidgetCityData? {
        getCities().first
    }

    /// Get last known location
    func getLocation() -> SharedLocation? {
        guard let defaults = defaults else { return nil }

        defaults.synchronize()

        // Try new format first
        if let data = defaults.data(forKey: Keys.location) {
            do {
                return try JSONDecoder().decode(SharedLocation.self, from: data)
            } catch {
                // Fall through to legacy format
            }
        }

        // Fallback to legacy format
        let lat = defaults.double(forKey: Keys.legacyLatitude)
        let lon = defaults.double(forKey: Keys.legacyLongitude)

        guard lat != 0 && lon != 0 else { return nil }

        return SharedLocation(latitude: lat, longitude: lon)
    }

    /// Get age of primary city's data in minutes
    func getPrimaryCacheAgeMinutes() -> Double {
        guard let primary = getPrimaryCity(),
              let lastUpdate = primary.lastUpdated else {
            return Double.infinity
        }

        return Date().timeIntervalSince(lastUpdate) / 60
    }

    // MARK: - Write Operations

    /// Update primary city's temperature (called after WeatherKit fetch)
    /// Updates the single source of truth (saved_cities array)
    func updatePrimaryTemperature(fahrenheit: Double) {
        guard let defaults = defaults else {
            logger.error("updatePrimaryTemperature: App Group not available")
            return
        }

        var cities = getCities()

        guard !cities.isEmpty else {
            logger.warning("updatePrimaryTemperature: No cities to update")
            return
        }

        // Update first city (primary/current location)
        cities[0].fahrenheit = fahrenheit
        cities[0].lastUpdated = Date()

        // Save back to UserDefaults
        do {
            let data = try JSONEncoder().encode(cities)
            defaults.set(data, forKey: Keys.cities)
            defaults.synchronize()

            logger.data("updatePrimaryTemperature: \(cities[0].name) → \(Int(fahrenheit))°F")
        } catch {
            logger.error("updatePrimaryTemperature: Encode error - \(error.localizedDescription)")
        }
    }

    // MARK: - Diagnostic

    /// Check if App Group is accessible
    var isAppGroupAvailable: Bool {
        defaults != nil
    }
}
