import Foundation
import XCTest
@testable import PolyPayCheckout

/// Verifies optional merchant presentation data used by the native summary card.
final class CheckoutOrderDecodingTests: XCTestCase {
    /// Decodes the server-provided HTTPS merchant avatar without making it required.
    func testDecodesMerchantAvatar() throws {
        let data = Data(#"{"trade_id":"trade_1","mch_order_id":"order_1","currency":"","network":"","amount":11,"actual_amount":11,"address":"","status":0,"expiration_time":2000000000,"merchant_name":"Example","merchant_avatar":"https://example.com/avatar.png"}"#.utf8)

        let order = try JSONDecoder().decode(CheckoutOrder.self, from: data)

        XCTAssertEqual(order.merchantAvatar, "https://example.com/avatar.png")
    }
}
