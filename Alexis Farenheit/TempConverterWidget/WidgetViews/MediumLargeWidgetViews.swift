#if canImport(WidgetKit)
import SwiftUI
import WidgetKit

struct MediumWidgetView: View {
    let entry: TemperatureEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TemperatureDisplayView(cityName: entry.cityName, fahrenheit: entry.fahrenheit, countryCode: entry.countryCode)
                .frame(maxWidth: .infinity, minHeight: 140)

            ConversionSliderView(fahrenheit: .constant(entry.fahrenheit))
                .allowsHitTesting(false) // Widgets are static in iOS 17 without App Intents here.
        }
        .padding(12)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct LargeWidgetView: View {
    let entry: TemperatureEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TemperatureDisplayView(cityName: entry.cityName, fahrenheit: entry.fahrenheit, countryCode: entry.countryCode)
                .frame(maxWidth: .infinity, minHeight: 140)

            HStack(spacing: 12) {
                TemperatureDisplayView(cityName: "Miami", fahrenheit: 86, countryCode: "US")
                TemperatureDisplayView(cityName: "San Francisco", fahrenheit: 62, countryCode: "US")
            }
            .frame(maxHeight: 160)
        }
        .padding(12)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}
#endif
