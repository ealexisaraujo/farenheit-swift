import Foundation
import WidgetKit
import os.log

/// Service for sharing weather data between main app and widget via App Group.
/// Uses UserDefaults in shared container so widget can read current temperature.
final class WidgetDataService {
    private let logger = Logger(subsystem: "com.alexis.farenheit", category: "WidgetData")

    /// App Group identifier - must match in both app and widget entitlements
    static let appGroupID = "group.alexisaraujo.alexisfarenheit"

    // MARK: - Keys
    private enum Keys {
        static let city = "widget_city"
        static let country = "widget_country"
        static let fahrenheit = "widget_fahrenheit"
        static let lastUpdate = "widget_last_update"
    }

    // MARK: - Singleton
    static let shared = WidgetDataService()

    /// Shared UserDefaults for App Group
    private var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: Self.appGroupID)
    }

    private init() {
        logger.debug("📦 WidgetDataService initialized")

        if sharedDefaults == nil {
            logger.error("📦 App Group not accessible!")
        }
    }

    // MARK: - Public Methods

    /// Check if App Group is accessible
    func isAppGroupAvailable() -> Bool {
        sharedDefaults != nil
    }

    /// Save temperature data for widget
    func saveTemperature(city: String, country: String, fahrenheit: Double) {
        guard let defaults = sharedDefaults else {
            logger.error("📦 Cannot save - App Group not available")
            return
        }

        defaults.set(city, forKey: Keys.city)
        defaults.set(country, forKey: Keys.country)
        defaults.set(fahrenheit, forKey: Keys.fahrenheit)
        defaults.set(Date().timeIntervalSince1970, forKey: Keys.lastUpdate)
        defaults.synchronize()

        logger.debug("📦 Saved: \(city), \(fahrenheit)°F")

        // Tell WidgetKit to refresh all widgets
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Load cached temperature data
    func loadTemperature() -> (city: String, country: String, fahrenheit: Double)? {
        guard let defaults = sharedDefaults else { return nil }

        let city = defaults.string(forKey: Keys.city) ?? ""
        let country = defaults.string(forKey: Keys.country) ?? ""
        let fahrenheit = defaults.double(forKey: Keys.fahrenheit)
        let lastUpdate = defaults.double(forKey: Keys.lastUpdate)

        // Check if we have valid data
        guard !city.isEmpty, lastUpdate > 0 else { return nil }

        return (city, country, fahrenheit)
    }
}
