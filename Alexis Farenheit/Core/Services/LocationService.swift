import Foundation
import Combine
import CoreLocation
import os.log

/// Lightweight CoreLocation wrapper for city lookup and permission handling.
/// Provides location updates and reverse geocoding to city names.
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let logger = Logger(subsystem: "com.alexis.farenheit", category: "Location")
    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()

    @Published var currentCity: String = "Unknown"
    @Published var currentCountry: String = ""
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var lastLocation: CLLocation?
    @Published var isRequesting: Bool = false
    @Published var errorMessage: String?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        authorizationStatus = locationManager.authorizationStatus
        logger.debug("📍 LocationService initialized (auth: \(self.authorizationStatus.rawValue))")
    }

    /// Request location permission - uses "Always" for best UX and background widget refresh
    func requestPermission() {
        logger.debug("📍 requestPermission (status: \(self.authorizationStatus.rawValue))")

        switch authorizationStatus {
        case .notDetermined:
            // First time - request "Always" permission
            locationManager.requestAlwaysAuthorization()
        case .authorizedWhenInUse:
            // User gave "When In Use" - upgrade to "Always" for background refresh
            locationManager.requestAlwaysAuthorization()
            // Also get location now
            requestLocation()
        case .authorizedAlways:
            // Best case - full permission granted
            requestLocation()
        case .denied, .restricted:
            errorMessage = "Permiso de ubicación denegado. Habilítalo en Ajustes."
        @unknown default:
            locationManager.requestAlwaysAuthorization()
        }
    }

    /// Request a single location update
    func requestLocation() {
        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            isRequesting = true
            errorMessage = nil
            locationManager.requestLocation()
        case .notDetermined:
            // Need permission first
            requestPermission()
        case .denied, .restricted:
            errorMessage = "Permiso de ubicación denegado. Habilítalo en Ajustes."
        @unknown default:
            requestPermission()
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let newStatus = manager.authorizationStatus
        authorizationStatus = newStatus
        logger.debug("📍 Auth changed: \(newStatus.rawValue)")

        switch newStatus {
        case .authorizedAlways:
            // Perfect - user granted full access
            logger.debug("📍 Always authorization granted")
            requestLocation()
        case .authorizedWhenInUse:
            // Good enough to work, but try to upgrade for background
            logger.debug("📍 WhenInUse granted, requesting Always for background refresh")
            requestLocation()
            // iOS will show prompt to upgrade to Always (only once)
            locationManager.requestAlwaysAuthorization()
        case .denied, .restricted:
            isRequesting = false
            errorMessage = "Permiso de ubicación denegado. Habilítalo en Ajustes."
        case .notDetermined:
            // User hasn't decided yet - don't show error
            logger.debug("📍 Status not determined yet")
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        logger.debug("📍 Location: \(location.coordinate.latitude), \(location.coordinate.longitude)")

        lastLocation = location
        isRequesting = false
        reverseGeocode(location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        logger.error("📍 Error: \(error.localizedDescription)")
        errorMessage = error.localizedDescription
        isRequesting = false
    }

    /// Reverse geocode location to city name
    private func reverseGeocode(_ location: CLLocation) {
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            guard let self else { return }

            if let error {
                self.logger.error("📍 Geocode error: \(error.localizedDescription)")
                self.errorMessage = error.localizedDescription
                return
            }

            guard let placemark = placemarks?.first else { return }

            let city = placemark.locality ?? placemark.administrativeArea ?? "Unknown"
            let country = placemark.isoCountryCode ?? ""

            DispatchQueue.main.async {
                self.currentCity = city
                self.currentCountry = country
                self.logger.debug("📍 City: \(city), \(country)")
            }
        }
    }
}
