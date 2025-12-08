//
//  AlexisExtensionFarenheit.swift
//  Temperature Converter Widget
//
//  Created by Alexis Araujo (CS) on 05/12/25.
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
    
    /// Placeholder entry for widget preview
    static var placeholder: TemperatureEntry {
        TemperatureEntry(
            date: Date(),
            cityName: "Los Angeles",
            countryCode: "US",
            fahrenheit: 72,
            celsius: 22.2
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

/// Provides timeline data for the widget
struct TemperatureProvider: TimelineProvider {
    
    func placeholder(in context: Context) -> TemperatureEntry {
        return .placeholder
    }
    
    func getSnapshot(in context: Context, completion: @escaping (TemperatureEntry) -> Void) {
        let entry = loadCachedEntry()
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<TemperatureEntry>) -> Void) {
        let entry = loadCachedEntry()
        // Refresh every 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
    
    /// Load cached temperature data from UserDefaults shared via App Group
    private func loadCachedEntry() -> TemperatureEntry {
        // Try to get shared UserDefaults
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            print("[Widget] ERROR: Could not access App Group: \(appGroupID)")
            return .placeholder
        }
        
        // Read values
        let city = defaults.string(forKey: "widget_city")
        let country = defaults.string(forKey: "widget_country") ?? ""
        let fahrenheit = defaults.double(forKey: "widget_fahrenheit")
        let lastUpdate = defaults.double(forKey: "widget_last_update")
        
        // Debug logging
        print("[Widget] Reading from App Group: city=\(city ?? "nil"), fahrenheit=\(fahrenheit), lastUpdate=\(lastUpdate)")
        
        // Validate we have data
        guard let cityName = city, !cityName.isEmpty, lastUpdate > 0 else {
            print("[Widget] No valid cached data found, using placeholder")
            return .placeholder
        }
        
        let celsius = (fahrenheit - 32) * 5 / 9
        
        print("[Widget] Loaded entry: \(cityName), \(fahrenheit)°F")
        
        return TemperatureEntry(
            date: Date(),
            cityName: cityName,
            countryCode: country,
            fahrenheit: fahrenheit,
            celsius: celsius
        )
    }
}

// MARK: - Conversion Data

/// Pre-computed conversion values for display
struct ConversionItem: Identifiable {
    let id: Int
    let fahrenheit: Int
    let celsius: Int
    
    var fText: String { "\(fahrenheit)°F" }
    var cText: String { "\(celsius)°C" }
}

/// Common conversion values
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

/// Small widget - Shows temperature only
struct SmallWidgetView: View {
    let entry: TemperatureEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            locationHeader
            Spacer()
            temperatureDisplay
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding()
    }
    
    private var locationHeader: some View {
        HStack(spacing: 4) {
            Image(systemName: "location.fill")
                .font(.caption2)
            Text(entry.cityName)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
        }
        .foregroundStyle(Color.white.opacity(0.9))
    }
    
    private var temperatureDisplay: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.fahrenheitText)
                .font(.system(size: 42, weight: .thin, design: .rounded))
                .foregroundStyle(Color.white)
            
            Text(entry.celsiusText)
                .font(.title3)
                .foregroundStyle(Color.white.opacity(0.7))
        }
    }
}

/// Medium widget - Temperature + conversion info
struct MediumWidgetView: View {
    let entry: TemperatureEntry
    
    var body: some View {
        HStack(spacing: 16) {
            leftColumn
            Spacer()
            rightColumn
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            locationRow
            Spacer()
            Text(entry.fahrenheitText)
                .font(.system(size: 48, weight: .thin, design: .rounded))
                .foregroundStyle(Color.white)
            Text(entry.celsiusText)
                .font(.title2)
                .foregroundStyle(Color.white.opacity(0.7))
        }
    }
    
    private var locationRow: some View {
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
    }
    
    private var rightColumn: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text("Conversión")
                .font(.caption2)
                .foregroundStyle(Color.white.opacity(0.6))
            
            ForEach(conversionScale) { item in
                conversionRow(item: item)
            }
        }
    }
    
    private func conversionRow(item: ConversionItem) -> some View {
        let isHighlighted = item.fahrenheit == Int(entry.fahrenheit.rounded())
        let textColor: Color = isHighlighted ? .yellow : .white.opacity(0.7)
        
        return HStack(spacing: 4) {
            Text(item.fText)
                .font(.caption2)
            Text("→")
                .font(.caption2)
                .foregroundStyle(Color.white.opacity(0.5))
            Text(item.cText)
                .font(.caption2)
        }
        .foregroundStyle(textColor)
    }
}

/// Large widget - Full temperature card with details
struct LargeWidgetView: View {
    let entry: TemperatureEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            Spacer()
            mainTemperature
            celsiusLabel
            Spacer()
            conversionTableSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private var headerRow: some View {
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
    }
    
    private var mainTemperature: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("\(Int(entry.fahrenheit))")
                .font(.system(size: 80, weight: .ultraLight, design: .rounded))
            Text("°F")
                .font(.system(size: 32, weight: .light))
        }
        .foregroundStyle(Color.white)
    }
    
    private var celsiusLabel: some View {
        Text(entry.celsiusText)
            .font(.title)
            .foregroundStyle(Color.white.opacity(0.7))
    }
    
    private var conversionTableSection: some View {
        VStack(spacing: 8) {
            Text("Tabla de conversión")
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 0) {
                ForEach(conversionTable) { item in
                    tableCell(item: item)
                }
            }
        }
        .padding(.top, 8)
    }
    
    private func tableCell(item: ConversionItem) -> some View {
        let isHighlighted = item.fahrenheit == Int(entry.fahrenheit.rounded())
        let bgColor: Color = isHighlighted ? Color.yellow.opacity(0.3) : Color.clear
        
        return VStack(spacing: 4) {
            Text(item.fText)
                .font(.caption2)
                .fontWeight(.bold)
            Text(item.cText)
                .font(.caption2)
                .foregroundStyle(Color.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(bgColor)
        .clipShape(RoundedRectangle(cornerRadius: 6))
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

/// Returns gradient based on temperature range
private func gradientBackground(for fahrenheit: Double) -> LinearGradient {
    let colors: [Color]
    
    if fahrenheit < 32 {
        colors = [Color(hex: "1a237e"), Color(hex: "0d47a1")]
    } else if fahrenheit < 50 {
        colors = [Color(hex: "0288d1"), Color(hex: "03a9f4")]
    } else if fahrenheit < 68 {
        colors = [Color(hex: "00897b"), Color(hex: "26a69a")]
    } else if fahrenheit < 86 {
        colors = [Color(hex: "ff7043"), Color(hex: "ff5722")]
    } else {
        colors = [Color(hex: "d32f2f"), Color(hex: "f44336")]
    }
    
    return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// Wrapper view that selects appropriate layout based on widget family
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
}

#Preview("Medium", as: .systemMedium) {
    AlexisExtensionFarenheit()
} timeline: {
    TemperatureEntry.placeholder
}

#Preview("Large", as: .systemLarge) {
    AlexisExtensionFarenheit()
} timeline: {
    TemperatureEntry.placeholder
}
