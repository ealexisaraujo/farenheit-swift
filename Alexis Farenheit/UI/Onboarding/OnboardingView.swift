import SwiftUI
import CoreLocation

/// New onboarding flow with 4 Lottie-animated pages.
/// Integrates location permission request on page 2.
struct OnboardingView: View {
    let locationService: LocationService
    let onComplete: () -> Void
    let onStartWalkthrough: () -> Void

    @State private var currentPage: OnboardingPage = .welcome
    @State private var dragOffset: CGFloat = 0
    @State private var hasAppeared = false
    @State private var locationPermissionGranted = false

    private let config = OnboardingConfiguration.shared
    private let pages = OnboardingPage.allCases

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background gradient
                backgroundGradient

                // Animated background elements
                floatingOrbs(size: geometry.size)

                VStack(spacing: 0) {
                    // Skip button
                    skipButton
                        .padding(.top, 16)

                    // Page content with gesture
                    pageContent(size: geometry.size)

                    // Bottom section
                    VStack(spacing: 20) {
                        pageIndicators
                        navigationButtons
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.2)) {
                hasAppeared = true
            }
            // Check current location permission status
            locationPermissionGranted = locationService.authorizationStatus == .authorizedWhenInUse ||
                                       locationService.authorizationStatus == .authorizedAlways
        }
        .onChange(of: locationService.authorizationStatus) { _, newStatus in
            if newStatus == .authorizedWhenInUse || newStatus == .authorizedAlways {
                locationPermissionGranted = true
                // Auto-advance from location page when permission granted
                if currentPage == .location {
                    advanceToNextPage()
                }
            }
        }
        .onChange(of: currentPage) { _, _ in
            triggerHaptic()
        }
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color.black,
                Color(hex: "0D0F1A"),
                Color(hex: "151829")
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func floatingOrbs(size: CGSize) -> some View {
        ZStack {
            // Large orb top-left
            Circle()
                .fill(
                    RadialGradient(
                        colors: [currentPage.accentColor.opacity(0.3), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 100
                    )
                )
                .frame(width: 200, height: 200)
                .offset(x: -size.width * 0.3, y: -size.height * 0.3)
                .blur(radius: 40)

            // Medium orb bottom-right
            Circle()
                .fill(
                    RadialGradient(
                        colors: [currentPage.accentColor.opacity(0.2), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 80
                    )
                )
                .frame(width: 160, height: 160)
                .offset(x: size.width * 0.25, y: size.height * 0.35)
                .blur(radius: 30)
        }
        .animation(.easeInOut(duration: 0.8), value: currentPage)
    }

    // MARK: - Skip Button

    private var skipButton: some View {
        HStack {
            Spacer()
            Button {
                triggerHaptic(.light)
                skipOnboarding()
            } label: {
                Text("onboarding.skip")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                    )
            }
        }
        .padding(.horizontal, 20)
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : -20)
    }

    // MARK: - Page Content

    private func pageContent(size: CGSize) -> some View {
        ZStack {
            ForEach(pages) { page in
                OnboardingPageView(
                    page: page,
                    isVisible: page == currentPage,
                    onAction: { handlePageAction(page) }
                )
                .offset(x: pageOffset(for: page, containerWidth: size.width))
                .opacity(page == currentPage ? 1 : 0.3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .gesture(dragGesture)
    }

    private func pageOffset(for page: OnboardingPage, containerWidth: CGFloat) -> CGFloat {
        let pageIndex = CGFloat(page.rawValue)
        let currentIndex = CGFloat(currentPage.rawValue)
        return (pageIndex - currentIndex) * containerWidth + dragOffset
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation.width
            }
            .onEnded { value in
                let threshold: CGFloat = 50
                withAnimation(.spring(response: config.springResponse, dampingFraction: config.springDamping)) {
                    if value.translation.width < -threshold {
                        advanceToNextPage()
                    } else if value.translation.width > threshold {
                        goToPreviousPage()
                    }
                    dragOffset = 0
                }
            }
    }

    // MARK: - Page Indicators

    private var pageIndicators: some View {
        HStack(spacing: 10) {
            ForEach(pages) { page in
                Capsule()
                    .fill(page == currentPage ? Color.white : Color.white.opacity(0.3))
                    .frame(
                        width: page == currentPage ? config.indicatorActiveWidth : config.indicatorInactiveWidth,
                        height: config.indicatorHeight
                    )
                    .shadow(
                        color: page == currentPage ? currentPage.accentColor.opacity(0.5) : .clear,
                        radius: 4
                    )
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack(spacing: 16) {
            // Back button (only show after first page)
            if currentPage != .welcome {
                Button {
                    triggerHaptic(.light)
                    goToPreviousPage()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 50, height: 50)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                        )
                }
            }

            Spacer()

            // Next/Continue button (unless page has its own action button)
            if currentPage.buttonTitle == nil {
                Button {
                    triggerHaptic(.medium)
                    advanceToNextPage()
                } label: {
                    HStack(spacing: 8) {
                        Text(currentPage.isFinalPage ? "walkthrough.done" : "walkthrough.next")
                            .fontWeight(.semibold)
                        Image(systemName: "arrow.right")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(
                        Capsule()
                            .fill(currentPage.accentColor)
                    )
                    .shadow(color: currentPage.accentColor.opacity(0.4), radius: 12, y: 4)
                }
            }
        }
        .opacity(hasAppeared ? 1 : 0)
    }

    // MARK: - Actions

    private func handlePageAction(_ page: OnboardingPage) {
        switch page {
        case .location:
            requestLocationPermission()
        case .ready:
            completeOnboarding()
        default:
            break
        }
    }

    private func requestLocationPermission() {
        locationService.requestPermission(preferAlways: true)
        // If already granted, advance immediately
        if locationPermissionGranted {
            advanceToNextPage()
        }
        // Otherwise, onChange will handle advancement when permission changes
    }

    private func advanceToNextPage() {
        guard let nextIndex = pages.firstIndex(of: currentPage).map({ $0 + 1 }),
              nextIndex < pages.count else {
            completeOnboarding()
            return
        }
        withAnimation(.spring(response: config.springResponse, dampingFraction: config.springDamping)) {
            currentPage = pages[nextIndex]
        }
    }

    private func goToPreviousPage() {
        guard let prevIndex = pages.firstIndex(of: currentPage).map({ $0 - 1 }),
              prevIndex >= 0 else { return }
        withAnimation(.spring(response: config.springResponse, dampingFraction: config.springDamping)) {
            currentPage = pages[prevIndex]
        }
    }

    private func skipOnboarding() {
        onComplete()
    }

    private func completeOnboarding() {
        onStartWalkthrough()
    }

    private func triggerHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .soft) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

// MARK: - Preview

#Preview {
    OnboardingView(
        locationService: LocationService(),
        onComplete: { print("Complete") },
        onStartWalkthrough: { print("Start walkthrough") }
    )
}
