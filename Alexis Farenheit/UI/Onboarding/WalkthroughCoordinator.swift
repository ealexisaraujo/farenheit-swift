import SwiftUI
import Combine

/// Coordinates walkthrough step state and manages transitions between steps.
/// This replaces the complex state management from HomeWalkthroughOverlay.
@Observable
final class WalkthroughCoordinator {
    // MARK: - Published State

    var currentStep: WalkthroughStep = .todaySnapshot
    var isActive: Bool = false
    var targetFrames: [HomeWalkthroughTarget: CGRect] = [:]

    // MARK: - Computed Properties

    var currentStepIndex: Int {
        currentStep.rawValue
    }

    var totalSteps: Int {
        WalkthroughStep.allCases.count
    }

    var isFirstStep: Bool {
        currentStep == .todaySnapshot
    }

    var isLastStep: Bool {
        currentStep == .tools
    }

    var progressText: String {
        "\(currentStepIndex + 1) / \(totalSteps)"
    }

    var currentTarget: HomeWalkthroughTarget {
        currentStep.target
    }

    var currentFrame: CGRect? {
        targetFrames[currentTarget]
    }

    // MARK: - Callbacks

    var onStepChanged: ((WalkthroughStep) -> Void)?
    var onFinished: (() -> Void)?

    // MARK: - Navigation

    func start() {
        currentStep = .todaySnapshot
        isActive = true
    }

    func next() {
        guard !isLastStep else {
            finish()
            return
        }

        let allSteps = WalkthroughStep.allCases
        if let currentIndex = allSteps.firstIndex(of: currentStep),
           currentIndex + 1 < allSteps.count {
            currentStep = allSteps[currentIndex + 1]
            onStepChanged?(currentStep)
        }
    }

    func previous() {
        guard !isFirstStep else { return }

        let allSteps = WalkthroughStep.allCases
        if let currentIndex = allSteps.firstIndex(of: currentStep),
           currentIndex > 0 {
            currentStep = allSteps[currentIndex - 1]
            onStepChanged?(currentStep)
        }
    }

    func skip() {
        finish()
    }

    func finish() {
        isActive = false
        onFinished?()
    }

    // MARK: - Frame Updates

    func updateFrame(_ frame: CGRect, for target: HomeWalkthroughTarget) {
        targetFrames[target] = frame
    }

    func updateFrames(_ frames: [HomeWalkthroughTarget: CGRect]) {
        targetFrames = frames
    }

    // MARK: - Scroll Anchors

    /// Returns the appropriate scroll anchor for the current step's target
    func scrollAnchor(for step: WalkthroughStep) -> UnitPoint {
        switch step {
        case .todaySnapshot:
            return .top
        case .quickActions:
            return UnitPoint(x: 0.5, y: 0.35)
        case .myCities:
            return .center
        case .tools:
            return UnitPoint(x: 0.5, y: 0.3)
        }
    }

    var currentScrollAnchor: UnitPoint {
        scrollAnchor(for: currentStep)
    }
}

// MARK: - SwiftUI Environment

extension EnvironmentValues {
    @Entry var walkthroughCoordinator: WalkthroughCoordinator = WalkthroughCoordinator()
}
