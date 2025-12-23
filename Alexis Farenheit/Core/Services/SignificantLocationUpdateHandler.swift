import Foundation
import CoreLocation
import WeatherKit

/// Handles Significant Location Change updates in a **testable** way.
///
/// Why this exists:
/// - Widgets cannot read location directly.
/// - The widget reads `saved_cities` and `widget_location` from the App Group.
/// - When the user moves to another city, we must update BOTH:
///   - the shared location (`widget_location`)
///   - and the *primary city identity* (`saved_cities[0]` name/coords/timezone)
///   Otherwise the widget can keep showing the previous city name for the new coordinates.
///
/// IMPORTANT iOS behavior:
/// - If the user **force-quits** the app (swipe up), iOS will not relaunch the app in background,
///   so Significant Location Changes and BGTasks won't run. We can only inform the user via UI.
final class SignificantLocationUpdateHandler {

    // MARK: - Configuration

    struct Config: Sendable, Equatable {
        /// When we cannot fetch WeatherKit, we still update city identity but mark it stale,
        /// so the widget will treat cache as old and fetch ASAP on next timeline request.
        ///
        /// NOTE: The widget uses a 15-minute staleness threshold; defaulting to 16m guarantees `needsFresh == true`.
        let staleMinutesWhenWeatherUnavailable: Double

        init(staleMinutesWhenWeatherUnavailable: Double = 16) {
            self.staleMinutesWhenWeatherUnavailable = staleMinutesWhenWeatherUnavailable
        }
    }

    // MARK: - Dependencies

    private let cityStorage: SignificantLocationCityStoring
    private let widgetRepository: SignificantLocationWidgetRepository
    private let geocoder: SignificantLocationReverseGeocoding
    private let weather: SignificantLocationWeatherFetching
    private let config: Config

    // MARK: - Init

    init(
        cityStorage: SignificantLocationCityStoring = CityStorageService.shared,
        widgetRepository: SignificantLocationWidgetRepository = WidgetRepository.shared,
        geocoder: SignificantLocationReverseGeocoding = CLGeocoderAdapter(),
        weather: SignificantLocationWeatherFetching = WeatherKitTemperatureFetcher(),
        config: Config = .init()
    ) {
        self.cityStorage = cityStorage
        self.widgetRepository = widgetRepository
        self.geocoder = geocoder
        self.weather = weather
        self.config = config
    }

    // MARK: - API

    /// Called when the app receives a Significant Location Change (background wake).
    /// This is **async** so we can use modern `async/await` for geocoding and WeatherKit.
    func handleSignificantLocationChange(_ location: CLLocation) async {
        // Always persist raw coordinates first so the widget can at least fetch weather by coords.
        // This is the bridge across processes (App -> Widget).
        let sharedLocation = SharedLocation(coordinate: location.coordinate)
        widgetRepository.saveLocation(sharedLocation)
        SharedLogger.shared.info(
            "Significant location: saved coords \(location.coordinate.latitude), \(location.coordinate.longitude)",
            category: "Background"
        )

        // Resolve the *city identity* (name/timezone). If we can't resolve it, do not proceed.
        // Reason: updating temperature without city identity can lead to mismatched “city name vs coords”.
        let geocodeResult: SignificantLocationGeocodeResult
        do {
            geocodeResult = try await geocoder.reverseGeocode(location)
        } catch {
            SharedLogger.shared.warning(
                "Significant location: reverse geocode failed: \(error.localizedDescription)",
                category: "Background"
            )
            return
        }

        // Preserve identity where possible.
        let existing = cityStorage.getCurrentLocationCity()
        let cityId = existing?.id ?? UUID()

        // Default “fallback temp” (only used if WeatherKit fails).
        let fallbackTemp = existing?.fahrenheit

        // Try fetching WeatherKit (best effort). If it fails, keep previous temp but mark stale.
        do {
            let tempF = try await weather.fetchTemperatureF(for: location)

            let updatedCity = CityModel(
                id: cityId,
                name: geocodeResult.cityName,
                countryCode: geocodeResult.countryCode,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                timeZoneIdentifier: geocodeResult.timeZoneIdentifier,
                fahrenheit: tempF,
                lastUpdated: Date(),
                isCurrentLocation: true,
                sortOrder: 0
            )

            await MainActor.run {
                self.cityStorage.updateCurrentLocation(updatedCity)
            }

            SharedLogger.shared.info(
                "Significant location: updated city '\(updatedCity.name)' with temp \(Int(tempF))°F",
                category: "Background"
            )
        } catch {
            let staleDate = Date().addingTimeInterval(-(config.staleMinutesWhenWeatherUnavailable * 60))

            let updatedCity = CityModel(
                id: cityId,
                name: geocodeResult.cityName,
                countryCode: geocodeResult.countryCode,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                timeZoneIdentifier: geocodeResult.timeZoneIdentifier,
                fahrenheit: fallbackTemp,
                // IMPORTANT: Do NOT set `lastUpdated` to nil.
                // The widget provider converts cache age to Int for logging; nil maps to infinity in repo code.
                lastUpdated: staleDate,
                isCurrentLocation: true,
                sortOrder: 0
            )

            await MainActor.run {
                self.cityStorage.updateCurrentLocation(updatedCity)
            }

            SharedLogger.shared.warning(
                "Significant location: WeatherKit failed (\(error.localizedDescription)). Updated city identity and marked stale for widget refresh.",
                category: "Background"
            )
        }
    }
}

// MARK: - Protocols (for testability)

struct SignificantLocationGeocodeResult: Sendable, Equatable {
    let cityName: String
    let countryCode: String
    let timeZoneIdentifier: String
}

protocol SignificantLocationReverseGeocoding {
    func reverseGeocode(_ location: CLLocation) async throws -> SignificantLocationGeocodeResult
}

protocol SignificantLocationWeatherFetching {
    func fetchTemperatureF(for location: CLLocation) async throws -> Double
}

protocol SignificantLocationWidgetRepository {
    func saveLocation(_ location: SharedLocation)
}

protocol SignificantLocationCityStoring {
    func getCurrentLocationCity() -> CityModel?
    func updateCurrentLocation(_ city: CityModel)
}

// MARK: - Production adapters

private struct CLGeocoderAdapter: SignificantLocationReverseGeocoding {
    func reverseGeocode(_ location: CLLocation) async throws -> SignificantLocationGeocodeResult {
        let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
        let placemark = placemarks.first

        let cityName = placemark?.locality
            ?? placemark?.administrativeArea
            ?? "Unknown"

        let countryCode = placemark?.isoCountryCode ?? ""
        let timeZoneIdentifier = placemark?.timeZone?.identifier ?? TimeZone.current.identifier

        return SignificantLocationGeocodeResult(
            cityName: cityName,
            countryCode: countryCode,
            timeZoneIdentifier: timeZoneIdentifier
        )
    }
}

private struct WeatherKitTemperatureFetcher: SignificantLocationWeatherFetching {
    private let service = WeatherKit.WeatherService.shared

    func fetchTemperatureF(for location: CLLocation) async throws -> Double {
        let weather = try await service.weather(for: location, including: .current)
        return weather.temperature.converted(to: .fahrenheit).value
    }
}

// MARK: - Conformances (existing services)

extension CityStorageService: SignificantLocationCityStoring {
    func getCurrentLocationCity() -> CityModel? {
        currentLocationCity
    }
}

extension WidgetRepository: SignificantLocationWidgetRepository {}


