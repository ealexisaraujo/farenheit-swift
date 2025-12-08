import Foundation
import Combine
import CoreLocation
import MapKit
import os.log

/// Main ViewModel for the home screen - manages temperature, location, and city search state.
/// Follows MVVM pattern with Combine bindings.
@MainActor
final class HomeViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.alexis.farenheit", category: "HomeVM")

    // MARK: - Published Properties

    /// Manual temperature input from slider for conversion display only
    /// This does NOT affect the weather data - it's purely for F↔C conversion tool
    @Published var manualFahrenheit: Double = 72

    /// City name from location or search
    @Published var selectedCity: String = "Detecting..."

    /// Country code (ISO format)
    @Published var selectedCountry: String = ""

    /// Current temperature from WeatherKit (nil if not fetched yet)
    @Published var currentFahrenheit: Double?

    /// Error message to display to user
    @Published var errorMessage: String?

    /// Location authorization status
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    /// Loading state for weather fetch
    @Published var isLoadingWeather: Bool = false

    // MARK: - Services

    private let locationService = LocationService()
    private let weatherService = WeatherService()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Computed Properties

    /// Display temperature for the main card - uses WeatherKit value if available
    var displayFahrenheit: Double {
        currentFahrenheit ?? manualFahrenheit
    }

    /// Celsius conversion of display temperature
    var displayCelsius: Double {
        (displayFahrenheit - 32) * 5 / 9
    }
    
    /// Celsius conversion of manual slider value (for the converter tool)
    var manualCelsius: Double {
        (manualFahrenheit - 32) * 5 / 9
    }

    // MARK: - Init

    init() {
        logger.debug("🏠 HomeViewModel initialized")
        bindLocation()
        bindWeather()
    }

    // MARK: - Public Methods

    /// Called when view appears - requests location permission
    func onAppear() {
        locationService.requestPermission()
    }

    /// Manually request location update
    func requestLocation() {
        locationService.requestLocation()
    }

    /// Refresh weather for current location
    func refreshWeatherIfPossible() async {
        guard let location = locationService.lastLocation else {
            logger.warning("🏠 No location available")
            return
        }
        await weatherService.fetchWeather(for: location)
    }

    /// Handle city selection from search
    func handleCitySelection(_ completion: MKLocalSearchCompletion) {
        logger.debug("🏠 City selected: \(completion.title)")
        
        // Update city info immediately for UI
        selectedCity = completion.title
        selectedCountry = ""
        
        // Clear any previous errors
        errorMessage = nil
        
        // Geocode and fetch weather for the selected city
        geocodeAndFetchWeather(for: completion.title)
    }
    
    // MARK: - Widget Data
    
    /// Save weather data to widget (only called when we have real weather data)
    private func saveWeatherToWidget() {
        guard selectedCity != "Detecting..." && selectedCity != "Unknown" else { return }
        guard let temp = currentFahrenheit else { return }
        
        logger.debug("🏠 Saving to widget: \(self.selectedCity), \(temp)°F")
        WidgetDataService.shared.saveTemperature(
            city: selectedCity,
            country: selectedCountry,
            fahrenheit: temp
        )
    }

    // MARK: - Private Bindings

    /// Bind to LocationService published properties
    private func bindLocation() {
        // When location updates, fetch weather
        locationService.$lastLocation
            .compactMap { $0 }
            .sink { [weak self] location in
                guard let self else { return }
                Task { await self.weatherService.fetchWeather(for: location) }
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

    /// Bind to WeatherService published properties
    private func bindWeather() {
        // Bind temperature - save to widget when we get real weather data
        weatherService.$currentTemperatureF
            .receive(on: RunLoop.main)
            .sink { [weak self] temp in
                guard let self, let temp else { return }
                self.currentFahrenheit = temp
                self.saveWeatherToWidget()
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
