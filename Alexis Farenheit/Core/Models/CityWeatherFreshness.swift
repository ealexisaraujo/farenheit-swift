import Foundation

/// UI-friendly freshness states for city weather data.
enum CityWeatherFreshness: Equatable, Sendable {
    case fresh
    case loading
    case stale
    case unavailable

    var label: String {
        switch self {
        case .fresh:
            return "Fresh"
        case .loading:
            return "Updating"
        case .stale:
            return "Stale"
        case .unavailable:
            return "No Data"
        }
    }
}
