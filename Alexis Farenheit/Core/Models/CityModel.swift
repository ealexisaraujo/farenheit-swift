import Foundation
import CoreLocation

/// Represents a saved city with weather and timezone data
/// Used for the multi-city card list feature
struct CityModel: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var countryCode: String
    var latitude: Double
    var longitude: Double
    var timeZoneIdentifier: String
    var fahrenheit: Double?
    var lastUpdated: Date?
    var isCurrentLocation: Bool

    /// Order in the list (0 = first/current location)
    var sortOrder: Int

    // MARK: - Computed Properties

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }

    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .current
    }

    var celsius: Double? {
        guard let f = fahrenheit else { return nil }
        return (f - 32) * 5 / 9
    }

    /// Display name with country code
    var displayName: String {
        if countryCode.isEmpty {
            return name
        }
        return "\(name), \(countryCode)"
    }

    /// Get local time for this city at a given reference time
    func localTime(at referenceDate: Date = Date()) -> Date {
        let sourceTimeZone = TimeZone.current
        let destinationTimeZone = timeZone

        let sourceOffset = sourceTimeZone.secondsFromGMT(for: referenceDate)
        let destinationOffset = destinationTimeZone.secondsFromGMT(for: referenceDate)
        let interval = TimeInterval(destinationOffset - sourceOffset)

        return referenceDate.addingTimeInterval(interval)
    }

    /// Get formatted local time string
    func localTimeString(at referenceDate: Date = Date(), style: DateFormatter.Style = .short) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.timeStyle = style
        formatter.dateStyle = .none
        return formatter.string(from: referenceDate)
    }

    /// Get time difference from current timezone in hours
    func hoursDifferenceFromLocal(at referenceDate: Date = Date()) -> Int {
        let localOffset = TimeZone.current.secondsFromGMT(for: referenceDate)
        let cityOffset = timeZone.secondsFromGMT(for: referenceDate)
        return (cityOffset - localOffset) / 3600
    }

    /// Formatted time difference string (e.g., "+5h", "-3h", "mismo")
    func timeDifferenceString(at referenceDate: Date = Date()) -> String {
        let diff = hoursDifferenceFromLocal(at: referenceDate)
        if diff == 0 {
            return ""
        } else if diff > 0 {
            return "+\(diff)h"
        } else {
            return "\(diff)h"
        }
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        name: String,
        countryCode: String = "",
        latitude: Double,
        longitude: Double,
        timeZoneIdentifier: String = TimeZone.current.identifier,
        fahrenheit: Double? = nil,
        lastUpdated: Date? = nil,
        isCurrentLocation: Bool = false,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.countryCode = countryCode
        self.latitude = latitude
        self.longitude = longitude
        self.timeZoneIdentifier = timeZoneIdentifier
        self.fahrenheit = fahrenheit
        self.lastUpdated = lastUpdated
        self.isCurrentLocation = isCurrentLocation
        self.sortOrder = sortOrder
    }

    // MARK: - Factory Methods

    /// Create a city model from geocoded location
    static func from(
        placemark: CLPlacemark,
        isCurrentLocation: Bool = false,
        sortOrder: Int = 0
    ) -> CityModel? {
        guard let location = placemark.location else { return nil }

        let cityName = placemark.locality
            ?? placemark.administrativeArea
            ?? placemark.name
            ?? "Unknown"

        return CityModel(
            name: cityName,
            countryCode: placemark.isoCountryCode ?? "",
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            timeZoneIdentifier: placemark.timeZone?.identifier ?? TimeZone.current.identifier,
            isCurrentLocation: isCurrentLocation,
            sortOrder: sortOrder
        )
    }

    // MARK: - Mutation

    /// Return a copy with updated weather data
    func withWeather(fahrenheit: Double) -> CityModel {
        var copy = self
        copy.fahrenheit = fahrenheit
        copy.lastUpdated = Date()
        return copy
    }

    /// Return a copy with updated sort order
    func withSortOrder(_ order: Int) -> CityModel {
        var copy = self
        copy.sortOrder = order
        return copy
    }
}

// MARK: - Constants

extension CityModel {
    /// Maximum number of cities allowed (free tier)
    static let maxCities = 5

    /// Placeholder for loading state
    static let placeholder = CityModel(
        name: "Loading...",
        latitude: 0,
        longitude: 0,
        sortOrder: 0
    )
}

// MARK: - Sample Data for Previews

extension CityModel {
    static let sampleCurrentLocation = CityModel(
        name: "Phoenix",
        countryCode: "US",
        latitude: 33.4484,
        longitude: -112.0740,
        timeZoneIdentifier: "America/Phoenix",
        fahrenheit: 95,
        lastUpdated: Date(),
        isCurrentLocation: true,
        sortOrder: 0
    )

    static let sampleTokyo = CityModel(
        name: "Tokyo",
        countryCode: "JP",
        latitude: 35.6762,
        longitude: 139.6503,
        timeZoneIdentifier: "Asia/Tokyo",
        fahrenheit: 72,
        lastUpdated: Date(),
        sortOrder: 1
    )

    static let sampleLondon = CityModel(
        name: "London",
        countryCode: "GB",
        latitude: 51.5074,
        longitude: -0.1278,
        timeZoneIdentifier: "Europe/London",
        fahrenheit: 55,
        lastUpdated: Date(),
        sortOrder: 2
    )

    static let sampleParis = CityModel(
        name: "Paris",
        countryCode: "FR",
        latitude: 48.8566,
        longitude: 2.3522,
        timeZoneIdentifier: "Europe/Paris",
        fahrenheit: 58,
        lastUpdated: Date(),
        sortOrder: 3
    )

    static let sampleSydney = CityModel(
        name: "Sydney",
        countryCode: "AU",
        latitude: -33.8688,
        longitude: 151.2093,
        timeZoneIdentifier: "Australia/Sydney",
        fahrenheit: 68,
        lastUpdated: Date(),
        sortOrder: 4
    )

    static let samples: [CityModel] = [
        .sampleCurrentLocation,
        .sampleTokyo,
        .sampleLondon,
        .sampleParis,
        .sampleSydney
    ]
}
