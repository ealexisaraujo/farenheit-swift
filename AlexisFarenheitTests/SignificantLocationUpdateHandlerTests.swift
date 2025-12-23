import XCTest
import CoreLocation

@testable import Alexis_Farenheit

/// TDD for the travel-widget refresh issue:
/// - When iOS wakes the app due to Significant Location Change, we must update the *city identity*
///   (name/coords/timezone) even if WeatherKit fails, otherwise the widget can get stuck showing
///   the old city name for the new coordinates.
@MainActor
final class SignificantLocationUpdateHandlerTests: XCTestCase {

    // MARK: - Test Doubles

    private struct DummyError: Error {}

    private final class TestGeocoder: SignificantLocationReverseGeocoding {
        var result: Result<SignificantLocationGeocodeResult, Error> = .failure(DummyError())
        private(set) var reverseGeocodeCalls: [CLLocation] = []

        func reverseGeocode(_ location: CLLocation) async throws -> SignificantLocationGeocodeResult {
            reverseGeocodeCalls.append(location)
            return try result.get()
        }
    }

    private final class TestWeather: SignificantLocationWeatherFetching {
        var result: Result<Double, Error> = .failure(DummyError())
        private(set) var fetchCalls: [CLLocation] = []

        func fetchTemperatureF(for location: CLLocation) async throws -> Double {
            fetchCalls.append(location)
            return try result.get()
        }
    }

    private final class TestWidgetRepository: SignificantLocationWidgetRepository {
        private(set) var savedLocations: [SharedLocation] = []

        func saveLocation(_ location: SharedLocation) {
            savedLocations.append(location)
        }
    }

    private final class TestCityStorage: SignificantLocationCityStoring {
        var currentCity: CityModel?
        private(set) var updateCalls: [CityModel] = []

        func getCurrentLocationCity() -> CityModel? {
            currentCity
        }

        func updateCurrentLocation(_ city: CityModel) {
            currentCity = city
            updateCalls.append(city)
        }
    }

    // MARK: - Tests

    func test_geocodeOk_weatherFails_updatesCityAndSavesLocation() async throws {
        let existingId = UUID()
        let existing = CityModel(
            id: existingId,
            name: "Chandler",
            countryCode: "US",
            latitude: 33.2589,
            longitude: -111.8560,
            timeZoneIdentifier: "America/Phoenix",
            fahrenheit: 70,
            lastUpdated: Date(),
            isCurrentLocation: true,
            sortOrder: 0
        )

        let cityStorage = TestCityStorage()
        cityStorage.currentCity = existing

        let widgetRepo = TestWidgetRepository()

        let geocoder = TestGeocoder()
        geocoder.result = .success(
            SignificantLocationGeocodeResult(
                cityName: "Tempe",
                countryCode: "US",
                timeZoneIdentifier: "America/Phoenix"
            )
        )

        let weather = TestWeather()
        weather.result = .failure(DummyError())

        let handler = SignificantLocationUpdateHandler(
            cityStorage: cityStorage,
            widgetRepository: widgetRepo,
            geocoder: geocoder,
            weather: weather,
            config: .init(staleMinutesWhenWeatherUnavailable: 16)
        )

        let newLocation = CLLocation(latitude: 33.4255, longitude: -111.9400) // Tempe-ish
        await handler.handleSignificantLocationChange(newLocation)

        // Location must always be persisted for widget/background refresh.
        XCTAssertEqual(widgetRepo.savedLocations.count, 1)
        let saved = try XCTUnwrap(widgetRepo.savedLocations.first)
        XCTAssertEqual(saved.latitude, newLocation.coordinate.latitude, accuracy: 0.0001)
        XCTAssertEqual(saved.longitude, newLocation.coordinate.longitude, accuracy: 0.0001)

        // City must be updated even if WeatherKit fails (name/coords/timezone).
        XCTAssertEqual(cityStorage.updateCalls.count, 1)
        let updated = try XCTUnwrap(cityStorage.updateCalls.first)
        // NOTE: The app target uses MainActor default isolation, so we evaluate values before passing
        // them to XCTest assertions (which use nonisolated autoclosures).
        let updatedId = updated.id
        let updatedName = updated.name
        let updatedCountry = updated.countryCode
        let updatedLatitude = updated.latitude
        let updatedLongitude = updated.longitude
        let updatedTimeZone = updated.timeZoneIdentifier
        let updatedIsCurrentLocation = updated.isCurrentLocation
        let updatedSortOrder = updated.sortOrder

        XCTAssertEqual(updatedId, existingId, "We should preserve the current-location city ID for continuity.")
        XCTAssertEqual(updatedName, "Tempe")
        XCTAssertEqual(updatedCountry, "US")
        XCTAssertEqual(updatedLatitude, newLocation.coordinate.latitude, accuracy: 0.0001)
        XCTAssertEqual(updatedLongitude, newLocation.coordinate.longitude, accuracy: 0.0001)
        XCTAssertEqual(updatedTimeZone, "America/Phoenix")
        XCTAssertEqual(updatedIsCurrentLocation, true)
        XCTAssertEqual(updatedSortOrder, 0)

        // Temperature should be preserved if we couldn't fetch fresh weather.
        let updatedTemp = updated.fahrenheit
        let existingTemp = existing.fahrenheit
        XCTAssertEqual(updatedTemp, existingTemp)

        // But it must be marked stale so the widget fetches ASAP on next timeline.
        let lastUpdated = try XCTUnwrap(updated.lastUpdated)
        XCTAssertLessThanOrEqual(lastUpdated, Date().addingTimeInterval(-15 * 60))
    }

    func test_geocodeOk_weatherOk_updatesCityAndTemperature() async throws {
        let existingId = UUID()
        let existing = CityModel(
            id: existingId,
            name: "Chandler",
            countryCode: "US",
            latitude: 33.2589,
            longitude: -111.8560,
            timeZoneIdentifier: "America/Phoenix",
            fahrenheit: 70,
            lastUpdated: Date(),
            isCurrentLocation: true,
            sortOrder: 0
        )

        let cityStorage = TestCityStorage()
        cityStorage.currentCity = existing

        let widgetRepo = TestWidgetRepository()

        let geocoder = TestGeocoder()
        geocoder.result = .success(
            SignificantLocationGeocodeResult(
                cityName: "Tempe",
                countryCode: "US",
                timeZoneIdentifier: "America/Phoenix"
            )
        )

        let weather = TestWeather()
        weather.result = .success(66.5)

        let handler = SignificantLocationUpdateHandler(
            cityStorage: cityStorage,
            widgetRepository: widgetRepo,
            geocoder: geocoder,
            weather: weather,
            config: .init(staleMinutesWhenWeatherUnavailable: 16)
        )

        let newLocation = CLLocation(latitude: 33.4255, longitude: -111.9400)
        let before = Date()
        await handler.handleSignificantLocationChange(newLocation)
        let after = Date()

        XCTAssertEqual(cityStorage.updateCalls.count, 1)
        let updated = try XCTUnwrap(cityStorage.updateCalls.first)
        let updatedId = updated.id
        let updatedName = updated.name
        let updatedTemp = try XCTUnwrap(updated.fahrenheit)
        XCTAssertEqual(updatedId, existingId)
        XCTAssertEqual(updatedName, "Tempe")
        XCTAssertEqual(updatedTemp, 66.5, accuracy: 0.0001)

        let lastUpdated = try XCTUnwrap(updated.lastUpdated)
        XCTAssertGreaterThanOrEqual(lastUpdated, before)
        XCTAssertLessThanOrEqual(lastUpdated, after)
    }

    func test_geocodeFails_doesNotCrash_savesLocation_andKeepsCity() async {
        let existingId = UUID()
        let existing = CityModel(
            id: existingId,
            name: "Chandler",
            countryCode: "US",
            latitude: 33.2589,
            longitude: -111.8560,
            timeZoneIdentifier: "America/Phoenix",
            fahrenheit: 70,
            lastUpdated: Date(),
            isCurrentLocation: true,
            sortOrder: 0
        )

        let cityStorage = TestCityStorage()
        cityStorage.currentCity = existing

        let widgetRepo = TestWidgetRepository()

        let geocoder = TestGeocoder()
        geocoder.result = .failure(DummyError())

        let weather = TestWeather()
        weather.result = .success(66.5) // Even if weather could succeed, we won't proceed without city identity.

        let handler = SignificantLocationUpdateHandler(
            cityStorage: cityStorage,
            widgetRepository: widgetRepo,
            geocoder: geocoder,
            weather: weather,
            config: .init(staleMinutesWhenWeatherUnavailable: 16)
        )

        let newLocation = CLLocation(latitude: 33.4255, longitude: -111.9400)
        await handler.handleSignificantLocationChange(newLocation)

        XCTAssertEqual(widgetRepo.savedLocations.count, 1)
        XCTAssertEqual(cityStorage.updateCalls.count, 0, "If we can't resolve a city identity, keep the existing primary city unchanged.")
        XCTAssertEqual(weather.fetchCalls.count, 0, "No city identity -> avoid updating temperature for the wrong city name.")
    }
}


