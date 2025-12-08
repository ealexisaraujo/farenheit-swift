import SwiftUI
import UIKit

/// Slider for manual temperature conversion F° ↔ C°
/// This is purely a conversion tool - doesn't affect weather data or widget
struct ConversionSliderView: View {
    @Binding var fahrenheit: Double

    // Track if we already gave haptic feedback to avoid rate-limiting
    @State private var hasGivenFeedback = false

    private var celsius: Double { (fahrenheit - 32) * 5 / 9 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Label("Conversor", systemImage: "arrow.left.arrow.right")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
            }

            // Temperature display
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                // Fahrenheit (editable)
                VStack(spacing: 4) {
                    Text(String(format: "%.0f°", fahrenheit))
                        .font(.system(size: 36, weight: .medium, design: .rounded))
                        .foregroundStyle(.orange)
                    Text("Fahrenheit")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Equals sign
                Image(systemName: "equal")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                // Celsius (calculated)
                VStack(spacing: 4) {
                    Text(String(format: "%.1f°", celsius))
                        .font(.system(size: 36, weight: .medium, design: .rounded))
                        .foregroundStyle(.cyan)
                    Text("Celsius")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            // Slider - only give haptic feedback once when starting to drag
            Slider(value: $fahrenheit, in: -40...140, step: 1) { editing in
                if editing && !hasGivenFeedback {
                    // Light haptic only at the START of interaction
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    hasGivenFeedback = true
                } else if !editing {
                    // Reset when user stops dragging
                    hasGivenFeedback = false
                }
            }
            .tint(.orange)

            // Scale labels
            HStack {
                Text("-40°F")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("140°F")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Conversor de temperatura")
        .accessibilityValue("\(Int(fahrenheit)) grados Fahrenheit es \(String(format: "%.1f", celsius)) grados Celsius")
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        ConversionSliderView(fahrenheit: .constant(72))
            .padding()
    }
    .preferredColorScheme(.dark)
}
