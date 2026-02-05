import Foundation
import Combine
import CoreLocation
import os.log

/// Lightweight CoreLocation wrapper for city lookup and permission handling.
/// Provides location updates and reverse geocoding to city names.
/// Supports Significant Location Changes for background updates when user moves between cities.
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let logger = Logger(subsystem: "com.alexis.farenheit", category: "Location")
    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var shouldUpgradeToAlwaysAuthorization = false
    private var hasRequestedAlwaysUpgradeInCurrentFlow = false

    @Published var currentCity: String = "Unknown"
    @Published var currentCountry: String = ""
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var lastLocation: CLLocation?
    @Published var isRequesting: Bool = false
    @Published var errorMessage: String?

    /// Callback when location changes significantly (for background updates)
    var onSignificantLocationChange: ((CLLocation) -> Void)?

    /// Whether significant location monitoring is active
    @Published var isMonitoringSignificantChanges: Bool = false

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        // Note: allowsBackgroundLocationUpdates is NOT needed for significantLocationChanges
        // The system will wake the app automatically when location changes significantly
        authorizationStatus = locationManager.authorizationStatus
        logger.debug("📍 LocationService initialized (auth: \(self.authorizationStatus.rawValue))")
    }

    /// Request location permission using iOS 13+ two-step flow:
    /// Step 1: Request "When In Use" (shows Allow Once, Allow While Using, Don't Allow)
    /// Step 2: If user chose "While Using", optionally request "Always" upgrade.
    /// Set `preferAlways` to `true` only from explicit user actions (e.g. onboarding CTA).
    func requestPermission(preferAlways: Bool = false) {
        shouldUpgradeToAlwaysAuthorization = preferAlways
        if preferAlways {
            // Allow a new user-initiated attempt to show the Always upgrade dialog.
            hasRequestedAlwaysUpgradeInCurrentFlow = false
        }

        logger.debug("📍 requestPermission (status: \(self.authorizationStatus.rawValue), preferAlways: \(preferAlways))")

        switch authorizationStatus {
        case .notDetermined:
            // Step 1: Request When In Use first (required by iOS 13+)
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            // User chose "While Using" - upgrade only when explicitly requested by user action.
            requestLocation()
            requestAlwaysUpgradeIfNeeded()
        case .authorizedAlways:
            // Best case - full permission, background refresh works
            shouldUpgradeToAlwaysAuthorization = false
            requestLocation()
        case .denied, .restricted:
            errorMessage = "Location permission denied. Enable it in Settings."
        @unknown default:
            locationManager.requestWhenInUseAuthorization()
        }
    }

    /// Request location only when already authorized.
    /// Useful for lifecycle refreshes without showing permission prompts on app open.
    func requestLocationIfAuthorized() {
        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            requestLocation()
        case .notDetermined, .denied, .restricted:
            logger.debug("📍 Skipping location request (auth: \(self.authorizationStatus.rawValue))")
        @unknown default:
            logger.debug("📍 Skipping location request (unknown auth state)")
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
            requestPermission(preferAlways: false)
        case .denied, .restricted:
            PerformanceMonitor.shared.endOperation("LocationRequest", category: "Location", metadata: ["status": "denied"], forceLog: true)
            errorMessage = "Location permission denied. Enable it in Settings."
        @unknown default:
            PerformanceMonitor.shared.endOperation("LocationRequest", category: "Location", metadata: ["status": "unknown"], forceLog: true)
            requestPermission(preferAlways: false)
        }
    }

    // MARK: - Significant Location Changes (Background Updates)

    /// Start monitoring significant location changes.
    /// This allows the app to wake up when user moves ~500m+ (e.g., between cities).
    /// Battery-efficient: uses cell towers instead of GPS.
    /// Requires "Always" authorization for background wake-up.
    func startMonitoringSignificantLocationChanges() {
        guard CLLocationManager.significantLocationChangeMonitoringAvailable() else {
            logger.warning("📍 Significant location changes not available on this device")
            return
        }

        // Only works with Always authorization for background wake
        guard authorizationStatus == .authorizedAlways else {
            logger.debug("📍 Significant changes requires Always authorization (current: \(self.authorizationStatus.rawValue))")
            // Still start - it will work while app is in foreground with whenInUse
            if authorizationStatus == .authorizedWhenInUse {
                locationManager.startMonitoringSignificantLocationChanges()
                isMonitoringSignificantChanges = true
                logger.debug("📍 Started significant location monitoring (foreground only)")
            }
            return
        }

        locationManager.startMonitoringSignificantLocationChanges()
        isMonitoringSignificantChanges = true
        logger.info("📍 Started significant location monitoring (background enabled) ✅")
        SharedLogger.shared.info("Significant location monitoring started", category: "Location")
    }

    /// Stop monitoring significant location changes.
    /// Call when app enters foreground to switch back to standard location updates.
    func stopMonitoringSignificantLocationChanges() {
        locationManager.stopMonitoringSignificantLocationChanges()
        isMonitoringSignificantChanges = false
        logger.debug("📍 Stopped significant location monitoring")
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
            shouldUpgradeToAlwaysAuthorization = false
            hasRequestedAlwaysUpgradeInCurrentFlow = false
            requestLocation()

        case .authorizedWhenInUse:
            logger.debug("📍 When In Use authorized")
            requestLocation()
            // Continue two-step flow only when explicitly requested.
            requestAlwaysUpgradeIfNeeded()

        case .denied, .restricted:
            isRequesting = false
            errorMessage = "Location permission denied. Enable it in Settings."

        case .notDetermined:
            // "Allow Once" expired or first launch - don't show error
            // User will see permission dialog when they interact with location features
            hasRequestedAlwaysUpgradeInCurrentFlow = false
            logger.debug("📍 Status not determined (Allow Once expired or first launch)")

        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        // Check if this is a significant location change (background update)
        let isSignificantChange = isMonitoringSignificantChanges && !isRequesting

        if isSignificantChange {
            logger.info("📍 Significant location change detected: \(location.coordinate.latitude), \(location.coordinate.longitude)")
            SharedLogger.shared.info("Significant location change: \(location.coordinate.latitude), \(location.coordinate.longitude)", category: "Location")
        } else {
            logger.debug("📍 Location: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        }

        // Performance tracking: End location request (successful)
        let metadata = [
            "latitude": String(format: "%.4f", location.coordinate.latitude),
            "longitude": String(format: "%.4f", location.coordinate.longitude),
            "accuracy": String(format: "%.0f", location.horizontalAccuracy),
            "is_significant_change": "\(isSignificantChange)"
        ]
        PerformanceMonitor.shared.endOperation("LocationRequest", category: "Location", metadata: metadata)

        lastLocation = location
        isRequesting = false

        // Notify callback for significant location changes (used by app delegate/background handler)
        if isSignificantChange {
            onSignificantLocationChange?(location)
        }

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

    /// Requests the second-step "Always" dialog when current flow asked for it.
    private func requestAlwaysUpgradeIfNeeded() {
        guard shouldUpgradeToAlwaysAuthorization else { return }
        guard authorizationStatus == .authorizedWhenInUse else { return }
        guard !hasRequestedAlwaysUpgradeInCurrentFlow else { return }

        hasRequestedAlwaysUpgradeInCurrentFlow = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            guard self.authorizationStatus == .authorizedWhenInUse else { return }
            self.logger.debug("📍 Requesting Always authorization upgrade")
            self.locationManager.requestAlwaysAuthorization()
        }
    }
}
