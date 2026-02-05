import SwiftUI
import CoreLocation
import UIKit

/// Cinematic onboarding flow with native SwiftUI paging and location permission integration.
struct OnboardingView: View {
    let locationService: LocationService
    let onComplete: () -> Void
    let onStartWalkthrough: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var flowState = OnboardingFlowState()
    @State private var hasAppeared = false
    @State private var animateBackground = false

    private let config = OnboardingConfiguration.shared

    private var theme: OnboardingVisualTheme {
        OnboardingVisualTheme.forColorScheme(colorScheme)
    }

    private var slides: [OnboardingSlideSpec] {
        config.slides
    }

    private var currentSlide: OnboardingSlideSpec {
        config.slide(for: flowState.selectedPage)
    }

    private var locationStatus: CLAuthorizationStatus {
        locationService.authorizationStatus
    }

    private var locationMessageKey: String {
        OnboardingLocationStatusMessage.key(for: locationStatus)
    }

    private var canContinueFromLocation: Bool {
        flowState.canContinueFromLocation(status: locationStatus)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                backgroundLayer(size: geometry.size)

                VStack(spacing: 0) {
                    topBar
                        .padding(.horizontal, theme.horizontalPadding)
                        .padding(.top, 12)

                    pager
                        .padding(.top, 8)

                    bottomRail
                        .padding(.horizontal, theme.horizontalPadding)
                        .padding(.bottom, 24)
                        .padding(.top, 8)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeOut(duration: 0.5).delay(0.12)) {
                hasAppeared = true
            }
            if !reduceMotion {
                animateBackground = true
            }
        }
        .onChange(of: locationService.authorizationStatus) { _, newStatus in
            let shouldAutoAdvance = flowState.shouldAutoAdvance(after: newStatus)
            guard shouldAutoAdvance else { return }
            withAnimation(.spring(response: theme.springResponse, dampingFraction: theme.springDamping)) {
                advanceToNextPage()
            }
        }
        .onChange(of: flowState.selectedPage) { _, _ in
            triggerHaptic()
        }
    }

    // MARK: - Background

    private func backgroundLayer(size: CGSize) -> some View {
        ZStack {
            ForEach(slides) { slide in
                Image(slide.backgroundAssetName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .opacity(flowState.selectedPage == slide.page ? theme.imageOpacity : 0)
                    .animation(.easeInOut(duration: theme.pageTransitionDuration), value: flowState.selectedPage)
            }

            Image("OnboardingBGOverlay")
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
                .opacity(theme.overlayOpacity * 0.55)

            LinearGradient(
                colors: [
                    theme.backgroundGradient.top,
                    theme.backgroundGradient.middle,
                    theme.backgroundGradient.bottom
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .opacity(theme.overlayOpacity)

            floatingOrbs(size: size)
        }
        .ignoresSafeArea()
    }

    private func floatingOrbs(size: CGSize) -> some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [currentSlide.accentColor.opacity(theme.backgroundOrbOpacity), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 132
                    )
                )
                .frame(width: 280, height: 280)
                .offset(
                    x: animateBackground ? -(size.width * 0.26) : -(size.width * 0.18),
                    y: animateBackground ? -(size.height * 0.34) : -(size.height * 0.28)
                )
                .blur(radius: theme.backgroundOrbBlur)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [currentSlide.accentColor.opacity(theme.backgroundOrbOpacity * 0.8), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 104
                    )
                )
                .frame(width: 220, height: 220)
                .offset(
                    x: animateBackground ? (size.width * 0.24) : (size.width * 0.18),
                    y: animateBackground ? (size.height * 0.31) : (size.height * 0.24)
                )
                .blur(radius: theme.backgroundOrbBlur * 0.88)
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 6.8).repeatForever(autoreverses: true),
            value: animateBackground
        )
        .animation(.easeInOut(duration: 0.65), value: flowState.selectedPage)
    }

    // MARK: - Layout

    private var topBar: some View {
        HStack {
            Spacer()

            Button {
                triggerHaptic(.light)
                skipOnboarding()
            } label: {
                Text("onboarding.skip")
                    .font(.subheadline.bold())
                    .foregroundStyle(theme.buttonText.opacity(0.94))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onboardingGlass(interactive: true, cornerRadius: 16)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(theme.glassStroke, lineWidth: 1)
            )
            .accessibilityLabel(Text("onboarding.skip"))
        }
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : -16)
        .animation(.easeOut(duration: 0.45), value: hasAppeared)
    }

    private var pager: some View {
        TabView(selection: $flowState.selectedPage) {
            ForEach(slides) { slide in
                OnboardingPageView(
                    slide: slide,
                    theme: theme,
                    isActive: flowState.selectedPage == slide.page,
                    reduceMotion: reduceMotion
                )
                .tag(slide.page)
                .padding(.bottom, 6)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(.easeInOut(duration: theme.pageTransitionDuration), value: flowState.selectedPage)
    }

    private var bottomRail: some View {
        VStack(spacing: 14) {
            pageIndicators
            actionSection

            if flowState.selectedPage == .location {
                locationStatusMessage
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .onboardingGlass(interactive: false, cornerRadius: theme.railCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: theme.railCornerRadius, style: .continuous)
                .strokeBorder(theme.glassStroke, lineWidth: 1)
        )
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 18)
        .animation(.easeOut(duration: 0.45), value: hasAppeared)
    }

    private var pageIndicators: some View {
        HStack(spacing: 10) {
            ForEach(slides) { slide in
                Capsule(style: .continuous)
                    .fill(slide.page == flowState.selectedPage ? theme.indicatorActive : theme.indicatorInactive)
                    .frame(
                        width: slide.page == flowState.selectedPage ? theme.indicatorActiveWidth : theme.indicatorInactiveWidth,
                        height: theme.indicatorHeight
                    )
                    .shadow(
                        color: slide.page == flowState.selectedPage ? currentSlide.accentColor.opacity(0.45) : .clear,
                        radius: 8
                    )
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: flowState.selectedPage)
    }

    private var actionSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                if flowState.selectedPage != .welcome {
                    backButton
                }

                primaryActionButton
            }

            if flowState.selectedPage == .location {
                continueWithoutLocationButton
            }
        }
    }

    private var backButton: some View {
        Button {
            triggerHaptic(.light)
            goToPreviousPage()
        } label: {
            Image(systemName: "chevron.left")
                .font(.headline)
                .foregroundStyle(theme.buttonText.opacity(0.9))
                .frame(width: 46, height: 46)
        }
        .buttonStyle(.plain)
        .onboardingGlass(interactive: true, cornerRadius: 14)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(theme.glassStroke, lineWidth: 1)
        )
        .accessibilityLabel(Text("walkthrough.back"))
    }

    private var primaryActionButton: some View {
        Button {
            handlePrimaryAction()
        } label: {
            HStack(spacing: 8) {
                if flowState.selectedPage == .location {
                    Image(systemName: locationStatus == .denied || locationStatus == .restricted ? "gearshape.fill" : "location.fill")
                } else if flowState.selectedPage == .ready {
                    Image(systemName: "sparkles")
                } else {
                    Image(systemName: "arrow.right")
                }

                Text(primaryActionTitle)
                    .bold()
            }
            .font(.headline)
            .foregroundStyle(theme.buttonText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: theme.buttonCornerRadius, style: .continuous)
                    .fill(currentSlide.accentColor.gradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: theme.buttonCornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.3), lineWidth: 1)
            )
            .shadow(color: currentSlide.accentColor.opacity(0.36), radius: 16, y: 6)
        }
        .buttonStyle(.plain)
    }

    private var continueWithoutLocationButton: some View {
        Button {
            triggerHaptic(.soft)
            advanceWithAnimation()
        } label: {
            Text("onboarding.location.continue")
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(theme.buttonText.opacity(canContinueFromLocation ? 0.92 : 0.5))
        }
        .buttonStyle(.plain)
        .onboardingGlass(interactive: canContinueFromLocation, cornerRadius: 14)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(theme.glassStroke, lineWidth: 1)
        )
        .disabled(!canContinueFromLocation)
    }

    private var locationStatusMessage: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(currentSlide.accentColor)
            Text(LocalizedStringKey(locationMessageKey))
                .font(theme.statusFont)
                .foregroundStyle(theme.tertiaryText)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .animation(.easeOut(duration: 0.24), value: locationStatus)
    }

    private var primaryActionTitle: LocalizedStringKey {
        switch flowState.selectedPage {
        case .location:
            if locationStatus == .denied || locationStatus == .restricted {
                return "onboarding.location.openSettings"
            }
            return "onboarding.page2.button"
        case .ready:
            return "onboarding.page4.button"
        case .welcome, .widget:
            return "walkthrough.next"
        }
    }

    // MARK: - Actions

    private func handlePrimaryAction() {
        switch flowState.selectedPage {
        case .location:
            handleLocationAction()
        case .ready:
            triggerHaptic(.medium)
            completeOnboarding()
        case .welcome, .widget:
            triggerHaptic(.medium)
            advanceWithAnimation()
        }
    }

    private func handleLocationAction() {
        triggerHaptic(.medium)
        flowState.registerLocationInteraction()

        switch locationStatus {
        case .denied, .restricted:
            openSystemSettings()
        case .authorizedAlways, .authorizedWhenInUse, .notDetermined:
            locationService.requestPermission(preferAlways: true)
        @unknown default:
            locationService.requestPermission(preferAlways: true)
        }
    }

    private func advanceWithAnimation() {
        withAnimation(.spring(response: theme.springResponse, dampingFraction: theme.springDamping)) {
            advanceToNextPage()
        }
    }

    private func advanceToNextPage() {
        let didFinish = flowState.advance()
        if didFinish {
            completeOnboarding()
        }
    }

    private func goToPreviousPage() {
        withAnimation(.spring(response: theme.springResponse, dampingFraction: theme.springDamping)) {
            flowState.goBack()
        }
    }

    private func skipOnboarding() {
        onComplete()
    }

    private func completeOnboarding() {
        onStartWalkthrough()
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(url)
    }

    private func triggerHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .soft) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

private extension View {
    @ViewBuilder
    func onboardingGlass(interactive: Bool, cornerRadius: CGFloat) -> some View {
        if #available(iOS 26.0, *) {
            if interactive {
                self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius, style: .continuous))
            } else {
                self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius, style: .continuous))
            }
        } else {
            self.background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        }
    }
}

// MARK: - Preview

#Preview("Dark") {
    OnboardingView(
        locationService: LocationService(),
        onComplete: { print("complete") },
        onStartWalkthrough: { print("walkthrough") }
    )
    .preferredColorScheme(.dark)
}

#Preview("Light") {
    OnboardingView(
        locationService: LocationService(),
        onComplete: { print("complete") },
        onStartWalkthrough: { print("walkthrough") }
    )
    .preferredColorScheme(.light)
}
