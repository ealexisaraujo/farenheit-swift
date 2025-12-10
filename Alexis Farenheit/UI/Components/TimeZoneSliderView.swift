import SwiftUI
import UIKit

/// Premium time zone slider for navigating through 24 hours
/// Allows users to see what time it is in different cities at any point in the day
struct TimeZoneSliderView: View {
    @ObservedObject var timeService: TimeZoneService
    @State private var isDragging = false
    @State private var hasGivenHaptic = false

    /// Reference city for displaying the primary time
    var referenceCity: CityModel?

    private let hapticFeedback = UIImpactFeedbackGenerator(style: .light)
    private let selectionFeedback = UISelectionFeedbackGenerator()

    var body: some View {
        VStack(spacing: 16) {
            // Header with current time display
            header

            // Time slider
            sliderSection

            // Quick time presets
            presetsRow
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 10, y: 4)
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "clock.fill")
                        .foregroundStyle(.blue)
                        .font(.title3)

                    Text("Zona Horaria")
                        .font(.headline)
                        .foregroundStyle(.primary)
                }

                if let city = referenceCity {
                    Text(city.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Large time display
            VStack(alignment: .trailing, spacing: 2) {
                Text(displayTime)
                    .font(.system(size: 32, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())

                if !timeService.isShowingCurrentTime {
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            timeService.resetToCurrentTime()
                        }
                        selectionFeedback.selectionChanged()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.caption2)
                            Text("Ahora")
                                .font(.caption)
                        }
                        .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Hora actual")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Slider

    private var sliderSection: some View {
        VStack(spacing: 8) {
            // Custom slider track
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Track background with gradient
                    trackBackground(width: geometry.size.width)

                    // Progress fill
                    trackFill(width: geometry.size.width)

                    // Thumb
                    sliderThumb
                        .offset(x: thumbOffset(for: geometry.size.width))
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    handleDrag(value: value, width: geometry.size.width)
                                }
                                .onEnded { _ in
                                    isDragging = false
                                    hasGivenHaptic = false
                                }
                        )
                }
            }
            .frame(height: 44)

            // Hour markers
            hourMarkers
        }
    }

    private func trackBackground(width: CGFloat) -> some View {
        // Day/night gradient
        LinearGradient(
            stops: [
                .init(color: Color(hex: "1a1a2e"), location: 0),      // Midnight - dark
                .init(color: Color(hex: "16213e"), location: 0.2),    // Early morning
                .init(color: Color(hex: "4a6fa5"), location: 0.25),   // Dawn
                .init(color: Color(hex: "87CEEB"), location: 0.35),   // Morning
                .init(color: Color(hex: "FFD700"), location: 0.5),    // Noon - bright
                .init(color: Color(hex: "FFA500"), location: 0.7),    // Afternoon
                .init(color: Color(hex: "FF6347"), location: 0.8),    // Sunset
                .init(color: Color(hex: "4a4e69"), location: 0.85),   // Dusk
                .init(color: Color(hex: "1a1a2e"), location: 1)       // Night
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 12)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
        )
    }

    private func trackFill(width: CGFloat) -> some View {
        // Current time indicator line
        let currentTimePosition = currentTimeOffset(for: width)

        return Rectangle()
            .fill(.white.opacity(0.3))
            .frame(width: 2, height: 16)
            .offset(x: currentTimePosition)
            .opacity(timeService.isShowingCurrentTime ? 0 : 1)
    }

    private var sliderThumb: some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: 28, height: 28)
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [.blue, .cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 20, height: 20)

            if isDragging {
                Circle()
                    .stroke(.white.opacity(0.5), lineWidth: 2)
                    .frame(width: 36, height: 36)
            }
        }
        .scaleEffect(isDragging ? 1.2 : 1)
        .animation(.spring(response: 0.3), value: isDragging)
    }

    private var hourMarkers: some View {
        HStack {
            ForEach([0, 6, 12, 18, 24], id: \.self) { hour in
                if hour == 0 {
                    Text("12AM")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                } else if hour == 24 {
                    Text("12AM")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    Spacer()
                    Text(hour == 12 ? "12PM" : "\(hour % 12)\(hour < 12 ? "AM" : "PM")")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Presets

    private var presetsRow: some View {
        HStack(spacing: 8) {
            ForEach(TimeZoneService.timePresets, id: \.hour) { preset in
                presetButton(preset)
            }
        }
    }

    private func presetButton(_ preset: (label: String, hour: Int)) -> some View {
        let isSelected = preset.hour == -1
            ? timeService.isShowingCurrentTime
            : isPresetSelected(hour: preset.hour)

        return Button {
            withAnimation(.spring(response: 0.3)) {
                if preset.hour == -1 {
                    timeService.resetToCurrentTime()
                } else {
                    timeService.setTime(hour: preset.hour)
                }
            }
            selectionFeedback.selectionChanged()
        } label: {
            Text(preset.label)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.blue : Color.clear)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(isSelected ? Color.clear : Color.secondary.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var displayTime: String {
        if let city = referenceCity {
            return timeService.formattedTimeWithPeriod(city)
        }
        return timeService.adjustedTimeString
    }

    private func thumbOffset(for width: CGFloat) -> CGFloat {
        let usableWidth = width - 28 // Subtract thumb width
        return timeService.sliderValue * usableWidth
    }

    private func currentTimeOffset(for width: CGFloat) -> CGFloat {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: Date())
        let minute = calendar.component(.minute, from: Date())
        let totalMinutes = Double(hour * 60 + minute)
        let progress = totalMinutes / (24 * 60)
        return progress * (width - 28) + 14
    }

    private func handleDrag(value: DragGesture.Value, width: CGFloat) {
        if !isDragging {
            isDragging = true
            hapticFeedback.impactOccurred()
        }

        let usableWidth = width - 28
        let progress = max(0, min(1, value.location.x / usableWidth))
        timeService.setSliderValue(progress)

        // Haptic at hour boundaries
        let totalMinutes = Int(progress * 24 * 60)
        if totalMinutes % 60 == 0 && !hasGivenHaptic {
            selectionFeedback.selectionChanged()
            hasGivenHaptic = true
        } else if totalMinutes % 60 != 0 {
            hasGivenHaptic = false
        }
    }

    private func isPresetSelected(hour: Int) -> Bool {
        let currentMinutes = Int(timeService.sliderValue * 24 * 60)
        let presetMinutes = hour * 60
        return abs(currentMinutes - presetMinutes) < 30 // Within 30 minutes
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        TimeZoneSliderView(
            timeService: TimeZoneService.shared,
            referenceCity: .sampleCurrentLocation
        )
        .padding()
    }
    .preferredColorScheme(.dark)
}
