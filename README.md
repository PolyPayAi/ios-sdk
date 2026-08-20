# PolyPay iOS SDK

Native SwiftUI checkout for PolyPay, with UIKit presentation support. It includes the payment-method selection page and payment page without embedding a WebView.

## Requirements

- iOS 15+
- Swift 5.9+
- A merchant server that creates a checkout through `POST /api/v1/pay/order/checkout`

Keep the merchant API Key on your server. Omit `currency` and `network` when creating checkout so PolyPay returns `/pay/{tradeId}` for native selection.

## Install

In Xcode, add package:

```text
https://github.com/PolyPayAi/ios-sdk.git
```

## SwiftUI

```swift
let configuration = try PolyPayCheckoutConfiguration(
    checkoutURL: checkoutURLFromYourServer
)

PolyPayCheckoutView(configuration: configuration) { outcome in
    // Never fulfill from this callback. Reconcile on your merchant server.
    orderModel.reconcile(outcome)
}
```

## UIKit

```swift
let controller = PolyPayCheckoutViewController.make(configuration: configuration) { outcome in
    merchantAPI.reconcileOrder()
}
present(controller, animated: true)
```

The SDK displays currencies, networks, fee estimates, exact amount, address, address-only QR, copy actions, and observed confirmation state. Outcomes intentionally exclude `paid`; fulfillment must use a verified webhook or authenticated server reconciliation.

## Test

```bash
swift test
```
