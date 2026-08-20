import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// Generates wallet-compatible address-only QR images.
enum QRCodeGenerator {
    /// Creates a high-contrast QR image without embedding unsupported payment parameters.
    static func image(for address: String) -> UIImage? {
        guard !address.isEmpty else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(address.utf8)
        filter.correctionLevel = "M"
        let context = CIContext()
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
