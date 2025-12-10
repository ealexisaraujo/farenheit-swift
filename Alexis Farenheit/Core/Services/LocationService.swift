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
        // Performance tracking: Start location request
        PerformanceMonitor.shared.startOperation("LocationRequest", category: "Location")

        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            isRequesting = true
            errorMessage = nil
            locationManager.requestLocation()
        case .notDetermined:
            // Need permission first
            PerformanceMonitor.shared.endOperation("LocationRequest", category: "Location", metadata: ["status": "not_determined"], forceLog: true)
            requestPermission()
        case .denied, .restricted:
            PerformanceMonitor.shared.endOperation("LocationRequest", category: "Location", metadata: ["status": "denied"], forceLog: true)
            errorMessage = "Permiso de ubicación denegado. Habilítalo en Ajustes."
        @unknown default:
            PerformanceMonitor.shared.endOperation("LocationRequest", category: "Location", metadata: ["status": "unknown"], forceLog: true)
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

        // Performance tracking: End location request (successful)
        let metadata = [
            "latitude": String(format: "%.4f", location.coordinate.latitude),
            "longitude": String(format: "%.4f", location.coordinate.longitude),
            "accuracy": String(format: "%.0f", location.horizontalAccuracy)
        ]
        PerformanceMonitor.shared.endOperation("LocationRequest", category: "Location", metadata: metadata)

        lastLocation = location
        isRequesting = false

        // Performance tracking: Start reverse geocoding
        PerformanceMonitor.shared.startOperation("ReverseGeocode", category: "Location")
        reverseGeocode(location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        logger.error("📍 Error: \(error.localizedDescription)")

        // Performance tracking: End location request (failed)
        let metadata = ["error": error.localizedDescription]
        PerformanceMonitor.shared.endOperation("LocationRequest", category: "Location", metadata: metadata, forceLog: true)

        errorMessage = error.localizedDescription
        isRequesting = false
    }

    /// Reverse geocode location to city name
    private func reverseGeocode(_ location: CLLocation) {
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            guard let self else { return }

            if let error {
                self.logger.error("📍 Geocode error: \(error.localizedDescription)")

                // Performance tracking: End reverse geocode (failed)
                let metadata = ["error": error.localizedDescription]
                PerformanceMonitor.shared.endOperation("ReverseGeocode", category: "Location", metadata: metadata, forceLog: true)

                self.errorMessage = error.localizedDescription
                return
            }

            guard let placemark = placemarks?.first else {
                // Performance tracking: End reverse geocode (no placemark)
                PerformanceMonitor.shared.endOperation("ReverseGeocode", category: "Location", metadata: ["status": "no_placemark"], forceLog: true)
                return
            }

            let city = placemark.locality ?? placemark.administrativeArea ?? "Unknown"
            let country = placemark.isoCountryCode ?? ""

            // Performance tracking: End reverse geocode (successful)
            let metadata = ["city": city, "country": country]
            PerformanceMonitor.shared.endOperation("ReverseGeocode", category: "Location", metadata: metadata)

            DispatchQueue.main.async {
                self.currentCity = city
                self.currentCountry = country
                self.logger.debug("📍 City: \(city), \(country)")
            }
        }
    }
}
