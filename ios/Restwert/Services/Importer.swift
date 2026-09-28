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
    /// Wie viele Gutscheine über 100 € in den letzten 7 Tagen schon erfasst wurden (Betrugsmuster „kauf Gutscheine“).
    var recentHighValueCount = 0
    /// „Speichern mit einem Tipp“: einmal berechnet, wenn das Ergebnis feststeht (und nach geändertem Kaufdatum).
    var canSave = false
    /// Ein gespeicherter Gutschein mit demselben Code (Name), sonst nil.
    var duplicateName: String?
    var duplicateID: UUID?
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

    /// Sicher genug für „Speichern“ ohne Formular: Gutschein mit bekanntem Laden, Betrag oder Rabatt, Code,
    /// Ablaufdatum vom Gutschein, gelesener oder am Code erkannter Barcode (oder reiner Online-Code), keine Warnung,
    /// nichts nur von Apple Intelligence.
    @MainActor var canSaveDirectly: Bool {
        let d = draft
        guard looksLikeVoucher, duplicateID == nil, !hasWarnings, aiFilled.isEmpty, d.merchantID != nil,
              d.value != nil || d.percent != nil, displayCode != nil, d.expires != nil, !d.expiresIsEstimate,
              let format = resolvedFormat else { return false }
        // Nur mit wirklich gelesenem Barcode (oder Online-Code): aus der Nummer abgeleitet kann die Art falsch sein.
        return format.origin == .scanned || format.format == .text
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
    /// Barcode und Text (inkl. Handschrift) lesen – gestuft über `VoucherScanner` (ganzes Bild, Kontrast, Ausschnitte,
    /// Ersatzwege ohne Neural Engine) –, danach optional mit Apple Intelligence strukturieren.
    /// `smart: false` für einzelne PDF-Seiten: Apple Intelligence läuft dann einmal über den ganzen Text.
    @concurrent
    static func analyze(cgImage: CGImage, smart: Bool = true) async -> ScanOutcome {
        ScanProgress.set("Barcode und Text werden gesucht …")
        let reading = await VoucherScanner.read(cgImage)
        var outcome = ScanOutcome(barcode: reading.best?.payload, format: reading.best?.format, text: reading.text)
        outcome.convertedSymbology = reading.best?.converted
        outcome.barcodeUnavailable = reading.detectorFailed
        // Abgebrochen: die teure KI-Auswertung nicht mehr starten.
        guard smart, !Task.isCancelled else { return outcome }
        if SmartExtractor.isAvailable { ScanProgress.set("Apple Intelligence ordnet die Angaben …") }
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
                let scale = 2600 / max(box.width, box.height, 1)   // fein genug für kleine Barcodes auf A4
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
