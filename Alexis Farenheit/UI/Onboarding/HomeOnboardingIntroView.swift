import SwiftUI
import UIKit

// MARK: - Data Models

private enum IntroBackgroundAsset: String {
    case welcome = "OnboardingBGWelcome"
    case cities = "OnboardingBGCities"
    case walkthrough = "OnboardingBGWalkthrough"
}

private struct IntroPage: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let message: String
    let accent: Color
    let backgroundAsset: IntroBackgroundAsset
}

// MARK: - Animation Values

private struct IconBreathingValues {
    var scale: CGFloat = 1.0
    var glowOpacity: Double = 0.3
    var rotation: Double = 0
}

private struct ParticleState: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var size: CGFloat
    var opacity: Double
    var speed: Double
}

// MARK: - Main View

struct HomeOnboardingIntroView: View {
    let onSkip: () -> Void
    let onStartWalkthrough: () -> Void

    @State private var currentPage = 0
    @State private var dragOffset: CGFloat = 0
    @State private var hasAppeared = false
    @State private var textRevealed = false
    @State private var particles: [ParticleState] = []
    @State private var particleTimer: Timer?
    @Namespace private var heroAnimation

    private let pages: [IntroPage] = [
        IntroPage(
            icon: "sun.max.fill",
            title: NSLocalizedString("Welcome to Alexis Farenheit", comment: "Onboarding intro first page title"),
            message: NSLocalizedString("Get current weather, world time, and quick city control in one place.", comment: "Onboarding intro first page message"),
            accent: Color(hex: "FFD166"),
            backgroundAsset: .welcome
        ),
        IntroPage(
            icon: "globe.americas.fill",
            title: NSLocalizedString("Your Cities, Your Rhythm", comment: "Onboarding intro second page title"),
            message: NSLocalizedString("Track multiple cities, compare local times, and keep your widget synced.", comment: "Onboarding intro second page message"),
            accent: Color(hex: "4CC9F0"),
            backgroundAsset: .cities
        ),
        IntroPage(
            icon: "wand.and.stars.inverse",
            title: NSLocalizedString("Interactive Walkthrough", comment: "Onboarding intro third page title"),
            message: NSLocalizedString("We will show every key area of the home screen in under one minute.", comment: "Onboarding intro third page message"),
            accent: Color(hex: "7B61FF"),
            backgroundAsset: .walkthrough
        )
    ]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Parallax background layers
                parallaxBackground(size: geometry.size)

                // Animated particles
                particleLayer(size: geometry.size)

                // Floating glass orbs
                floatingOrbsLayer(size: geometry.size)

                // Readability overlay
                readabilityOverlay

                // Main content
                VStack(spacing: 0) {
                    skipButton
                        .padding(.top, 8)

                    Spacer(minLength: 20)

                    // Hero icon with breathing animation
                    heroIconSection
                        .frame(height: 160)

                    Spacer(minLength: 16)

                    // Content cards with gesture
                    contentSection(size: geometry.size)

                    Spacer(minLength: 16)

                    // Bottom section
                    VStack(spacing: 20) {
                        reassuranceText
                        pageIndicators
                        primaryButton
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
                .safeAreaPadding(.top, 12)
            }
            .onAppear {
                initializeParticles(size: geometry.size)
                startParticleAnimation(size: geometry.size)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeOut(duration: 0.8).delay(0.2)) {
                hasAppeared = true
            }
            withAnimation(.easeOut(duration: 0.6).delay(0.5)) {
                textRevealed = true
            }
        }
        .onDisappear {
            particleTimer?.invalidate()
        }
        .onChange(of: currentPage) { _, _ in
            triggerHaptic()
            // Reset text reveal for new page
            textRevealed = false
            withAnimation(.easeOut(duration: 0.5).delay(0.2)) {
                textRevealed = true
            }
        }
    }

    // MARK: - Skip Button

    private var skipButton: some View {
        HStack {
            Spacer()
            Button(NSLocalizedString("Skip", comment: "Onboarding intro action to skip")) {
                triggerHaptic(.light)
                onSkip()
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white.opacity(0.82))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .glassButtonStyle()
        }
        .padding(.horizontal, 20)
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : -20)
    }

    // MARK: - Hero Icon Section

    private var heroIconSection: some View {
        ZStack {
            // Glow effect behind icon
            Circle()
                .fill(
                    RadialGradient(
                        colors: [activePage.accent.opacity(0.4), .clear],
                        center: .center,
                        startRadius: 30,
                        endRadius: 100
                    )
                )
                .frame(width: 200, height: 200)
                .phaseAnimator([0.8, 1.0, 0.8]) { content, phase in
                    content
                        .scaleEffect(phase)
                        .opacity(phase == 1.0 ? 0.6 : 0.3)
                } animation: { _ in
                    .easeInOut(duration: 2.0)
                }

            // Main icon with breathing effect
            iconView(for: activePage)
        }
        .opacity(hasAppeared ? 1 : 0)
        .scaleEffect(hasAppeared ? 1 : 0.5)
    }

    private func iconView(for page: IntroPage) -> some View {
        ZStack {
            // Animated gradient border
            Circle()
                .strokeBorder(
                    AngularGradient(
                        colors: [
                            page.accent,
                            page.accent.opacity(0.3),
                            page.accent,
                            page.accent.opacity(0.3),
                            page.accent
                        ],
                        center: .center
                    ),
                    lineWidth: 2
                )
                .frame(width: 124, height: 124)
                .phaseAnimator([0.0, 360.0]) { content, phase in
                    content.rotationEffect(.degrees(phase))
                } animation: { _ in
                    .linear(duration: 8.0)
                }

            // Glass background
            Circle()
                .glassCardStyle(accent: page.accent)
                .frame(width: 120, height: 120)

            // Icon with breathing animation
            Image(systemName: page.icon)
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [page.accent, page.accent.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .phaseAnimator([1.0, 1.08, 1.0]) { content, scale in
                    content.scaleEffect(scale)
                } animation: { _ in
                    .easeInOut(duration: 2.5)
                }
                .shadow(color: page.accent.opacity(0.5), radius: 10)
        }
        .matchedGeometryEffect(id: "heroIcon", in: heroAnimation)
    }

    // MARK: - Content Section

    private func contentSection(size: CGSize) -> some View {
        ZStack {
            ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                contentCard(page, index: index, size: size)
                    .opacity(index == currentPage ? 1 : 0)
                    .offset(x: CGFloat(index - currentPage) * size.width + dragOffset)
                    .rotation3DEffect(
                        .degrees(Double(index - currentPage) * 15 + Double(dragOffset / 30)),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0.5
                    )
            }
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation.width
                }
                .onEnded { value in
                    let threshold: CGFloat = 50
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        if value.translation.width < -threshold && currentPage < pages.count - 1 {
                            currentPage += 1
                        } else if value.translation.width > threshold && currentPage > 0 {
                            currentPage -= 1
                        }
                        dragOffset = 0
                    }
                }
        )
    }

    private func contentCard(_ page: IntroPage, index: Int, size: CGSize) -> some View {
        VStack(spacing: 20) {
            // Title with staggered reveal
            Text(page.title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .opacity(textRevealed && index == currentPage ? 1 : 0)
                .offset(y: textRevealed && index == currentPage ? 0 : 20)

            // Message with delayed reveal
            Text(page.message)
                .font(.title3)
                .foregroundStyle(.white.opacity(0.82))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .opacity(textRevealed && index == currentPage ? 1 : 0)
                .offset(y: textRevealed && index == currentPage ? 0 : 15)
                .animation(.easeOut(duration: 0.5).delay(0.15), value: textRevealed)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: min(size.width - 40, 380))
    }

    // MARK: - Reassurance Text

    private var reassuranceText: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(.green)
                .phaseAnimator([1.0, 1.1, 1.0]) { content, scale in
                    content.scaleEffect(scale)
                } animation: { _ in
                    .easeInOut(duration: 1.5)
                }

            Text(NSLocalizedString("Quick, optional, and focused on what you need now", comment: "Onboarding reassurance text"))
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassChipStyle()
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 20)
    }

    // MARK: - Page Indicators

    private var pageIndicators: some View {
        HStack(spacing: 10) {
            ForEach(0..<pages.count, id: \.self) { index in
                Capsule()
                    .fill(index == currentPage ? Color.white : Color.white.opacity(0.3))
                    .frame(width: index == currentPage ? 28 : 8, height: 8)
                    .shadow(color: index == currentPage ? activePage.accent.opacity(0.5) : .clear, radius: 4)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
    }

    // MARK: - Primary Button

    private var primaryButton: some View {
        Button {
            triggerHaptic(.medium)
            if currentPage < pages.count - 1 {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    currentPage += 1
                }
            } else {
                onStartWalkthrough()
            }
        } label: {
            HStack(spacing: 10) {
                Text(currentPage == pages.count - 1
                    ? NSLocalizedString("Start Walkthrough", comment: "Onboarding intro primary CTA on final page")
                    : NSLocalizedString("Continue", comment: "Onboarding intro primary CTA"))
                    .fontWeight(.semibold)

                Image(systemName: currentPage == pages.count - 1 ? "play.fill" : "arrow.right")
                    .font(.subheadline.weight(.semibold))
                    .phaseAnimator([0.0, 5.0, 0.0]) { content, offset in
                        content.offset(x: offset)
                    } animation: { _ in
                        .easeInOut(duration: 1.2)
                    }
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                ZStack {
                    // Animated gradient background
                    LinearGradient(
                        colors: [activePage.accent, activePage.accent.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )

                    // Shimmer effect
                    shimmerOverlay
                }
            )
            .clipShape(.rect(cornerRadius: 16))
            .shadow(color: activePage.accent.opacity(0.4), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 30)
        .animation(.spring(response: 0.3), value: currentPage)
    }

    private var shimmerOverlay: some View {
        GeometryReader { geometry in
            LinearGradient(
                colors: [
                    .clear,
                    .white.opacity(0.2),
                    .clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 60)
            .offset(x: -60)
            .phaseAnimator([0.0, geometry.size.width + 120]) { content, offset in
                content.offset(x: offset)
            } animation: { _ in
                .linear(duration: 2.5).delay(1.0)
            }
        }
        .clipShape(.rect(cornerRadius: 16))
    }

    // MARK: - Parallax Background

    private func parallaxBackground(size: CGSize) -> some View {
        ZStack {
            // Base gradient
            LinearGradient(
                colors: [Color.black, Color(hex: "0D0F1A"), Color(hex: "151829")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Background images with parallax
            ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                Image(page.backgroundAsset.rawValue)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .offset(x: parallaxOffset(for: index))
                    .opacity(index == currentPage ? 1 : 0)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: currentPage)
    }

    private func parallaxOffset(for index: Int) -> CGFloat {
        let baseOffset = CGFloat(index - currentPage) * 30
        let dragParallax = dragOffset * 0.15
        return baseOffset + dragParallax
    }

    // MARK: - Readability Overlay

    private var readabilityOverlay: some View {
        ZStack {
            // Top gradient
            LinearGradient(
                colors: [Color.black.opacity(0.6), .clear],
                startPoint: .top,
                endPoint: .center
            )

            // Bottom gradient for button area
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.7)],
                startPoint: .center,
                endPoint: .bottom
            )

            // Center radial for text readability
            RadialGradient(
                colors: [Color.black.opacity(0.2), Color.black.opacity(0.4)],
                center: .center,
                startRadius: 100,
                endRadius: 400
            )
        }
    }

    // MARK: - Floating Orbs

    private func floatingOrbsLayer(size: CGSize) -> some View {
        ZStack {
            // Large orb top-left
            floatingOrb(size: 80, color: pages[0].accent)
                .offset(x: -size.width * 0.35, y: -size.height * 0.3)
                .phaseAnimator([0.0, 20.0, 0.0, -15.0, 0.0]) { content, offset in
                    content.offset(y: offset)
                } animation: { _ in
                    .easeInOut(duration: 4.0)
                }

            // Medium orb top-right
            floatingOrb(size: 50, color: pages[1].accent)
                .offset(x: size.width * 0.3, y: -size.height * 0.25)
                .phaseAnimator([0.0, -25.0, 0.0, 20.0, 0.0]) { content, offset in
                    content.offset(y: offset)
                } animation: { _ in
                    .easeInOut(duration: 5.0)
                }

            // Small orb bottom-left
            floatingOrb(size: 35, color: pages[2].accent)
                .offset(x: -size.width * 0.25, y: size.height * 0.35)
                .phaseAnimator([0.0, 15.0, 0.0, -20.0, 0.0]) { content, offset in
                    content.offset(y: offset)
                } animation: { _ in
                    .easeInOut(duration: 3.5)
                }
        }
        .opacity(0.3)
        .blur(radius: 20)
    }

    private func floatingOrb(size: CGFloat, color: Color) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color, color.opacity(0.3), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: size / 2
                )
            )
            .frame(width: size, height: size)
    }

    // MARK: - Particle System

    private func particleLayer(size: CGSize) -> some View {
        ZStack {
            ForEach(particles) { particle in
                Circle()
                    .fill(Color.white)
                    .frame(width: particle.size, height: particle.size)
                    .position(x: particle.x, y: particle.y)
                    .opacity(particle.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func initializeParticles(size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        particles = (0..<30).map { _ in
            ParticleState(
                x: CGFloat.random(in: 0...size.width),
                y: CGFloat.random(in: 0...size.height),
                size: CGFloat.random(in: 1...3),
                opacity: Double.random(in: 0.1...0.4),
                speed: Double.random(in: 0.3...1.0)
            )
        }
    }

    private func startParticleAnimation(size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let width = size.width
        let height = size.height
        particleTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            withAnimation(.linear(duration: 0.05)) {
                for index in particles.indices {
                    particles[index].y -= particles[index].speed
                    if particles[index].y < -10 {
                        particles[index].y = height + 10
                        particles[index].x = CGFloat.random(in: 0...width)
                    }
                    // Subtle horizontal drift
                    particles[index].x += CGFloat.random(in: -0.3...0.3)
                }
            }
        }
    }

    // MARK: - Helpers

    private var clampedPageIndex: Int {
        guard !pages.isEmpty else { return 0 }
        return min(max(currentPage, 0), pages.count - 1)
    }

    private var activePage: IntroPage {
        pages[clampedPageIndex]
    }

    private func triggerHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .soft) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

// MARK: - Glass Effect Modifiers

private extension View {
    @ViewBuilder
    func glassCardStyle(accent: Color) -> some View {
        if #available(iOS 26, *) {
            self
                .background(.clear)
                .glassEffect(.regular.tint(accent.opacity(0.1)), in: .circle)
        } else {
            self
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Circle()
                                .fill(accent.opacity(0.1))
                        )
                )
        }
    }

    @ViewBuilder
    func glassButtonStyle() -> some View {
        if #available(iOS 26, *) {
            self
                .glassEffect(.regular.interactive(), in: .capsule)
        } else {
            self
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                )
        }
    }

    @ViewBuilder
    func glassChipStyle() -> some View {
        if #available(iOS 26, *) {
            self
                .glassEffect(.regular, in: .capsule)
        } else {
            self
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.3))
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
        }
    }
}

// MARK: - Preview

#Preview {
    HomeOnboardingIntroView(onSkip: {}, onStartWalkthrough: {})
}
