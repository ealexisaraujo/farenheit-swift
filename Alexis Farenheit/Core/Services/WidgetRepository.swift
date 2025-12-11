//
//  WidgetRepository.swift
//  Alexis Farenheit
//
//  Single source of truth for all widget-related data.
//  Implements the Repository Pattern to eliminate data duplication.
//
//  ARCHITECTURE:
//  ┌─────────────────┐     ┌─────────────────────────┐     ┌──────────────────┐
//  │   Main App      │────▶│   WidgetRepository      │◀────│   Widget Ext     │
//  │ (HomeViewModel) │     │  (Single Source)        │     │ (Provider)       │
//  └─────────────────┘     └───────────┬─────────────┘     └──────────────────┘
//                                      │
//                                      ▼
//                          ┌─────────────────────────┐
//                          │   App Group (UserDef)   │
//                          │   - saved_cities (JSON) │
//                          │   - widget_location     │
//                          └─────────────────────────┘
//
//  USAGE:
//  - App: WidgetRepository.shared.updatePrimaryTemperature(fahrenheit: 72.0)
//  - Widget: WidgetRepository.shared.getPrimaryCity()
//

import Foundation
import CoreLocation
import WidgetKit
import os.log

// MARK: - Shared Data Model

/// Unified location data for widget sharing
/// Encapsulates coordinates to avoid scattered lat/lon keys
public struct SharedLocation: Codable, Equatable {
    public let latitude: Double
    public let longitude: Double
    public let timestamp: Date

    public init(latitude: Double, longitude: Double, timestamp: Date = Date()) {
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
    }

    public init(coordinate: CLLocationCoordinate2D, timestamp: Date = Date()) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.timestamp = timestamp
    }

    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    public var isValid: Bool {
        latitude != 0 && longitude != 0
    }
}

/// Lightweight city data for widget display
/// Mirrors CityModel but without heavy dependencies
public struct WidgetCityData: Codable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var countryCode: String
    public var latitude: Double
    public var longitude: Double
    public var timeZoneIdentifier: String
    public var fahrenheit: Double?
    public var lastUpdated: Date?
    public var isCurrentLocation: Bool
    public var sortOrder: Int

    // MARK: - Public Memberwise Initializer
    // Required because Swift's synthesized init is internal for public structs
    public init(
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

    public var celsius: Double? {
        guard let f = fahrenheit else { return nil }
        return (f - 32) * 5 / 9
    }

    public var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .current
    }

    /// Check if it's daytime (6AM - 6PM) in this city
    public var isDaytime: Bool {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let hour = calendar.component(.hour, from: Date())
        return hour >= 6 && hour < 18
    }

    /// Get formatted local time string
    public func localTimeString() -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: Date())
    }
}

// MARK: - Widget Repository Protocol

/// Protocol for accessing widget data
/// Enables testing and alternative implementations
public protocol WidgetRepositoryProtocol {
    // MARK: - Read Operations
    func getCities() -> [WidgetCityData]
    func getPrimaryCity() -> WidgetCityData?
    func getLocation() -> SharedLocation?

    // MARK: - Write Operations
    func saveCities(_ cities: [WidgetCityData])
    func updatePrimaryTemperature(fahrenheit: Double)
    func updateCityTemperature(cityId: UUID, fahrenheit: Double)
    func saveLocation(_ location: SharedLocation)

    // MARK: - Widget Control
    func reloadWidgets()
}

// MARK: - Widget Repository Implementation

/// Concrete implementation of WidgetRepository
/// Uses App Group UserDefaults for cross-process data sharing
public final class WidgetRepository: WidgetRepositoryProtocol {

    // MARK: - Constants

    /// App Group ID - MUST match in both targets' entitlements
    public static let appGroupID = "group.alexisaraujo.alexisfarenheit"

    /// UserDefaults keys - Single source of truth
    private enum Keys {
        static let cities = "saved_cities"        // [WidgetCityData] - PRIMARY DATA
        static let location = "widget_location"   // SharedLocation - Last known location
    }

    // MARK: - Singleton

    public static let shared = WidgetRepository()

    // MARK: - Properties

    private let defaults: UserDefaults?
    private let logger = Logger(subsystem: "com.alexis.farenheit", category: "WidgetRepository")

    /// Throttle widget reloads to avoid spamming
    private var lastReload: Date?
    private let reloadThrottle: TimeInterval = 5 // Min 5 seconds between reloads

    // MARK: - Init

    private init() {
        defaults = UserDefaults(suiteName: Self.appGroupID)

        if defaults == nil {
            logger.error("❌ WidgetRepository: Cannot access App Group '\(Self.appGroupID)'")
        } else {
            logger.debug("✅ WidgetRepository initialized")
        }
    }

    /// Designated initializer for testing
    internal init(userDefaults: UserDefaults?) {
        self.defaults = userDefaults
    }

    // MARK: - Read Operations

    /// Get all saved cities
    /// Returns empty array if no data or decoding fails
    public func getCities() -> [WidgetCityData] {
        guard let defaults = defaults else {
            logger.error("getCities: App Group not available")
            return []
        }

        // IMPORTANT: Synchronize to get latest data from other processes
        defaults.synchronize()

        guard let data = defaults.data(forKey: Keys.cities) else {
            logger.debug("getCities: No data found")
            return []
        }

        do {
            let cities = try JSONDecoder().decode([WidgetCityData].self, from: data)
            logger.debug("getCities: Loaded \(cities.count) cities")
            return cities.sorted { $0.sortOrder < $1.sortOrder }
        } catch {
            logger.error("getCities: Decode error - \(error.localizedDescription)")
            return []
        }
    }

    /// Get the primary city (first city, usually current location)
    /// Returns nil if no cities saved
    public func getPrimaryCity() -> WidgetCityData? {
        getCities().first
    }

    /// Get last known location
    /// Returns nil if no location saved
    public func getLocation() -> SharedLocation? {
        guard let defaults = defaults else { return nil }

        defaults.synchronize()

        guard let data = defaults.data(forKey: Keys.location) else {
            return nil
        }

        do {
            return try JSONDecoder().decode(SharedLocation.self, from: data)
        } catch {
            logger.warning("getLocation: Decode error - \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Write Operations

    /// Save cities array to storage
    /// Triggers widget reload if data changed
    public func saveCities(_ cities: [WidgetCityData]) {
        guard let defaults = defaults else {
            logger.error("saveCities: App Group not available")
            return
        }

        do {
            let data = try JSONEncoder().encode(cities)
            defaults.set(data, forKey: Keys.cities)
            defaults.synchronize()

            logger.debug("saveCities: Saved \(cities.count) cities")

            reloadWidgets()
        } catch {
            logger.error("saveCities: Encode error - \(error.localizedDescription)")
        }
    }

    /// Update ONLY the primary city's temperature
    /// This is the most common operation from widget fresh fetch
    public func updatePrimaryTemperature(fahrenheit: Double) {
        var cities = getCities()

        guard !cities.isEmpty else {
            logger.warning("updatePrimaryTemperature: No cities to update")
            return
        }

        // Update first city (primary/current location)
        cities[0].fahrenheit = fahrenheit
        cities[0].lastUpdated = Date()

        // Save WITHOUT triggering widget reload (caller handles that)
        saveWithoutReload(cities)

        logger.debug("updatePrimaryTemperature: Updated to \(Int(fahrenheit))°F")
    }

    /// Update a specific city's temperature
    public func updateCityTemperature(cityId: UUID, fahrenheit: Double) {
        var cities = getCities()

        guard let index = cities.firstIndex(where: { $0.id == cityId }) else {
            logger.warning("updateCityTemperature: City not found")
            return
        }

        cities[index].fahrenheit = fahrenheit
        cities[index].lastUpdated = Date()

        saveCities(cities)

        logger.debug("updateCityTemperature: Updated \(cities[index].name) to \(Int(fahrenheit))°F")
    }

    /// Save location to storage
    public func saveLocation(_ location: SharedLocation) {
        guard let defaults = defaults else { return }

        do {
            let data = try JSONEncoder().encode(location)
            defaults.set(data, forKey: Keys.location)
            defaults.synchronize()

            logger.debug("saveLocation: \(location.latitude), \(location.longitude)")
        } catch {
            logger.error("saveLocation: Encode error - \(error.localizedDescription)")
        }
    }

    // MARK: - Widget Control

    /// Reload all widget timelines (throttled)
    public func reloadWidgets() {
        let now = Date()

        // Throttle reloads
        if let lastReload = lastReload,
           now.timeIntervalSince(lastReload) < reloadThrottle {
            logger.debug("reloadWidgets: Throttled")
            return
        }

        WidgetCenter.shared.reloadAllTimelines()
        lastReload = now

        logger.debug("reloadWidgets: Triggered")
    }

    /// Force reload widgets (bypasses throttle)
    public func forceReloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
        lastReload = Date()
        logger.debug("reloadWidgets: Forced")
    }

    // MARK: - Private Helpers

    /// Save without triggering widget reload (used for incremental updates)
    private func saveWithoutReload(_ cities: [WidgetCityData]) {
        guard let defaults = defaults else { return }

        do {
            let data = try JSONEncoder().encode(cities)
            defaults.set(data, forKey: Keys.cities)
            defaults.synchronize()
        } catch {
            logger.error("saveWithoutReload: Error - \(error.localizedDescription)")
        }
    }

    // MARK: - Diagnostic

    /// Check if App Group is properly configured
    public var isAppGroupAvailable: Bool {
        defaults != nil
    }

    /// Get diagnostic info for debugging
    public func getDiagnosticInfo() -> String {
        let cities = getCities()
        let location = getLocation()

        return """
        WidgetRepository Diagnostic:
        - App Group: \(isAppGroupAvailable ? "✅" : "❌")
        - Cities: \(cities.count)
        - Primary City: \(cities.first?.name ?? "None")
        - Primary Temp: \(cities.first?.fahrenheit.map { "\(Int($0))°F" } ?? "None")
        - Location: \(location.map { "\($0.latitude), \($0.longitude)" } ?? "None")
        """
    }
}

// MARK: - Extension for CityModel Conversion

extension WidgetCityData {
    /// Create WidgetCityData from CityModel
    /// Used when app needs to save to widget
    init(from cityModel: CityModel) {
        self.init(
            id: cityModel.id,
            name: cityModel.name,
            countryCode: cityModel.countryCode,
            latitude: cityModel.latitude,
            longitude: cityModel.longitude,
            timeZoneIdentifier: cityModel.timeZoneIdentifier,
            fahrenheit: cityModel.fahrenheit,
            lastUpdated: cityModel.lastUpdated,
            isCurrentLocation: cityModel.isCurrentLocation,
            sortOrder: cityModel.sortOrder
        )
    }
}
