import Foundation
import UIKit
import Vision
import PDFKit
import UniformTypeIdentifiers

/// Ergebnis einer Analyse: gefundener Barcode und erkannter Text (gedruckt oder handschriftlich).
struct ScanOutcome: Sendable {
    var barcode: String?
    var format: CodeFormat?
    var text: String = ""
    var photo: Data?
}

extension CodeFormat {
    init(symbology: VNBarcodeSymbology) {
        switch symbology {
        case .ean13: self = .ean13
        case .ean8: self = .ean8
        case .upce: self = .upca
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

enum Importer {
    /// Barcode und Text (inkl. Handschrift) aus einem Bild lesen.
    static func analyze(cgImage: CGImage) async -> ScanOutcome {
        await Task.detached(priority: .userInitiated) { () -> ScanOutcome in
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            let barcodes = VNDetectBarcodesRequest()
            let text = VNRecognizeTextRequest()
            text.recognitionLevel = .accurate          // erkennt auch Handschrift
            text.usesLanguageCorrection = true
            text.automaticallyDetectsLanguage = true
            text.recognitionLanguages = ["de-DE", "en-US"]
            try? handler.perform([barcodes, text])
            let found = (barcodes.results ?? []).filter { !($0.payloadStringValue ?? "").isEmpty }
            // Strichcodes vor QR bevorzugen: Gutscheinkarten tragen meist den Strichcode an der Kasse.
            let best = found.first { !$0.symbology.isTwoD } ?? found.first
            let lines = (text.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            return ScanOutcome(barcode: best?.payloadStringValue,
                               format: best.map { CodeFormat(symbology: $0.symbology) },
                               text: lines.joined(separator: "\n"))
        }.value
    }

    static func analyze(image: UIImage) async -> ScanOutcome {
        guard let cg = image.normalizedCGImage else { return ScanOutcome() }
        var out = await analyze(cgImage: cg)
        out.photo = image.thumbnailJPEG()
        return out
    }

    /// PDF, Bild oder Text aus Dateien, Mail-Anhängen oder „Teilen“.
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
                let scale = 1800 / max(box.width, box.height, 1)
                let img = page.thumbnail(of: CGSize(width: box.width * scale, height: box.height * scale), for: .mediaBox)
                if let cg = img.cgImage {
                    let o = await analyze(cgImage: cg)
                    if result.barcode == nil, o.barcode != nil { result.barcode = o.barcode; result.format = o.format }
                    texts.append(pageText.isEmpty ? o.text : pageText)
                    if result.photo == nil { result.photo = img.thumbnailJPEG() }
                } else {
                    texts.append(pageText)
                }
            }
            result.text = texts.joined(separator: "\n")
            return result
        }
        if type?.conforms(to: .image) == true, let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
            return await analyze(image: img)
        }
        if let s = try? String(contentsOf: url, encoding: .utf8) {
            return ScanOutcome(text: s)
        }
        return ScanOutcome()
    }
}

private extension VNBarcodeSymbology {
    var isTwoD: Bool { [.qr, .microQR, .aztec, .dataMatrix, .pdf417, .microPDF417].contains(self) }
}

extension UIImage {
    /// CGImage in korrekter Ausrichtung, damit Vision Fotos vom iPhone richtig liest.
    var normalizedCGImage: CGImage? {
        if imageOrientation == .up, let cg = cgImage { return cg }
        let r = UIGraphicsImageRenderer(size: size)
        return r.image { _ in draw(in: CGRect(origin: .zero, size: size)) }.cgImage
    }

    func thumbnailJPEG(maxSide: CGFloat = 900) -> Data? {
        let s = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: size.width * s, height: size.height * s)
        let img = UIGraphicsImageRenderer(size: target).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
        return img.jpegData(compressionQuality: 0.72)
    }
}

// MARK: - Text parsing (E-Mail, PDF, Handschrift)

struct CardDraft {
    var merchantID: String?
    var number: String?
    var pin: String?
    var value: Double?
    var expires: Date?
}

enum TextParser {
    static func parse(_ text: String) -> CardDraft {
        var d = CardDraft()
        let t = text.replacingOccurrences(of: "\u{00A0}", with: " ")
        d.merchantID = merchant(in: t)
        d.pin = firstMatch(#"(?i)\bPIN\s*[:#]?\s*([0-9]{3,8})\b"#, in: t)
        d.value = amount(in: t)
        d.expires = expiry(in: t)
        d.number = code(in: t, excluding: d.pin)
        return d
    }

    private static func regex(_ p: String) -> NSRegularExpression? { try? NSRegularExpression(pattern: p) }

    private static func matches(_ p: String, in s: String) -> [[String]] {
        guard let re = regex(p) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { m in
            (0..<m.numberOfRanges).map { i in
                let r = m.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
        }
    }

    private static func firstMatch(_ p: String, in s: String) -> String? {
        matches(p, in: s).first.flatMap { $0.count > 1 ? $0[1] : nil }
    }

    static func merchant(in s: String) -> String? {
        for m in Merchant.all {
            let name = NSRegularExpression.escapedPattern(for: m.name)
            if !matches("(?i)(?<![A-Za-z0-9])\(name)(?![A-Za-z0-9])", in: s).isEmpty { return m.id }
        }
        return nil
    }

    static func amount(in s: String) -> Double? {
        let p = #"(?i)(?:€|EUR)\s?(\d{1,4}(?:[.,]\d{1,2})?)|(\d{1,4}(?:[.,]\d{1,2})?)\s?(?:€|EUR\b|Euro\b)"#
        let values = matches(p, in: s).compactMap { g -> Double? in
            let raw = g[1].isEmpty ? g[2] : g[1]
            return parseMoney(raw)
        }.filter { $0 > 0 && $0 <= 2000 }
        // Beträge nahe „Wert“, „Betrag“, „Guthaben“ bevorzugen
        if let labeled = matches(#"(?i)(?:Wert|Betrag|Guthaben|Gutscheinwert|Value)\D{0,20}(\d{1,4}(?:[.,]\d{1,2})?)"#, in: s)
            .compactMap({ parseMoney($0[1]) }).first(where: { $0 > 0 && $0 <= 2000 }) {
            return labeled
        }
        return values.max()
    }

    static func expiry(in s: String) -> Date? {
        let cal = Calendar.current
        func date(_ g: [String]) -> Date? {
            guard let d = Int(g[1]), let m = Int(g[2]), var y = Int(g[3]) else { return nil }
            if y < 100 { y += 2000 }
            return cal.date(from: DateComponents(year: y, month: m, day: d))
        }
        let labeled = matches(#"(?i)(?:gültig|gueltig|bis|ablauf|verfällt|valid|expires?)[^\d]{0,25}(\d{1,2})\.(\d{1,2})\.(\d{2,4})"#, in: s).compactMap(date)
        if let first = labeled.first { return first }
        let all = matches(#"\b(\d{1,2})\.(\d{1,2})\.(\d{2,4})\b"#, in: s).compactMap(date).filter { $0 > .now }
        return all.max()
    }

    static func code(in s: String, excluding pin: String?) -> String? {
        let labeled = #"(?i)(?:Gutscheincode|Gutschein-Code|Gutscheinnummer|Kartennummer|Karten-Nr\.?|Kartennr\.?|Code|Nummer|Card number|Seriennummer)\s*[:#]?\s*([A-Z0-9][A-Z0-9 \-]{5,40})"#
        for g in matches(labeled, in: s) {
            let cleaned = clean(g[1])
            if cleaned.count >= 6, cleaned != pin, cleaned.contains(where: \.isNumber) { return cleaned }
        }
        let candidates = matches(#"\b[A-Z0-9][A-Z0-9\-]{7,30}\b"#, in: s.uppercased())
            .map { $0[0] }
            .filter { $0.filter(\.isNumber).count >= 4 && $0 != pin }
        return candidates.max { $0.count < $1.count }
    }

    /// Ziffernblöcke zusammenziehen, Wörter am Ende abschneiden.
    private static func clean(_ raw: String) -> String {
        let firstLine = raw.split(whereSeparator: \.isNewline).first.map(String.init) ?? raw
        let parts = firstLine.split(separator: " ")
        var kept: [Substring] = []
        for p in parts {
            if p.contains(where: \.isNumber) || (p.count >= 3 && p.uppercased() == p && p.contains("-")) { kept.append(p) } else { break }
        }
        let joined = kept.joined(separator: kept.allSatisfy { $0.allSatisfy(\.isNumber) } ? "" : " ")
        return joined.trimmingCharacters(in: .whitespaces)
    }
}
