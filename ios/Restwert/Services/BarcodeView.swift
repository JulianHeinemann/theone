import SwiftUI
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import RestwertKit

/// Baut den Barcode im Originalformat der Karte nach.
/// EAN, UPC, ITF, Code 39 und Data Matrix kodiert RestwertKit; Code 128, QR, PDF417 und Aztec kommen aus Core Image.
enum BarcodeRenderer {
    enum Output {
        case bars([Bool])
        case image(UIImage)
    }

    private static let context = CIContext()

    /// Fertige Codes je Nummer und Format: Core Image und Encoder laufen nur einmal, nicht bei jedem Neuzeichnen.
    private final class Entry { let output: Output?; init(_ output: Output?) { self.output = output } }
    private static let cache: NSCache<NSString, Entry> = {
        let c = NSCache<NSString, Entry>()
        c.countLimit = 40
        return c
    }()

    static func cached(_ raw: String, format: CodeFormat) -> Output? {
        let key = "\(format.rawValue)|\(raw)" as NSString
        if let hit = cache.object(forKey: key) { return hit.output }
        let output = render(raw, format: format)
        cache.setObject(Entry(output), forKey: key)
        return output
    }

    static func render(_ raw: String, format: CodeFormat) -> Output? {
        // Ziffern ohne Anzeige-Leerzeichen, andere Codes unverändert (Leerzeichen gehört dann zum Code).
        let value = BarcodeEncoder.payload(raw)
        guard !value.isEmpty else { return nil }
        if format == .dataMatrix {
            return BarcodeEncoder.dataMatrix(value).map { .image(matrixImage($0)) }
        }
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
            // Code 128 und Fallback, wenn EAN/ITF/Code 39 den Inhalt nicht kodieren können.
            // Als Module auslesen und selbst zeichnen: dann gilt dasselbe Pixelraster wie für EAN (gleich breite Striche).
            let f = CIFilter.code128BarcodeGenerator()
            f.message = Data(value.utf8)
            f.quietSpace = 0
            if let bars = modules(of: f.outputImage) { return .bars(bars) }
            f.quietSpace = 10
            return image(f.outputImage)
        }
    }

    /// Kann das gewählte Format den Inhalt nicht darstellen, zeichnet Restwert Code 128 mit demselben Inhalt.
    /// Die Kasse zeigt das dann unter dem Barcode an.
    static func drawnAsCode128(_ raw: String, format: CodeFormat) -> Bool {
        switch format {
        case .code128, .qr, .pdf417, .aztec, .dataMatrix, .text: return false
        default:
            let value = BarcodeEncoder.payload(raw)
            return !value.isEmpty && BarcodeEncoder.modules(for: value, format: format) == nil
        }
    }

    /// Eine Zeile des 1-Pixel-pro-Modul-Bildes von Core Image als Strich/Lücke lesen.
    private static func modules(of ci: CIImage?) -> [Bool]? {
        guard let ci, let cg = context.createCGImage(ci, from: ci.extent), cg.width > 0 else { return nil }
        let w = cg.width
        var pixels = [UInt8](repeating: 255, count: w * 4)
        guard let ctx = CGContext(data: &pixels, width: w, height: 1, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Mittlere Zeile des Codes in den 1-Zeilen-Puffer zeichnen.
        ctx.draw(cg, in: CGRect(x: 0, y: -CGFloat(cg.height) / 2, width: CGFloat(w), height: CGFloat(cg.height)))
        let bars = (0..<w).map { pixels[$0 * 4] < 128 }
        return bars.contains(true) ? bars : nil
    }

    /// Data-Matrix-Module als scharfes Bild (8 px je Modul, ohne Glätten).
    private static func matrixImage(_ m: [[Bool]]) -> UIImage {
        let module: CGFloat = 8, n = CGFloat(m.count)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: n * module, height: n * module), format: format).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: n * module, height: n * module))
            UIColor.black.setFill()
            for (y, row) in m.enumerated() { for (x, on) in row.enumerated() where on {
                ctx.fill(CGRect(x: CGFloat(x) * module, y: CGFloat(y) * module, width: module, height: module)) } }
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
    /// Nur für den Text-Rückfall: Nummer als „•••• 1234“ zeigen.
    var masked = false
    /// „Codes erst nach Face ID zeigen“: auch den Barcode selbst nicht zeichnen (er ließe sich sonst abscannen).
    var concealed = false
    @Environment(\.displayScale) private var displayScale

    /// Wird der Inhalt als Code 128 statt im Originalformat gezeichnet (z. B. ungerades ITF), sagt VoiceOver das.
    private var accessibilityName: String {
        BarcodeRenderer.drawnAsCode128(number, format: format) ? "Barcode als Code 128" : "Barcode \(format.label)"
    }

    var body: some View {
        if concealed {
            VStack(spacing: 8) {
                Image(systemName: "lock.fill").font(.scaled(22))
                Text("Geschützt – tippen und entsperren").font(.scaled(15, weight: .semibold))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(Color.ink2)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(Color.fill, in: .rect(cornerRadius: Layout.buttonRadius, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Geschützt. Tippen und entsperren")
        } else {
            rendered
        }
    }

    @ViewBuilder private var rendered: some View {
        switch BarcodeRenderer.cached(number, format: format) {
        case .bars(let modules)?:
            let padded = Array(repeating: false, count: 10) + modules + Array(repeating: false, count: 10)
            Canvas { ctx, size in
                // Modulbreite auf ganze Bildschirmpixel gerundet: jede Strichkante liegt auf einem Pixel,
                // alle Module sind exakt gleich breit (wichtig für ältere Laserscanner). Mittig in der Fläche.
                let px = 1 / displayScale
                let w = max(px, (size.width / CGFloat(padded.count) / px).rounded(.down) * px)
                let x0 = ((size.width - w * CGFloat(padded.count)) / 2 / px).rounded(.down) * px
                var i = 0
                while i < padded.count {
                    guard padded[i] else { i += 1; continue }
                    var j = i
                    while j < padded.count && padded[j] { j += 1 }
                    ctx.fill(Path(CGRect(x: x0 + CGFloat(i) * w, y: 0, width: CGFloat(j - i) * w, height: size.height)), with: .color(.black))
                    i = j
                }
            }
            .frame(maxWidth: 640)
            .frame(height: height)
            .whitePlate()
            .frame(maxWidth: .infinity)
            .accessibilityLabel(accessibilityName)
        case .image(let img)? where format.isTwoDimensional:
            Image(uiImage: img)
                .interpolation(.none)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: format != .pdf417 ? height * 2.4 : height)
                .whitePlate()
                .frame(maxWidth: .infinity)
                .accessibilityLabel(accessibilityName)
        case .image(let img)?:
            // Strichcode (Code 128): in der Breite strecken, so breit wie Platz ist – auf dem iPad nicht als schmaler Streifen.
            Image(uiImage: img)
                .interpolation(.none)
                .resizable()
                .frame(maxWidth: 640)
                .frame(height: height)
                .whitePlate()
                .frame(maxWidth: .infinity)
                .accessibilityLabel(accessibilityName)
        case nil:
            Group {
                if masked {
                    Text(number.masked)
                } else {
                    Text(number).textSelection(.enabled)
                }
            }
            .font(.scaled(28, weight: .heavy, design: .monospaced))
            .multilineTextAlignment(.center)
            .padding(.vertical, 12)
        }
    }
}

private extension View {
    /// Weiße Platte mit kleinem Radius: Scanner brauchen Schwarz auf Weiß, auch im Dunkelmodus.
    func whitePlate() -> some View {
        padding(8)
            .background(Color.white, in: .rect(cornerRadius: Layout.controlRadius, style: .continuous))
    }
}
