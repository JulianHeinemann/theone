import Foundation
import UIKit
import Vision
import CoreImage
import OSLog
import PDFKit
import UniformTypeIdentifiers
import RestwertKit

/// Ergebnis einer Analyse: gefundener Barcode, erkannter Text (gedruckt oder handschriftlich) und ein Foto.
nonisolated struct ScanOutcome: Sendable, Equatable {
    /// Woher der Gutschein kam: bestimmt z. B. den Aufbewahrungsort-Vorschlag.
    enum Source: Sendable, Equatable { case camera, photo, document, text }

    var barcode: String?
    var format: CodeFormat?
    var text: String = ""
    var photo: Data?
    /// Von Apple Intelligence aufbereitete Felder, falls verfügbar.
    var smart: CardDraft?
    var usedAppleIntelligence = false
    var source: Source = .photo
    /// „Wann gekauft/erhalten?“ aus dem Scan-Ergebnis; das Formular rechnet Fristen davon.
    var received: Date?
    /// Die Barcode-Suche selbst ist gescheitert (z. B. Gerät ohne Neural Engine) – nicht dasselbe wie „kein Barcode im Bild“.
    var barcodeUnavailable = false
    /// Gelesene Barcode-Art, die Restwert nicht nachzeichnen kann (z. B. Code 93, Codabar) und als Code 128 zeigt.
    var convertedSymbology: String?

    /// Regel-Parser plus KI-Ergebnis; die KI füllt nur Lücken, und nur mit Angaben, die im Text stehen.
    /// Mit „Wann gekauft?“ werden Laufzeit und gesetzliche Frist ab diesem Tag gerechnet.
    var draft: CardDraft { ScanDraft.merge(text: text, smart: smart, now: received ?? .now) }

    /// Angezeigter und gespeicherter Code: der gelesene Barcode. Bei reinen Online-Codes ohne Barcode-Anzeige
    /// die gedruckte Schreibweise („OT-7731-5520-9912“), wenn sie bis auf Bindestriche/Leerzeichen dasselbe ist.
    var displayCode: String? {
        let d = draft
        guard let barcode else { return d.number }
        let online = d.merchantID.flatMap { Merchant.byID[$0] }?.category == .codeOnly
        func plain(_ s: String) -> String { s.filter { $0.isLetter || $0.isNumber }.uppercased() }
        if online, let printed = d.number, plain(printed) == plain(barcode) { return printed }
        return barcode
    }

    /// Ladenname für die Überschrift; bei Stadtgutscheinen mit Stadt („Stadtgutschein Kassel“).
    var displayMerchantName: String? {
        let d = draft
        guard let id = d.merchantID, let m = Merchant.byID[id] else { return d.customName }
        if id == "stadtgutschein",
           let city = text.firstMatch(of: /([A-ZÄÖÜ][a-zäöüß]+(?:-[A-ZÄÖÜ][a-zäöüß]+)?)\s+Stadtgutschein|Stadtgutschein\s+([A-ZÄÖÜ][a-zäöüß]+)/)
            .flatMap({ $0.1 ?? $0.2 }).map(String.init), city.lowercased() != "der", city.lowercased() != "ihr" {
            return "\(m.name) \(city)"
        }
        return m.name
    }

    /// Felder, die nur Apple Intelligence gefunden hat (der Regel-Parser nicht): im Ergebnis markiert.
    var aiFilled: Set<String> {
        guard smart != nil else { return [] }
        let rules = TextParser.parse(text, now: received ?? .now)
        let d = draft
        var out: Set<String> = []
        if rules.value == nil && d.value != nil || rules.percent == nil && d.percent != nil { out.insert("Wert") }
        if rules.number == nil && d.number != nil { out.insert("Code") }
        if rules.expires == nil && d.expires != nil { out.insert("Gültig bis") }
        if rules.pin == nil && d.pin != nil { out.insert("PIN") }
        return out
    }

    /// Genug gefunden, um von einem Gutschein auszugehen (Laden, Betrag, Code, Barcode oder Gutschein-Wörter).
    var looksLikeVoucher: Bool { ScanDraft.looksLikeVoucher(draft, text: text, hasBarcode: barcode != nil) }

    /// Barcode-Format, das der Gutschein bekommt: gescannt, aus einer gültigen EAN im Text oder vom Laden.
    /// Formular und Ergebnis nutzen dieselbe Regel, damit sie sich nicht widersprechen.
    var resolvedFormat: (format: CodeFormat, origin: FormatOrigin)? {
        let d = draft
        // Reine Online-Läden: an der Kasse nur der Code zum Eintippen, auch wenn ein Barcode gelesen wurde.
        if d.percent == nil, d.merchantID.flatMap({ Merchant.byID[$0] })?.category == .codeOnly { return (.text, .merchant) }
        if barcode != nil, let format { return (format, .scanned) }
        guard let number = d.number else { return nil }
        // 13 Ziffern mit gültiger EAN-Prüfziffer: sehr wahrscheinlich ein EAN-Barcode (auch bei bekannten Läden).
        if d.percent == nil, let check = ScanDraft.retailCheck(number), check.valid { return (check.format, .number) }
        return (CodeFormat.automatic(kind: d.percent == nil ? .giftCard : .discountCode, merchantID: d.merchantID), .merchant)
    }

    enum FormatOrigin: Sendable { case scanned, number, merchant }
}

nonisolated extension CodeFormat {
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

nonisolated extension CodeFormat {
    /// Diese Arten zeichnet Restwert im Original nach; andere (Code 93, Codabar, GS1 DataBar, MSI …) als Code 128.
    static func nativelyDrawn(_ s: BarcodeSymbology) -> Bool {
        [.ean13, .ean8, .upce, .itf14, .i2of5, .i2of5Checksum, .code39, .code39Checksum, .code39FullASCII, .code39FullASCIIChecksum,
         .code128, .qr, .microQR, .pdf417, .microPDF417, .aztec, .dataMatrix].contains(s)
    }

    static func nativelyDrawn(legacy s: VNBarcodeSymbology) -> Bool {
        [.ean13, .ean8, .upce, .itf14, .i2of5, .i2of5Checksum, .code39, .code39Checksum, .code39FullASCII, .code39FullASCIIChecksum,
         .code128, .qr, .microQR, .pdf417, .microPDF417, .aztec, .dataMatrix].contains(s)
    }

    init(legacy symbology: VNBarcodeSymbology) {
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

nonisolated extension BarcodeObservation {
    /// Nutzlast passend zu CodeFormat: UPC-E auf die 12 Ziffern von UPC-A erweitert.
    var normalizedPayload: String? {
        guard symbology == .upce, let p = payloadString else { return payloadString }
        return BarcodeEncoder.expandUPCE(p) ?? p
    }
}

/// Welcher Schritt beim Lesen gerade läuft – für die Anzeige „Wird gelesen …“.
@MainActor @Observable
final class ScanProgress {
    static let shared = ScanProgress()
    var step = "Barcode und Text werden gesucht …"

    nonisolated static func set(_ text: String) {
        Task { @MainActor in shared.step = text }
    }
}

nonisolated enum Importer {
    private static let log = Logger(subsystem: "de.restwert.app", category: "Scan")

    /// Barcode und Text (inkl. Handschrift) mit der Vision-Swift-API lesen, danach optional mit Apple Intelligence strukturieren.
    /// `smart: false` für einzelne PDF-Seiten: Apple Intelligence läuft dann einmal über den ganzen Text.
    @concurrent
    static func analyze(cgImage: CGImage, smart: Bool = true) async -> ScanOutcome {
        ScanProgress.set("Barcode und Text werden gesucht …")
        async let codes = detectBarcodes(cgImage)
        async let lines = recognizeText(cgImage)
        let (found, text) = await (codes, lines)
        // Strichcodes vor 2D-Codes bevorzugen: Gutscheinkarten tragen an der Kasse meist den Strichcode.
        let best = found.codes.first { !CodeFormat($0.symbology).isTwoDimensional } ?? found.codes.first
        var outcome = ScanOutcome(barcode: best?.normalizedPayload, format: best.map { CodeFormat($0.symbology) }, text: text)
        if let s = best?.symbology, !CodeFormat.nativelyDrawn(s) { outcome.convertedSymbology = "\(s)".uppercased() }
        if found.failed {
            switch await legacyBarcodes(cgImage) {
            case .found(let payload, let symbology):
                outcome.barcode = symbology == .upce ? (BarcodeEncoder.expandUPCE(payload) ?? payload) : payload
                outcome.format = CodeFormat(legacy: symbology)
                if !CodeFormat.nativelyDrawn(legacy: symbology) {
                    outcome.convertedSymbology = symbology.rawValue.replacingOccurrences(of: "VNBarcodeSymbology", with: "").uppercased()
                }
            case .none: break          // Suche lief, nur kein Barcode im Bild
            case .failed:
                // Letzter Weg ohne Neural Engine: CoreImage liest wenigstens QR-Codes.
                if let qr = qrWithCoreImage(cgImage) {
                    outcome.barcode = qr
                    outcome.format = .qr
                } else {
                    outcome.barcodeUnavailable = true
                }
            }
        }
        // Abgebrochen: die teure KI-Auswertung nicht mehr starten.
        guard smart, !Task.isCancelled else { return outcome }
        if SmartExtractor.isAvailable { ScanProgress.set("Apple Intelligence ordnet die Angaben …") }
        if let smart = await SmartExtractor.extract(from: text) {
            outcome.smart = smart
            outcome.usedAppleIntelligence = true
        }
        return outcome
    }

    /// Gefundene Codes; `failed`, wenn die Suche selbst nicht lief (sonst sähe das aus wie „kein Barcode im Bild“).
    @concurrent
    private static func detectBarcodes(_ image: CGImage) async -> (codes: [BarcodeObservation], failed: Bool) {
        let request = DetectBarcodesRequest()
        do {
            let results = try await request.perform(on: image)
            return (results.filter { !($0.payloadString ?? "").isEmpty }, false)
        } catch {
            log.error("Barcode-Suche fehlgeschlagen: \(String(describing: error), privacy: .public)")
            return ([], true)
        }
    }

    /// Ältere Vision-Schnittstelle als Ersatz, wenn die neue keinen Detektor anlegen kann.
    /// QR-Code mit CoreImage (läuft auch ohne Neural Engine, z. B. im Simulator).
    private static func qrWithCoreImage(_ image: CGImage) -> String? {
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let features = detector?.features(in: CIImage(cgImage: image)) ?? []
        return features.compactMap { ($0 as? CIQRCodeFeature)?.messageString }.first { !$0.isEmpty }
    }

    private enum LegacyResult { case found(String, VNBarcodeSymbology), none, failed }

    @concurrent
    private static func legacyBarcodes(_ image: CGImage) async -> LegacyResult {
        // Erst die aktuelle Revision, dann Revision 1: ältere, nicht KI-basierte Erkennung, die auch ohne
        // Neural Engine läuft (Simulator, sehr alte Geräte).
        var request = VNDetectBarcodesRequest()
        do { try VNImageRequestHandler(cgImage: image).perform([request]) } catch {
            log.error("Ersatz-Barcode-Suche fehlgeschlagen: \(String(describing: error), privacy: .public)")
            let r1 = VNDetectBarcodesRequest()
            r1.revision = VNDetectBarcodesRequestRevision1
            do { try VNImageRequestHandler(cgImage: image).perform([r1]); request = r1 } catch {
                log.error("Barcode-Suche Revision 1 fehlgeschlagen: \(String(describing: error), privacy: .public)")
                return .failed
            }
        }
        let found = (request.results ?? []).compactMap { r in r.payloadStringValue.flatMap { $0.isEmpty ? nil : ($0, r.symbology) } }
        guard let best = found.first(where: { !CodeFormat(legacy: $0.1).isTwoDimensional }) ?? found.first else { return .none }
        return .found(best.0, best.1)
    }

    @concurrent
    private static func recognizeText(_ image: CGImage) async -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate          // erkennt auch Handschrift
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        request.recognitionLanguages = [Locale.Language(identifier: "de-DE"), Locale.Language(identifier: "en-US")]
        let observations: [RecognizedTextObservation]
        do { observations = try await request.perform(on: image) } catch {
            log.error("Texterkennung fehlgeschlagen: \(String(describing: error), privacy: .public)")
            observations = []
        }
        return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
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
        ScanProgress.set(SmartExtractor.isAvailable ? "Apple Intelligence ordnet die Angaben …" : "Text wird ausgewertet …")
        var out = ScanOutcome(text: text, source: .text)
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
            var result = ScanOutcome(source: .document)
            var texts: [String] = []
            for i in 0..<min(doc.pageCount, 3) {
                guard let page = doc.page(at: i) else { continue }
                let pageText = page.string ?? ""
                let box = page.bounds(for: .mediaBox)
                let scale = 1800 / max(box.width, box.height, 1)
                let img = page.thumbnail(of: CGSize(width: box.width * scale, height: box.height * scale), for: .mediaBox)
                if result.photo == nil { result.photo = img.thumbnailJPEG() }
                if let cg = img.cgImage {
                    guard !Task.isCancelled else { break }
                    let o = await analyze(cgImage: cg, smart: false)
                    result.barcodeUnavailable = result.barcodeUnavailable || o.barcodeUnavailable
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
            if SmartExtractor.isAvailable, !Task.isCancelled { ScanProgress.set("Apple Intelligence ordnet die Angaben …") }
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
