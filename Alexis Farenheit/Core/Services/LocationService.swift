import Foundation
import Combine
import CoreLocation
import SwiftUI
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

    /// Tracks if we already asked for Always upgrade (iOS only shows this once)
    @AppStorage("hasRequestedAlwaysAuth") private var hasRequestedAlwaysAuth = false

    /// Request location permission using iOS 13+ two-step flow:
    /// Step 1: Request "When In Use" (shows Allow Once, Allow While Using, Don't Allow)
    /// Step 2: If user chose "While Using", request "Always" upgrade
    func requestPermission() {
        logger.debug("📍 requestPermission (status: \(self.authorizationStatus.rawValue))")

        switch authorizationStatus {
        case .notDetermined:
            // Step 1: Request When In Use first (required by iOS 13+)
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            // User chose "While Using" - try to upgrade to Always (only once)
            requestLocation()
            if !hasRequestedAlwaysAuth {
                hasRequestedAlwaysAuth = true
                // Step 2: This shows "Keep While Using" vs "Change to Always"
                locationManager.requestAlwaysAuthorization()
            }
        case .authorizedAlways:
            // Best case - full permission, background refresh works
            requestLocation()
        case .denied, .restricted:
            errorMessage = "Permiso de ubicación denegado. Habilítalo en Ajustes."
        @unknown default:
            locationManager.requestWhenInUseAuthorization()
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
            // Need permission first - this will trigger the dialog
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
        let previousStatus = authorizationStatus
        authorizationStatus = newStatus
        logger.debug("📍 Auth changed: \(previousStatus.rawValue) → \(newStatus.rawValue)")

        switch newStatus {
        case .authorizedAlways:
            logger.debug("📍 Always authorized - background refresh enabled!")
            requestLocation()

        case .authorizedWhenInUse:
            logger.debug("📍 When In Use authorized")
            requestLocation()
            // Immediately ask for Always upgrade if we haven't yet
            // This creates the two-step flow Apple recommends
            if !hasRequestedAlwaysAuth {
                hasRequestedAlwaysAuth = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.locationManager.requestAlwaysAuthorization()
                }
            }

        case .denied, .restricted:
            isRequesting = false
            errorMessage = "Permiso de ubicación denegado. Habilítalo en Ajustes."

        case .notDetermined:
            // "Allow Once" expired or first launch - don't show error
            // User will see permission dialog when they interact with location features
            logger.debug("📍 Status not determined (Allow Once expired or first launch)")

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
