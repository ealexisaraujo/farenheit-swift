//
//  BackgroundTaskService.swift
//  Alexis Farenheit
//
//  Background task service to refresh widget data without opening the app.
//  Uses BGTaskScheduler to periodically fetch weather data and update the widget.
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
    private let widgetDataService = WidgetDataService.shared
    private let logger = Logger(subsystem: "alexisaraujo.AlexisFarenheit", category: "BackgroundTask")

    // MARK: - Init
    private init() {
        print("🔄 BackgroundTaskService initialized")
        SharedLogger.shared.info("BackgroundTaskService initialized", category: "Background")
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
                // Save to widget
                let city = loadLastKnownCity() ?? "Unknown"
                let country = loadLastKnownCountry() ?? ""

                widgetDataService.saveTemperature(city: city, country: country, fahrenheit: temp)

                print("🔄 Background refresh complete: \(city), \(Int(temp))°F ✅")
                SharedLogger.shared.widget("Background refresh: \(city), \(Int(temp))°F ✅", category: "Background")

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

    /// Load last known city from UserDefaults
    private func loadLastKnownCity() -> String? {
        UserDefaults(suiteName: "group.alexisaraujo.alexisfarenheit")?.string(forKey: "widget_city")
    }

    /// Load last known country from UserDefaults
    private func loadLastKnownCountry() -> String? {
        UserDefaults(suiteName: "group.alexisaraujo.alexisfarenheit")?.string(forKey: "widget_country")
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

