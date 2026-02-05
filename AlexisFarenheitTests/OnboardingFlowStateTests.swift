import XCTest
import CoreLocation

@testable import Alexis_Farenheit

final class OnboardingFlowStateTests: XCTestCase {

    func test_advanceMovesThroughPagesAndCompletesOnLastPage() {
        var state = OnboardingFlowState()

        XCTAssertEqual(state.selectedPage, .welcome)
        XCTAssertFalse(state.advance())
        XCTAssertEqual(state.selectedPage, .location)

        XCTAssertFalse(state.advance())
        XCTAssertEqual(state.selectedPage, .widget)

        XCTAssertFalse(state.advance())
        XCTAssertEqual(state.selectedPage, .ready)

        XCTAssertTrue(state.advance(), "Advancing on final page should signal completion.")
        XCTAssertEqual(state.selectedPage, .ready)
    }

    func test_goBackMovesToPreviousPage() {
        var state = OnboardingFlowState()
        state.selectedPage = .widget
        state.goBack()
        XCTAssertEqual(state.selectedPage, .location)

        state.goBack()
        XCTAssertEqual(state.selectedPage, .welcome)

        state.goBack()
        XCTAssertEqual(state.selectedPage, .welcome, "Going back on first page should be a no-op.")
    }

    func test_canContinueFromLocationRequiresInteractionWhenNotDetermined() {
        var state = OnboardingFlowState()
        state.selectedPage = .location
        XCTAssertFalse(state.canContinueFromLocation(status: .notDetermined))

        state.registerLocationInteraction()
        XCTAssertTrue(state.canContinueFromLocation(status: .notDetermined))
    }

    func test_canContinueFromLocationAllowedIfPermissionPreviouslyDecided() {
        var state = OnboardingFlowState()
        state.selectedPage = .location
        XCTAssertTrue(state.canContinueFromLocation(status: .denied))
        XCTAssertTrue(state.canContinueFromLocation(status: .authorizedWhenInUse))
    }

    func test_shouldAutoAdvanceOnlyOnceAfterPositiveAuthorization() {
        var state = OnboardingFlowState()
        state.selectedPage = .location

        XCTAssertTrue(state.shouldAutoAdvance(after: .authorizedWhenInUse))
        XCTAssertFalse(state.shouldAutoAdvance(after: .authorizedAlways), "Auto-advance should only fire once.")
    }

    func test_shouldAutoAdvanceDoesNothingOutsideLocationPage() {
        var state = OnboardingFlowState()
        state.selectedPage = .widget
        XCTAssertFalse(state.shouldAutoAdvance(after: .authorizedAlways))
    }
}
