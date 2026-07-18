import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

/// QR encode / decode helpers (native stand-in for Scripting `QRCode.*`).
enum QRCodeToolkit {
    private static let context = CIContext()

    // MARK: - Generate

    static func generateImage(from content: String, dimension: CGFloat = 512, quietZone: CGFloat = 0.08) -> UIImage? {
        guard !content.isEmpty else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(content.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }

        let extent = output.extent.integral
        guard extent.width > 0, extent.height > 0 else { return nil }

        let scale = dimension / max(extent.width, extent.height)
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let scaledExtent = scaled.extent.integral

        // White background with quiet zone
        let pad = max(4, dimension * quietZone)
        let canvasSize = CGSize(
            width: scaledExtent.width + pad * 2,
            height: scaledExtent.height + pad * 2
        )
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let cgContext = CGContext(
            data: nil,
            width: Int(canvasSize.width),
            height: Int(canvasSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        cgContext.setFillColor(UIColor.white.cgColor)
        cgContext.fill(CGRect(origin: .zero, size: canvasSize))

        guard let cgImage = context.createCGImage(scaled, from: scaledExtent) else { return nil }
        cgContext.draw(
            cgImage,
            in: CGRect(x: pad, y: pad, width: scaledExtent.width, height: scaledExtent.height)
        )
        guard let final = cgContext.makeImage() else { return nil }
        return UIImage(cgImage: final)
    }

    // MARK: - Parse image

    static func parseQR(from image: UIImage) async -> String? {
        guard let cgImage = image.cgImage else {
            // Try redraw if only CIImage-backed
            if let ci = image.ciImage, let rendered = context.createCGImage(ci, from: ci.extent) {
                return await detect(in: rendered)
            }
            return nil
        }
        return await detect(in: cgImage)
    }

    private static func detect(in cgImage: CGImage) async -> String? {
        await withCheckedContinuation { continuation in
            let request = VNDetectBarcodesRequest { request, _ in
                let payloads = (request.results as? [VNBarcodeObservation] ?? [])
                    .compactMap(\.payloadStringValue)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                continuation.resume(returning: payloads.first)
            }
            request.symbologies = [.qr]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
}
