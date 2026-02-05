import Foundation
import Combine
import CoreLocation
import MapKit
import SwiftUI
import os.log

actor WeatherRefreshCoordinator {
    typealias TemperatureLoader = @Sendable (_ latitude: Double, _ longitude: Double) async -> Double?
    private var inFlight: [UUID: Task<Double?, Never>] = [:]

    func temperature(for city: CityModel, loader: @escaping TemperatureLoader) async -> Double? {
        if let existingTask = inFlight[city.id] {
            return await existingTask.value
        }

        let task = Task { await loader(city.latitude, city.longitude) }
        inFlight[city.id] = task

        let result = await task.value
        inFlight[city.id] = nil
        return result
    }
}

/// Main ViewModel for the home screen - manages temperature, location, and multi-city state.
/// Follows MVVM pattern with Combine bindings.
/// Auto-refreshes weather on foreground and tracks last update time.
@MainActor
final class HomeViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.alexis.farenheit", category: "HomeVM")

    // MARK: - Published Properties

    /// Manual temperature input from slider for conversion display only
    @Published var manualFahrenheit: Double = 72

    /// City name from location or search (legacy - for backward compatibility)
    @Published var selectedCity: String = "Detecting..."

    /// Country code (ISO format) (legacy - for backward compatibility)
    @Published var selectedCountry: String = ""

    /// Current temperature from WeatherKit (nil if not fetched yet) (legacy)
    @Published var currentFahrenheit: Double?

    /// Error message to display to user
    @Published var errorMessage: String?

    /// Location authorization status
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    /// Loading state for weather fetch
    @Published var isLoadingWeather: Bool = false

    /// Last time weather was successfully updated
    @Published var lastUpdateTime: Date?

    // MARK: - Multi-City Properties

    /// All saved cities with weather data
    @Published var cities: [CityModel] = []

    /// Currently loading cities (by ID)
    @Published var loadingCityIds: Set<UUID> = []

    /// The time zone service for managing time slider
    @Published var timeService = TimeZoneService.shared

    /// The city storage service
    private let cityStorage = CityStorageService.shared
    private let widgetRepository = WidgetRepository.shared

    // MARK: - Services

    private let locationService = LocationService()
    private let weatherService = WeatherService()
    private let refreshCoordinator = WeatherRefreshCoordinator()
    private var cancellables = Set<AnyCancellable>()

    /// Minimum interval between automatic refreshes (5 minutes)
    private let minimumRefreshInterval: TimeInterval = 5 * 60

    /// Track if initial setup is complete to avoid duplicate fetches
    private var hasCompletedInitialLoad = false

    /// Track last fetch time per city to avoid duplicates
    private var lastFetchTime: [UUID: Date] = [:]

    /// Minimum interval between fetches for the same city (30 seconds)
    private let minimumFetchInterval: TimeInterval = 30
    private let staleDataThreshold: TimeInterval = 15 * 60

    // MARK: - Computed Properties

    /// Display temperature for the main card - uses WeatherKit value if available
    var displayFahrenheit: Double {
        currentFahrenheit ?? manualFahrenheit
    }

    /// Celsius conversion of display temperature
    var displayCelsius: Double {
        (displayFahrenheit - 32) * 5 / 9
    }

    /// Celsius conversion of manual slider value
    var manualCelsius: Double {
        (manualFahrenheit - 32) * 5 / 9
    }

    /// Check if enough time has passed to allow auto-refresh
    private var canAutoRefresh: Bool {
        guard let lastUpdate = lastUpdateTime else { return true }
        return Date().timeIntervalSince(lastUpdate) >= minimumRefreshInterval
    }

    /// Primary city (current location or first in list)
    var primaryCity: CityModel? {
        cities.first
    }

    /// Whether we can add more cities
    var canAddCity: Bool {
        cities.count < CityModel.maxCities
    }

    /// Remaining city slots
    var remainingCitySlots: Int {
        max(0, CityModel.maxCities - cities.count)
    }

    /// Freshness for current location card in "Today Snapshot"
    var primaryCityFreshness: CityWeatherFreshness {
        guard let primaryCity else { return .unavailable }
        return freshness(for: primaryCity)
    }

    /// Widget confidence status shown in the home snapshot.
    var widgetSyncStatusText: String {
        guard let primaryCity else {
            return "Widget waiting for first city"
        }

        if loadingCityIds.contains(primaryCity.id) {
            return "Widget syncing"
        }

        if widgetRepository.getLocation() == nil {
            return "Widget location pending"
        }

        switch freshness(for: primaryCity) {
        case .fresh:
            return "Widget synced"
        case .stale:
            return "Widget may be stale"
        case .loading:
            return "Widget syncing"
        case .unavailable:
            return "Widget waiting for data"
        }
    }

    // MARK: - Init

    init() {
        logger.debug("🏠 HomeViewModel initialized")
        loadSavedCities()
        bindLocation()
        bindWeather()
        bindCityStorage()
    }

    // MARK: - Public Methods

    /// Called when view appears for the first time
    func onAppear() {
        guard !hasCompletedInitialLoad else {
            logger.debug("🏠 View appeared - already loaded, skipping")
            return
        }

        logger.debug("🏠 View appeared - requesting permission")
        locationService.requestPermission()
        hasCompletedInitialLoad = true
    }

    /// Lazy load weather on initial app launch
    /// Uses cached data immediately, then refreshes stale data in background
    private func lazyLoadInitialWeather() {
        // Cities already have cached temperatures from storage
        // Only refresh if data is stale (>15 min) or missing
        // Primary city (current location) is handled by location service binding
        // For other cities, check if they need refresh
        let citiesToRefresh = cities.dropFirst().filter { city in
            guard let lastUpdated = city.lastUpdated else {
                return city.fahrenheit == nil
            }
            return Date().timeIntervalSince(lastUpdated) > staleDataThreshold
        }

        // Stagger the refresh to avoid blocking UI
        for (index, city) in citiesToRefresh.enumerated() {
            let delay = Double(index) * 0.5 // 500ms between each
            Task {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                await MainActor.run {
                    fetchWeather(for: city)
                }
            }
        }

        logger.debug("🏠 Lazy load: \(citiesToRefresh.count) cities need refresh")
    }

    /// Called when app returns to foreground
    func onBecameActive() {
        logger.debug("🏠 App became active")

        // ALWAYS request fresh location when app becomes active
        // This ensures we detect if user moved to a different city
        logger.debug("🏠 Requesting fresh location...")
        locationService.requestLocation()

        // Only auto-refresh weather if enough time has passed
        guard canAutoRefresh else {
            logger.debug("🏠 Skipping weather auto-refresh - last update too recent")
            return
        }

        logger.debug("🏠 Auto-refreshing weather...")
        // Only refresh all cities - this includes the primary city
        // Don't call refreshWeatherIfPossible() separately to avoid duplicate fetches
        refreshAllCities()
    }

    /// Force refresh weather (user-initiated)
    func forceRefresh() {
        logger.debug("🏠 Force refresh requested")
        locationService.requestLocation()
        refreshAllCities()
    }

    /// Manually request location update
    func requestLocation() {
        locationService.requestLocation()
    }

    /// Refresh weather for current/last known location
    func refreshWeatherIfPossible() {
        guard let location = locationService.lastLocation else {
            logger.warning("🏠 No location available for refresh")
            // Try to get location first
            locationService.requestLocation()
            return
        }

        Task {
            await weatherService.fetchWeather(for: location)
        }
    }

    /// Handle city selection from search (legacy - replaces current city)
    func handleCitySelection(_ result: CitySearchResult) {
        logger.debug("🏠 City selected: \(result.title)")

        // Update city info immediately for UI
        selectedCity = result.title
        selectedCountry = ""
        errorMessage = nil

        // Use the location from the search result directly
        // iOS 26+: Use mapItem.location directly
        // Legacy: Use placemark.coordinate
        let location: CLLocation
        if #available(iOS 26.0, *) {
            location = result.mapItem.location
        } else {
            location = CLLocation(
                latitude: result.mapItem.placemark.coordinate.latitude,
                longitude: result.mapItem.placemark.coordinate.longitude
            )
        }
        Task {
            await weatherService.fetchWeather(for: location)
        }
    }

    /// Freshness helper used by city cards and Today Snapshot.
    func freshness(for city: CityModel) -> CityWeatherFreshness {
        if loadingCityIds.contains(city.id) {
            return .loading
        }

        guard let lastUpdated = city.lastUpdated else {
            return .unavailable
        }

        let age = Date().timeIntervalSince(lastUpdated)
        return age <= staleDataThreshold ? .fresh : .stale
    }

    // MARK: - Multi-City Methods

    /// Add a new city from search result (using MKLocalSearch)
    func addCity(from result: CitySearchResult) {
        guard canAddCity else {
            errorMessage = String(
                format: NSLocalizedString("Maximum of %d cities reached", comment: "City limit reached"),
                CityModel.maxCities
            )
            return
        }

        logger.debug("🏠 Adding city: \(result.title)")

        // Use MKMapItem directly to avoid deprecated MKPlacemark properties
        addCityFromMapItem(result.mapItem, title: result.title)
    }

    /// Add city from MKMapItem (from MKLocalSearch)
    /// Uses iOS 26+ APIs when available, falls back to placemark for older versions
    private func addCityFromMapItem(_ mapItem: MKMapItem, title: String) {
        // Get coordinates from location (iOS 26+) or placemark (legacy)
        let coordinate: CLLocationCoordinate2D
        let cityName: String
        let countryCode: String
        let timeZoneId: String

        if #available(iOS 26.0, *) {
            // iOS 26+: Use location and address properties
            coordinate = mapItem.location.coordinate
            cityName = mapItem.name ?? title
            // Extract country code from address if available
            // MKAddress only has fullAddress/shortAddress, so we use a default
            countryCode = "XX"
            timeZoneId = mapItem.timeZone?.identifier ?? TimeZone.current.identifier
        } else {
            // Legacy: Use placemark properties
            let placemark = mapItem.placemark
            coordinate = placemark.coordinate
            cityName = placemark.locality ?? title
            countryCode = placemark.isoCountryCode ?? placemark.countryCode ?? "XX"
            timeZoneId = placemark.timeZone?.identifier ?? TimeZone.current.identifier
        }

        let newCity = CityModel(
            id: UUID(),
            name: cityName,
            countryCode: countryCode,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            timeZoneIdentifier: timeZoneId,
            fahrenheit: nil,
            lastUpdated: nil,
            isCurrentLocation: false,
            sortOrder: cities.count
        )

        // Check for duplicates
        let isDuplicate = cities.contains { existing in
            existing.location.distance(from: newCity.location) < 1000
        }

        if isDuplicate {
            errorMessage = "This city is already in your list"
            return
        }

        // Add to list
        cities.append(newCity)
        cityStorage.addCity(newCity)

        logger.info("🏠 Added city: \(newCity.name)")

        // Fetch weather for new city
        fetchWeather(for: newCity)
    }

    /// Add city from placemark
    private func addCityFromPlacemark(_ placemark: CLPlacemark) {
        guard let newCity = CityModel.from(
            placemark: placemark,
            isCurrentLocation: false,
            sortOrder: cities.count
        ) else {
            errorMessage = "Could not add city"
            return
        }

        // Check for duplicates
        let isDuplicate = cities.contains { existing in
            existing.location.distance(from: newCity.location) < 1000
        }

        if isDuplicate {
            errorMessage = "This city is already in your list"
            return
        }

        // Add to list
        cities.append(newCity)
        cityStorage.addCity(newCity)

        logger.info("🏠 Added city: \(newCity.name)")

        // Fetch weather for new city
        fetchWeather(for: newCity)
    }

    /// Remove a city
    func removeCity(_ city: CityModel) {
        guard !city.isCurrentLocation && city.sortOrder != 0 else {
            logger.warning("🏠 Cannot remove primary city")
            return
        }

        cities.removeAll { $0.id == city.id }
        cityStorage.removeCity(id: city.id)

        // Reorder remaining cities
        for (index, _) in cities.enumerated() {
            cities[index].sortOrder = index
        }

        logger.info("🏠 Removed city: \(city.name)")
    }

    /// Reorder cities
    func moveCities(from source: IndexSet, to destination: Int) {
        // Prevent moving current location
        if source.contains(0) && cities.first?.isCurrentLocation == true {
            return
        }

        if destination == 0 && cities.first?.isCurrentLocation == true {
            return
        }

        cities.move(fromOffsets: source, toOffset: destination)

        // Update sort orders
        for (index, _) in cities.enumerated() {
            cities[index].sortOrder = index
        }

        cityStorage.moveCity(from: source, to: destination)
    }

    /// Fetch weather for a specific city (with throttling)
    func fetchWeather(for city: CityModel) {
        // Skip if already loading
        guard !loadingCityIds.contains(city.id) else {
            logger.debug("🏠 Skipping fetch for \(city.name) - already loading")
            return
        }

        // Throttle: Skip if fetched recently
        if let lastFetch = lastFetchTime[city.id],
           Date().timeIntervalSince(lastFetch) < minimumFetchInterval {
            logger.debug("🏠 Skipping fetch for \(city.name) - fetched recently")
            return
        }

        loadingCityIds.insert(city.id)
        lastFetchTime[city.id] = Date()

        // Performance tracking: Start city weather fetch
        let metadata = [
            "city_id": city.id.uuidString,
            "city_name": city.name,
            "is_current_location": "\(city.isCurrentLocation)"
        ]
        PerformanceMonitor.shared.startOperation("CityWeatherFetch", category: "Network", metadata: metadata)

        Task {
            // Ensure cleanup happens even if task is cancelled
            defer {
                loadingCityIds.remove(city.id)
            }

            // Check if task was cancelled before starting
            guard !Task.isCancelled else {
                PerformanceMonitor.shared.endOperation("CityWeatherFetch", category: "Network", metadata: metadata, forceLog: true)
                return
            }

            let temp = await refreshCoordinator.temperature(for: city) { latitude, longitude in
                let location = CLLocation(latitude: latitude, longitude: longitude)
                do {
                    return try await WeatherService.fetchCurrentTemperatureF(for: location)
                } catch {
                    return nil
                }
            }

            // Check again if task was cancelled after fetch
            guard !Task.isCancelled else {
                PerformanceMonitor.shared.endOperation("CityWeatherFetch", category: "Network", metadata: metadata, forceLog: true)
                return
            }

            if let temp {
                // Update city with new temperature
                if let index = cities.firstIndex(where: { $0.id == city.id }) {
                    cities[index] = cities[index].withWeather(fahrenheit: temp)
                    cityStorage.updateCity(cities[index])
                    // Note: Widget now uses saved_cities as single source of truth
                    // CityStorageService.updateCity() handles widget reload with throttling

                    // REPOSITORY PATTERN: Save coordinates via WidgetRepository
                    if cities[index].isCurrentLocation {
                        let updatedCity = cities[index]
                        currentFahrenheit = temp
                        lastUpdateTime = Date()

                        let sharedLocation = SharedLocation(
                            latitude: updatedCity.latitude,
                            longitude: updatedCity.longitude
                        )
                        WidgetRepository.shared.saveLocation(sharedLocation)
                        logger.debug("🏠 Updated current location weather: \(updatedCity.name), \(temp)°F")
                    }
                }

                // Performance tracking: End city weather fetch (success)
                var successMetadata = metadata
                successMetadata["temperature"] = String(format: "%.1f", temp)
                PerformanceMonitor.shared.endOperation("CityWeatherFetch", category: "Network", metadata: successMetadata)
            } else {
                // Performance tracking: End city weather fetch (no temp)
                PerformanceMonitor.shared.endOperation("CityWeatherFetch", category: "Network", metadata: metadata, forceLog: true)
            }
        }
    }

    /// Refresh weather for all cities with lazy/staggered loading
    /// Primary city loads first, then others load with delay to avoid blocking UI
    func refreshAllCities() {
        let citiesToRefresh = cities
        Task {
            await withTaskGroup(of: Void.self) { group in
                for (index, city) in citiesToRefresh.enumerated() {
                    group.addTask { [weak self] in
                        let delay = Double(index) * 0.3
                        if delay > 0 {
                            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        }
                        await self?.refreshFromWave(city)
                    }
                }
            }
        }
    }

    private func refreshFromWave(_ city: CityModel) {
        fetchWeather(for: city)
    }

    /// Lazy load cities that don't have recent weather data
    /// Only fetches weather for cities that are stale (>15 min old) or have no data
    func lazyRefreshStaleCity() {
        for city in cities {
            let isStale: Bool
            if let lastUpdated = city.lastUpdated {
                isStale = Date().timeIntervalSince(lastUpdated) > staleDataThreshold
            } else {
                isStale = city.fahrenheit == nil
            }

            if isStale && !loadingCityIds.contains(city.id) {
                fetchWeather(for: city)
                // Only fetch one stale city at a time to keep UI responsive
                break
            }
        }
    }

    // MARK: - Widget Data

    /// Save location coordinates to App Group for widget and background task access
    /// Uses WidgetRepository as SINGLE SOURCE OF TRUTH
    private func saveLocationForBackgroundRefresh() {
        guard let location = locationService.lastLocation else { return }

        // REPOSITORY PATTERN: Use WidgetRepository instead of direct UserDefaults access
        // This ensures widget can read the location we save
        let sharedLocation = SharedLocation(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        WidgetRepository.shared.saveLocation(sharedLocation)

        logger.debug("🏠 Saved location via WidgetRepository: \(location.coordinate.latitude), \(location.coordinate.longitude)")
    }

    // MARK: - Private Bindings

    /// Load saved cities from storage
    private func loadSavedCities() {
        cities = cityStorage.cities
        logger.debug("🏠 Loaded \(self.cities.count) saved cities")
    }

    /// Bind to city storage changes
    private func bindCityStorage() {
        cityStorage.$cities
            .receive(on: RunLoop.main)
            .sink { [weak self] storedCities in
                // Only update if different to avoid loops
                if self?.cities != storedCities {
                    self?.cities = storedCities
                }
            }
            .store(in: &cancellables)
    }

    /// Bind to LocationService published properties
    private func bindLocation() {
        // When location updates, update current location city
        // Use debounce to avoid multiple rapid updates
        locationService.$lastLocation
            .compactMap { $0 }
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .removeDuplicates { old, new in
                // Consider same location if within 100 meters
                old.distance(from: new) < 100
            }
            .sink { [weak self] location in
                guard let self else { return }
                // Only update city info, weather fetch is handled by refreshAllCities
                self.updateCurrentLocationCity(with: location)
            }
            .store(in: &cancellables)

        // Bind city name
        locationService.$currentCity
            .receive(on: RunLoop.main)
            .assign(to: \.selectedCity, on: self)
            .store(in: &cancellables)

        // Bind country code
        locationService.$currentCountry
            .receive(on: RunLoop.main)
            .assign(to: \.selectedCountry, on: self)
            .store(in: &cancellables)

        // Bind location errors
        locationService.$errorMessage
            .receive(on: RunLoop.main)
            .compactMap { $0 }
            .sink { [weak self] error in
                self?.errorMessage = String(
                    format: NSLocalizedString("Location: %@", comment: "Location error prefix"),
                    error
                )
            }
            .store(in: &cancellables)

        // Bind authorization status
        locationService.$authorizationStatus
            .receive(on: RunLoop.main)
            .assign(to: \.authorizationStatus, on: self)
            .store(in: &cancellables)
    }

    /// Update or create the current location city
    private func updateCurrentLocationCity(with location: CLLocation) {
        // REPOSITORY PATTERN: Save coordinates via WidgetRepository immediately
        let sharedLocation = SharedLocation(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        WidgetRepository.shared.saveLocation(sharedLocation)
        logger.debug("🏠 Saved location via WidgetRepository: \(location.coordinate.latitude), \(location.coordinate.longitude)")

        // Reverse geocode to get timezone
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            guard let self, let placemark = placemarks?.first else { return }

            Task { @MainActor in
                let cityName = placemark.locality
                    ?? placemark.administrativeArea
                    ?? "Current Location"

                let countryCode = placemark.isoCountryCode ?? ""
                let timeZoneId = placemark.timeZone?.identifier ?? TimeZone.current.identifier

                // Check if we already have a current location city
                if let existingIndex = self.cities.firstIndex(where: { $0.isCurrentLocation }) {
                    // Check if city name changed (requires forced widget reload)
                    let oldCityName = self.cities[existingIndex].name
                    let cityNameChanged = oldCityName != cityName

                    // Update existing
                    var updatedCity = self.cities[existingIndex]
                    updatedCity.name = cityName
                    updatedCity.countryCode = countryCode
                    updatedCity.latitude = location.coordinate.latitude
                    updatedCity.longitude = location.coordinate.longitude
                    updatedCity.timeZoneIdentifier = timeZoneId

                    self.cities[existingIndex] = updatedCity

                    // Use updateCurrentLocation when city name changes (forces widget reload)
                    // Otherwise use regular updateCity (throttled)
                    if cityNameChanged {
                        self.logger.debug("🏠 City name changed: \(oldCityName) → \(cityName)")
                        self.cityStorage.updateCurrentLocation(updatedCity)
                        // Fetch fresh weather for new city location
                        self.fetchWeather(for: updatedCity)
                    } else {
                        self.cityStorage.updateCity(updatedCity)
                    }
                    // Note: Widget now uses saved_cities as single source of truth
                    // No need for separate WidgetDataService.saveTemperature() call
                } else {
                    // Create new current location city
                    let newCity = CityModel(
                        name: cityName,
                        countryCode: countryCode,
                        latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude,
                        timeZoneIdentifier: timeZoneId,
                        isCurrentLocation: true,
                        sortOrder: 0
                    )

                    // Insert at beginning
                    self.cities.insert(newCity, at: 0)

                    // Update sort orders for others
                    for i in 1..<self.cities.count {
                        self.cities[i].sortOrder = i
                    }

                    self.cityStorage.updateCurrentLocation(newCity)

                    // Fetch weather for new current location
                    self.fetchWeather(for: newCity)
                }
            }
        }
    }

    /// Bind to WeatherService published properties
    private func bindWeather() {
        // Bind temperature - update timestamp and save to storage
        // Widget uses saved_cities as single source of truth
        weatherService.$currentTemperatureF
            .receive(on: RunLoop.main)
            .sink { [weak self] temp in
                guard let self, let temp else { return }
                self.currentFahrenheit = temp
                self.lastUpdateTime = Date()

                // Update current location city temperature in storage
                // This triggers widget reload via CityStorageService
                if let index = self.cities.firstIndex(where: { $0.isCurrentLocation }) {
                    self.cities[index] = self.cities[index].withWeather(fahrenheit: temp)
                    self.cityStorage.updateCity(self.cities[index])
                }

                // Save coordinates for background refresh
                self.saveLocationForBackgroundRefresh()
            }
            .store(in: &cancellables)

        // Bind loading state
        weatherService.$isLoading
            .receive(on: RunLoop.main)
            .assign(to: \.isLoadingWeather, on: self)
            .store(in: &cancellables)

        // Bind weather errors
        weatherService.$errorMessage
            .receive(on: RunLoop.main)
            .compactMap { $0 }
            .sink { [weak self] error in
                self?.errorMessage = String(
                    format: NSLocalizedString("Weather: %@", comment: "Weather error prefix"),
                    error
                )
            }
            .store(in: &cancellables)
    }

    /// Geocode city name and fetch weather
    private func geocodeAndFetchWeather(for cityName: String) {
        isLoadingWeather = true

        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString(cityName) { [weak self] placemarks, error in
            guard let self else { return }

            if let error {
                self.logger.error("🏠 Geocode error: \(error.localizedDescription)")
                Task { @MainActor in
                    self.isLoadingWeather = false
                    self.errorMessage = "Could not find location"
                }
                return
            }

            guard let placemark = placemarks?.first else {
                Task { @MainActor in
                    self.isLoadingWeather = false
                }
                return
            }

            // Update country from geocode result
            if let country = placemark.isoCountryCode {
                Task { @MainActor in
                    self.selectedCountry = country
                }
            }

            guard let location = placemark.location else {
                Task { @MainActor in
                    self.isLoadingWeather = false
                }
                return
            }

            Task { await self.weatherService.fetchWeather(for: location) }
        }
    }
}
