import Foundation
import CoreGraphics
import CoreImage
import Vision

/// Ergebnis einer Bildauswertung: bester Code, alle gefundenen Codes und der Text in Leserichtung.
public struct ScanReading: Sendable, Equatable {
    public struct Code: Sendable, Equatable, Hashable {
        public let payload: String
        public let format: CodeFormat
        public init(payload: String, format: CodeFormat) {
            self.payload = payload
            self.format = format
        }
    }

    public var best: Code?
    public var codes: [Code] = []
    public var text: String = ""

    public init(best: Code? = nil, codes: [Code] = [], text: String = "") {
        self.best = best
        self.codes = codes
        self.text = text
    }
}

public extension CodeFormat {
    /// Vision-Symbologie auf das Kassenformat abbilden.
    init(_ symbology: BarcodeSymbology) {
        switch symbology {
        case .ean13: self = .ean13
        case .ean8: self = .ean8
        case .upce: self = .upca          // Wert dazu mit BarcodeEncoder.expandUPCE auf 12 Ziffern bringen
        case .itf14, .i2of5, .i2of5Checksum: self = .itf
        case .code39, .code39Checksum, .code39FullASCII, .code39FullASCIIChecksum: self = .code39
        case .qr, .microQR: self = .qr
        case .pdf417, .microPDF417: self = .pdf417
        case .aztec: self = .aztec
        case .dataMatrix: self = .dataMatrix
        default: self = .code128
        }
    }
}

public extension BarcodeObservation {
    /// Nutzlast passend zu CodeFormat: UPC-E auf die 12 Ziffern von UPC-A erweitert.
    var normalizedPayload: String? {
        guard symbology == .upce, let p = payloadString else { return payloadString }
        return BarcodeEncoder.expandUPCE(p) ?? p
    }
}

/// Liest Gutscheine aus Fotos, PDF-Seiten und Kamerabildern – so, dass es auch bei schwierigen Bildern klappt:
/// 1. ganzes Bild, 2. kontrastverstärkt in Graustufen, 3. vergrößerte Ausschnitte (kleine Codes auf großen Fotos).
/// Riesige Fotos werden vorher auf eine handliche Größe gebracht.
public enum VoucherScanner {
    /// Längste Bildseite für die Auswertung. Größer bringt Vision nichts, kostet aber Zeit und Speicher.
    static let maxSide: CGFloat = 3200

    @concurrent
    public static func read(_ source: CGImage) async -> ScanReading {
        let image = downscaled(source, maxSide: maxSide) ?? source
        async let codesTask = findCodes(image, original: source)
        async let textTask = readText(image)
        let (codes, text) = await (codesTask, textTask)
        return ScanReading(best: bestCode(codes), codes: codes, text: text)
    }

    /// Bester Code für die Kasse: Strichcodes vor 2D-Codes, gültige Prüfziffer vor ungültiger, längere Nummer vor kürzerer.
    public static func bestCode(_ codes: [ScanReading.Code]) -> ScanReading.Code? {
        codes.max { a, b in score(a) < score(b) }
    }

    public static func score(_ c: ScanReading.Code) -> Int {
        var s = 0
        if !c.format.isTwoDimensional { s += 1000 }
        switch BarcodeEncoder.hasValidChecksum(c.payload, format: c.format) {
        case true?: s += 300
        case false?: s -= 800            // falsche Prüfziffer = Lesefehler, nur als letzte Wahl
        case nil: break
        }
        s += min(c.payload.count, 60)
        return s
    }

    // MARK: Codes

    @concurrent
    static func findCodes(_ image: CGImage, original: CGImage? = nil) async -> [ScanReading.Code] {
        var found = await detect(image)
        if found.contains(where: { !$0.format.isTwoDimensional }) { return found }

        // Stufe 2: Graustufen, mehr Kontrast, geschärft – hilft bei Glanz, Schatten und blassem Druck.
        if let enhanced = enhanced(image) {
            found = merge(found, await detect(enhanced))
            if found.contains(where: { !$0.format.isTwoDimensional }) { return found }
        }

        // Stufe 3: überlappende Ausschnitte aus dem ORIGINAL (nicht dem verkleinerten Bild), vergrößert –
        // für kleine Codes auf großen Fotos. Beim Verkleinern gingen die feinen Balken sonst verloren.
        for tile in tiles(of: original ?? image) {
            found = merge(found, await detect(tile))
            if found.contains(where: { !$0.format.isTwoDimensional }) { break }
        }
        return found
    }

    @concurrent
    static func detect(_ image: CGImage) async -> [ScanReading.Code] {
        let request = DetectBarcodesRequest()
        let results = (try? await request.perform(on: image)) ?? []
        var codes: [ScanReading.Code] = []
        for r in results {
            guard let raw = r.normalizedPayload?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { continue }
            let code = ScanReading.Code(payload: raw, format: CodeFormat(r.symbology))
            if !codes.contains(code) { codes.append(code) }
        }
        return codes
    }

    static func merge(_ a: [ScanReading.Code], _ b: [ScanReading.Code]) -> [ScanReading.Code] {
        a + b.filter { !a.contains($0) }
    }

    // MARK: Text

    @concurrent
    static func readText(_ image: CGImage) async -> String {
        let first = await recognize(image)
        if !first.isEmpty { return first }
        // Kein Text gefunden: mit verstärktem Kontrast noch einmal versuchen (blasser Druck, Bleistift).
        guard let enhanced = enhanced(image) else { return first }
        return await recognize(enhanced)
    }

    @concurrent
    static func recognize(_ image: CGImage) async -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate          // erkennt auch Handschrift
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        request.recognitionLanguages = [Locale.Language(identifier: "de-DE"), Locale.Language(identifier: "en-US")]
        let observations = (try? await request.perform(on: image)) ?? []
        // Leserichtung: oben nach unten, in einer Zeile links nach rechts (Vision-Koordinaten: y wächst nach oben).
        let lines = observations.compactMap { o -> (String, CGFloat, CGFloat)? in
            guard let s = o.topCandidates(1).first?.string else { return nil }
            let box = o.boundingBox.cgRect
            return (s, box.maxY, box.minX)
        }
        return lines
            .sorted { abs($0.1 - $1.1) > 0.012 ? $0.1 > $1.1 : $0.2 < $1.2 }
            .map(\.0)
            .joined(separator: "\n")
    }

    // MARK: Bildhilfen

    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    static func downscaled(_ image: CGImage, maxSide: CGFloat) -> CGImage? {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let longest = max(w, h)
        guard longest > maxSide else { return image }
        let s = maxSide / longest
        let size = CGSize(width: (w * s).rounded(), height: (h * s).rounded())
        guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(origin: .zero, size: size))
        return ctx.makeImage()
    }

    static func enhanced(_ image: CGImage) -> CGImage? {
        let input = CIImage(cgImage: image)
        let gray = input.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0, kCIInputContrastKey: 1.6, kCIInputBrightnessKey: 0.02,
        ])
        let sharp = gray.applyingFilter("CISharpenLuminance", parameters: [kCIInputSharpnessKey: 0.8])
        return context.createCGImage(sharp, from: input.extent)
    }

    /// Überlappende Ausschnitte in einem Raster (2×2 bis 4×4 je nach Bildgröße), jeweils auf ca. 2400 px vergrößert.
    static func tiles(of image: CGImage) -> [CGImage] {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        guard w >= 400, h >= 400 else { return [] }
        let n = min(4, max(2, Int((max(w, h) / 1500).rounded(.up))))
        let tw = min(w, w / CGFloat(n) * 1.35), th = min(h, h / CGFloat(n) * 1.35)
        var result: [CGImage] = []
        for row in 0..<n {
            for col in 0..<n {
                let x = n == 1 ? 0 : (w - tw) * CGFloat(col) / CGFloat(n - 1)
                let y = n == 1 ? 0 : (h - th) * CGFloat(row) / CGFloat(n - 1)
                guard let crop = image.cropping(to: CGRect(x: x, y: y, width: tw, height: th).integral) else { continue }
                let factor = min(3, max(1, 2400 / max(tw, th)))
                result.append(factor > 1.05 ? (upscaled(crop, factor: factor) ?? crop) : crop)
            }
        }
        return result
    }

    static func upscaled(_ image: CGImage, factor: CGFloat) -> CGImage? {
        let size = CGSize(width: CGFloat(image.width) * factor, height: CGFloat(image.height) * factor)
        guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        ctx.interpolationQuality = .none    // Balkenkanten scharf halten
        ctx.draw(image, in: CGRect(origin: .zero, size: size))
        return ctx.makeImage()
    }
}
