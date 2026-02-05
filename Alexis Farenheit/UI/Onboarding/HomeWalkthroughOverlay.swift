import SwiftUI

enum HomeWalkthroughCoordinateSpace {
    static let name = "homeWalkthroughCoordinateSpace"
}

enum HomeWalkthroughTarget: Hashable {
    case todaySnapshot
    case quickActions
    case myCities
    case tools
}

struct HomeWalkthroughStep: Identifiable {
    let id = UUID()
    let target: HomeWalkthroughTarget
    let title: String
    let message: String
    let accent: Color
    let actionTitle: String?
}

struct HomeWalkthroughFramePreferenceKey: PreferenceKey {
    static var defaultValue: [HomeWalkthroughTarget: CGRect] = [:]

    static func reduce(value: inout [HomeWalkthroughTarget: CGRect], nextValue: () -> [HomeWalkthroughTarget: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct HomeWalkthroughTargetModifier: ViewModifier {
    let target: HomeWalkthroughTarget

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: HomeWalkthroughFramePreferenceKey.self,
                    value: [target: proxy.frame(in: .named(HomeWalkthroughCoordinateSpace.name))]
                )
            }
        )
    }
}

extension View {
    func homeWalkthroughTarget(_ target: HomeWalkthroughTarget) -> some View {
        modifier(HomeWalkthroughTargetModifier(target: target))
    }
}

struct HomeWalkthroughOverlay: View {
    let steps: [HomeWalkthroughStep]
    let targetFrames: [HomeWalkthroughTarget: CGRect]
    @Binding var currentStepIndex: Int
    @Binding var isPresented: Bool
    var onStepAction: ((HomeWalkthroughStep) -> Void)?
    var onFinished: (() -> Void)?

    @State private var pulse = false

    var body: some View {
        if steps.isEmpty {
            Color.clear
                .onAppear {
                    isPresented = false
                    onFinished?()
                }
        } else {
            GeometryReader { proxy in
                let canvas = proxy.frame(in: .named(HomeWalkthroughCoordinateSpace.name))
                let size = proxy.size
                let step = steps[clampedIndex(in: steps)]
                let focusRect = localFocusRect(for: step.target, canvas: canvas, size: size)

                ZStack {
                    SpotlightCutoutShape(cutout: focusRect.insetBy(dx: -4, dy: -4))
                        .fill(Color.black.opacity(0.78), style: FillStyle(eoFill: true))
                        .ignoresSafeArea()

                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(step.accent.opacity(0.95), lineWidth: 2.5)
                        .frame(width: focusRect.width + 16, height: focusRect.height + 16)
                        .position(x: focusRect.midX, y: focusRect.midY)
                        .shadow(color: step.accent.opacity(0.45), radius: pulse ? 20 : 10)
                        .scaleEffect(pulse ? 1.015 : 0.99)
                        .animation(
                            .easeInOut(duration: 1.05).repeatForever(autoreverses: true),
                            value: pulse
                        )

                    Button {
                        advance()
                    } label: {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.clear)
                            .frame(width: focusRect.width + 28, height: focusRect.height + 28)
                    }
                    .position(x: focusRect.midX, y: focusRect.midY)
                    .accessibilityLabel(NSLocalizedString("Next walkthrough step", comment: "Accessibility label for walkthrough spotlight tap target"))

                    walkthroughCard(for: step, in: size, focusRect: focusRect)
                }
                .onAppear {
                    pulse = true
                }
            }
            .transition(.opacity)
            .zIndex(100)
        }
    }

    private func walkthroughCard(for step: HomeWalkthroughStep, in size: CGSize, focusRect: CGRect) -> some View {
        let cardWidth = min(size.width - 32, 360)
        let cardHeight: CGFloat = 230
        let yPadding: CGFloat = 16
        let shouldPlaceBelow = focusRect.midY < (size.height * 0.48)

        let cardCenterY: CGFloat
        if shouldPlaceBelow {
            let proposed = focusRect.maxY + yPadding + (cardHeight / 2)
            cardCenterY = min(proposed, size.height - 24 - (cardHeight / 2))
        } else {
            let proposed = focusRect.minY - yPadding - (cardHeight / 2)
            cardCenterY = max(proposed, 24 + (cardHeight / 2))
        }

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(NSLocalizedString("Walkthrough", comment: "Title shown on walkthrough overlay card"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(clampedIndex(in: steps) + 1) / \(steps.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            Text(step.title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)

            Text(step.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let actionTitle = step.actionTitle {
                Button(actionTitle) {
                    onStepAction?(step)
                }
                .buttonStyle(.borderedProminent)
                .tint(step.accent)
            }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Button(NSLocalizedString("Skip", comment: "Walkthrough action to skip onboarding")) {
                    finish()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Spacer()

                if clampedIndex(in: steps) > 0 {
                    Button(NSLocalizedString("Back", comment: "Walkthrough action to go to previous step")) {
                        currentStepIndex = max(0, currentStepIndex - 1)
                    }
                    .buttonStyle(.bordered)
                }

                Button(isLastStep ? NSLocalizedString("Done", comment: "Walkthrough final action") : NSLocalizedString("Next", comment: "Walkthrough next action")) {
                    advance()
                }
                .buttonStyle(.borderedProminent)
                .tint(step.accent)
            }
        }
        .padding(16)
        .frame(width: cardWidth, height: cardHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .position(x: size.width / 2, y: cardCenterY)
    }

    private var isLastStep: Bool {
        clampedIndex(in: steps) >= steps.count - 1
    }

    private func advance() {
        if isLastStep {
            finish()
        } else {
            currentStepIndex += 1
        }
    }

    private func finish() {
        isPresented = false
        onFinished?()
    }

    private func clampedIndex(in steps: [HomeWalkthroughStep]) -> Int {
        guard !steps.isEmpty else { return 0 }
        return min(max(currentStepIndex, 0), steps.count - 1)
    }

    private func localFocusRect(for target: HomeWalkthroughTarget, canvas: CGRect, size: CGSize) -> CGRect {
        if let globalRect = targetFrames[target] {
            let localRect = CGRect(
                x: globalRect.minX - canvas.minX,
                y: globalRect.minY - canvas.minY,
                width: globalRect.width,
                height: globalRect.height
            )
            if localRect.width > 0, localRect.height > 0 {
                return localRect
            }
        }

        let fallbackWidth = size.width - 56
        return CGRect(
            x: 28,
            y: (size.height * 0.45) - 54,
            width: fallbackWidth,
            height: 108
        )
    }
}

private struct SpotlightCutoutShape: Shape {
    let cutout: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.addRoundedRect(
            in: cutout,
            cornerSize: CGSize(width: 24, height: 24)
        )
        return path
    }
}
