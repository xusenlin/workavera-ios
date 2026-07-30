import XCTest
@testable import Workavera

final class ChatApprovalAvailabilityTests: XCTestCase {
    func testApprovalBecomesActionableWhenItsRunBecomesActive() {
        XCTAssertFalse(
            ChatApprovalAvailability.isAwaitingDecision(
                partState: "approval-requested",
                messageRunID: "run-1",
                activeRunID: nil,
                messageStatus: .streaming
            )
        )

        XCTAssertTrue(
            ChatApprovalAvailability.isAwaitingDecision(
                partState: "approval-requested",
                messageRunID: "run-1",
                activeRunID: "run-1",
                messageStatus: .streaming
            )
        )
    }

    func testApprovalIsNotActionableForAnotherOrFinishedRun() {
        for activeRunID in [nil, "run-2"] {
            XCTAssertFalse(
                ChatApprovalAvailability.isAwaitingDecision(
                    partState: "approval-requested",
                    messageRunID: "run-1",
                    activeRunID: activeRunID,
                    messageStatus: .streaming
                )
            )
        }
        for status in [ChatMessageStatus.error, .cancelled] {
            XCTAssertFalse(
                ChatApprovalAvailability.isAwaitingDecision(
                    partState: "approval-requested",
                    messageRunID: "run-1",
                    activeRunID: "run-1",
                    messageStatus: status
                )
            )
        }
    }

    func testOnlyApprovalRequestedStateIsActionable() {
        for state in ["input-available", "approval-responded", "output-available"] {
            XCTAssertFalse(
                ChatApprovalAvailability.isAwaitingDecision(
                    partState: state,
                    messageRunID: "run-1",
                    activeRunID: "run-1",
                    messageStatus: .streaming
                )
            )
        }
    }
}
