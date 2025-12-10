//
//  BackgroundTaskService.swift
//  Alexis Farenheit
//
//  Background task service to refresh widget data without opening the app.
//  Uses BGTaskScheduler to periodically fetch weather data and update the widget.
//  Also handles Significant Location Changes to update widget when user moves cities.
//

import Foundation
import BackgroundTasks
import CoreLocation
import os.log

/// Service to handle background app refresh for widget updates
/// Rule: iOS decides when to run these tasks based on usage patterns
final class BackgroundTaskService {

    // MARK: - Singleton
    static let shared = BackgroundTaskService()

    // MARK: - Constants
    /// Task identifier - must match Info.plist BGTaskSchedulerPermittedIdentifiers
    static let refreshTaskIdentifier = "alexisaraujo.AlexisFarenheit.refresh"

    // MARK: - Dependencies
    private let weatherService = WeatherService()
    private let cityStorage = CityStorageService.shared
    private let logger = Logger(subsystem: "alexisaraujo.AlexisFarenheit", category: "BackgroundTask")

    /// Location service for significant location changes (must keep strong reference)
    private var locationService: LocationService?

    // MARK: - Init
    private init() {
        print("🔄 BackgroundTaskService initialized")
        SharedLogger.shared.info("BackgroundTaskService initialized", category: "Background")
    }

    // MARK: - Significant Location Changes

    /// Setup background location monitoring.
    /// Creates a dedicated LocationService for monitoring significant location changes.
    /// Call this early in app lifecycle (init).
    func setupBackgroundLocationMonitoring() {
        // Create dedicated location service for background monitoring
        let bgLocationService = LocationService()
        self.locationService = bgLocationService

        // Set callback for when location changes significantly
        bgLocationService.onSignificantLocationChange = { [weak self] location in
            self?.handleSignificantLocationChange(location)
        }

        logger.info("🔄 Background location monitoring configured")
    }

    /// Start monitoring significant location changes (call when app goes to background)
    func startSignificantLocationMonitoring() {
        locationService?.startMonitoringSignificantLocationChanges()
        logger.debug("🔄 Started significant location monitoring")
    }

    /// Stop monitoring significant location changes (call when app enters foreground)
    func stopSignificantLocationMonitoring() {
        locationService?.stopMonitoringSignificantLocationChanges()
        logger.debug("🔄 Stopped significant location monitoring")
    }

    /// Handle significant location change - fetch weather and update widget
    private func handleSignificantLocationChange(_ location: CLLocation) {
        logger.info("🔄 Handling significant location change...")
        SharedLogger.shared.info("Significant location change - updating widget", category: "Background")

        // Save new coordinates to App Group immediately
        saveLocationToAppGroup(location)

        // Fetch weather for new location and update widget
        Task {
            await fetchWeatherAndUpdateWidget(for: location)
        }
    }

    /// Save location coordinates to App Group for widget access
    private func saveLocationToAppGroup(_ location: CLLocation) {
        guard let defaults = UserDefaults(suiteName: "group.alexisaraujo.alexisfarenheit") else {
            return
        }

        defaults.set(location.coordinate.latitude, forKey: "last_latitude")
        defaults.set(location.coordinate.longitude, forKey: "last_longitude")
        defaults.synchronize()

        logger.debug("🔄 Saved new location to App Group: \(location.coordinate.latitude), \(location.coordinate.longitude)")
    }

    /// Fetch weather for location and update widget
    /// Updates saved_cities which is the single source of truth for widgets
    private func fetchWeatherAndUpdateWidget(for location: CLLocation) async {
        // Reverse geocode to get city name and timezone
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            let cityName = placemarks.first?.locality
                ?? placemarks.first?.administrativeArea
                ?? "Unknown"
            let countryCode = placemarks.first?.isoCountryCode ?? ""
            let timeZoneId = placemarks.first?.timeZone?.identifier ?? TimeZone.current.identifier

            // Fetch weather
            await weatherService.fetchWeather(for: location)

            if let temp = await MainActor.run(body: { weatherService.currentTemperatureF }) {
                // Update saved_cities (single source of truth for widget)
                await MainActor.run {
                    // Create/update current location city
                    let currentLocationCity = CityModel(
                        name: cityName,
                        countryCode: countryCode,
                        latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude,
                        timeZoneIdentifier: timeZoneId,
                        fahrenheit: temp,
                        lastUpdated: Date(),
                        isCurrentLocation: true,
                        sortOrder: 0
                    )
                    cityStorage.updateCurrentLocation(currentLocationCity)
                }

                logger.info("🔄 Widget updated from significant location: \(cityName), \(Int(temp))°F")
                SharedLogger.shared.info("Widget updated: \(cityName), \(Int(temp))°F", category: "Background")
            }
        } catch {
            logger.error("🔄 Failed to geocode location: \(error.localizedDescription)")
        }
    }

    // MARK: - Public Methods

    /// Register background tasks with the system
    /// Must be called early in app lifecycle (e.g., didFinishLaunchingWithOptions)
    func registerBackgroundTasks() {
        // Debug: Registration attempt
        print("🔄 Registering background task: \(Self.refreshTaskIdentifier)")
        SharedLogger.shared.info("Registering background task", category: "Background")

        // Register the app refresh task
        let success = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.refreshTaskIdentifier,
            using: nil
        ) { [weak self] task in
            // Debug: Task execution started
            print("🔄 Background task executing...")
            SharedLogger.shared.widget("Background refresh task started", category: "Background")

            guard let bgTask = task as? BGAppRefreshTask else {
                print("🔄 Invalid task type")
                task.setTaskCompleted(success: false)
                return
            }

            self?.handleAppRefresh(task: bgTask)
        }

        if success {
            print("🔄 Background task registered successfully ✅")
            SharedLogger.shared.info("Background task registered ✅", category: "Background")
        } else {
            print("🔄 Background task registration failed ❌")
            SharedLogger.shared.error("Background task registration failed ❌", category: "Background")
        }
    }

    /// Schedule the next background refresh
    /// Call this after app goes to background or after a successful refresh
    func scheduleAppRefresh() {
        // Debug: Scheduling attempt
        print("🔄 Scheduling next background refresh...")

        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskIdentifier)

        // Schedule for 15 minutes from now (iOS may adjust this)
        // Note: iOS has minimum interval of ~15 minutes
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)

        do {
            try BGTaskScheduler.shared.submit(request)
            print("🔄 Background refresh scheduled for ~15 min from now ✅")
            SharedLogger.shared.info("Background refresh scheduled ✅", category: "Background")
        } catch {
            print("🔄 Failed to schedule background refresh: \(error.localizedDescription)")
            SharedLogger.shared.error("Schedule failed: \(error.localizedDescription)", category: "Background")
        }
    }

    /// Cancel all pending background tasks
    func cancelAllPendingTasks() {
        BGTaskScheduler.shared.cancelAllTaskRequests()
        print("🔄 All pending background tasks cancelled")
    }

    // MARK: - Private Methods

    /// Handle the background app refresh task
    /// Updates saved_cities which is the single source of truth for widgets
    private func handleAppRefresh(task: BGAppRefreshTask) {
        // Debug: Starting refresh
        SharedLogger.shared.widget("Handling background refresh", category: "Background")

        // Schedule the next refresh before we do anything
        scheduleAppRefresh()

        // Set up expiration handler
        task.expirationHandler = { [weak self] in
            print("🔄 Background task expired")
            SharedLogger.shared.warning("Background task expired", category: "Background")
            self?.weatherService.cancelFetch()
        }

        // Fetch weather data for last known location
        Task {
            // Get last known location from UserDefaults
            guard let location = loadLastKnownLocation() else {
                print("🔄 No last known location, completing task")
                SharedLogger.shared.warning("No location for background refresh", category: "Background")
                task.setTaskCompleted(success: false)
                return
            }

            // Fetch weather - create CLLocation from coordinates
            print("🔄 Fetching weather for background refresh...")
            SharedLogger.shared.info("Background: Fetching weather", category: "Background")

            let clLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
            await weatherService.fetchWeather(for: clLocation)

            // Check if we got temperature (access @MainActor property safely)
            if let temp = await MainActor.run(body: { weatherService.currentTemperatureF }) {
                // Update saved_cities - single source of truth for widget
                await MainActor.run {
                    // Update current location city with new temperature
                    if let currentCity = cityStorage.currentLocationCity {
                        let updatedCity = currentCity.withWeather(fahrenheit: temp)
                        cityStorage.updateCity(updatedCity)
                    }
                }

                let cityName = await MainActor.run { cityStorage.currentLocationCity?.name ?? "Unknown" }
                print("🔄 Background refresh complete: \(cityName), \(Int(temp))°F ✅")
                SharedLogger.shared.widget("Background refresh: \(cityName), \(Int(temp))°F ✅", category: "Background")

                task.setTaskCompleted(success: true)
            } else {
                print("🔄 Background refresh failed - no temperature")
                SharedLogger.shared.error("Background refresh: No temperature", category: "Background")
                task.setTaskCompleted(success: false)
            }
        }
    }

    // MARK: - Location Helpers

    /// Load last known location from UserDefaults (App Group)
    private func loadLastKnownLocation() -> CLLocationCoordinate2D? {
        guard let defaults = UserDefaults(suiteName: "group.alexisaraujo.alexisfarenheit") else {
            return nil
        }

        let lat = defaults.double(forKey: "last_latitude")
        let lon = defaults.double(forKey: "last_longitude")

        // Check if we have valid coordinates
        guard lat != 0 && lon != 0 else { return nil }

        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

// MARK: - WeatherService Extension for Background Tasks

extension WeatherService {
    /// Cancel any ongoing fetch (for task expiration)
    func cancelFetch() {
        // Currently no cancellation mechanism, but could add one
        print("🌤️ Weather fetch cancellation requested")
    }
}

