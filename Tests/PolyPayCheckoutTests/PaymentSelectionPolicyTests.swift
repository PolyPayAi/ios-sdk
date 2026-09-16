import XCTest
@testable import PolyPayCheckout

/// Tests deterministic defaults used by the native selection page.
final class PaymentSelectionPolicyTests: XCTestCase {
    /// Prefers the merchant default over general SDK heuristics.
    func testMerchantDefaultWins() {
        let methods = [
            method("Tron", ["USDT"]),
            method("Ethereum", ["USDC", "ETH"], defaultCurrency: "USDC"),
        ]
        XCTAssertEqual(
            PaymentSelectionPolicy.preferred(methods),
            PaymentSelection(currency: "USDC", network: "Ethereum")
        )
    }

    /// Uses USDT on Tron when the merchant has not configured a default.
    func testTronUSDTFallback() {
        let methods = [
            method("Ethereum", ["USDT", "USDC"]),
            method("Tron", ["USDT"]),
        ]
        XCTAssertEqual(
            PaymentSelectionPolicy.preferred(methods),
            PaymentSelection(currency: "USDT", network: "Tron")
        )
    }

    /// Prefers the native GRAM currency while preserving the TON network name.
    func testGramNativeCurrency() {
        let methods = [method("TON", ["CUSTOM", "GRAM"])]
        XCTAssertEqual(
            PaymentSelectionPolicy.preferred(methods),
            PaymentSelection(currency: "GRAM", network: "TON")
        )
    }

    /// Creates a compact payment-method test fixture.
    private func method(
        _ network: String,
        _ currencies: [String],
        defaultCurrency: String? = nil
    ) -> PaymentMethodGroup {
        PaymentMethodGroup(
            network: network,
            currencies: currencies,
            defaultCurrency: defaultCurrency,
            feeQuotes: nil
        )
    }
}
