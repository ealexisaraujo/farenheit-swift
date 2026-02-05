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

    private let focusPadding: CGFloat = 4
    private let tapPadding: CGFloat = 12

    var body: some View {
        if steps.isEmpty {
            Color.clear
                .onAppear {
                    isPresented = false
                    onFinished?()
                }
        } else {
            GeometryReader { proxy in
                let safeAreaTop = proxy.safeAreaInsets.top
                let size = proxy.size
                let step = steps[clampedIndex(in: steps)]
                // Use global coordinate space to get absolute screen position
                let overlayFrameInGlobal = proxy.frame(in: .global)
                let focusRect = globalFocusRect(
                    for: step.target,
                    overlayGlobalOrigin: overlayFrameInGlobal.origin,
                    safeAreaTop: safeAreaTop,
                    size: size
                )

                ZStack {
                    // Dark overlay with cutout using compositingGroup + destinationOut
                    // This avoids coordinate system issues from ignoresSafeArea on the shape
                    ZStack {
                        Rectangle()
                            .fill(Color.black.opacity(0.78))

                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .frame(
                                width: focusRect.width + (focusPadding * 2),
                                height: focusRect.height + (focusPadding * 2)
                            )
                            // Offset by safeAreaTop to compensate for .ignoresSafeArea() shifting coordinate origin
                            .position(x: focusRect.midX, y: focusRect.midY + safeAreaTop)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                    .ignoresSafeArea()

                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(step.accent.opacity(0.95), lineWidth: 2.5)
                        .frame(
                            width: focusRect.width + (focusPadding * 2),
                            height: focusRect.height + (focusPadding * 2)
                        )
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
                            .frame(
                                width: focusRect.width + (tapPadding * 2),
                                height: focusRect.height + (tapPadding * 2)
                            )
                    }
                    .position(x: focusRect.midX, y: focusRect.midY)
                    .accessibilityLabel(NSLocalizedString("Next walkthrough step", comment: "Accessibility label for walkthrough spotlight tap target"))

                    walkthroughCard(for: step, in: size, focusRect: focusRect)
                }
                .onAppear {
                    pulse = true
                    logOverlay(
                        step: step,
                        focusRect: focusRect,
                        source: "appear",
                        overlayGlobalOrigin: overlayFrameInGlobal.origin,
                        safeAreaTop: safeAreaTop
                    )
                }
                .onChange(of: currentStepIndex) { _, _ in
                    let nextStep = steps[clampedIndex(in: steps)]
                    let nextRect = globalFocusRect(
                        for: nextStep.target,
                        overlayGlobalOrigin: overlayFrameInGlobal.origin,
                        safeAreaTop: safeAreaTop,
                        size: size
                    )
                    logOverlay(
                        step: nextStep,
                        focusRect: nextRect,
                        source: "stepChanged",
                        overlayGlobalOrigin: overlayFrameInGlobal.origin,
                        safeAreaTop: safeAreaTop
                    )
                }
                .onChange(of: targetFrames) { _, _ in
                    let currentStep = steps[clampedIndex(in: steps)]
                    let currentRect = globalFocusRect(
                        for: currentStep.target,
                        overlayGlobalOrigin: overlayFrameInGlobal.origin,
                        safeAreaTop: safeAreaTop,
                        size: size
                    )
                    logOverlay(
                        step: currentStep,
                        focusRect: currentRect,
                        source: "framesChanged",
                        overlayGlobalOrigin: overlayFrameInGlobal.origin,
                        safeAreaTop: safeAreaTop
                    )
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

    /// Calculate the focus rectangle in overlay-local coordinates.
    /// The targetFrames are in the named coordinate space (ScrollView content).
    /// We need to convert them to the overlay's local coordinate space.
    private func globalFocusRect(
        for target: HomeWalkthroughTarget,
        overlayGlobalOrigin: CGPoint,
        safeAreaTop: CGFloat,
        size: CGSize
    ) -> CGRect {
        if let targetRect = targetFrames[target] {
            // targetRect is in the named coordinate space (relative to the ZStack with coordinateSpace modifier)
            // The overlay's GeometryReader origin is also relative to that same ZStack
            // Since the named coordinate space is on the ZStack, and the overlay fills the ZStack,
            // the target frames are already in the correct coordinate space.
            // However, we need to account for any safe area offset between the overlay and the content.

            // The targetRect.minY is relative to the coordinateSpace origin (top of ZStack content area)
            // The overlay's local coordinate system has (0,0) at its top-left corner
            // These should match since both are children of the same ZStack
            let localRect = CGRect(
                x: targetRect.minX,
                y: targetRect.minY,
                width: targetRect.width,
                height: targetRect.height
            )
            if localRect.width > 0, localRect.height > 0,
               localRect.minY >= -50, // Allow some negative (scrolled above)
               localRect.maxY <= size.height + 50 { // Allow some overflow (scrolled below)
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

    private func logOverlay(
        step: HomeWalkthroughStep,
        focusRect: CGRect,
        source: String,
        overlayGlobalOrigin: CGPoint,
        safeAreaTop: CGFloat
    ) {
#if DEBUG
        let targetRect = targetFrames[step.target]
        let line =
            "[WalkthroughOverlay] source=\(source) step=\(clampedIndex(in: steps)) " +
            "target=\(targetName(step.target)) " +
            "focus=\(rectSummary(focusRect)) " +
            "targetFrame=\(rectSummary(targetRect)) " +
            "overlayOrigin=(\(Int(overlayGlobalOrigin.x)),\(Int(overlayGlobalOrigin.y))) " +
            "safeTop=\(Int(safeAreaTop))"
        print(line)
#endif
    }

    private func targetName(_ target: HomeWalkthroughTarget) -> String {
        switch target {
        case .todaySnapshot:
            return "todaySnapshot"
        case .quickActions:
            return "quickActions"
        case .myCities:
            return "myCities"
        case .tools:
            return "tools"
        }
    }

    private func rectSummary(_ rect: CGRect?) -> String {
        guard let rect else { return "nil" }
        let x = Int(rect.minX.rounded())
        let y = Int(rect.minY.rounded())
        let width = Int(rect.width.rounded())
        let height = Int(rect.height.rounded())
        return "x:\(x),y:\(y),w:\(width),h:\(height)"
    }
}

