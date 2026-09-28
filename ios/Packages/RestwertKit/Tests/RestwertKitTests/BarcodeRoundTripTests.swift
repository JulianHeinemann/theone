#if canImport(Vision) && canImport(CoreGraphics)
import Foundation
import Testing
import Vision
import CoreGraphics
@testable import RestwertKit

/// Zeichnet Barcodes wie die App (Module mit Ruhezone) und liest sie mit Apples Barcode-Erkennung zurück.
/// So ist geprüft, dass ein Scanner an der Kasse genau den gespeicherten Code bekommt.
@Suite("Barcodes: zeichnen und zurücklesen")
struct BarcodeRoundTripTests {
    static func linear(_ m: [Bool], module: Int = 3) -> CGImage {
        let padded = Array(repeating: false, count: 10) + m + Array(repeating: false, count: 10)
        let w = padded.count * module + 40, h = 190
        let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(CGColor(gray: 1, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: w, height: h))
        c.setFillColor(CGColor(gray: 0, alpha: 1))
        for (i, on) in padded.enumerated() where on { c.fill(CGRect(x: 20 + i * module, y: 20, width: module, height: 150)) }
        return c.makeImage()!
    }

    static func matrix(_ m: [[Bool]], module: Int = 10) -> CGImage {
        let n = m.count, q = 2 * module, w = n * module + 2 * q
        let c = CGContext(data: nil, width: w, height: w, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(CGColor(gray: 1, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: w, height: w))
        c.setFillColor(CGColor(gray: 0, alpha: 1))
        for (y, row) in m.enumerated() { for (x, on) in row.enumerated() where on {
            c.fill(CGRect(x: q + x * module, y: w - q - (y + 1) * module, width: module, height: module)) } }
        return c.makeImage()!
    }

    static func read(_ image: CGImage) -> [String] {
        let r = VNDetectBarcodesRequest()
        try? VNImageRequestHandler(cgImage: image).perform([r])
        return (r.results ?? []).compactMap(\.payloadStringValue)
    }

    static func withCheck(_ body: String) -> String {
        body + String(BarcodeEncoder.checkDigit(body.compactMap(\.wholeNumberValue)))
    }

    @Test("EAN-13, EAN-8, UPC-A, ITF, Code 39", arguments: [
        (CodeFormat.ean13, "4006381333931"), (.ean13, "5901234123457"), (.ean13, withCheck("400638133393")),
        (.ean8, "96385074"), (.ean8, "55123457"),
        (.upca, "036000291452"), (.upca, "012345678905"),
        (.itf, "1234567890"), (.itf, "00012345678905"),
        (.code39, "ABC-123"), (.code39, "GUTSCHEIN 42")])
    func linearFormats(_ format: CodeFormat, _ value: String) throws {
        let m = try #require(BarcodeEncoder.modules(for: value, format: format))
        let got = Self.read(Self.linear(m))
        let expected = format == .upca ? ["0" + value, value] : [value]
        #expect(got.contains { expected.contains($0) }, "gelesen: \(got)")
    }

    @Test("Data Matrix in allen Symbolgrößen, mit Ziffernpaaren, Leerzeichen und Umlauten", arguments: [
        "0123456789", "A", "Hello", "KS-2026-004711", "6280 1234 5678 9012", "GUTSCHEIN 42", "abc123XYZ!?",
        "Käse & Öl", "Preis 5 €", String(repeating: "1234567890", count: 8), String(repeating: "Gutschein-", count: 12)])
    func dataMatrix(_ value: String) throws {
        let m = try #require(BarcodeEncoder.dataMatrix(value))
        #expect(Self.read(Self.matrix(m)).contains(BarcodeEncoder.payload(value)))
    }

    @Test("Anzeige-Leerzeichen nur bei Ziffern entfernen")
    func payload() {
        #expect(BarcodeEncoder.payload("6280 1234 5678 9012") == "6280123456789012")
        #expect(BarcodeEncoder.payload("GUTSCHEIN 42") == "GUTSCHEIN 42")
        #expect(BarcodeEncoder.payload("  AB-12  ") == "AB-12")
    }
}
#endif
