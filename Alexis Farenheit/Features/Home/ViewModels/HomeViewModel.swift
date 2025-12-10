import Foundation
import Combine
import CoreLocation
import MapKit
import SwiftUI
import os.log

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

    // MARK: - Services

    private let locationService = LocationService()
    private let weatherService = WeatherService()
    private var cancellables = Set<AnyCancellable>()

    /// Minimum interval between automatic refreshes (5 minutes)
    private let minimumRefreshInterval: TimeInterval = 5 * 60

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
        logger.debug("🏠 View appeared - requesting permission")
        locationService.requestPermission()
    }

    /// Called when app returns to foreground
    func onBecameActive() {
        logger.debug("🏠 App became active")

        // Only auto-refresh if enough time has passed
        guard canAutoRefresh else {
            logger.debug("🏠 Skipping auto-refresh - last update too recent")
            return
        }

        logger.debug("🏠 Auto-refreshing weather...")
        refreshWeatherIfPossible()
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
    func handleCitySelection(_ completion: MKLocalSearchCompletion) {
        logger.debug("🏠 City selected: \(completion.title)")

        // Update city info immediately for UI
        selectedCity = completion.title
        selectedCountry = ""
        errorMessage = nil

        // Geocode and fetch weather for the selected city
        geocodeAndFetchWeather(for: completion.title)
    }

    // MARK: - Multi-City Methods

    /// Add a new city from search completion
    func addCity(from completion: MKLocalSearchCompletion) {
        guard canAddCity else {
            errorMessage = "Máximo de \(CityModel.maxCities) ciudades alcanzado"
            return
        }

        logger.debug("🏠 Adding city: \(completion.title)")

        // Geocode to get full details
        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString(completion.title) { [weak self] placemarks, error in
            guard let self else { return }

            if let error {
                self.logger.error("🏠 Geocode error: \(error.localizedDescription)")
                Task { @MainActor in
                    self.errorMessage = "No se pudo encontrar la ubicación"
                }
                return
            }

            guard let placemark = placemarks?.first else {
                Task { @MainActor in
                    self.errorMessage = "Ubicación no encontrada"
                }
                return
            }

            Task { @MainActor in
                self.addCityFromPlacemark(placemark)
            }
        }
    }

    /// Add city from placemark
    private func addCityFromPlacemark(_ placemark: CLPlacemark) {
        guard let newCity = CityModel.from(
            placemark: placemark,
            isCurrentLocation: false,
            sortOrder: cities.count
        ) else {
            errorMessage = "No se pudo agregar la ciudad"
            return
        }

        // Check for duplicates
        let isDuplicate = cities.contains { existing in
            existing.location.distance(from: newCity.location) < 1000
        }

        if isDuplicate {
            errorMessage = "Esta ciudad ya está en tu lista"
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

    /// Fetch weather for a specific city
    func fetchWeather(for city: CityModel) {
        guard !loadingCityIds.contains(city.id) else { return }

        loadingCityIds.insert(city.id)

        Task {
            let tempService = WeatherService()
            await tempService.fetchWeather(for: city.location)

            if let temp = tempService.currentTemperatureF {
                // Update city with new temperature
                if let index = cities.firstIndex(where: { $0.id == city.id }) {
                    cities[index] = cities[index].withWeather(fahrenheit: temp)
                    cityStorage.updateCity(cities[index])
                }
            }

            loadingCityIds.remove(city.id)
        }
    }

    /// Refresh weather for all cities
    func refreshAllCities() {
        for city in cities {
            fetchWeather(for: city)
        }
    }

    // MARK: - Widget Data

    /// Save weather data to widget and location for background refresh
    private func saveWeatherToWidget() {
        guard selectedCity != "Detecting..." && selectedCity != "Unknown" else { return }
        guard let temp = currentFahrenheit else { return }

        logger.debug("🏠 Saving to widget: \(self.selectedCity), \(temp)°F")
        WidgetDataService.shared.saveTemperature(
            city: selectedCity,
            country: selectedCountry,
            fahrenheit: temp
        )

        // Also save location coordinates for background refresh
        saveLocationForBackgroundRefresh()
    }

    /// Save location coordinates to App Group for background task access
    private func saveLocationForBackgroundRefresh() {
        guard let location = locationService.lastLocation else { return }
        guard let defaults = UserDefaults(suiteName: "group.alexisaraujo.alexisfarenheit") else { return }

        defaults.set(location.coordinate.latitude, forKey: "last_latitude")
        defaults.set(location.coordinate.longitude, forKey: "last_longitude")
        defaults.synchronize()

        logger.debug("🏠 Saved location for background: \(location.coordinate.latitude), \(location.coordinate.longitude)")
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
        // When location updates, fetch weather and update current location city
        locationService.$lastLocation
            .compactMap { $0 }
            .sink { [weak self] location in
                guard let self else { return }
                Task { await self.weatherService.fetchWeather(for: location) }
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
                self?.errorMessage = "Location: \(error)"
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
                    // Update existing
                    var updatedCity = self.cities[existingIndex]
                    updatedCity.name = cityName
                    updatedCity.countryCode = countryCode
                    updatedCity.latitude = location.coordinate.latitude
                    updatedCity.longitude = location.coordinate.longitude
                    updatedCity.timeZoneIdentifier = timeZoneId

                    self.cities[existingIndex] = updatedCity
                    self.cityStorage.updateCity(updatedCity)
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
                }
            }
        }
    }

    /// Bind to WeatherService published properties
    private func bindWeather() {
        // Bind temperature - save to widget and update timestamp
        weatherService.$currentTemperatureF
            .receive(on: RunLoop.main)
            .sink { [weak self] temp in
                guard let self, let temp else { return }
                self.currentFahrenheit = temp
                self.lastUpdateTime = Date()
                self.saveWeatherToWidget()

                // Also update current location city temperature
                if let index = self.cities.firstIndex(where: { $0.isCurrentLocation }) {
                    self.cities[index] = self.cities[index].withWeather(fahrenheit: temp)
                    self.cityStorage.updateCity(self.cities[index])
                }
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
                self?.errorMessage = "Weather: \(error)"
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
                    self.errorMessage = "No se pudo encontrar la ubicación"
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
