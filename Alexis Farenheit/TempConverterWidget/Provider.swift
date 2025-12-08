#if canImport(WidgetKit)
import WidgetKit
import SwiftUI
import CoreLocation

struct TemperatureEntry: TimelineEntry {
    let date: Date
    let fahrenheit: Double
    let celsius: Double
    let cityName: String
    let countryCode: String
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> TemperatureEntry {
        TemperatureEntry(date: Date(), fahrenheit: 72, celsius: 22, cityName: "My Location", countryCode: "US")
    }

    func getSnapshot(in context: Context, completion: @escaping (TemperatureEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TemperatureEntry>) -> Void) {
        // Stubbed timeline for now; in real widget we'd fetch location + weather here.
        let entry = TemperatureEntry(date: Date(), fahrenheit: 72, celsius: 22, cityName: "Snapshot", countryCode: "US")
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}
#endif
