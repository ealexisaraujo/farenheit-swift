#if canImport(WidgetKit)
import WidgetKit
import SwiftUI

struct TempConverterWidget: Widget {
    let kind: String = "TempConverterWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            SmallWidgetView(entry: entry)
        }
        .configurationDisplayName("Temp Converter")
        .description("Shows temperature and quick conversion.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
#endif
