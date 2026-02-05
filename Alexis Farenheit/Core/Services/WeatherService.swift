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

    @Published var currentTemperatureF: Double?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    init() {
        logger.debug("🌤️ WeatherService initialized")
    }

    /// Shared async fetch helper usable from any actor/context.
    nonisolated static func fetchCurrentTemperatureF(for location: CLLocation) async throws -> Double {
        let weatherKit = WeatherKit.WeatherService.shared
        let weather = try await weatherKit.weather(for: location, including: .current)
        return weather.temperature.converted(to: .fahrenheit).value
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
            let tempF = try await Self.fetchCurrentTemperatureF(for: location)
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
