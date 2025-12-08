#if canImport(WidgetKit)
import SwiftUI
import WidgetKit

struct SmallWidgetView: View {
    let entry: TemperatureEntry

    var body: some View {
        TemperatureDisplayView(cityName: entry.cityName, fahrenheit: entry.fahrenheit, countryCode: entry.countryCode)
            .containerBackground(.fill.tertiary, for: .widget)
            .padding(8)
    }
}
#endif
