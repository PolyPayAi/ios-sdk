import XCTest
@testable import PolyPayCheckout

/// Guards the server-authoritative public result contract.
final class OutcomeTests: XCTestCase {
    /// Ensures every public outcome still requires server confirmation.
    func testEveryOutcomeRequiresServerConfirmation() {
        let outcomes: [PolyPayCheckoutOutcome] = [
            .closed(tradeID: "trade_12345678"),
            .paymentDetected(tradeID: "trade_12345678"),
            .expired(tradeID: "trade_12345678"),
            .cancelled(tradeID: "trade_12345678"),
            .error(code: "network_error"),
        ]
        XCTAssertTrue(outcomes.allSatisfy(\.requiresServerConfirmation))
    }
}
