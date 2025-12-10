import Foundation
import Combine

/// Service for time zone calculations and time slider functionality
/// Manages the selected time offset and calculates times for all cities
final class TimeZoneService: ObservableObject {
    static let shared = TimeZoneService()

    /// The base reference time (usually current time)
    @Published var baseTime: Date = Date()

    /// Time offset in minutes from baseTime (-720 to +720, representing ±12 hours)
    /// This is controlled by the slider
    @Published var timeOffsetMinutes: Int = 0

    /// Timer to update baseTime every minute
    private var timer: Timer?

    // MARK: - Computed Properties

    /// The adjusted time based on slider offset
    var adjustedTime: Date {
        baseTime.addingTimeInterval(TimeInterval(timeOffsetMinutes * 60))
    }

    /// Formatted string for current slider time
    var adjustedTimeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: adjustedTime)
    }

    /// Hour value (0-23) of adjusted time
    var adjustedHour: Int {
        Calendar.current.component(.hour, from: adjustedTime)
    }

    /// Minute value (0-59) of adjusted time
    var adjustedMinute: Int {
        Calendar.current.component(.minute, from: adjustedTime)
    }

    /// Whether we're showing current time (offset is 0)
    var isShowingCurrentTime: Bool {
        timeOffsetMinutes == 0
    }

    // MARK: - Init

    private init() {
        startTimer()
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: - Timer

    private func startTimer() {
        // Update baseTime every minute
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.baseTime = Date()
        }
    }

    // MARK: - Time Calculations

    /// Get the time in a specific timezone at the adjusted time
    func timeInCity(_ city: CityModel) -> Date {
        let cityTimeZone = city.timeZone
        let localTimeZone = TimeZone.current

        // Get offsets at the adjusted time
        let localOffset = localTimeZone.secondsFromGMT(for: adjustedTime)
        let cityOffset = cityTimeZone.secondsFromGMT(for: adjustedTime)

        // Calculate the time in the city
        let offsetDifference = TimeInterval(cityOffset - localOffset)
        return adjustedTime.addingTimeInterval(offsetDifference)
    }

    /// Get formatted time string for a city
    func formattedTimeInCity(_ city: CityModel, style: DateFormatter.Style = .short) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = city.timeZone
        formatter.timeStyle = style
        formatter.dateStyle = .none
        return formatter.string(from: adjustedTime)
    }

    /// Get formatted time with AM/PM for a city
    func formattedTimeWithPeriod(_ city: CityModel) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = city.timeZone
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: adjustedTime)
    }

    /// Get hour (0-23) in a city at adjusted time
    func hourInCity(_ city: CityModel) -> Int {
        var calendar = Calendar.current
        calendar.timeZone = city.timeZone
        return calendar.component(.hour, from: adjustedTime)
    }

    /// Get time difference string between local and city
    func timeDifferenceString(for city: CityModel) -> String {
        let localOffset = TimeZone.current.secondsFromGMT(for: adjustedTime)
        let cityOffset = city.timeZone.secondsFromGMT(for: adjustedTime)
        let hoursDiff = (cityOffset - localOffset) / 3600

        if hoursDiff == 0 {
            return ""
        } else if hoursDiff > 0 {
            return "+\(hoursDiff)h"
        } else {
            return "\(hoursDiff)h"
        }
    }

    /// Check if it's daytime (6AM - 6PM) in a city
    func isDaytime(in city: CityModel) -> Bool {
        let hour = hourInCity(city)
        return hour >= 6 && hour < 18
    }

    /// Check if it's a "tomorrow" relative to local timezone
    func isTomorrow(in city: CityModel) -> Bool {
        let localCalendar = Calendar.current
        let localDay = localCalendar.component(.day, from: adjustedTime)

        var cityCalendar = Calendar.current
        cityCalendar.timeZone = city.timeZone
        let cityDay = cityCalendar.component(.day, from: adjustedTime)

        return cityDay > localDay
    }

    /// Check if it's "yesterday" relative to local timezone
    func isYesterday(in city: CityModel) -> Bool {
        let localCalendar = Calendar.current
        let localDay = localCalendar.component(.day, from: adjustedTime)

        var cityCalendar = Calendar.current
        cityCalendar.timeZone = city.timeZone
        let cityDay = cityCalendar.component(.day, from: adjustedTime)

        return cityDay < localDay
    }

    /// Get relative day indicator
    func relativeDayIndicator(for city: CityModel) -> String? {
        if isTomorrow(in: city) {
            return "+1"
        } else if isYesterday(in: city) {
            return "-1"
        }
        return nil
    }

    // MARK: - Slider Controls

    /// Reset to current time
    func resetToCurrentTime() {
        timeOffsetMinutes = 0
        baseTime = Date()
    }

    /// Set specific time (useful for quick selections)
    func setTime(hour: Int, minute: Int = 0) {
        let calendar = Calendar.current
        let now = Date()
        let currentHour = calendar.component(.hour, from: now)
        let currentMinute = calendar.component(.minute, from: now)

        let targetMinutes = hour * 60 + minute
        let currentMinutes = currentHour * 60 + currentMinute

        timeOffsetMinutes = targetMinutes - currentMinutes
    }

    /// Convert slider value (0...1) to time offset
    func setSliderValue(_ value: Double) {
        // Slider goes from 0 (midnight) to 1 (23:59)
        // We convert this to minutes offset from current time
        let targetMinutes = Int(value * 24 * 60) // 0 to 1440
        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: baseTime)
        let currentMinute = calendar.component(.minute, from: baseTime)
        let currentMinutes = currentHour * 60 + currentMinute

        timeOffsetMinutes = targetMinutes - currentMinutes
    }

    /// Get slider value (0...1) from current offset
    var sliderValue: Double {
        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: baseTime)
        let currentMinute = calendar.component(.minute, from: baseTime)
        let currentMinutes = currentHour * 60 + currentMinute

        let targetMinutes = currentMinutes + timeOffsetMinutes
        // Normalize to 0-1440 range
        let normalizedMinutes = ((targetMinutes % 1440) + 1440) % 1440
        return Double(normalizedMinutes) / (24 * 60)
    }
}

// MARK: - Time Helpers

extension TimeZoneService {
    /// Get array of common time presets
    static let timePresets: [(label: String, hour: Int)] = [
        ("12 AM", 0),
        ("6 AM", 6),
        ("12 PM", 12),
        ("6 PM", 18),
        ("Now", -1) // -1 indicates current time
    ]

    /// Format minutes to HH:MM string
    static func formatMinutes(_ totalMinutes: Int) -> String {
        let normalizedMinutes = ((totalMinutes % 1440) + 1440) % 1440
        let hours = normalizedMinutes / 60
        let minutes = normalizedMinutes % 60
        return String(format: "%02d:%02d", hours, minutes)
    }
}
