import SwiftUI

/// Individual city card showing temperature and local time
/// Premium design inspired by Apple Weather app and 2025 design awards
struct CityCardView: View {
    let city: CityModel
    @ObservedObject var timeService: TimeZoneService

    /// Whether this is the current/primary city (cannot be deleted)
    var isPrimary: Bool = false

    /// Callback when delete is requested
    var onDelete: (() -> Void)?

    @State private var isPressed = false

    // MARK: - Computed Properties

    private var localTime: String {
        timeService.formattedTimeWithPeriod(city)
    }

    private var timeDiff: String {
        timeService.timeDifferenceString(for: city)
    }

    private var isDaytime: Bool {
        timeService.isDaytime(in: city)
    }

    private var dayIndicator: String? {
        timeService.relativeDayIndicator(for: city)
    }

    private var temperature: String {
        guard let f = city.fahrenheit else { return "--°" }
        return "\(Int(round(f)))°"
    }

    private var celsius: String {
        guard let c = city.celsius else { return "--°C" }
        return "\(Int(round(c)))°C"
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 16) {
            // Left: City info + time
            leftSection

            Spacer()

            // Right: Temperature
            rightSection
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: shadowColor, radius: isPressed ? 4 : 8, y: isPressed ? 2 : 4)
        .scaleEffect(isPressed ? 0.98 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .onLongPressGesture(minimumDuration: 0.1, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Left Section

    private var leftSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            // City name row
            HStack(spacing: 8) {
                if isPrimary {
                    Image(systemName: "location.fill")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.9))
                }

                Text(city.name)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if !city.countryCode.isEmpty {
                    Text(city.countryCode)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(.white.opacity(0.15))
                        )
                }
            }

            // Time row
            HStack(spacing: 8) {
                // Day/night indicator
                Image(systemName: isDaytime ? "sun.max.fill" : "moon.fill")
                    .font(.caption)
                    .foregroundStyle(isDaytime ? .yellow : .white.opacity(0.8))

                // Local time
                Text(localTime)
                    .font(.system(size: 24, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())

                // Day indicator (+1, -1)
                if let indicator = dayIndicator {
                    Text(indicator)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(.white.opacity(0.2))
                        )
                }

                // Time difference
                if !timeDiff.isEmpty && !isPrimary {
                    Text(timeDiff)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }

    // MARK: - Right Section

    private var rightSection: some View {
        VStack(alignment: .trailing, spacing: 4) {
            // Main temperature
            Text(temperature)
                .font(.system(size: 44, weight: .thin, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())

            // Celsius
            Text(celsius)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    // MARK: - Background

    private var cardBackground: some View {
        ZStack {
            // Base gradient based on temperature
            temperatureGradient(for: city.fahrenheit ?? 70)
                .opacity(0.9)

            // Day/night overlay
            LinearGradient(
                colors: isDaytime
                    ? [.clear, .white.opacity(0.05)]
                    : [.black.opacity(0.2), .black.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Subtle noise texture effect
            Color.white.opacity(0.02)
        }
    }

    private var shadowColor: Color {
        guard let temp = city.fahrenheit else { return .black.opacity(0.2) }
        switch temp {
        case ..<32:
            return Color(hex: "667eea").opacity(0.3)
        case 32..<70:
            return Color(hex: "11998e").opacity(0.3)
        case 70..<85:
            return Color(hex: "f093fb").opacity(0.3)
        default:
            return Color(hex: "ff512f").opacity(0.3)
        }
    }

    private var accessibilityLabel: String {
        let tempLabel = city.fahrenheit != nil
            ? "\(Int(city.fahrenheit!)) degrees Fahrenheit"
            : "Temperature unavailable"
        return "\(city.name), \(city.countryCode). \(tempLabel). Local time: \(localTime)"
    }
}

// MARK: - Compact Card Variant

/// Smaller card variant for inline display
struct CityCardCompactView: View {
    let city: CityModel
    @ObservedObject var timeService: TimeZoneService

    var body: some View {
        HStack(spacing: 12) {
            // City name
            VStack(alignment: .leading, spacing: 2) {
                Text(city.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)

                Text(timeService.formattedTimeWithPeriod(city))
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Temperature
            if let temp = city.fahrenheit {
                Text("\(Int(round(temp)))°")
                    .font(.system(size: 28, weight: .light, design: .rounded))
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Preview

#Preview("City Card") {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 16) {
            CityCardView(
                city: .sampleCurrentLocation,
                timeService: TimeZoneService.shared,
                isPrimary: true
            )

            CityCardView(
                city: .sampleTokyo,
                timeService: TimeZoneService.shared
            )

            CityCardView(
                city: .sampleLondon,
                timeService: TimeZoneService.shared
            )
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}

#Preview("Compact Card") {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 8) {
            CityCardCompactView(
                city: .sampleCurrentLocation,
                timeService: TimeZoneService.shared
            )

            CityCardCompactView(
                city: .sampleTokyo,
                timeService: TimeZoneService.shared
            )
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}
