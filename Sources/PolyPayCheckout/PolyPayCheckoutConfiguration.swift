import Foundation

/// Configuration for a native PolyPay checkout session.
public struct PolyPayCheckoutConfiguration: Sendable, Equatable {
    public let checkoutURL: URL
    public let allowedCheckoutHosts: Set<String>
    public let apiBaseURL: URL
    public let pollInterval: TimeInterval
    let tradeID: String

    /// Creates and validates a checkout configuration without accepting merchant secrets.
    public init(
        checkoutURL: URL,
        allowedCheckoutHosts: Set<String> = ["checkout.polypay.ai"],
        apiBaseURL: URL = URL(string: "https://api.polypay.ai/api/v1/pay")!,
        pollInterval: TimeInterval = 5
    ) throws {
        guard pollInterval >= 2 else { throw PolyPayCheckoutError.invalidConfiguration }
        guard !allowedCheckoutHosts.isEmpty,
              allowedCheckoutHosts.allSatisfy({ Self.isValidHost($0) }) else {
            throw PolyPayCheckoutError.invalidConfiguration
        }
        guard apiBaseURL.scheme == "https",
              apiBaseURL.host?.isEmpty == false,
              apiBaseURL.user == nil,
              apiBaseURL.password == nil else {
            throw PolyPayCheckoutError.invalidConfiguration
        }
        let tradeID = try CheckoutURLParser.parse(checkoutURL, allowedHosts: allowedCheckoutHosts)
        self.checkoutURL = checkoutURL
        self.allowedCheckoutHosts = allowedCheckoutHosts
        self.apiBaseURL = apiBaseURL
        self.pollInterval = pollInterval
        self.tradeID = tradeID
    }

    /// Returns true for a normalized hostname without path or port syntax.
    private static func isValidHost(_ value: String) -> Bool {
        !value.isEmpty && value == value.lowercased() && !value.contains("/") && !value.contains(":")
    }
}

/// Stable SDK errors suitable for diagnostics without leaking checkout data.
public enum PolyPayCheckoutError: Error, Equatable, Sendable {
    case invalidConfiguration
    case invalidCheckoutURL
    case network(code: String)
    case invalidResponse
    case noPaymentMethods
}

/// A non-authoritative outcome emitted by the native checkout UI.
public enum PolyPayCheckoutOutcome: Equatable, Sendable {
    case closed(tradeID: String)
    case paymentDetected(tradeID: String)
    case expired(tradeID: String)
    case cancelled(tradeID: String)
    case error(code: String)

    /// Always requires the merchant server to reconcile before fulfillment.
    public var requiresServerConfirmation: Bool { true }
}

/// Strict parser for server-created `/pay/{tradeId}` checkout URLs.
enum CheckoutURLParser {
    /// Extracts a trade ID only from an exact allowlisted HTTPS host.
    static func parse(_ url: URL, allowedHosts: Set<String>) throws -> String {
        guard url.scheme == "https",
              url.user == nil,
              url.password == nil,
              url.fragment == nil,
              let host = url.host?.lowercased(),
              allowedHosts.map({ $0.lowercased() }).contains(host) else {
            throw PolyPayCheckoutError.invalidCheckoutURL
        }
        let segments = url.pathComponents.filter { $0 != "/" }
        guard segments.count >= 2,
              segments[segments.count - 2] == "pay" else {
            throw PolyPayCheckoutError.invalidCheckoutURL
        }
        let tradeID = segments.last ?? ""
        let pattern = try NSRegularExpression(pattern: "^[A-Za-z0-9_-]{8,128}$")
        let range = NSRange(tradeID.startIndex..<tradeID.endIndex, in: tradeID)
        guard pattern.firstMatch(in: tradeID, range: range) != nil else {
            throw PolyPayCheckoutError.invalidCheckoutURL
        }
        return tradeID
    }
}
