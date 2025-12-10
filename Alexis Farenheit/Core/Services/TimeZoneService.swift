import Foundation
import Combine

/// Service for time zone calculations and time slider functionality
/// Manages the selected time offset and calculates times for all cities
/// Slider range: 12:00 AM (0:00) to 11:59 PM (23:59) with fixed limits
final class TimeZoneService: ObservableObject {
    static let shared = TimeZoneService()

    /// The base reference date (today's date at midnight)
    @Published var baseDate: Date = Date()

    /// Selected time in minutes from midnight (0 to 1439)
    /// 0 = 12:00 AM, 720 = 12:00 PM, 1439 = 11:59 PM
    @Published var selectedMinutes: Int = 0

    /// Timer to update current time marker
    private var timer: Timer?

    /// Current time in minutes from midnight (for the "now" indicator)
    var currentTimeMinutes: Int {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: Date())
        let minute = calendar.component(.minute, from: Date())
        return hour * 60 + minute
    }

    // MARK: - Computed Properties

    /// The selected time as a Date object (today at selected time)
    var selectedTime: Date {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: baseDate)
        return startOfDay.addingTimeInterval(TimeInterval(selectedMinutes * 60))
    }

    /// Formatted string for selected time
    var selectedTimeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: selectedTime)
    }

    /// Hour value (0-23) of selected time
    var selectedHour: Int {
        selectedMinutes / 60
    }

    /// Minute value (0-59) of selected time
    var selectedMinute: Int {
        selectedMinutes % 60
    }

    /// Whether we're showing current time
    var isShowingCurrentTime: Bool {
        abs(selectedMinutes - currentTimeMinutes) < 5 // Within 5 minutes
    }

    /// Slider value normalized to 0...1 range
    var sliderValue: Double {
        Double(selectedMinutes) / 1439.0 // 1439 = 23:59
    }

    // MARK: - Init

    private init() {
        // Initialize to current time
        selectedMinutes = currentTimeMinutes
        startTimer()
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: - Timer

    private func startTimer() {
        // Update baseDate at midnight
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.baseDate = Date()
        }
    }

    // MARK: - Time Calculations

    /// Get the time in a specific timezone at the selected time
    func timeInCity(_ city: CityModel) -> Date {
        let cityTimeZone = city.timeZone
        let localTimeZone = TimeZone.current

        // Get offsets at the selected time
        let localOffset = localTimeZone.secondsFromGMT(for: selectedTime)
        let cityOffset = cityTimeZone.secondsFromGMT(for: selectedTime)

        // Calculate the time in the city
        let offsetDifference = TimeInterval(cityOffset - localOffset)
        return selectedTime.addingTimeInterval(offsetDifference)
    }

    /// Get formatted time string for a city
    func formattedTimeInCity(_ city: CityModel, style: DateFormatter.Style = .short) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = city.timeZone
        formatter.timeStyle = style
        formatter.dateStyle = .none
        return formatter.string(from: selectedTime)
    }

    /// Get formatted time with AM/PM for a city
    func formattedTimeWithPeriod(_ city: CityModel) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = city.timeZone
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: selectedTime)
    }

    /// Get hour (0-23) in a city at selected time
    func hourInCity(_ city: CityModel) -> Int {
        var calendar = Calendar.current
        calendar.timeZone = city.timeZone
        return calendar.component(.hour, from: selectedTime)
    }

    /// Get time difference string between local and city
    func timeDifferenceString(for city: CityModel) -> String {
        let localOffset = TimeZone.current.secondsFromGMT(for: selectedTime)
        let cityOffset = city.timeZone.secondsFromGMT(for: selectedTime)
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
        let localDay = localCalendar.component(.day, from: selectedTime)

        var cityCalendar = Calendar.current
        cityCalendar.timeZone = city.timeZone
        let cityDay = cityCalendar.component(.day, from: selectedTime)

        return cityDay > localDay
    }

    /// Check if it's "yesterday" relative to local timezone
    func isYesterday(in city: CityModel) -> Bool {
        let localCalendar = Calendar.current
        let localDay = localCalendar.component(.day, from: selectedTime)

        var cityCalendar = Calendar.current
        cityCalendar.timeZone = city.timeZone
        let cityDay = cityCalendar.component(.day, from: selectedTime)

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
        selectedMinutes = currentTimeMinutes
    }

    /// Set specific time by hour (0-23)
    func setTime(hour: Int, minute: Int = 0) {
        let clampedHour = max(0, min(23, hour))
        let clampedMinute = max(0, min(59, minute))
        selectedMinutes = clampedHour * 60 + clampedMinute
    }

    /// Set slider value from normalized 0...1 range
    /// Clamped to prevent wrapping
    func setSliderValue(_ value: Double) {
        let clampedValue = max(0, min(1, value))
        selectedMinutes = Int(clampedValue * 1439) // 0 to 1439 (11:59 PM)
    }

    /// Set time directly in minutes from midnight
    func setMinutes(_ minutes: Int) {
        selectedMinutes = max(0, min(1439, minutes))
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
        let clampedMinutes = max(0, min(1439, totalMinutes))
        let hours = clampedMinutes / 60
        let minutes = clampedMinutes % 60
        return String(format: "%02d:%02d", hours, minutes)
    }

    /// Format minutes to 12-hour format
    static func formatMinutes12Hour(_ totalMinutes: Int) -> String {
        let clampedMinutes = max(0, min(1439, totalMinutes))
        let hours = clampedMinutes / 60
        let minutes = clampedMinutes % 60
        let period = hours < 12 ? "AM" : "PM"
        let displayHour = hours == 0 ? 12 : (hours > 12 ? hours - 12 : hours)
        return String(format: "%d:%02d %@", displayHour, minutes, period)
    }
}
