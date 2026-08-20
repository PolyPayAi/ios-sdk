import SwiftUI
import UIKit

/// UIKit convenience factory for presenting the native SwiftUI checkout.
@MainActor
public enum PolyPayCheckoutViewController {
    /// Creates a hosting controller that dismisses itself after emitting an outcome.
    public static func make(
        configuration: PolyPayCheckoutConfiguration,
        onOutcome: @escaping (PolyPayCheckoutOutcome) -> Void
    ) -> UIViewController {
        var controller: UIViewController?
        let view = PolyPayCheckoutView(configuration: configuration) { outcome in
            controller?.dismiss(animated: true)
            onOutcome(outcome)
        }
        let hostingController = UIHostingController(rootView: view)
        controller = hostingController
        return hostingController
    }
}
