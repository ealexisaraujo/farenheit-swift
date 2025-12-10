import Foundation
import Combine
import CoreLocation
import WeatherKit
import os.log

/// WeatherKit wrapper returning Fahrenheit values.
/// Requires WeatherKit capability and entitlement to be configured in Xcode and Apple Developer Portal.
@MainActor
final class WeatherService: ObservableObject {
    private let logger = Logger(subsystem: "com.alexis.farenheit", category: "Weather")
    private let weatherKit = WeatherKit.WeatherService.shared

    @Published var currentTemperatureF: Double?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    init() {
        logger.debug("🌤️ WeatherService initialized")
    }

    /// Fetch current weather for a location
    func fetchWeather(for location: CLLocation) async {
        logger.debug("🌤️ Fetching weather for \(location.coordinate.latitude), \(location.coordinate.longitude)")

        // Performance tracking: Start weather fetch operation
        let metadata = [
            "latitude": String(format: "%.4f", location.coordinate.latitude),
            "longitude": String(format: "%.4f", location.coordinate.longitude)
        ]
        PerformanceMonitor.shared.startOperation("WeatherFetch", category: "Network", metadata: metadata)

        isLoading = true
        errorMessage = nil

        do {
            // Request current weather only
            let weather = try await weatherKit.weather(for: location, including: .current)

            // Extract temperature in Fahrenheit
            let tempF = weather.temperature.converted(to: .fahrenheit).value
            logger.debug("🌤️ Temperature: \(tempF)°F")

            // Performance tracking: Log successful fetch
            var successMetadata = metadata
            successMetadata["temperature"] = String(format: "%.1f", tempF)
            PerformanceMonitor.shared.endOperation("WeatherFetch", category: "Network", metadata: successMetadata)

            currentTemperatureF = tempF
            errorMessage = nil

        } catch {
            let nsError = error as NSError
            logger.error("🌤️ Error: \(error.localizedDescription)")

            // Performance tracking: Log failed fetch
            var errorMetadata = metadata
            errorMetadata["error"] = error.localizedDescription
            errorMetadata["error_domain"] = nsError.domain
            PerformanceMonitor.shared.endOperation("WeatherFetch", category: "Network", metadata: errorMetadata, forceLog: true)

            // User-friendly error message
            if nsError.domain.contains("WeatherDaemon") || nsError.domain.contains("JWT") {
                errorMessage = "WeatherKit auth error. Verifica Developer Portal."
            } else {
                errorMessage = error.localizedDescription
            }
        }

        isLoading = false
    }
}
