import SwiftUI
import Lottie

/// SwiftUI wrapper for Lottie animations with control over playback.
/// Supports looping, one-shot playback, and animation speed control.
struct LottieView: UIViewRepresentable {
    let animationName: String
    let loopMode: LottieLoopMode
    let animationSpeed: CGFloat
    let contentMode: UIView.ContentMode
    let playbackTrigger: Int

    /// Called when animation completes (only for non-looping animations)
    var onComplete: (() -> Void)?

    init(
        animationName: String,
        loopMode: LottieLoopMode = .loop,
        animationSpeed: CGFloat = 1.0,
        contentMode: UIView.ContentMode = .scaleAspectFit,
        playbackTrigger: Int = 0,
        onComplete: (() -> Void)? = nil
    ) {
        self.animationName = animationName
        self.loopMode = loopMode
        self.animationSpeed = animationSpeed
        self.contentMode = contentMode
        self.playbackTrigger = playbackTrigger
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
        context.coordinator.currentPlaybackTrigger = playbackTrigger
        context.coordinator.currentLoopMode = loopMode
        context.coordinator.currentAnimationSpeed = animationSpeed

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
        let animationNameChanged = context.coordinator.currentAnimationName != animationName
        let playbackChanged = context.coordinator.currentPlaybackTrigger != playbackTrigger
        let loopModeChanged = context.coordinator.currentLoopMode != loopMode
        let speedChanged = context.coordinator.currentAnimationSpeed != animationSpeed

        if animationNameChanged {
            context.coordinator.currentAnimationName = animationName
            uiView.animation = LottieAnimation.named(animationName)
        }

        if animationNameChanged || playbackChanged || loopModeChanged || speedChanged {
            context.coordinator.currentPlaybackTrigger = playbackTrigger
            context.coordinator.currentLoopMode = loopMode
            context.coordinator.currentAnimationSpeed = animationSpeed
            uiView.loopMode = loopMode
            uiView.animationSpeed = animationSpeed
            uiView.currentProgress = 0
            uiView.play { completed in
                if completed {
                    onComplete?()
                }
            }
        }
    }

    class Coordinator {
        var currentAnimationName: String = ""
        var currentPlaybackTrigger: Int = 0
        var currentLoopMode: LottieLoopMode = .loop
        var currentAnimationSpeed: CGFloat = 1.0
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
