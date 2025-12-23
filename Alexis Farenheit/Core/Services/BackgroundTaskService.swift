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

    /// Testable handler for Significant Location Changes.
    /// This isolates geocode + WeatherKit + persistence so we can TDD it without fighting BGTask/CLLocationManager.
    private let significantLocationHandler = SignificantLocationUpdateHandler()

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
        // Debug note:
        // If the user force-quits the app (swipe up), iOS will not run background location updates.
        SharedLogger.shared.info(
            "Starting significant location monitoring (note: force-quit disables background updates)",
            category: "Background"
        )
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
        // Delegate to testable handler (TDD coverage lives in AlexisFarenheitTests).
        // This updates App Group coords + saved_cities identity even if WeatherKit fails.
        Task {
            await significantLocationHandler.handleSignificantLocationChange(location)
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

        // We'll run our async work in a Task so we can cancel on expiration.
        var refreshTask: Task<Void, Never>?

        // Set up expiration handler
        task.expirationHandler = { [weak self] in
            print("🔄 Background task expired")
            SharedLogger.shared.warning("Background task expired", category: "Background")
            refreshTask?.cancel()
            self?.weatherService.cancelFetch()
        }

        // Fetch weather data for *current* location (best-effort) so the widget can follow travel.
        // Fallback: if we cannot get current location quickly, use last known App Group location.
        refreshTask = Task { [weak self] in
            guard let self else { return }

            // 1) Try current location (best-effort)
            if let currentLocation = await self.fetchCurrentLocationForBackgroundRefresh(timeoutSeconds: 10) {
                SharedLogger.shared.info(
                    "Background refresh: got current location (\(String(format: "%.4f", currentLocation.coordinate.latitude)), \(String(format: "%.4f", currentLocation.coordinate.longitude)))",
                    category: "Background"
                )

                // Reuse the same handler used for Significant Location Changes.
                // This updates widget_location + current city identity, then fetches WeatherKit (best-effort).
                await self.significantLocationHandler.handleSignificantLocationChange(currentLocation)

                SharedLogger.shared.widget("Background refresh: updated via current location ✅", category: "Background")
                task.setTaskCompleted(success: true)
                return
            } else {
                SharedLogger.shared.warning(
                    "Background refresh: could not get current location quickly; falling back to last known App Group location",
                    category: "Background"
                )
            }

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
            await self.weatherService.fetchWeather(for: clLocation)

            // Check if we got temperature (access @MainActor property safely)
            if let temp = await MainActor.run(body: { self.weatherService.currentTemperatureF }) {
                // Update saved_cities - single source of truth for widget
                await MainActor.run {
                    // Update current location city with new temperature
                    if let currentCity = self.cityStorage.currentLocationCity {
                        let updatedCity = currentCity.withWeather(fahrenheit: temp)
                        self.cityStorage.updateCity(updatedCity)
                    }
                }

                let cityName = await MainActor.run { self.cityStorage.currentLocationCity?.name ?? "Unknown" }
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

    /// Best-effort current location for BGAppRefresh.
    /// - Important: iOS may delay or deny location delivery in background depending on system state.
    /// - This is a fallback to improve travel updates when Significant Location Changes aren't delivered.
    private func fetchCurrentLocationForBackgroundRefresh(timeoutSeconds: TimeInterval) async -> CLLocation? {
        // Only attempt if we have Always authorization; otherwise it won't work reliably in background.
        let status = CLLocationManager().authorizationStatus
        guard status == .authorizedAlways else {
            SharedLogger.shared.warning(
                "Background refresh: skipping current-location request (auth: \(status.rawValue))",
                category: "Background"
            )
            return nil
        }

        do {
            let location = try await BackgroundOneShotLocationProvider().requestLocation(timeoutSeconds: timeoutSeconds)
            return location
        } catch {
            SharedLogger.shared.warning(
                "Background refresh: current-location request failed: \(error.localizedDescription)",
                category: "Background"
            )
            return nil
        }
    }

    /// Load last known location from WidgetRepository (App Group)
    /// Uses WidgetRepository as SINGLE SOURCE OF TRUTH
    private func loadLastKnownLocation() -> CLLocationCoordinate2D? {
        // REPOSITORY PATTERN: Read from WidgetRepository instead of direct UserDefaults
        guard let location = WidgetRepository.shared.getLocation() else {
            return nil
        }

        // Validate coordinates
        guard location.isValid else { return nil }

        return location.coordinate
    }
}

// MARK: - One-shot Location Provider (Background Refresh)

/// Small async wrapper around CLLocationManager.requestLocation() for BG refresh.
/// Keeps logic local to BackgroundTaskService and avoids coupling with the UI LocationService.
@MainActor
private final class BackgroundOneShotLocationProvider: NSObject, CLLocationManagerDelegate {

    enum LocationError: LocalizedError {
        case timeout
        case noLocation

        var errorDescription: String? {
            switch self {
            case .timeout: return "Location request timed out"
            case .noLocation: return "No location returned"
            }
        }
    }

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?
    private var isResolved = false

    func requestLocation(timeoutSeconds: TimeInterval) async throws -> CLLocation {
        // NOTE: iOS requires location services enabled.
        guard CLLocationManager.locationServicesEnabled() else {
            throw CLError(.denied)
        }

        // Configure for fast coarse fixes (good enough for city-level widgets).
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            // Fire request
            manager.requestLocation()

            // Timeout guard (best-effort)
            DispatchQueue.main.asyncAfter(deadline: .now() + timeoutSeconds) { [weak self] in
                self?.resolve(.failure(LocationError.timeout))
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else {
            resolve(.failure(LocationError.noLocation))
            return
        }
        resolve(.success(last))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        resolve(.failure(error))
    }

    private func resolve(_ result: Result<CLLocation, Error>) {
        guard !isResolved else { return }
        isResolved = true

        manager.delegate = nil

        switch result {
        case .success(let location):
            continuation?.resume(returning: location)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
        continuation = nil
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

