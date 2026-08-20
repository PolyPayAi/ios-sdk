import Foundation

/// HTTPS client for PolyPay's public checkout-scoped endpoints.
actor PolyPayAPIClient {
    private let baseURL: URL
    private let session: URLSession
    private let decoder = JSONDecoder()

    /// Creates a client that never follows API redirects.
    init(baseURL: URL) {
        self.baseURL = baseURL
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        self.session = URLSession(configuration: configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }

    /// Loads a checkout order without merchant credentials.
    func checkout(tradeID: String) async throws -> CheckoutOrder {
        try await request(
            path: "public/checkout-counter",
            method: "GET",
            query: [URLQueryItem(name: "trade_id", value: tradeID)]
        )
    }

    /// Loads merchant-enabled methods for the checkout placeholder.
    func paymentMethods(tradeID: String) async throws -> [PaymentMethodGroup] {
        let data: PaymentMethodsData = try await request(
            path: "public/order/payment-methods",
            method: "GET",
            query: [URLQueryItem(name: "trade_id", value: tradeID)]
        )
        return data.methods
    }

    /// Converts the checkout placeholder into a payable order for one method.
    func select(tradeID: String, selection: PaymentSelection) async throws -> CheckoutOrder {
        let body = [
            "trade_id": tradeID,
            "network": selection.network,
            "currency": selection.currency,
        ]
        let _: SelectedPaymentData = try await request(
            path: "public/order/select-payment-method",
            method: "POST",
            body: body
        )
        return try await checkout(tradeID: tradeID)
    }

    /// Polls public observation state for display updates only.
    func status(tradeID: String) async throws -> CheckoutStatus {
        try await request(
            path: "public/check-status",
            method: "POST",
            body: ["trade_id": tradeID]
        )
    }

    /// Performs one response-envelope request with bounded data handling.
    private func request<Value: Decodable>(
        path: String,
        method: String,
        query: [URLQueryItem] = [],
        body: [String: String]? = nil
    ) async throws -> Value {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url, url.scheme == "https" else {
            throw PolyPayCheckoutError.invalidConfiguration
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: request)
        guard data.count <= 1_000_000,
              let http = response as? HTTPURLResponse else {
            throw PolyPayCheckoutError.invalidResponse
        }
        let envelope = try decoder.decode(APIEnvelope<Value>.self, from: data)
        guard (200..<300).contains(http.statusCode), envelope.code == 0, let value = envelope.data else {
            let code = envelope.code == 0 ? http.statusCode : envelope.code
            throw PolyPayCheckoutError.network(code: "api_\(code)")
        }
        return value
    }
}

/// URL session delegate that rejects redirects at the API boundary.
private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    /// Stops automatic redirects, including any HTTPS downgrade or host change.
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
