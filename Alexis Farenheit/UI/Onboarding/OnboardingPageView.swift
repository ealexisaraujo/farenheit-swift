import SwiftUI
import Lottie

/// A cinematic onboarding page that focuses on the animated hero and narrative copy.
struct OnboardingPageView: View {
    let slide: OnboardingSlideSpec
    let theme: OnboardingVisualTheme
    let isActive: Bool
    let reduceMotion: Bool

    @State private var hasAnimatedIn = false
    @State private var playbackTrigger = 0

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 8)

            heroSection

            textSection

            Spacer(minLength: 24)
        }
        .padding(.horizontal, theme.horizontalPadding)
        .onAppear {
            guard isActive else { return }
            playbackTrigger += 1
            animateIn()
        }
        .onChange(of: isActive) { _, visible in
            if visible {
                playbackTrigger += 1
                animateIn()
            } else {
                hasAnimatedIn = false
            }
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [slide.accentColor.opacity(0.42), .clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: theme.animationSize * 0.65
                    )
                )
                .frame(width: theme.animationSize * 1.15, height: theme.animationSize * 1.15)
                .blur(radius: 24)
                .scaleEffect(reduceMotion ? 1.0 : (hasAnimatedIn ? 1.02 : 0.96))

            Circle()
                .stroke(slide.accentColor.opacity(0.26), lineWidth: 1.2)
                .frame(width: theme.animationSize * 1.03, height: theme.animationSize * 1.03)
                .blur(radius: 1.4)
                .opacity(hasAnimatedIn ? 1 : 0)

            LottieView(
                animationName: slide.animationName,
                loopMode: slide.shouldLoopAnimation ? .loop : .playOnce,
                animationSpeed: slide.shouldLoopAnimation ? 1.0 : 0.92,
                playbackTrigger: playbackTrigger
            )
            .frame(width: theme.animationSize, height: theme.animationSize)
            .shadow(color: slide.accentColor.opacity(0.38), radius: 24, y: 8)
        }
        .frame(maxWidth: .infinity)
        .opacity(hasAnimatedIn ? 1 : 0)
        .offset(y: hasAnimatedIn ? 0 : 24)
        .scaleEffect(hasAnimatedIn ? 1 : 0.92)
        .animation(.easeOut(duration: 0.45), value: hasAnimatedIn)
    }

    // MARK: - Copy

    private var textSection: some View {
        VStack(spacing: 12) {
            Text(LocalizedStringKey(slide.titleKey))
                .font(theme.titleFont)
                .foregroundStyle(theme.primaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(LocalizedStringKey(slide.subtitleKey))
                .font(theme.subtitleFont)
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .opacity(hasAnimatedIn ? 1 : 0)
        .offset(y: hasAnimatedIn ? 0 : 20)
        .animation(.easeOut(duration: 0.42).delay(0.04), value: hasAnimatedIn)
    }

    // MARK: - Animation

    private func animateIn() {
        guard !reduceMotion else {
            hasAnimatedIn = true
            return
        }

        withAnimation(.spring(response: theme.springResponse, dampingFraction: theme.springDamping).delay(0.08)) {
            hasAnimatedIn = true
        }
    }
}

// MARK: - Preview

#Preview("Welcome") {
    let slide = OnboardingConfiguration.shared.slide(for: .welcome)
    let theme = OnboardingVisualTheme.forColorScheme(.dark)
    ZStack {
        Color.black.ignoresSafeArea()
        OnboardingPageView(
            slide: slide,
            theme: theme,
            isActive: true,
            reduceMotion: false
        )
    }
}

#Preview("Location - Light") {
    let slide = OnboardingConfiguration.shared.slide(for: .location)
    let theme = OnboardingVisualTheme.forColorScheme(.light)
    ZStack {
        Color.white.ignoresSafeArea()
        OnboardingPageView(
            slide: slide,
            theme: theme,
            isActive: true,
            reduceMotion: false
        )
    }
}
