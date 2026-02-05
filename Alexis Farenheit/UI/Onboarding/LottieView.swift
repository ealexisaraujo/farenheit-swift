import SwiftUI
import Lottie

/// SwiftUI wrapper for Lottie animations with control over playback.
/// Supports looping, one-shot playback, and animation speed control.
struct LottieView: UIViewRepresentable {
    let animationName: String
    let loopMode: LottieLoopMode
    let animationSpeed: CGFloat
    let contentMode: UIView.ContentMode

    /// Called when animation completes (only for non-looping animations)
    var onComplete: (() -> Void)?

    init(
        animationName: String,
        loopMode: LottieLoopMode = .loop,
        animationSpeed: CGFloat = 1.0,
        contentMode: UIView.ContentMode = .scaleAspectFit,
        onComplete: (() -> Void)? = nil
    ) {
        self.animationName = animationName
        self.loopMode = loopMode
        self.animationSpeed = animationSpeed
        self.contentMode = contentMode
        self.onComplete = onComplete
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> LottieAnimationView {
        let animationView = LottieAnimationView(name: animationName)
        animationView.loopMode = loopMode
        animationView.animationSpeed = animationSpeed
        animationView.contentMode = contentMode
        animationView.backgroundBehavior = .pauseAndRestore

        // Track current animation name
        context.coordinator.currentAnimationName = animationName

        // Allow SwiftUI to size the view
        animationView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        animationView.setContentHuggingPriority(.defaultLow, for: .vertical)
        animationView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        animationView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        animationView.play { completed in
            if completed {
                onComplete?()
            }
        }

        return animationView
    }

    func updateUIView(_ uiView: LottieAnimationView, context: Context) {
        // Update animation if name changed
        if context.coordinator.currentAnimationName != animationName {
            context.coordinator.currentAnimationName = animationName
            uiView.animation = LottieAnimation.named(animationName)
            uiView.loopMode = loopMode
            uiView.animationSpeed = animationSpeed
            uiView.play()
        }
    }

    class Coordinator {
        var currentAnimationName: String = ""
    }
}

// MARK: - Convenience Initializers

extension LottieView {
    /// Creates a looping animation (ideal for onboarding hero animations)
    static func looping(_ name: String, speed: CGFloat = 1.0) -> LottieView {
        LottieView(
            animationName: name,
            loopMode: .loop,
            animationSpeed: speed
        )
    }

    /// Creates a one-shot animation (ideal for success/completion animations)
    static func oneShot(_ name: String, speed: CGFloat = 1.0, onComplete: (() -> Void)? = nil) -> LottieView {
        LottieView(
            animationName: name,
            loopMode: .playOnce,
            animationSpeed: speed,
            onComplete: onComplete
        )
    }

    /// Creates an animation that plays once then holds on the last frame
    static func playAndHold(_ name: String, speed: CGFloat = 1.0) -> LottieView {
        LottieView(
            animationName: name,
            loopMode: .playOnce,
            animationSpeed: speed
        )
    }
}

// MARK: - Preview

#Preview("Looping Animation") {
    LottieView.looping("onboarding-thermometer")
        .frame(width: 200, height: 200)
}

#Preview("One-Shot Animation") {
    LottieView.oneShot("onboarding-success")
        .frame(width: 200, height: 200)
}
