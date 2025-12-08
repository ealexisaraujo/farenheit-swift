//
//  AlexisExtensionFarenheit.swift
//  Temperature Converter Widget
//
//  Displays temperature in °F and °C with automatic updates.
//  Uses App Group to share data with main app.
//  Logs are written to shared file for debugging via main app.
//

import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

/// Data model for widget timeline entry
struct TemperatureEntry: TimelineEntry {
    let date: Date
    let cityName: String
    let countryCode: String
    let fahrenheit: Double
    let celsius: Double
    let isPlaceholder: Bool

    /// Placeholder entry for widget preview
    static var placeholder: TemperatureEntry {
        TemperatureEntry(
            date: Date(),
            cityName: "Los Angeles",
            countryCode: "US",
            fahrenheit: 72,
            celsius: 22.2,
            isPlaceholder: true
        )
    }

    /// Create entry from cached data
    static func fromCache(city: String, country: String, fahrenheit: Double, date: Date = Date()) -> TemperatureEntry {
        TemperatureEntry(
            date: date,
            cityName: city,
            countryCode: country,
            fahrenheit: fahrenheit,
            celsius: (fahrenheit - 32) * 5 / 9,
            isPlaceholder: false
        )
    }

    /// Formatted fahrenheit string
    var fahrenheitText: String {
        "\(Int(fahrenheit))°F"
    }

    /// Formatted celsius string
    var celsiusText: String {
        String(format: "%.1f°C", celsius)
    }
}

// MARK: - Timeline Provider

/// App Group ID - must match exactly with main app
private let appGroupID = "group.alexisaraujo.alexisfarenheit"

/// Widget kind - must match Widget definition
private let widgetKind = "AlexisExtensionFarenheit"

/// Provides timeline data for the widget.
/// Logs all operations for debugging via main app's Log Viewer.
struct TemperatureProvider: TimelineProvider {

    private let logger = WidgetLogger.shared

    // MARK: - TimelineProvider Protocol

    func placeholder(in context: Context) -> TemperatureEntry {
        logger.timeline("placeholder() called")
        return .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (TemperatureEntry) -> Void) {
        logger.timeline("getSnapshot() called (isPreview: \(context.isPreview))")

        if context.isPreview {
            completion(.placeholder)
        } else {
            let entry = loadCachedEntry()
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TemperatureEntry>) -> Void) {
        logger.timeline("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        logger.timeline("getTimeline() CALLED")
        logger.timeline("Family: \(context.family.description)")

        let currentDate = Date()
        let cachedData = loadCachedData()

        var entries: [TemperatureEntry] = []

        // Create entries for the next 4 hours
        for hourOffset in 0..<4 {
            guard let entryDate = Calendar.current.date(byAdding: .hour, value: hourOffset, to: currentDate) else {
                continue
            }

            let entry: TemperatureEntry
            if let data = cachedData {
                entry = TemperatureEntry.fromCache(
                    city: data.city,
                    country: data.country,
                    fahrenheit: data.fahrenheit,
                    date: entryDate
                )
            } else {
                entry = TemperatureEntry(
                    date: entryDate,
                    cityName: "Open App",
                    countryCode: "",
                    fahrenheit: 72,
                    celsius: 22.2,
                    isPlaceholder: true
                )
            }

            entries.append(entry)
        }

        // Request refresh after 4 hours
        let refreshDate = Calendar.current.date(byAdding: .hour, value: 4, to: currentDate) ?? currentDate
        let timeline = Timeline(entries: entries, policy: .after(refreshDate))

        logger.timeline("Timeline created: \(entries.count) entries")
        logger.timeline("Current: \(entries.first?.cityName ?? "nil"), \(entries.first?.fahrenheitText ?? "nil")")
        logger.timeline("Next refresh: \(Self.timeFormatter.string(from: refreshDate))")
        logger.timeline("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        completion(timeline)
    }

    // MARK: - Data Loading

    private func loadCachedData() -> (city: String, country: String, fahrenheit: Double, lastUpdate: Date)? {
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            logger.error("Cannot access App Group: \(appGroupID)")
            return nil
        }

        let city = defaults.string(forKey: "widget_city")
        let country = defaults.string(forKey: "widget_country") ?? ""
        let fahrenheit = defaults.double(forKey: "widget_fahrenheit")
        let lastUpdate = defaults.double(forKey: "widget_last_update")

        guard let cityName = city, !cityName.isEmpty, lastUpdate > 0 else {
            logger.data("No cached data found")
            return nil
        }

        let updateDate = Date(timeIntervalSince1970: lastUpdate)
        let ageMinutes = Int(Date().timeIntervalSince(updateDate) / 60)

        logger.data("Loaded cache: \(cityName), \(Int(fahrenheit))°F (age: \(ageMinutes)m)")

        return (cityName, country, fahrenheit, updateDate)
    }

    private func loadCachedEntry() -> TemperatureEntry {
        if let data = loadCachedData() {
            return TemperatureEntry.fromCache(
                city: data.city,
                country: data.country,
                fahrenheit: data.fahrenheit
            )
        }
        return .placeholder
    }

    // MARK: - Helpers

    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        return df
    }()
}

// MARK: - Conversion Data

struct ConversionItem: Identifiable {
    let id: Int
    let fahrenheit: Int
    let celsius: Int

    var fText: String { "\(fahrenheit)°F" }
    var cText: String { "\(celsius)°C" }
}

let conversionScale: [ConversionItem] = [
    ConversionItem(id: 0, fahrenheit: 32, celsius: 0),
    ConversionItem(id: 1, fahrenheit: 50, celsius: 10),
    ConversionItem(id: 2, fahrenheit: 68, celsius: 20),
    ConversionItem(id: 3, fahrenheit: 86, celsius: 30),
    ConversionItem(id: 4, fahrenheit: 104, celsius: 40)
]

let conversionTable: [ConversionItem] = [
    ConversionItem(id: 0, fahrenheit: 0, celsius: -18),
    ConversionItem(id: 1, fahrenheit: 32, celsius: 0),
    ConversionItem(id: 2, fahrenheit: 50, celsius: 10),
    ConversionItem(id: 3, fahrenheit: 68, celsius: 20),
    ConversionItem(id: 4, fahrenheit: 86, celsius: 30),
    ConversionItem(id: 5, fahrenheit: 100, celsius: 38)
]

// MARK: - Widget Views

struct SmallWidgetView: View {
    let entry: TemperatureEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "location.fill")
                    .font(.caption2)
                Text(entry.cityName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
            .foregroundStyle(Color.white.opacity(0.9))

            Spacer()

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.fahrenheitText)
                    .font(.system(size: 42, weight: .thin, design: .rounded))
                    .foregroundStyle(Color.white)

                Text(entry.celsiusText)
                    .font(.title3)
                    .foregroundStyle(Color.white.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding()
    }
}

struct MediumWidgetView: View {
    let entry: TemperatureEntry

    var body: some View {
        HStack(spacing: 16) {
            // Left column - temperature
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .font(.caption2)
                    Text(entry.cityName)
                        .font(.caption)
                        .fontWeight(.medium)
                    if !entry.countryCode.isEmpty {
                        Text(entry.countryCode)
                            .font(.caption2)
                            .foregroundStyle(Color.secondary)
                    }
                }
                .foregroundStyle(Color.white.opacity(0.9))

                Spacer()

                Text(entry.fahrenheitText)
                    .font(.system(size: 48, weight: .thin, design: .rounded))
                    .foregroundStyle(Color.white)
                Text(entry.celsiusText)
                    .font(.title2)
                    .foregroundStyle(Color.white.opacity(0.7))
            }

            Spacer()

            // Right column - conversion
            VStack(alignment: .trailing, spacing: 6) {
                Text("Conversión")
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.6))

                ForEach(conversionScale) { item in
                    let isHighlighted = item.fahrenheit == Int(entry.fahrenheit.rounded())
                    HStack(spacing: 4) {
                        Text(item.fText)
                            .font(.caption2)
                        Text("→")
                            .font(.caption2)
                            .foregroundStyle(Color.white.opacity(0.5))
                        Text(item.cText)
                            .font(.caption2)
                    }
                    .foregroundStyle(isHighlighted ? .yellow : .white.opacity(0.7))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct LargeWidgetView: View {
    let entry: TemperatureEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .font(.caption)
                    Text(entry.cityName)
                        .font(.headline)
                    if !entry.countryCode.isEmpty {
                        Text(entry.countryCode)
                            .font(.subheadline)
                            .foregroundStyle(Color.secondary)
                    }
                }
                Spacer()
                Image(systemName: "thermometer.medium")
                    .font(.title2)
                    .foregroundStyle(Color.yellow)
            }
            .foregroundStyle(Color.white)

            Spacer()

            // Temperature
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("\(Int(entry.fahrenheit))")
                    .font(.system(size: 80, weight: .ultraLight, design: .rounded))
                Text("°F")
                    .font(.system(size: 32, weight: .light))
            }
            .foregroundStyle(Color.white)

            Text(entry.celsiusText)
                .font(.title)
                .foregroundStyle(Color.white.opacity(0.7))

            Spacer()

            // Conversion table
            VStack(spacing: 8) {
                Text("Tabla de conversión")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 0) {
                    ForEach(conversionTable) { item in
                        let isHighlighted = item.fahrenheit == Int(entry.fahrenheit.rounded())
                        VStack(spacing: 4) {
                            Text(item.fText)
                                .font(.caption2)
                                .fontWeight(.bold)
                            Text(item.cText)
                                .font(.caption2)
                                .foregroundStyle(Color.white.opacity(0.7))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(isHighlighted ? Color.yellow.opacity(0.3) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Widget Definition

struct AlexisExtensionFarenheit: Widget {
    let kind: String = "AlexisExtensionFarenheit"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TemperatureProvider()) { entry in
            WidgetContentView(entry: entry)
                .containerBackground(for: .widget) {
                    gradientBackground(for: entry.fahrenheit)
                }
        }
        .configurationDisplayName("Temp Converter")
        .description("Muestra temperatura en °F y °C con conversión rápida.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private func gradientBackground(for fahrenheit: Double) -> LinearGradient {
    let colors: [Color]

    switch fahrenheit {
    case ..<32:
        colors = [Color(hex: "1a237e"), Color(hex: "0d47a1")]
    case 32..<50:
        colors = [Color(hex: "0288d1"), Color(hex: "03a9f4")]
    case 50..<68:
        colors = [Color(hex: "00897b"), Color(hex: "26a69a")]
    case 68..<86:
        colors = [Color(hex: "ff7043"), Color(hex: "ff5722")]
    default:
        colors = [Color(hex: "d32f2f"), Color(hex: "f44336")]
    }

    return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
}

struct WidgetContentView: View {
    @Environment(\.widgetFamily) var family
    let entry: TemperatureEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .systemLarge:
            LargeWidgetView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    AlexisExtensionFarenheit()
} timeline: {
    TemperatureEntry.placeholder
    TemperatureEntry.fromCache(city: "Chandler", country: "US", fahrenheit: 69)
}

#Preview("Medium", as: .systemMedium) {
    AlexisExtensionFarenheit()
} timeline: {
    TemperatureEntry.fromCache(city: "Detroit", country: "US", fahrenheit: 62)
}

#Preview("Large", as: .systemLarge) {
    AlexisExtensionFarenheit()
} timeline: {
    TemperatureEntry.placeholder
}
