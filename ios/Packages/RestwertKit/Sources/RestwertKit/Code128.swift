import CoreImage
import CoreImage.CIFilterBuiltins

/// Code 128 als Modulfolge (Strich/Lücke je Modul), aus dem Generator von Core Image ohne Ruhezone gelesen.
/// Eigene Datei im Paket, damit die Norm (11 Module je Zeichen, Stopp 13) per Unit-Test prüfbar ist;
/// die App zeichnet die Module mit demselben Pixelraster wie EAN (gleich breite Striche).
public enum Code128 {
    private static let context = CIContext()

    public static func modules(_ value: String) -> [Bool]? {
        let f = CIFilter.code128BarcodeGenerator()
        f.message = Data(value.utf8)
        f.quietSpace = 0
        guard let ci = f.outputImage, let cg = context.createCGImage(ci, from: ci.extent), cg.width > 0 else { return nil }
        let w = cg.width
        var pixels = [UInt8](repeating: 255, count: w * 4)
        guard let ctx = CGContext(data: &pixels, width: w, height: 1, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Mittlere Zeile des Codes in den 1-Zeilen-Puffer zeichnen.
        ctx.draw(cg, in: CGRect(x: 0, y: -CGFloat(cg.height) / 2, width: CGFloat(w), height: CGFloat(cg.height)))
        let bars = (0..<w).map { pixels[$0 * 4] < 128 }
        return bars.contains(true) ? bars : nil
    }
}
