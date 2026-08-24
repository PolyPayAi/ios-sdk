import SwiftUI
import UIKit

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
        NavigationView {
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
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: store.close) {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel(localized("close"))
                }
            }
        }
        .navigationViewStyle(.stack)
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

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    /// Derives the networks available for the selected currency.
    private var availableNetworks: [PaymentMethodGroup] {
        methods.filter { $0.currencies.contains(selection.currency) }
    }

    /// Returns the deterministic default so its network can be marked as recommended.
    private var preferredSelection: PaymentSelection? {
        PaymentSelectionPolicy.preferred(methods)
    }

    /// Renders an iOS-native grouped checkout with a safe-area primary action.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summary
                selectedMethodSummary
                sectionHeader(step: 1, title: localized("select_currency"))
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(PaymentSelectionPolicy.currencies(methods), id: \.self) { currency in
                        currencyButton(currency)
                    }
                }
                sectionHeader(step: 2, title: localized("select_network"))
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(availableNetworks, id: \.network) { method in
                        networkButton(method)
                    }
                }
                securityNote
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomAction }
    }

    /// Displays merchant identity, amount, and order identifier in a grouped iOS card.
    private var summary: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                MerchantAvatarView(urlString: order.merchantAvatar)
                VStack(alignment: .leading, spacing: 2) {
                    Text(order.merchantName ?? "PolyPay")
                        .font(.headline)
                        .lineLimit(1)
                    Text(localized("requests_payment"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(localized("amount_due"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(NSDecimalNumber(decimal: order.amount).stringValue)
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("USD")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }
            if let orderID = order.merchantOrderID {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localized("merchant_order_id"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(orderID)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// Shows the active pair without compressing the full network name.
    private var selectedMethodSummary: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.indigo)
            VStack(alignment: .leading, spacing: 2) {
                Text(localized("selected_method"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(selection.currency) · \(networkName(selection.network))")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let standard = transferStandard(network: selection.network, currency: selection.currency) {
                    Text(standard).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Creates a compact selectable currency card using native SF Symbols.
    private func currencyButton(_ currency: String) -> some View {
        selectionCard(
            icon: currencySymbol(currency),
            title: currency,
            subtitle: currencyName(currency),
            selected: currency == selection.currency,
            recommended: false
        ) {
            selectCurrency(currency)
        }
    }

    /// Creates one selectable network card with readable two-line metadata.
    private func networkButton(_ method: PaymentMethodGroup) -> some View {
        selectionCard(
            icon: networkSymbol(method.network),
            title: networkName(method.network),
            subtitle: transferStandard(network: method.network, currency: selection.currency),
            selected: method.network == selection.network,
            recommended: preferredSelection?.network == method.network && preferredSelection?.currency == selection.currency
        ) {
            onSelection(PaymentSelection(currency: selection.currency, network: method.network))
        }
    }

    /// Builds a responsive two-line radio card without truncating common network names.
    private func selectionCard(
        icon: String,
        title: String,
        subtitle: String?,
        selected: Bool,
        recommended: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(selected ? .indigo : .secondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    HStack(spacing: 5) {
                        if let subtitle {
                            Text(subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if recommended {
                            Text(localized("recommended"))
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.12), in: Capsule())
                        }
                    }
                }
                Spacer(minLength: 2)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundColor(selected ? .indigo : .secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            selected ? Color.indigo.opacity(0.1) : Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(selected ? Color.indigo : Color(uiColor: .separator).opacity(0.35), lineWidth: selected ? 1.5 : 1)
        }
        .disabled(busy)
    }

    /// Creates a numbered iOS section heading.
    private func sectionHeader(step: Int, title: String) -> some View {
        HStack(spacing: 8) {
            Text(String(step))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.indigo)
                .frame(width: 22, height: 22)
                .background(Color.indigo.opacity(0.12), in: Circle())
            Text(title).font(.headline)
        }
    }

    /// Pins the primary action above the iPhone home indicator.
    private var bottomAction: some View {
        Button(action: onContinue) {
            Group {
                if busy {
                    ProgressView().tint(.white)
                } else {
                    Text(continueTitle)
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.borderedProminent)
        .tint(.indigo)
        .controlSize(.large)
        .disabled(busy)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    /// Returns the current localized call-to-action label.
    private var continueTitle: String {
        let network = networkName(selection.network)
        let standard = transferStandard(network: selection.network, currency: selection.currency)
        let suffix = standard.map { " (\($0))" } ?? ""
        return localizedFormat("pay_with_method", selection.currency, network, suffix)
    }

    /// Selects a currency and the first compatible network.
    private func selectCurrency(_ currency: String) {
        guard let network = methods.first(where: { $0.currencies.contains(currency) })?.network else { return }
        onSelection(PaymentSelection(currency: currency, network: network))
    }

    /// Returns the full display name for a supported currency.
    private func currencyName(_ currency: String) -> String? {
        ["USDT": "Tether USD", "USDC": "USD Coin", "ETH": "Ether", "TRX": "TRON", "BTC": "Bitcoin"][currency]
    }

    /// Returns a familiar SF Symbol for one currency.
    private func currencySymbol(_ currency: String) -> String {
        switch currency {
        case "ETH": return "diamond.fill"
        case "BTC": return "bitcoinsign.circle.fill"
        default: return "dollarsign.circle.fill"
        }
    }

    /// Returns the customer-facing network name shared with the Web and Android checkout.
    private func networkName(_ network: String) -> String {
        ["Tron": "TRON", "BSC": "BNB Smart Chain", "Arbitrum": "Arbitrum One"][network] ?? network
    }

    /// Returns a familiar SF Symbol for one transfer network.
    private func networkSymbol(_ network: String) -> String {
        switch network {
        case "Ethereum": return "diamond.fill"
        case "Tron": return "triangle.fill"
        case "Base": return "square.fill"
        default: return "link.circle.fill"
        }
    }

    /// Returns the token transfer standard, hiding it for native network currencies.
    private func transferStandard(network: String, currency: String) -> String? {
        let nativeCurrencies: [String: Set<String>] = [
            "Ethereum": ["ETH"], "Base": ["ETH"], "BSC": ["BNB"], "Tron": ["TRX"],
        ]
        if nativeCurrencies[network]?.contains(currency) == true { return nil }
        return ["Ethereum": "ERC20", "Base": "ERC20", "Arbitrum": "ERC20", "Optimism": "ERC20", "BSC": "BEP20", "Tron": "TRC20"][network]
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

/// Displays an optional remote merchant avatar with a system-native placeholder.
private struct MerchantAvatarView: View {
    let urlString: String?

    /// Loads the remote avatar while preserving a deterministic iOS placeholder.
    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString), url.scheme == "https" {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: 48, height: 48)
        .background(Color.indigo.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Shows a semantic merchant glyph when no remote avatar is available.
    private var placeholder: some View {
        Image(systemName: "building.2.fill")
            .font(.title3)
            .foregroundStyle(.indigo)
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
