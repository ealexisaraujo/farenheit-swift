import Foundation
import Combine
import CoreLocation
import SwiftUI
import WidgetKit
import os.log

/// Service for persisting and managing saved cities
/// Uses UserDefaults with App Group for widget access
final class CityStorageService: ObservableObject {
    static let shared = CityStorageService()

    private let logger = Logger(subsystem: "com.alexis.farenheit", category: "CityStorage")
    private let defaults: UserDefaults?
    private let citiesKey = "saved_cities"

    /// Published list of saved cities, sorted by sortOrder
    @Published private(set) var cities: [CityModel] = []

    /// Maximum cities allowed
    let maxCities = CityModel.maxCities

    /// Check if we can add more cities
    var canAddCity: Bool {
        cities.count < maxCities
    }

    /// Number of remaining slots
    var remainingSlots: Int {
        max(0, maxCities - cities.count)
    }

    // MARK: - Init

    private init() {
        defaults = UserDefaults(suiteName: "group.alexisaraujo.alexisfarenheit")
        loadCities()
        logger.debug("🏙️ CityStorageService initialized with \(self.cities.count) cities")
    }

    // MARK: - CRUD Operations

    /// Add a new city to the list
    @discardableResult
    func addCity(_ city: CityModel) -> Bool {
        guard canAddCity else {
            logger.warning("🏙️ Cannot add city - max limit reached (\(self.maxCities))")
            return false
        }

        // Check for duplicates (same coordinates within ~1km)
        let isDuplicate = cities.contains { existing in
            let distance = existing.location.distance(from: city.location)
            return distance < 1000 // 1km threshold
        }

        if isDuplicate {
            logger.warning("🏙️ City already exists: \(city.name)")
            return false
        }

        var newCity = city
        newCity.sortOrder = cities.count

        cities.append(newCity)
        saveCities()

        logger.info("🏙️ Added city: \(city.name) at position \(newCity.sortOrder)")
        return true
    }

    /// Update an existing city (e.g., with new weather data)
    /// Reloads widgets (throttled to avoid spam)
    func updateCity(_ city: CityModel) {
        guard let index = cities.firstIndex(where: { $0.id == city.id }) else {
            logger.warning("🏙️ City not found for update: \(city.name)")
            return
        }

        cities[index] = city
        saveCities() // Reload widgets (throttled internally)
    }

    /// Update weather for a specific city
    func updateWeather(for cityId: UUID, fahrenheit: Double) {
        guard let index = cities.firstIndex(where: { $0.id == cityId }) else {
            return
        }

        cities[index] = cities[index].withWeather(fahrenheit: fahrenheit)
        saveCities() // Reload widgets (throttled internally)
    }

    /// Remove a city by ID (cannot remove current location)
    func removeCity(id: UUID) {
        guard let city = cities.first(where: { $0.id == id }) else { return }

        // Prevent removing current location
        if city.isCurrentLocation {
            logger.warning("🏙️ Cannot remove current location city")
            return
        }

        cities.removeAll { $0.id == id }
        reorderCities()
        saveCities()

        logger.info("🏙️ Removed city: \(city.name)")
    }

    /// Remove city at index (cannot remove index 0 if it's current location)
    func removeCity(at index: Int) {
        guard index >= 0 && index < cities.count else { return }

        let city = cities[index]
        if city.isCurrentLocation {
            logger.warning("🏙️ Cannot remove current location city")
            return
        }

        cities.remove(at: index)
        reorderCities()
        saveCities()

        logger.info("🏙️ Removed city at index \(index): \(city.name)")
    }

    /// Move city from one position to another
    func moveCity(from source: IndexSet, to destination: Int) {
        // Prevent moving the current location city from position 0
        if source.contains(0) && cities.first?.isCurrentLocation == true {
            logger.warning("🏙️ Cannot move current location city")
            return
        }

        // Prevent moving to position 0 if current location is there
        if destination == 0 && cities.first?.isCurrentLocation == true {
            logger.warning("🏙️ Cannot move city to position 0 (current location)")
            return
        }

        cities.move(fromOffsets: source, toOffset: destination)
        reorderCities()
        saveCities()

        logger.debug("🏙️ Reordered cities")
    }

    /// Update or create current location city
    /// Forces widget reload because city name change is a critical update
    func updateCurrentLocation(_ city: CityModel) {
        if let existingIndex = cities.firstIndex(where: { $0.isCurrentLocation }) {
            // Update existing current location - create new city with existing ID
            let existingId = cities[existingIndex].id
            let updatedCity = CityModel(
                id: existingId,
                name: city.name,
                countryCode: city.countryCode,
                latitude: city.latitude,
                longitude: city.longitude,
                timeZoneIdentifier: city.timeZoneIdentifier,
                fahrenheit: city.fahrenheit,
                lastUpdated: city.lastUpdated,
                isCurrentLocation: true,
                sortOrder: 0
            )
            cities[existingIndex] = updatedCity
        } else {
            // Insert at beginning
            var newCity = city
            newCity.sortOrder = 0
            cities.insert(newCity, at: 0)
            reorderCities()
        }

        // Force reload because city name change is critical for widget display
        saveCities(forceReload: true)
        logger.info("🏙️ Updated current location: \(city.name)")
    }

    /// Clear all cities except current location
    func clearSavedCities() {
        cities = cities.filter { $0.isCurrentLocation }
        saveCities()
        logger.info("🏙️ Cleared all saved cities")
    }

    // MARK: - Persistence

    /// Track last widget reload to avoid spamming
    private var lastWidgetReload: Date?
    private let widgetReloadThrottle: TimeInterval = 10 // Min 10 seconds between reloads

    /// Save cities to storage and optionally reload widgets
    /// - Parameters:
    ///   - reloadWidgets: Whether to reload widgets (default true)
    ///   - forceReload: If true, bypasses throttling for critical updates like city changes
    private func saveCities(reloadWidgets: Bool = true, forceReload: Bool = false) {
        do {
            let data = try JSONEncoder().encode(cities)
            defaults?.set(data, forKey: citiesKey)
            defaults?.synchronize()

            // Only reload widgets if requested
            if reloadWidgets {
                let now = Date()
                let shouldThrottle = !forceReload &&
                    lastWidgetReload != nil &&
                    now.timeIntervalSince(lastWidgetReload!) < widgetReloadThrottle

                if shouldThrottle {
                    // logger.debug("🏙️ Skipping widget reload - throttled")
                } else {
                    WidgetCenter.shared.reloadAllTimelines()
                    lastWidgetReload = now
                    logger.debug("🏙️ Triggered widget reload\(forceReload ? " (forced)" : "")")
                }
            }
        } catch {
            logger.error("🏙️ Failed to save cities: \(error.localizedDescription)")
        }
    }

    private func loadCities() {
        guard let data = defaults?.data(forKey: citiesKey) else {
            logger.debug("🏙️ No saved cities found")
            return
        }

        do {
            cities = try JSONDecoder().decode([CityModel].self, from: data)
            cities.sort { $0.sortOrder < $1.sortOrder }
            logger.debug("🏙️ Loaded \(self.cities.count) cities from storage")
        } catch {
            logger.error("🏙️ Failed to load cities: \(error.localizedDescription)")
            cities = []
        }
    }

    /// Reorder cities to ensure consecutive sort orders
    private func reorderCities() {
        for (index, _) in cities.enumerated() {
            cities[index].sortOrder = index
        }
    }

    // MARK: - Queries

    /// Get city by ID
    func city(withId id: UUID) -> CityModel? {
        cities.first { $0.id == id }
    }

    /// Get current location city
    var currentLocationCity: CityModel? {
        cities.first { $0.isCurrentLocation }
    }

    /// Get all non-current-location cities
    var savedCities: [CityModel] {
        cities.filter { !$0.isCurrentLocation }
    }
}
