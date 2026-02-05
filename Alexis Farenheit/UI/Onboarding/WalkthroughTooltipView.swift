import SwiftUI
import Lottie

/// Lottie-powered floating tooltip overlay for the walkthrough.
/// Replaces the spotlight-based HomeWalkthroughOverlay with a modern, animated tooltip design.
struct WalkthroughTooltipView: View {
    @Bindable var coordinator: WalkthroughCoordinator
    var onExpandTools: (() -> Void)?

    @State private var pulse = false
    @State private var tooltipOpacity: Double = 0

    private let focusPadding: CGFloat = 8
    private let tooltipWidth: CGFloat = 320

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let safeAreaTop = geometry.safeAreaInsets.top
            let step = coordinator.currentStep
            let focusRect = getFocusRect(size: size)

            ZStack {
                // Semi-transparent backdrop
                Rectangle()
                    .fill(Color.black.opacity(0.7))
                    .ignoresSafeArea()
                    .onTapGesture {
                        coordinator.next()
                    }

                // Focus highlight with cutout effect
                focusHighlight(focusRect: focusRect, safeAreaTop: safeAreaTop, size: size)

                // Pulsing border around focus
                focusBorder(focusRect: focusRect, step: step)

                // Lottie gesture hint
                gestureHint(focusRect: focusRect, step: step)

                // Tooltip card
                tooltipCard(focusRect: focusRect, step: step, size: size)
            }
            .onAppear {
                pulse = true
                withAnimation(.easeOut(duration: 0.3)) {
                    tooltipOpacity = 1
                }
            }
            .onChange(of: coordinator.currentStep) { _, _ in
                // Reset and re-animate tooltip
                tooltipOpacity = 0
                withAnimation(.easeOut(duration: 0.3).delay(0.1)) {
                    tooltipOpacity = 1
                }
            }
        }
        .transition(.opacity)
        .zIndex(100)
    }

    // MARK: - Focus Highlight

    private func focusHighlight(focusRect: CGRect, safeAreaTop: CGFloat, size: CGSize) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.78))

            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .frame(
                    width: focusRect.width + (focusPadding * 2),
                    height: focusRect.height + (focusPadding * 2)
                )
                .position(x: focusRect.midX, y: focusRect.midY + safeAreaTop)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func focusBorder(focusRect: CGRect, step: WalkthroughStep) -> some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .stroke(step.accentColor.opacity(0.9), lineWidth: 2.5)
            .frame(
                width: focusRect.width + (focusPadding * 2),
                height: focusRect.height + (focusPadding * 2)
            )
            .position(x: focusRect.midX, y: focusRect.midY)
            .shadow(color: step.accentColor.opacity(0.4), radius: pulse ? 16 : 8)
            .scaleEffect(pulse ? 1.01 : 0.99)
            .animation(
                .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                value: pulse
            )
            .allowsHitTesting(false)
    }

    // MARK: - Gesture Hint Animation

    private func gestureHint(focusRect: CGRect, step: WalkthroughStep) -> some View {
        LottieView.looping(step.animationName, speed: 0.8)
            .frame(width: 60, height: 60)
            .position(
                x: focusRect.maxX - 20,
                y: focusRect.minY - 40
            )
            .opacity(tooltipOpacity)
            .allowsHitTesting(false)
    }

    // MARK: - Tooltip Card

    private func tooltipCard(focusRect: CGRect, step: WalkthroughStep, size: CGSize) -> some View {
        let cardHeight: CGFloat = step == .tools ? 200 : 180
        let shouldPlaceBelow = focusRect.midY < (size.height * 0.45)

        let cardCenterY: CGFloat = shouldPlaceBelow
            ? min(focusRect.maxY + 20 + (cardHeight / 2), size.height - 24 - (cardHeight / 2))
            : max(focusRect.minY - 20 - (cardHeight / 2), 24 + (cardHeight / 2))

        return VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("walkthrough.header")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(coordinator.progressText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            // Title
            Text(step.title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)

            // Message
            Text(step.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Action button for tools step
            if step == .tools {
                Button {
                    onExpandTools?()
                } label: {
                    Text("walkthrough.tools.action")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(step.accentColor)
            }

            Spacer(minLength: 0)

            // Navigation buttons
            navigationButtons(step: step)
        }
        .padding(16)
        .frame(width: tooltipWidth, height: cardHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .position(x: size.width / 2, y: cardCenterY)
        .opacity(tooltipOpacity)
    }

    private func navigationButtons(step: WalkthroughStep) -> some View {
        HStack(spacing: 10) {
            // Skip button
            Button {
                coordinator.skip()
            } label: {
                Text("walkthrough.skip")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Back button
            if !coordinator.isFirstStep {
                Button {
                    coordinator.previous()
                } label: {
                    Text("walkthrough.back")
                }
                .buttonStyle(.bordered)
            }

            // Next/Done button
            Button {
                coordinator.next()
            } label: {
                Text(coordinator.isLastStep ? "walkthrough.done" : "walkthrough.next")
            }
            .buttonStyle(.borderedProminent)
            .tint(step.accentColor)
        }
    }

    // MARK: - Focus Rect Calculation

    private func getFocusRect(size: CGSize) -> CGRect {
        if let frame = coordinator.currentFrame,
           frame.width > 0, frame.height > 0,
           frame.minY >= -50,
           frame.maxY <= size.height + 50 {
            return frame
        }

        // Fallback rect
        let fallbackWidth = size.width - 56
        return CGRect(
            x: 28,
            y: (size.height * 0.45) - 54,
            width: fallbackWidth,
            height: 108
        )
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var coordinator = WalkthroughCoordinator()

        var body: some View {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack {
                    Text("Content behind walkthrough")
                        .foregroundStyle(.white)
                }

                if coordinator.isActive {
                    WalkthroughTooltipView(coordinator: coordinator)
                }
            }
            .onAppear {
                coordinator.updateFrame(
                    CGRect(x: 20, y: 200, width: 350, height: 150),
                    for: .todaySnapshot
                )
                coordinator.start()
            }
        }
    }

    return PreviewWrapper()
}
