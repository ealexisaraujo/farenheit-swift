import SwiftUI
import UIKit

/// Premium time zone slider for navigating through 24 hours
/// Range: 12:00 AM to 11:59 PM with fixed limits (no wrapping)
struct TimeZoneSliderView: View {
    @ObservedObject var timeService: TimeZoneService
    @State private var isDragging = false
    @State private var lastHapticHour: Int = -1

    /// Reference city for displaying the primary time
    var referenceCity: CityModel?

    private let hapticFeedback = UIImpactFeedbackGenerator(style: .light)
    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let boundaryFeedback = UINotificationFeedbackGenerator()

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

                    // Current time indicator (vertical line)
                    currentTimeIndicator(width: geometry.size.width)

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
                                    lastHapticHour = -1
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
        // Day/night gradient - starts and ends dark (night)
        LinearGradient(
            stops: [
                .init(color: Color(hex: "1a1a2e"), location: 0),      // 12 AM - Midnight
                .init(color: Color(hex: "16213e"), location: 0.15),   // 3-4 AM
                .init(color: Color(hex: "4a6fa5"), location: 0.22),   // 5 AM - Dawn
                .init(color: Color(hex: "87CEEB"), location: 0.30),   // 7 AM - Morning
                .init(color: Color(hex: "87CEEB"), location: 0.40),   // 9 AM
                .init(color: Color(hex: "FFD700"), location: 0.50),   // 12 PM - Noon
                .init(color: Color(hex: "FFA500"), location: 0.65),   // 3 PM - Afternoon
                .init(color: Color(hex: "FF6347"), location: 0.75),   // 6 PM - Sunset
                .init(color: Color(hex: "4a4e69"), location: 0.82),   // 8 PM - Dusk
                .init(color: Color(hex: "1a1a2e"), location: 1.0)     // 11:59 PM - Night
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
        // Add end caps to indicate limits
        .overlay(
            HStack {
                // Left cap (12 AM)
                Circle()
                    .fill(Color(hex: "1a1a2e"))
                    .frame(width: 6, height: 6)
                    .offset(x: 3)
                Spacer()
                // Right cap (11:59 PM)
                Circle()
                    .fill(Color(hex: "1a1a2e"))
                    .frame(width: 6, height: 6)
                    .offset(x: -3)
            }
        )
    }

    private func currentTimeIndicator(width: CGFloat) -> some View {
        let currentProgress = Double(timeService.currentTimeMinutes) / 1439.0
        let position = currentProgress * (width - 28) + 14

        return Group {
            if !timeService.isShowingCurrentTime {
                Rectangle()
                    .fill(.white.opacity(0.4))
                    .frame(width: 2, height: 18)
                    .offset(x: position - 1)
            }
        }
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
            Text("12 AM")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            Text("6 AM")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            Text("12 PM")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            Text("6 PM")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            Text("12 AM")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
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
        return timeService.selectedTimeString
    }

    private func thumbOffset(for width: CGFloat) -> CGFloat {
        let usableWidth = width - 28 // Subtract thumb width
        return timeService.sliderValue * usableWidth
    }

    private func handleDrag(value: DragGesture.Value, width: CGFloat) {
        if !isDragging {
            isDragging = true
            hapticFeedback.impactOccurred()
        }

        let usableWidth = width - 28
        var progress = value.location.x / usableWidth

        // Clamp to 0...1 with hard stops
        progress = max(0, min(1, progress))

        // Haptic feedback at boundaries
        if progress <= 0.01 || progress >= 0.99 {
            if lastHapticHour != (progress <= 0.01 ? 0 : 24) {
                boundaryFeedback.notificationOccurred(.warning)
                lastHapticHour = progress <= 0.01 ? 0 : 24
            }
        }

        timeService.setSliderValue(progress)

        // Haptic at hour boundaries
        let currentHour = timeService.selectedHour
        if currentHour != lastHapticHour && lastHapticHour != 0 && lastHapticHour != 24 {
            selectionFeedback.selectionChanged()
            lastHapticHour = currentHour
        }
    }

    private func isPresetSelected(hour: Int) -> Bool {
        let selectedHour = timeService.selectedHour
        let selectedMinute = timeService.selectedMinute
        // Within 30 minutes of preset
        let presetMinutes = hour * 60
        let selectedMinutes = selectedHour * 60 + selectedMinute
        return abs(selectedMinutes - presetMinutes) < 30
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
