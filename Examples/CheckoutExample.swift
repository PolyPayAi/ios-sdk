import PolyPayCheckout
import SwiftUI

/// Example merchant screen that receives its checkout URL from a trusted server.
struct CheckoutExample: View {
    let checkoutURL: URL
    @State private var configuration: PolyPayCheckoutConfiguration?

    /// Presents the complete native checkout after validating the URL.
    var body: some View {
        Group {
            if let configuration {
                PolyPayCheckoutView(configuration: configuration) { outcome in
                    // Send the trade identifier to the merchant server for reconciliation.
                    print("Non-authoritative checkout outcome: \(outcome)")
                }
            } else {
                ProgressView()
                    .task { configuration = try? PolyPayCheckoutConfiguration(checkoutURL: checkoutURL) }
            }
        }
    }
}
