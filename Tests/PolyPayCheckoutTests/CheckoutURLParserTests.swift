import Foundation
import XCTest
@testable import PolyPayCheckout

/// Security boundary tests for native checkout URL parsing.
final class CheckoutURLParserTests: XCTestCase {
    /// Accepts exact allowlisted localized payment URLs.
    func testParsesAllowedPaymentURL() throws {
        let url = try XCTUnwrap(URL(string: "https://checkout.polypay.ai/zh/pay/trade_12345678"))
        XCTAssertEqual(
            try CheckoutURLParser.parse(url, allowedHosts: ["checkout.polypay.ai"]),
            "trade_12345678"
        )
    }

    /// Rejects schemes, host suffix attacks, credentials, fragments, and checkout sessions.
    func testRejectsUnsafeURLs() {
        let values = [
            "http://checkout.polypay.ai/pay/trade_12345678",
            "https://checkout.polypay.ai.evil.test/pay/trade_12345678",
            "https://user@checkout.polypay.ai/pay/trade_12345678",
            "https://checkout.polypay.ai/pay/trade_12345678#fragment",
            "https://checkout.polypay.ai/checkout/session_12345678",
        ]
        for value in values {
            XCTAssertThrowsError(
                try CheckoutURLParser.parse(URL(string: value)!, allowedHosts: ["checkout.polypay.ai"])
            )
        }
    }
}
