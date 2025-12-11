import SwiftUI

struct TemperatureDisplayView: View {
    let cityName: String
    let fahrenheit: Double
    let countryCode: String

    private var celsius: Double { (fahrenheit - 32) * 5 / 9 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            temperatureGradient(for: fahrenheit)
                .opacity(0.95)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 12, y: 6)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "location.fill")
                        .foregroundStyle(.white.opacity(0.9))
                    Text(cityName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                    if !countryCode.isEmpty {
                        Text(countryCode)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(fahrenheit.roundedInt)°F")
                        .font(.system(size: 72, weight: .thin, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("\(celsius.roundedInt)°C")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .padding(20)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Temperature: \(fahrenheit.roundedInt) degrees Fahrenheit, \(celsius.roundedInt) degrees Celsius in \(cityName)")
        .accessibilityHint("Current temperature card")
    }
}

#Preview {
    TemperatureDisplayView(cityName: "New York", fahrenheit: 72, countryCode: "US")
        .padding()
        .background(Color.black)
}
