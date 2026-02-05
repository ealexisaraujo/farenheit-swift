import SwiftUI
import CoreLocation

// MARK: - Onboarding Page Definition

enum OnboardingPage: Int, CaseIterable, Identifiable {
    case welcome = 0
    case location = 1
    case widget = 2
    case ready = 3

    var id: Int { rawValue }
}

struct OnboardingSlideSpec: Identifiable {
    let page: OnboardingPage
    let titleKey: String
    let subtitleKey: String
    let animationName: String
    let backgroundAssetName: String
    let accentColor: Color
    let shouldLoopAnimation: Bool
    let primaryButtonKey: String?

    var id: OnboardingPage { page }

    var hasPermissionAction: Bool {
        page == .location
    }

    var isFinalPage: Bool {
        page == .ready
    }
}

struct OnboardingVisualTheme {
    struct GradientPalette {
        let top: Color
        let middle: Color
        let bottom: Color
    }

    let backgroundGradient: GradientPalette
    let primaryText: Color
    let secondaryText: Color
    let tertiaryText: Color
    let indicatorActive: Color
    let indicatorInactive: Color
    let buttonText: Color
    let glassStroke: Color
    let imageOpacity: Double
    let overlayOpacity: Double
    let titleFont: Font
    let subtitleFont: Font
    let statusFont: Font
    let animationSize: CGFloat
    let horizontalPadding: CGFloat
    let railCornerRadius: CGFloat
    let buttonCornerRadius: CGFloat
    let indicatorActiveWidth: CGFloat
    let indicatorInactiveWidth: CGFloat
    let indicatorHeight: CGFloat
    let pageTransitionDuration: Double
    let springResponse: Double
    let springDamping: Double
    let backgroundOrbBlur: CGFloat
    let backgroundOrbOpacity: Double

    static func forColorScheme(_ scheme: ColorScheme) -> Self {
        switch scheme {
        case .dark:
            return OnboardingVisualTheme(
                backgroundGradient: .init(
                    top: Color(hex: "04070D"),
                    middle: Color(hex: "111C33"),
                    bottom: Color(hex: "090C14")
                ),
                primaryText: .white,
                secondaryText: Color.white.opacity(0.82),
                tertiaryText: Color.white.opacity(0.62),
                indicatorActive: .white,
                indicatorInactive: Color.white.opacity(0.28),
                buttonText: .white,
                glassStroke: Color.white.opacity(0.16),
                imageOpacity: 0.42,
                overlayOpacity: 0.72,
                titleFont: .system(size: 36, weight: .bold, design: .rounded),
                subtitleFont: .system(size: 17, weight: .medium, design: .rounded),
                statusFont: .footnote.weight(.medium),
                animationSize: 250,
                horizontalPadding: 22,
                railCornerRadius: 26,
                buttonCornerRadius: 18,
                indicatorActiveWidth: 30,
                indicatorInactiveWidth: 10,
                indicatorHeight: 6,
                pageTransitionDuration: 0.45,
                springResponse: 0.48,
                springDamping: 0.84,
                backgroundOrbBlur: 36,
                backgroundOrbOpacity: 0.35
            )
        case .light:
            return OnboardingVisualTheme(
                backgroundGradient: .init(
                    top: Color(hex: "EAF2FF"),
                    middle: Color(hex: "DCE9FF"),
                    bottom: Color(hex: "F8FBFF")
                ),
                primaryText: Color(hex: "101A2B"),
                secondaryText: Color(hex: "2A3F5C").opacity(0.86),
                tertiaryText: Color(hex: "395170").opacity(0.74),
                indicatorActive: Color(hex: "163C78"),
                indicatorInactive: Color(hex: "163C78").opacity(0.22),
                buttonText: Color(hex: "0F1C2F"),
                glassStroke: Color.white.opacity(0.42),
                imageOpacity: 0.24,
                overlayOpacity: 0.36,
                titleFont: .system(size: 34, weight: .bold, design: .rounded),
                subtitleFont: .system(size: 17, weight: .medium, design: .rounded),
                statusFont: .footnote.weight(.medium),
                animationSize: 236,
                horizontalPadding: 22,
                railCornerRadius: 26,
                buttonCornerRadius: 18,
                indicatorActiveWidth: 30,
                indicatorInactiveWidth: 10,
                indicatorHeight: 6,
                pageTransitionDuration: 0.45,
                springResponse: 0.48,
                springDamping: 0.86,
                backgroundOrbBlur: 34,
                backgroundOrbOpacity: 0.24
            )
        @unknown default:
            return Self.forColorScheme(.dark)
        }
    }
}

struct OnboardingFlowState: Equatable {
    var selectedPage: OnboardingPage = .welcome
    var hasInteractedWithLocationPrompt = false
    private(set) var hasAutoAdvancedFromLocation = false

    mutating func advance() -> Bool {
        let pages = OnboardingPage.allCases
        guard let currentIndex = pages.firstIndex(of: selectedPage) else {
            return false
        }

        let nextIndex = currentIndex + 1
        guard nextIndex < pages.count else {
            return true
        }

        selectedPage = pages[nextIndex]
        return false
    }

    mutating func goBack() {
        let pages = OnboardingPage.allCases
        guard let currentIndex = pages.firstIndex(of: selectedPage), currentIndex > 0 else {
            return
        }

        selectedPage = pages[currentIndex - 1]
    }

    mutating func registerLocationInteraction() {
        hasInteractedWithLocationPrompt = true
    }

    func canContinueFromLocation(status: CLAuthorizationStatus) -> Bool {
        hasInteractedWithLocationPrompt || status != .notDetermined
    }

    mutating func shouldAutoAdvance(after status: CLAuthorizationStatus) -> Bool {
        guard selectedPage == .location else { return false }
        guard !hasAutoAdvancedFromLocation else { return false }

        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            hasAutoAdvancedFromLocation = true
            return true
        case .denied, .restricted, .notDetermined:
            return false
        @unknown default:
            return false
        }
    }
}

enum OnboardingLocationStatusMessage {
    static func key(for status: CLAuthorizationStatus) -> String {
        switch status {
        case .authorizedAlways:
            return "onboarding.location.status.always"
        case .authorizedWhenInUse:
            return "onboarding.location.status.whenInUse"
        case .denied, .restricted:
            return "onboarding.location.status.denied"
        case .notDetermined:
            return "onboarding.location.status.notDetermined"
        @unknown default:
            return "onboarding.location.status.notDetermined"
        }
    }
}

// MARK: - Walkthrough Step Definition

enum WalkthroughStep: Int, CaseIterable, Identifiable {
    case todaySnapshot = 0
    case quickActions = 1
    case myCities = 2
    case tools = 3

    var id: Int { rawValue }

    var animationName: String {
        switch self {
        case .todaySnapshot: return "walkthrough-tap"
        case .quickActions: return "walkthrough-tap"
        case .myCities: return "walkthrough-swipe"
        case .tools: return "walkthrough-expand"
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .todaySnapshot: return "walkthrough.step1.title"
        case .quickActions: return "walkthrough.step2.title"
        case .myCities: return "walkthrough.step3.title"
        case .tools: return "walkthrough.step4.title"
        }
    }

    var message: LocalizedStringKey {
        switch self {
        case .todaySnapshot: return "walkthrough.step1.message"
        case .quickActions: return "walkthrough.step2.message"
        case .myCities: return "walkthrough.step3.message"
        case .tools: return "walkthrough.step4.message"
        }
    }

    var accentColor: Color {
        switch self {
        case .todaySnapshot: return .cyan
        case .quickActions: return .blue
        case .myCities: return .indigo
        case .tools: return .teal
        }
    }

    var target: HomeWalkthroughTarget {
        switch self {
        case .todaySnapshot: return .todaySnapshot
        case .quickActions: return .quickActions
        case .myCities: return .myCities
        case .tools: return .tools
        }
    }
}

// MARK: - Onboarding Configuration

struct OnboardingConfiguration {
    static let shared = OnboardingConfiguration()

    let slides: [OnboardingSlideSpec] = [
        OnboardingSlideSpec(
            page: .welcome,
            titleKey: "onboarding.page1.title",
            subtitleKey: "onboarding.page1.subtitle",
            animationName: "onboarding-thermometer",
            backgroundAssetName: "OnboardingBGWelcome",
            accentColor: Color(hex: "FF6B6B"),
            shouldLoopAnimation: true,
            primaryButtonKey: nil
        ),
        OnboardingSlideSpec(
            page: .location,
            titleKey: "onboarding.page2.title",
            subtitleKey: "onboarding.page2.subtitle",
            animationName: "onboarding-location",
            backgroundAssetName: "OnboardingBGCities",
            accentColor: Color(hex: "4CC9F0"),
            shouldLoopAnimation: true,
            primaryButtonKey: "onboarding.page2.button"
        ),
        OnboardingSlideSpec(
            page: .widget,
            titleKey: "onboarding.page3.title",
            subtitleKey: "onboarding.page3.subtitle",
            animationName: "onboarding-widget",
            backgroundAssetName: "OnboardingBGWalkthrough",
            accentColor: Color(hex: "7B61FF"),
            shouldLoopAnimation: true,
            primaryButtonKey: nil
        ),
        OnboardingSlideSpec(
            page: .ready,
            titleKey: "onboarding.page4.title",
            subtitleKey: "onboarding.page4.subtitle",
            animationName: "onboarding-success",
            backgroundAssetName: "OnboardingBGWalkthrough",
            accentColor: Color(hex: "33C759"),
            shouldLoopAnimation: false,
            primaryButtonKey: "onboarding.page4.button"
        )
    ]

    private init() {}

    func slide(for page: OnboardingPage) -> OnboardingSlideSpec {
        slides.first(where: { $0.page == page }) ?? slides[0]
    }
}
