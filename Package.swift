// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PolyPayCheckout",
    defaultLocalization: "en",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "PolyPayCheckout", targets: ["PolyPayCheckout"]),
    ],
    targets: [
        .target(
            name: "PolyPayCheckout",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "PolyPayCheckoutTests",
            dependencies: ["PolyPayCheckout"]
        ),
    ]
)
