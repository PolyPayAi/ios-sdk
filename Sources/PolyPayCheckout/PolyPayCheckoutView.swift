import SwiftUI

/// Native SwiftUI checkout containing payment-method selection and payment pages.
@MainActor
public struct PolyPayCheckoutView: View {
    @StateObject private var store: PolyPayCheckoutStore

    /// Creates the native checkout view from a server-created payment URL.
    public init(
        configuration: PolyPayCheckoutConfiguration,
        onOutcome: @escaping (PolyPayCheckoutOutcome) -> Void
    ) {
        _store = StateObject(wrappedValue: PolyPayCheckoutStore(
            configuration: configuration,
            onOutcome: onOutcome
        ))
    }

    /// Renders the current state-machine page using native SwiftUI controls.
    public var body: some View {
        NavigationStack {
            Group {
                switch store.phase {
                case .loading:
                    ProgressView(localized("loading"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case let .selecting(order, methods, selection, busy):
                    PaymentMethodSelectionView(
                        order: order,
                        methods: methods,
                        selection: selection,
                        busy: busy,
                        onSelection: store.updateSelection,
                        onContinue: { Task { await store.submitSelection() } }
                    )
                case let .paying(order):
                    PaymentPageView(
                        order: order,
                        onChangeMethod: { Task { await store.loadMethods(order: order) } }
                    )
                case .expired:
                    TerminalView(title: localized("expired"), retry: { Task { await store.load() } })
                case .cancelled:
                    TerminalView(title: localized("cancelled"), retry: { Task { await store.load() } })
                case let .error(code):
                    TerminalView(title: localized("error") + " (\(code))", retry: { Task { await store.load() } })
                }
            }
            .navigationTitle(localized("title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(localized("close"), action: store.close)
                }
            }
        }
        .task { await store.load() }
    }
}

/// Native selection page for currency and network choices.
private struct PaymentMethodSelectionView: View {
    let order: CheckoutOrder
    let methods: [PaymentMethodGroup]
    let selection: PaymentSelection
    let busy: Bool
    let onSelection: (PaymentSelection) -> Void
    let onContinue: () -> Void

    /// Derives the networks available for the selected currency.
    private var availableNetworks: [PaymentMethodGroup] {
        methods.filter { $0.currencies.contains(selection.currency) }
    }

    /// Renders merchant summary, currency chips, network cards, and continuation.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(localized("choose_method")).font(.title.bold())
                if let merchant = order.merchantName { Text(merchant).foregroundStyle(.secondary) }
                summary
                Text(localized("currency")).font(.headline)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(PaymentSelectionPolicy.currencies(methods), id: \.self) { currency in
                            Button(currency) { selectCurrency(currency) }
                                .buttonStyle(.borderedProminent)
                                .tint(currency == selection.currency ? .indigo : .gray)
                        }
                    }
                }
                Text(localized("network")).font(.headline)
                ForEach(availableNetworks, id: \.network) { method in
                    networkButton(method)
                }
                Button(action: onContinue) {
                    if busy { ProgressView().frame(maxWidth: .infinity) }
                    else { Text(localized("continue")).frame(maxWidth: .infinity) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(busy)
                securityNote
            }
            .padding(20)
        }
    }

    /// Displays the original checkout amount and merchant order identifier.
    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(NSDecimalNumber(decimal: order.amount).stringValue) USD")
                .font(.title2.monospacedDigit().bold())
            if let orderID = order.merchantOrderID {
                Text(orderID).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
    }

    /// Creates one selectable network card with its server fee quote.
    private func networkButton(_ method: PaymentMethodGroup) -> some View {
        Button {
            onSelection(PaymentSelection(currency: selection.currency, network: method.network))
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(method.network).font(.headline)
                    if let quote = method.feeQuotes?[selection.currency],
                       quote.status == "available", let fee = quote.standardFee {
                        Text("\(localized("estimated_fee")) \(fee) \(quote.feeCurrency ?? "")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: method.network == selection.network ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(.indigo)
            }
            .padding()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    /// Selects a currency and the first compatible network.
    private func selectCurrency(_ currency: String) {
        guard let network = methods.first(where: { $0.currencies.contains(currency) })?.network else { return }
        onSelection(PaymentSelection(currency: currency, network: network))
    }

    /// Reminds integrators that client state is not fulfillment authority.
    private var securityNote: some View {
        Text(localized("security_note"))
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}

/// Native QR, address, amount, and payment-state page.
private struct PaymentPageView: View {
    let order: CheckoutOrder
    let onChangeMethod: () -> Void
    @State private var copied = false

    /// Maps observed state to careful user-facing copy without declaring fulfillment.
    private var statusText: String {
        switch order.status {
        case 2, 7: return localized("submitted")
        case 6: return localized("confirming")
        default: return localized("waiting")
        }
    }

    /// Renders the complete native payment page.
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text(order.merchantName ?? localized("title")).font(.title2.bold())
                Text(statusText).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Text(localized("amount_due")).font(.caption).foregroundStyle(.secondary)
                Text("\(order.exactAmountText) \(order.currency)")
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .minimumScaleFactor(0.6)
                Button(localized("copy_amount")) { copy(order.exactAmountText) }
                    .buttonStyle(.bordered)
                if let image = QRCodeGenerator.image(for: order.address) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 220, height: 220)
                        .padding(12)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
                }
                Text(localized("scan")).font(.caption).foregroundStyle(.secondary)
                Text(order.address)
                    .font(.footnote.monospaced())
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                Button(localized("copy_address")) { copy(order.address) }
                    .buttonStyle(.bordered)
                Text("\(order.currency) · \(order.network)").font(.headline)
                Button(localized("change_method"), action: onChangeMethod)
                    .buttonStyle(.bordered)
                Text(localized("security_note"))
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if copied { Text(localized("copied")).font(.caption).foregroundStyle(.green) }
            }
            .padding(20)
        }
    }

    /// Copies an exact payment value to the iOS pasteboard.
    private func copy(_ value: String) {
        UIPasteboard.general.string = value
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            copied = false
        }
    }
}

/// Retryable terminal view for expired, cancelled, and network errors.
private struct TerminalView: View {
    let title: String
    let retry: () -> Void

    /// Renders one focused terminal message and retry action.
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
            Text(title).font(.headline).multilineTextAlignment(.center)
            Button(localized("retry"), action: retry).buttonStyle(.borderedProminent)
            Text(localized("security_note")).font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
