import SwiftUI
import Lottie

/// A single page in the onboarding flow with Lottie animation, title, subtitle, and optional action button.
struct OnboardingPageView: View {
    let page: OnboardingPage
    let isVisible: Bool
    var onAction: (() -> Void)?

    @State private var hasAnimatedIn = false

    private let config = OnboardingConfiguration.shared

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Lottie Animation
            animationSection
                .frame(width: config.animationSize, height: config.animationSize)
                .opacity(hasAnimatedIn ? 1 : 0)
                .scaleEffect(hasAnimatedIn ? 1 : 0.8)

            // Text Content
            VStack(spacing: 16) {
                Text(page.title)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .opacity(hasAnimatedIn ? 1 : 0)
                    .offset(y: hasAnimatedIn ? 0 : 20)

                Text(page.subtitle)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .opacity(hasAnimatedIn ? 1 : 0)
                    .offset(y: hasAnimatedIn ? 0 : 15)
            }
            .padding(.horizontal, config.cardPadding)

            // Action Button (for location permission and final page)
            if let buttonTitle = page.buttonTitle {
                actionButton(title: buttonTitle)
                    .opacity(hasAnimatedIn ? 1 : 0)
                    .offset(y: hasAnimatedIn ? 0 : 20)
            }

            Spacer()
            Spacer()
        }
        .onChange(of: isVisible) { _, visible in
            if visible {
                animateIn()
            } else {
                hasAnimatedIn = false
            }
        }
        .onAppear {
            if isVisible {
                animateIn()
            }
        }
    }

    // MARK: - Animation Section

    @ViewBuilder
    private var animationSection: some View {
        ZStack {
            // Glow effect behind animation
            Circle()
                .fill(
                    RadialGradient(
                        colors: [page.accentColor.opacity(0.3), .clear],
                        center: .center,
                        startRadius: 40,
                        endRadius: 120
                    )
                )
                .frame(width: config.animationSize + 40, height: config.animationSize + 40)
                .blur(radius: 20)

            // Lottie Animation
            if page.shouldLoopAnimation {
                LottieView.looping(page.animationName)
                    .frame(width: config.animationSize, height: config.animationSize)
            } else {
                LottieView.oneShot(page.animationName)
                    .frame(width: config.animationSize, height: config.animationSize)
            }
        }
    }

    // MARK: - Action Button

    private func actionButton(title: LocalizedStringKey) -> some View {
        Button {
            triggerHaptic(.medium)
            onAction?()
        } label: {
            HStack(spacing: 8) {
                if page.hasPermissionAction {
                    Image(systemName: "location.fill")
                }
                Text(title)
                    .fontWeight(.semibold)
                if page.isFinalPage {
                    Image(systemName: "arrow.right")
                }
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: 280)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(page.accentColor)
            )
            .shadow(color: page.accentColor.opacity(0.4), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Animation

    private func animateIn() {
        withAnimation(.spring(response: config.springResponse, dampingFraction: config.springDamping).delay(0.1)) {
            hasAnimatedIn = true
        }
    }

    private func triggerHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

// MARK: - Preview

#Preview("Welcome Page") {
    ZStack {
        Color.black.ignoresSafeArea()
        OnboardingPageView(page: .welcome, isVisible: true)
    }
}

#Preview("Location Page") {
    ZStack {
        Color.black.ignoresSafeArea()
        OnboardingPageView(page: .location, isVisible: true) {
            print("Request location permission")
        }
    }
}

#Preview("Ready Page") {
    ZStack {
        Color.black.ignoresSafeArea()
        OnboardingPageView(page: .ready, isVisible: true) {
            print("Start using app")
        }
    }
}
