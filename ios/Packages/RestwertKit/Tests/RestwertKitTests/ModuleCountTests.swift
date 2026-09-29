import Testing
@testable import RestwertKit

/// Modulzahl je Barcode-Art nach Norm: stimmt sie, liegen Start-/Stopp- und Trennzeichen richtig.
@Suite("Barcodes: Modulzahl nach Norm")
struct ModuleCountTests {
    @Test("EAN-13 und UPC-A: 95 Module")
    func ean13() {
        #expect(BarcodeEncoder.modules(for: "4006381333931", format: .ean13)?.count == 95)
        #expect(BarcodeEncoder.modules(for: "036000291452", format: .upca)?.count == 95)
    }

    @Test("EAN-8: 67 Module")
    func ean8() {
        #expect(BarcodeEncoder.modules(for: "96385074", format: .ean8)?.count == 67)
    }

    @Test("ITF (breit = 3 schmal): Start 4, je Ziffernpaar 18, Stopp 5 Module")
    func itf() {
        // 14 Ziffern = 7 Paare: 4 + 7 × 18 + 5 = 135.
        let m = BarcodeEncoder.modules(for: "00012345678905", format: .itf)
        #expect(m?.count == 135)
        #expect(m?.first == true && m?.last == true)
        // Ungerade Ziffernzahl lässt sich nicht als ITF kodieren.
        #expect(BarcodeEncoder.modules(for: "123", format: .itf) == nil)
    }

    @Test("Code 39: jedes Zeichen gleich breit, Start und Stopp mit *")
    func code39() {
        let one = BarcodeEncoder.modules(for: "A", format: .code39)?.count ?? 0
        let two = BarcodeEncoder.modules(for: "AB", format: .code39)?.count ?? 0
        #expect(one > 0)
        // Zeichen = 9 Elemente, davon 3 breit (3:1) = 15 Module, plus 1 Modul Zeichenabstand.
        #expect(two - one == 16)
        #expect(BarcodeEncoder.modules(for: "a", format: .code39) == BarcodeEncoder.modules(for: "A", format: .code39))
    }

    @Test("Code 128: Start + Zeichen + Prüfzeichen je 11 Module, Stopp 13; beginnt mit Strich, endet mit Doppelstrich")
    func code128() throws {
        for value in ["A", "RESTWERT-2026", "6300981274561234", "SG-2291-7730", "ab c+/%"] {
            let m = try #require(Code128.modules(value), "\(value)")
            #expect((m.count - 13) % 11 == 0, "\(value): \(m.count) Module")
            #expect(m.count >= 11 * 3 + 13)
            #expect(m.first == true && m.last == true)
            // Stopp-Muster 2331112 = 11000111010 11
            #expect(Array(m.suffix(13)) == [true, true, false, false, false, true, true, true, false, true, false, true, true])
        }
        // Außerhalb von ASCII (é, €) kann Code 128 nichts darstellen: kein Barcode, die App zeigt den Code als Text.
        #expect(Code128.modules("Café 25€") == nil)
        // Reine Ziffern nutzt Code-Satz C (Paare): kürzer als dieselbe Länge in Buchstaben.
        let digits = try #require(Code128.modules("12345678901234"))
        let letters = try #require(Code128.modules("ABCDEFGHIJKLMN"))
        #expect(digits.count < letters.count)
    }
}
