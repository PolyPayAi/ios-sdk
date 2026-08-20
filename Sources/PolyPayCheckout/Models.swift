import Foundation

/// A merchant-enabled network and its supported currencies.
struct PaymentMethodGroup: Decodable, Equatable, Sendable {
    let network: String
    let currencies: [String]
    let defaultCurrency: String?
    let feeQuotes: [String: NetworkFeeQuote]?

    enum CodingKeys: String, CodingKey {
        case network, currencies
        case defaultCurrency = "default_currency"
        case feeQuotes = "fee_quotes"
    }
}

/// A display-only server-provided network fee quote.
struct NetworkFeeQuote: Decodable, Equatable, Sendable {
    let feeCurrency: String?
    let standardFee: String?
    let status: String

    enum CodingKeys: String, CodingKey {
        case status
        case feeCurrency = "fee_currency"
        case standardFee = "standard_fee"
    }
}

/// Checkout information displayed by the native payment page.
struct CheckoutOrder: Decodable, Equatable, Sendable {
    let tradeID: String
    let merchantOrderID: String?
    let currency: String
    let network: String
    let amount: Decimal
    let actualAmount: Decimal
    let displayAmount: String?
    let address: String
    let status: Int
    let expirationTime: Int64
    let merchantName: String?

    enum CodingKeys: String, CodingKey {
        case currency, network, amount, address, status
        case tradeID = "trade_id"
        case merchantOrderID = "mch_order_id"
        case actualAmount = "actual_amount"
        case displayAmount = "display_amount"
        case expirationTime = "expiration_time"
        case merchantName = "merchant_name"
    }

    /// Returns the server-normalized exact amount for display and copying.
    var exactAmountText: String {
        displayAmount ?? NSDecimalNumber(decimal: actualAmount).stringValue
    }
}

/// Public status observation used only to update checkout UX.
struct CheckoutStatus: Decodable, Equatable, Sendable {
    let status: Int
    let confirmations: Int?
    let requiredConfirmations: Int?

    enum CodingKeys: String, CodingKey {
        case status, confirmations
        case requiredConfirmations = "required_confirmations"
    }
}

/// Response carrying available payment methods.
struct PaymentMethodsData: Decodable, Sendable {
    let methods: [PaymentMethodGroup]
}

/// Response returned after selecting a payment method.
struct SelectedPaymentData: Decodable, Sendable {
    let tradeID: String

    enum CodingKeys: String, CodingKey { case tradeID = "trade_id" }
}

/// Standard PolyPay JSON response envelope.
struct APIEnvelope<Value: Decodable>: Decodable {
    let code: Int
    let message: String?
    let data: Value?
}

/// A concrete currency and network selection.
struct PaymentSelection: Equatable, Sendable {
    let currency: String
    let network: String
}

/// Deterministic defaults shared by native method selection views.
enum PaymentSelectionPolicy {
    /// Selects a merchant default, then USDT on Tron, then the first pair.
    static func preferred(_ methods: [PaymentMethodGroup]) -> PaymentSelection? {
        if let item = methods.first(where: {
            guard let value = $0.defaultCurrency else { return false }
            return $0.currencies.contains(value)
        }), let currency = item.defaultCurrency {
            return PaymentSelection(currency: currency, network: item.network)
        }
        if let item = methods.first(where: {
            $0.network.caseInsensitiveCompare("Tron") == .orderedSame && $0.currencies.contains("USDT")
        }) {
            return PaymentSelection(currency: "USDT", network: item.network)
        }
        if let item = methods.first(where: { $0.currencies.contains("USDT") }) {
            return PaymentSelection(currency: "USDT", network: item.network)
        }
        guard let item = methods.first(where: { !$0.currencies.isEmpty }),
              let currency = item.currencies.first else { return nil }
        return PaymentSelection(currency: currency, network: item.network)
    }

    /// Returns unique currencies in a stable checkout display order.
    static func currencies(_ methods: [PaymentMethodGroup]) -> [String] {
        let order = ["USDT", "USDC", "BUSD", "DAI", "ETH", "BNB", "TRX", "TON"]
        return Array(Set(methods.flatMap(\.currencies))).sorted {
            let left = order.firstIndex(of: $0) ?? Int.max
            let right = order.firstIndex(of: $1) ?? Int.max
            return left == right ? $0 < $1 : left < right
        }
    }
}
