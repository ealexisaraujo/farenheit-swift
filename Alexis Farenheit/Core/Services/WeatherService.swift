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

        isLoading = true
        errorMessage = nil

        do {
            // Request current weather only
            let weather = try await weatherKit.weather(for: location, including: .current)

            // Extract temperature in Fahrenheit
            let tempF = weather.temperature.converted(to: .fahrenheit).value
            logger.debug("🌤️ Temperature: \(tempF)°F")

            currentTemperatureF = tempF
            errorMessage = nil

        } catch {
            let nsError = error as NSError
            logger.error("🌤️ Error: \(error.localizedDescription)")

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
