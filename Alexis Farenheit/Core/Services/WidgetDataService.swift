import Foundation
import WidgetKit
import os.log

/// Service for sharing weather data between main app and widget via App Group.
///
/// ARCHITECTURE NOTE (Repository Pattern):
/// This service is now a thin wrapper around WidgetRepository, which is the
/// SINGLE SOURCE OF TRUTH for all widget data. This maintains backwards
/// compatibility with existing code while using the new unified data layer.
///
/// Data Flow:
/// ┌────────────────┐     ┌───────────────────┐     ┌────────────────┐
/// │ HomeViewModel  │────▶│ WidgetDataService │────▶│ WidgetRepository│
/// │                │     │   (wrapper)       │     │ (single source)│
/// └────────────────┘     └───────────────────┘     └────────────────┘
///
final class WidgetDataService {

    /// App Group identifier - delegates to WidgetRepository
    static var appGroupID: String {
        WidgetRepository.appGroupID
    }

    /// Widget kind identifier - must match Widget definition
    static let widgetKind = "AlexisExtensionFarenheit"

    // MARK: - Singleton
    static let shared = WidgetDataService()

    /// Reference to the actual repository (single source of truth)
    private let repository = WidgetRepository.shared

    private init() {
        logInfo("WidgetDataService initialized (wrapper for WidgetRepository)", category: "Widget")
    }

    // MARK: - Public Methods

    /// Check if App Group is accessible
    func isAppGroupAvailable() -> Bool {
        repository.isAppGroupAvailable
    }

    /// Save temperature data for widget and trigger reload
    /// NOTE: This method is kept for backwards compatibility.
    /// New code should use CityStorageService.updateWeather() instead,
    /// which updates saved_cities directly.
    func saveTemperature(city: String, country: String, fahrenheit: Double) {
        // Performance tracking: Start widget data save
        PerformanceMonitor.shared.startOperation("WidgetDataSave", category: "Widget", metadata: ["city": city])

        // REPOSITORY PATTERN: Update via repository
        // This ensures all data stays in sync (saved_cities is updated)
        repository.updatePrimaryTemperature(fahrenheit: fahrenheit)

        logInfo("Saved to widget via repository: \(city), \(Int(fahrenheit))°F", category: "Widget")

        // Performance tracking: End widget data save
        PerformanceMonitor.shared.endOperation("WidgetDataSave", category: "Widget", metadata: ["city": city, "temperature": String(format: "%.1f", fahrenheit)])

        // Small delay to ensure UserDefaults is synced across processes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.reloadWidget()
        }
    }

    /// Force widget to reload its timeline
    func reloadWidget() {
        // Performance tracking: Start widget reload
        PerformanceMonitor.shared.startOperation("WidgetReload", category: "Widget")

        logInfo("Requesting widget reload", category: "Widget")

        // Delegate to repository (which handles throttling)
        repository.forceReloadWidgets()

        logInfo("Widget reload triggered via repository", category: "Widget")

        // Performance tracking: End widget reload
        PerformanceMonitor.shared.endOperation("WidgetReload", category: "Widget")
    }

    /// Load cached temperature data
    /// Returns data from repository (single source of truth)
    func loadTemperature() -> (city: String, country: String, fahrenheit: Double, lastUpdate: Date)? {
        guard let primary = repository.getPrimaryCity(),
              let temp = primary.fahrenheit else {
            return nil
        }

        return (primary.name, primary.countryCode, temp, primary.lastUpdated ?? Date())
    }

    // MARK: - New Repository-Based Methods

    /// Get all cities from repository
    func getCities() -> [WidgetCityData] {
        repository.getCities()
    }

    /// Save location to repository
    func saveLocation(latitude: Double, longitude: Double) {
        let location = SharedLocation(latitude: latitude, longitude: longitude)
        repository.saveLocation(location)
    }

    /// Get diagnostic info
    func getDiagnosticInfo() -> String {
        repository.getDiagnosticInfo()
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
