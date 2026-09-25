import SwiftUI
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import RestwertKit

/// Baut den Barcode im Originalformat der Karte nach.
/// EAN, UPC, ITF und Code 39 kodiert RestwertKit; Code 128, QR, PDF417 und Aztec kommen aus Core Image.
enum BarcodeRenderer {
    enum Output {
        case bars([Bool])
        case image(UIImage)
    }

    private static let context = CIContext()

    static func render(_ raw: String, format: CodeFormat) -> Output? {
        let value = raw.replacingOccurrences(of: " ", with: "")
        guard !value.isEmpty else { return nil }
        if let modules = BarcodeEncoder.modules(for: value, format: format) { return .bars(modules) }
        switch format {
        case .qr:
            let f = CIFilter.qrCodeGenerator()
            f.message = Data(value.utf8)
            f.correctionLevel = "M"
            return image(f.outputImage)
        case .pdf417:
            let f = CIFilter.pdf417BarcodeGenerator()
            f.message = Data(value.utf8)
            return image(f.outputImage)
        case .aztec:
            let f = CIFilter.aztecCodeGenerator()
            f.message = Data(value.utf8)
            return image(f.outputImage)
        case .text, .dataMatrix:
            return nil
        default:
            // Code 128 und Fallback, wenn EAN/ITF/Code 39 den Inhalt nicht kodieren können
            let f = CIFilter.code128BarcodeGenerator()
            f.message = Data(value.utf8)
            f.quietSpace = 10
            return image(f.outputImage)
        }
    }

    private static func image(_ ci: CIImage?) -> Output? {
        guard let ci else { return nil }
        let scaled = ci.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return .image(UIImage(cgImage: cg))
    }
}

/// Zeigt den Barcode einer Karte. Für Formate ohne Generator fällt die Ansicht auf die Nummer zurück.
struct BarcodeView: View {
    let number: String
    let format: CodeFormat
    var height: CGFloat = 90

    var body: some View {
        switch BarcodeRenderer.render(number, format: format) {
        case .bars(let modules)?:
            let padded = Array(repeating: false, count: 10) + modules + Array(repeating: false, count: 10)
            Canvas { ctx, size in
                let w = size.width / CGFloat(padded.count)
                for (i, on) in padded.enumerated() where on {
                    ctx.fill(Path(CGRect(x: CGFloat(i) * w, y: 0, width: w + 0.35, height: size.height)), with: .color(.black))
                }
            }
            .frame(height: height)
            .background(Color.white)
            .accessibilityLabel("Barcode \(format.label)")
        case .image(let img)?:
            Image(uiImage: img)
                .interpolation(.none)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: format == .qr || format == .aztec ? height * 2.4 : height)
                .accessibilityLabel("Barcode \(format.label)")
        case nil:
            Text(number)
                .font(.system(size: 26, weight: .heavy, design: .monospaced))
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .padding(.vertical, 12)
        }
    }
}
