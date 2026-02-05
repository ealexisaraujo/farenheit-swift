import SwiftUI

struct HomeOnboardingIntroView: View {
    struct IntroPage: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let message: String
        let accent: Color
    }

    let onSkip: () -> Void
    let onStartWalkthrough: () -> Void

    @State private var currentPage = 0

    private let pages: [IntroPage] = [
        IntroPage(
            icon: "sun.max.fill",
            title: NSLocalizedString("Welcome to Alexis Farenheit", comment: "Onboarding intro first page title"),
            message: NSLocalizedString("Get current weather, world time, and quick city control in one place.", comment: "Onboarding intro first page message"),
            accent: Color(hex: "FFD166")
        ),
        IntroPage(
            icon: "globe.americas.fill",
            title: NSLocalizedString("Your Cities, Your Rhythm", comment: "Onboarding intro second page title"),
            message: NSLocalizedString("Track multiple cities, compare local times, and keep your widget synced.", comment: "Onboarding intro second page message"),
            accent: Color(hex: "4CC9F0")
        ),
        IntroPage(
            icon: "wand.and.stars.inverse",
            title: NSLocalizedString("Interactive Walkthrough", comment: "Onboarding intro third page title"),
            message: NSLocalizedString("We will show every key area of the home screen in under one minute.", comment: "Onboarding intro third page message"),
            accent: Color(hex: "7B61FF")
        )
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(hex: "161827"), Color(hex: "1D1F33")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                header

                TabView(selection: $currentPage) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                        pageCard(page)
                            .padding(.horizontal, 20)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                pageIndicators
                primaryButton
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }
            .padding(.top, 20)
        }
    }

    private var header: some View {
        HStack {
            Spacer()
            Button(NSLocalizedString("Skip", comment: "Onboarding intro action to skip")) {
                onSkip()
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
    }

    private func pageCard(_ page: IntroPage) -> some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .fill(page.accent.opacity(0.22))
                    .frame(width: 120, height: 120)

                Image(systemName: page.icon)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(page.accent)
            }
            .padding(.top, 12)

            Text(page.title)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(page.message)
                .font(.title3)
                .foregroundStyle(.white.opacity(0.78))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)

            Spacer()

            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(.green)
                Text(NSLocalizedString("Quick, optional, and focused on what you need now", comment: "Onboarding reassurance text"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 14)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(page.accent.opacity(0.35), lineWidth: 1)
                )
        )
    }

    private var pageIndicators: some View {
        HStack(spacing: 8) {
            ForEach(0..<pages.count, id: \.self) { index in
                Capsule()
                    .fill(index == currentPage ? Color.white : Color.white.opacity(0.28))
                    .frame(width: index == currentPage ? 26 : 8, height: 8)
                    .animation(.easeInOut(duration: 0.2), value: currentPage)
            }
        }
    }

    private var primaryButton: some View {
        Button {
            if currentPage < pages.count - 1 {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    currentPage += 1
                }
            } else {
                onStartWalkthrough()
            }
        } label: {
            HStack(spacing: 8) {
                Text(currentPage == pages.count - 1
                    ? NSLocalizedString("Start Walkthrough", comment: "Onboarding intro primary CTA on final page")
                    : NSLocalizedString("Continue", comment: "Onboarding intro primary CTA"))
                Image(systemName: currentPage == pages.count - 1 ? "play.fill" : "arrow.right")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color(hex: "4CC9F0"))
    }
}

#Preview {
    HomeOnboardingIntroView(onSkip: {}, onStartWalkthrough: {})
}
