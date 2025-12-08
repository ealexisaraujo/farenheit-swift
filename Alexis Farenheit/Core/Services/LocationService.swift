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

    /// Request location permission
    func requestPermission() {
        if authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        } else if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            requestLocation()
        } else {
            errorMessage = "Permiso de ubicación denegado. Habilítalo en Ajustes."
        }
    }

    /// Request a single location update
    func requestLocation() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            errorMessage = "Permiso de ubicación denegado. Habilítalo en Ajustes."
            return
        }
        isRequesting = true
        errorMessage = nil
        locationManager.requestLocation()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        logger.debug("📍 Auth changed: \(manager.authorizationStatus.rawValue)")

        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            requestLocation()
        } else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            isRequesting = false
            errorMessage = "Permiso de ubicación denegado. Habilítalo en Ajustes."
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
