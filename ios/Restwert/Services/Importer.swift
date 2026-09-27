import Foundation
import UIKit
import Vision
import PDFKit
import UniformTypeIdentifiers
import RestwertKit

/// Ergebnis einer Analyse: gefundener Barcode, erkannter Text (gedruckt oder handschriftlich) und ein Foto.
nonisolated struct ScanOutcome: Sendable, Equatable {
    var barcode: String?
    var format: CodeFormat?
    var text: String = ""
    var photo: Data?
    /// Von Apple Intelligence aufbereitete Felder, falls verfügbar.
    var smart: CardDraft?
    var usedAppleIntelligence = false

    /// Regel-Parser plus KI-Ergebnis zusammengeführt; die KI füllt nur Lücken und korrigiert offensichtliche Fehler.
    var draft: CardDraft {
        var d = TextParser.parse(text)
        guard let smart else { return d }
        d.merchantID = d.merchantID ?? smart.merchantID
        if d.merchantID == nil { d.customName = smart.customName }
        d.value = d.value ?? smart.value
        d.pin = d.pin ?? smart.pin
        d.expires = d.expires ?? smart.expires
        d.percent = d.percent ?? smart.percent
        if d.number == nil || (d.number?.count ?? 0) < (smart.number?.count ?? 0) { d.number = smart.number ?? d.number }
        return d
    }
}

nonisolated enum Importer {
    /// Barcode und Text (inkl. Handschrift) lesen – gestuft über `VoucherScanner` (ganzes Bild, Kontrast, Ausschnitte) –,
    /// danach optional mit Apple Intelligence strukturieren.
    @concurrent
    static func analyze(cgImage: CGImage) async -> ScanOutcome {
        let reading = await VoucherScanner.read(cgImage)
        var outcome = ScanOutcome(barcode: reading.best?.payload, format: reading.best?.format, text: reading.text)
        if let smart = await SmartExtractor.extract(from: reading.text) {
            outcome.smart = smart
            outcome.usedAppleIntelligence = true
        }
        return outcome
    }

    @MainActor
    static func analyze(image: UIImage) async -> ScanOutcome {
        guard let cg = image.normalizedCGImage else { return ScanOutcome() }
        // Vorschaubild parallel zur Erkennung und nicht auf dem Main Thread rechnen.
        async let thumb = thumbnail(cg)
        var out = await analyze(cgImage: cg)
        out.photo = await thumb
        return out
    }

    @concurrent
    private static func thumbnail(_ cg: CGImage) async -> Data? {
        UIImage(cgImage: cg).thumbnailJPEG()
    }

    /// E-Mail-Text: nur Parser und Apple Intelligence, kein Bild.
    @MainActor
    static func analyze(text: String) async -> ScanOutcome {
        var out = ScanOutcome(text: text)
        if let smart = await SmartExtractor.extract(from: text) {
            out.smart = smart
            out.usedAppleIntelligence = true
        }
        return out
    }

    /// PDF, Bild oder Text aus Dateien, Mail-Anhängen oder „Teilen“.
    @MainActor
    static func analyze(url: URL) async -> ScanOutcome {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let type = UTType(filenameExtension: url.pathExtension.lowercased())

        if type?.conforms(to: .pdf) == true, let doc = PDFDocument(url: url) {
            var result = ScanOutcome()
            var texts: [String] = []
            for i in 0..<min(doc.pageCount, 3) {
                guard let page = doc.page(at: i) else { continue }
                let pageText = page.string ?? ""
                let box = page.bounds(for: .mediaBox)
                let scale = 2600 / max(box.width, box.height, 1)   // fein genug für kleine Barcodes auf A4
                let img = page.thumbnail(of: CGSize(width: box.width * scale, height: box.height * scale), for: .mediaBox)
                if result.photo == nil { result.photo = img.thumbnailJPEG() }
                if let cg = img.cgImage {
                    let o = await analyze(cgImage: cg)
                    if result.barcode == nil, o.barcode != nil {
                        result.barcode = o.barcode
                        result.format = o.format
                    }
                    texts.append(pageText.isEmpty ? o.text : pageText)
                } else {
                    texts.append(pageText)
                }
            }
            result.text = texts.joined(separator: "\n")
            if let smart = await SmartExtractor.extract(from: result.text) {
                result.smart = smart
                result.usedAppleIntelligence = true
            }
            return result
        }
        if type?.conforms(to: .image) == true, let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
            return await analyze(image: img)
        }
        if let s = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1)) {
            return await analyze(text: s)
        }
        return ScanOutcome()
    }
}

extension UIImage {
    /// CGImage in korrekter Ausrichtung, damit Vision Fotos vom iPhone richtig liest.
    var normalizedCGImage: CGImage? {
        if imageOrientation == .up, let cg = cgImage { return cg }
        // Originalpixel, nicht Bildschirm-Scale (sonst 3-fache Auflösung)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in draw(in: CGRect(origin: .zero, size: size)) }.cgImage
    }

    /// Auch abseits des Main Threads nutzbar (UIGraphicsImageRenderer ist threadsicher).
    nonisolated func thumbnailJPEG(maxSide: CGFloat = 900) -> Data? {
        let s = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: size.width * s, height: size.height * s)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let img = UIGraphicsImageRenderer(size: target, format: format).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
        return img.jpegData(compressionQuality: 0.72)
    }
}
