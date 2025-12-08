import Foundation
import WidgetKit
import os.log

/// Service for sharing weather data between main app and widget via App Group.
/// Uses UserDefaults in shared container so widget can read current temperature.
/// Logs all operations to SharedLogger for debugging.
final class WidgetDataService {

    /// App Group identifier - must match in both app and widget entitlements
    static let appGroupID = "group.alexisaraujo.alexisfarenheit"

    /// Widget kind identifier - must match Widget definition
    static let widgetKind = "AlexisExtensionFarenheit"

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
        logInfo("WidgetDataService initialized", category: "Widget")

        if sharedDefaults == nil {
            logError("App Group not accessible: \(Self.appGroupID)", category: "Widget")
        }
    }

    // MARK: - Public Methods

    /// Check if App Group is accessible
    func isAppGroupAvailable() -> Bool {
        sharedDefaults != nil
    }

    /// Save temperature data for widget and trigger reload
    func saveTemperature(city: String, country: String, fahrenheit: Double) {
        guard let defaults = sharedDefaults else {
            logError("Cannot save - App Group not available", category: "Widget")
            return
        }

        defaults.set(city, forKey: Keys.city)
        defaults.set(country, forKey: Keys.country)
        defaults.set(fahrenheit, forKey: Keys.fahrenheit)
        defaults.set(Date().timeIntervalSince1970, forKey: Keys.lastUpdate)
        defaults.synchronize()

        logInfo("Saved to widget: \(city), \(Int(fahrenheit))°F", category: "Widget")

        // Reload widget
        reloadWidget()
    }

    /// Force widget to reload its timeline
    func reloadWidget() {
        logInfo("Requesting widget reload (kind: \(Self.widgetKind))", category: "Widget")

        WidgetCenter.shared.reloadTimelines(ofKind: Self.widgetKind)

        // Check current widget configurations
        WidgetCenter.shared.getCurrentConfigurations { [weak self] result in
            switch result {
            case .success(let widgets):
                if widgets.isEmpty {
                    self?.logWarning("No widgets on home screen", category: "Widget")
                } else {
                    for widget in widgets {
                        self?.logInfo("Widget active: \(widget.kind), family: \(widget.family.description)", category: "Widget")
                    }
                }
            case .failure(let error):
                self?.logError("Failed to get widget configs: \(error.localizedDescription)", category: "Widget")
            }
        }
    }

    /// Load cached temperature data
    func loadTemperature() -> (city: String, country: String, fahrenheit: Double, lastUpdate: Date)? {
        guard let defaults = sharedDefaults else { return nil }

        let city = defaults.string(forKey: Keys.city) ?? ""
        let country = defaults.string(forKey: Keys.country) ?? ""
        let fahrenheit = defaults.double(forKey: Keys.fahrenheit)
        let lastUpdate = defaults.double(forKey: Keys.lastUpdate)

        guard !city.isEmpty, lastUpdate > 0 else { return nil }

        return (city, country, fahrenheit, Date(timeIntervalSince1970: lastUpdate))
    }

    // MARK: - Private Logging (using SharedLogger)

    private func logInfo(_ message: String, category: String) {
        SharedLogger.shared.info(message, category: category)
    }

    private func logWarning(_ message: String, category: String) {
        SharedLogger.shared.warning(message, category: category)
    }

    private func logError(_ message: String, category: String) {
        SharedLogger.shared.error(message, category: category)
    }
}
