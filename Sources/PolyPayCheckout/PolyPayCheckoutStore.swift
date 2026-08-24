import Combine
import Foundation

/// View state for the two native checkout pages and their terminal states.
@MainActor
enum PolyPayCheckoutPhase {
    case loading
    case selecting(order: CheckoutOrder, methods: [PaymentMethodGroup], selection: PaymentSelection, busy: Bool)
    case paying(order: CheckoutOrder)
    case expired
    case cancelled
    case error(code: String)
}

/// Main-actor state machine for native checkout navigation and status polling.
@MainActor
final class PolyPayCheckoutStore: ObservableObject {
    @Published private(set) var phase: PolyPayCheckoutPhase = .loading
    private let configuration: PolyPayCheckoutConfiguration
    private let client: PolyPayAPIClient
    private let tradeID: String
    private let onOutcome: (PolyPayCheckoutOutcome) -> Void
    private var pollingTask: Task<Void, Never>?

    /// Creates a store from an already validated SDK configuration.
    init(
        configuration: PolyPayCheckoutConfiguration,
        onOutcome: @escaping (PolyPayCheckoutOutcome) -> Void
    ) {
        self.configuration = configuration
        self.tradeID = configuration.tradeID
        self.client = PolyPayAPIClient(baseURL: configuration.apiBaseURL)
        self.onOutcome = onOutcome
    }

    deinit {
        pollingTask?.cancel()
    }

    /// Loads the order and routes to native selection or payment UI.
    func load() async {
        pollingTask?.cancel()
        phase = .loading
        do {
            let order = try await client.checkout(tradeID: tradeID)
            switch order.status {
            case 0: await loadMethods(order: order)
            case 3: phase = .expired
            case 4: phase = .cancelled
            default: showPayment(order)
            }
        } catch {
            phase = .error(code: stableCode(error))
        }
    }

    /// Loads server-provided methods and applies the deterministic initial selection.
    func loadMethods(order: CheckoutOrder? = nil) async {
        pollingTask?.cancel()
        do {
            let currentOrder: CheckoutOrder
            if let order {
                currentOrder = order
            } else {
                currentOrder = try await client.checkout(tradeID: tradeID)
            }
            let methods = try await client.paymentMethods(tradeID: tradeID)
            guard let selection = PaymentSelectionPolicy.preferred(methods) else {
                phase = .error(code: "no_payment_methods")
                return
            }
            phase = .selecting(order: currentOrder, methods: methods, selection: selection, busy: false)
        } catch {
            phase = .error(code: stableCode(error))
        }
    }

    /// Changes the in-memory selection without sending a network request.
    func updateSelection(_ selection: PaymentSelection) {
        guard case let .selecting(order, methods, _, busy) = phase, !busy else { return }
        phase = .selecting(order: order, methods: methods, selection: selection, busy: false)
    }

    /// Submits the selected method and opens the native payment page.
    func submitSelection() async {
        guard case let .selecting(order, methods, selection, busy) = phase, !busy else { return }
        phase = .selecting(order: order, methods: methods, selection: selection, busy: true)
        do {
            let updated = try await client.select(tradeID: tradeID, selection: selection)
            showPayment(updated)
        } catch {
            phase = .error(code: stableCode(error))
        }
    }

    /// Emits a close event that never asserts the order is paid.
    func close() {
        switch phase {
        case .expired:
            onOutcome(.expired(tradeID: tradeID))
            return
        case .cancelled:
            onOutcome(.cancelled(tradeID: tradeID))
            return
        case let .error(code):
            onOutcome(.error(code: code))
            return
        default:
            break
        }
        let detected = currentStatus.map { [2, 6, 7].contains($0) } ?? false
        onOutcome(detected ? .paymentDetected(tradeID: tradeID) : .closed(tradeID: tradeID))
    }

    /// Shows a payment page and starts lifecycle-bound status observation.
    private func showPayment(_ order: CheckoutOrder) {
        phase = .paying(order: order)
        pollingTask?.cancel()
        guard ![2, 3, 4, 7].contains(order.status) else { return }
        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(configuration.pollInterval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                do {
                    let status = try await client.status(tradeID: tradeID)
                    guard case let .paying(current) = phase else { return }
                    switch status.status {
                    case 3: phase = .expired; return
                    case 4: phase = .cancelled; return
                    default:
                        let updated = CheckoutOrder(
                            tradeID: current.tradeID,
                            merchantOrderID: current.merchantOrderID,
                            currency: current.currency,
                            network: current.network,
                            amount: current.amount,
                            actualAmount: current.actualAmount,
                            displayAmount: current.displayAmount,
                            address: current.address,
                            status: status.status,
                            expirationTime: current.expirationTime,
                            merchantName: current.merchantName,
                            merchantAvatar: current.merchantAvatar
                        )
                        phase = .paying(order: updated)
                        if [2, 7].contains(status.status) { return }
                    }
                } catch {
                    continue
                }
            }
        }
    }

    /// Returns the status currently visible on a payment page.
    private var currentStatus: Int? {
        guard case let .paying(order) = phase else { return nil }
        return order.status
    }

    /// Maps implementation errors to stable public diagnostic codes.
    private func stableCode(_ error: Error) -> String {
        guard let checkoutError = error as? PolyPayCheckoutError else { return "network_error" }
        switch checkoutError {
        case .invalidConfiguration: return "invalid_configuration"
        case .invalidCheckoutURL: return "invalid_checkout_url"
        case let .network(code): return code
        case .invalidResponse: return "invalid_response"
        case .noPaymentMethods: return "no_payment_methods"
        }
    }
}
