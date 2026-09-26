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
        d.value = d.value ?? smart.value
        d.pin = d.pin ?? smart.pin
        d.expires = d.expires ?? smart.expires
        d.percent = d.percent ?? smart.percent
        if d.number == nil || (d.number?.count ?? 0) < (smart.number?.count ?? 0) { d.number = smart.number ?? d.number }
        return d
    }
}

nonisolated extension CodeFormat {
    init(_ symbology: BarcodeSymbology) {
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

nonisolated enum Importer {
    /// Barcode und Text (inkl. Handschrift) mit der Vision-Swift-API lesen, danach optional mit Apple Intelligence strukturieren.
    @concurrent
    static func analyze(cgImage: CGImage) async -> ScanOutcome {
        async let codes = detectBarcodes(cgImage)
        async let lines = recognizeText(cgImage)
        let (found, text) = await (codes, lines)
        // Strichcodes vor 2D-Codes bevorzugen: Gutscheinkarten tragen an der Kasse meist den Strichcode.
        let best = found.first { !CodeFormat($0.symbology).isTwoDimensional } ?? found.first
        var outcome = ScanOutcome(barcode: best?.payloadString, format: best.map { CodeFormat($0.symbology) }, text: text)
        if let smart = await SmartExtractor.extract(from: text) {
            outcome.smart = smart
            outcome.usedAppleIntelligence = true
        }
        return outcome
    }

    @concurrent
    private static func detectBarcodes(_ image: CGImage) async -> [BarcodeObservation] {
        let request = DetectBarcodesRequest()
        let results = (try? await request.perform(on: image)) ?? []
        return results.filter { !($0.payloadString ?? "").isEmpty }
    }

    @concurrent
    private static func recognizeText(_ image: CGImage) async -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate          // erkennt auch Handschrift
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        request.recognitionLanguages = [Locale.Language(identifier: "de-DE"), Locale.Language(identifier: "en-US")]
        let observations = (try? await request.perform(on: image)) ?? []
        return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    @MainActor
    static func analyze(image: UIImage) async -> ScanOutcome {
        guard let cg = image.normalizedCGImage else { return ScanOutcome() }
        var out = await analyze(cgImage: cg)
        out.photo = image.thumbnailJPEG()
        return out
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
                let scale = 1800 / max(box.width, box.height, 1)
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
        if let s = try? String(contentsOf: url, encoding: .utf8) {
            return await analyze(text: s)
        }
        return ScanOutcome()
    }
}

extension UIImage {
    /// CGImage in korrekter Ausrichtung, damit Vision Fotos vom iPhone richtig liest.
    var normalizedCGImage: CGImage? {
        if imageOrientation == .up, let cg = cgImage { return cg }
        return UIGraphicsImageRenderer(size: size).image { _ in draw(in: CGRect(origin: .zero, size: size)) }.cgImage
    }

    func thumbnailJPEG(maxSide: CGFloat = 900) -> Data? {
        let s = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: size.width * s, height: size.height * s)
        let img = UIGraphicsImageRenderer(size: target).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
        return img.jpegData(compressionQuality: 0.72)
    }
}
