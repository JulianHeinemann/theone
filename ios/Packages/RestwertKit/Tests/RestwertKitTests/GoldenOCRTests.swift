import Foundation
import Testing
@testable import RestwertKit

/// Echte Texterkennung (Vision, macOS) der Testgutscheine aus docs/evaluation/testgutscheine.
/// Geprüft wird nur der Regel-Parser, also ohne Apple Intelligence (ältere Geräte, KI aus).
@Suite("Golden-Set: Testgutscheine ohne KI")
struct GoldenOCRTests {
    struct Case: CustomTestStringConvertible, Sendable {
        let id: String
        let text: String
        var merchant: String?
        var value: Double?
        var percent: Double?
        var number: String?
        var pin: String?
        var expires: [Int]?
        var voucher = true
        var testDescription: String { id }
    }

    static let now = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 27, hour: 12))!

    static let cases: [Case] = [
        Case(id: "v01 Douglas", text: "DOUGLAS\nGeschenkkarte • Wert: 50,00 €\nKartennummer: 4006381333931\nGültig bis 31.12.2029\n4006381333931",
             merchant: "douglas", value: 50, number: "4006381333931", expires: [2029, 12, 31]),
        Case(id: "v02 Thalia", text: "Thalia Geschenkkarte\nGuthaben 25 €\nKartennr. 6280 1234 5678 9012\nPIN: 4821 gültig bis 30.06.2028",
             merchant: "thalia", value: 25, number: "6280123456789012", pin: "4821", expires: [2028, 6, 30]),
        Case(id: "v03 IKEA", text: "IKEA Gutschein\n100,00 EUR\nCode: IK-9934-2281-4410\n3 Jahre gültig ab Ausstellung",
             merchant: "ikea", value: 100, number: "IK-9934-2281-4410", expires: [2029, 9, 27]),
        Case(id: "v04 Café Handschrift", text: "GUTSCHEIN\ncafé sonnenschein\nüber 30, - Euro\nfür oma Gisela\ngültig bis Ende 2027",
             value: 30, expires: [2027, 12, 31]),
        Case(id: "v05 Zalando Rabatt", text: "ZALANDO\n15 % Rabatt auf alles - ab 50 € Mindestbestellwert\nGutscheincode: ZAL15SOMMER26\neinlösbar bis 15.10.2026",
             merchant: "zalando", percent: 15, number: "ZAL15SOMMER26", expires: [2026, 10, 15]),
        Case(id: "v06 MediaMarkt", text: "MediaMarkt Geschenkkarte\nWert 200 €\nKundennummer: 88812345678\ngültig bis 01.03.2030\n4006381333934",
             merchant: "mediamarkt", value: 200, number: "4006381333934", expires: [2030, 3, 1]),
        Case(id: "v07 H&M abgelaufen", text: "H&M Geschenkkarte\nWert: 20,00 €\nKartennummer 7002 5566 7788 9900\ngültig bis 31.12.2024",
             merchant: "hm", value: 20, number: "7002556677889900", expires: [2024, 12, 31]),
        Case(id: "v08 Rossmann unscharf", text: "Rossmann Geschenkkarte\n15 €\nNummer 9120 4455 1234\ngültig bis 12/28",
             merchant: "rossmann", value: 15, number: "912044551234", expires: [2028, 12, 31]),
        Case(id: "v09 Amazon", text: "amazon.de Gutschein\nBetrag: 1.250,00 €\nGutscheincode: AQ7K-2ZPM4H-R8TX\nGuthaben ist 10 Jahre gültig",
             merchant: "amazon", value: 1250, number: "AQ7K-2ZPM4H-R8TX", expires: [2036, 9, 27]),
        Case(id: "v10 CinemaxX englisch", text: "CinemaxX Gift Card\nValue: EUR 40\nCard number 5021 0099 3344 7781\nValid thru Dec 31, 2028",
             merchant: "cinemaxx", value: 40, number: "5021009933447781", expires: [2028, 12, 31]),
        Case(id: "v11 Einkaufsliste", text: "Einkaufsliste\nMilch, Brot, Äpfel", voucher: false),
        // Gestalteter Bäckerei-Gutschein (Foto aus der Fotos-App, Juli-Test): „Geschenkgutschein“ in Schreibschrift nicht oder verlesen.
        Case(id: "Krustenzauber ohne Gutschein-Wort", text: "KRUSTEN\nZAUBER\nKRUSTENZAUBER\nFÜR UNSERE BACKWELT\n25 €\nFür echte Backfreude und besondere Brotbackmomente.",
             value: 25),
        Case(id: "Krustenzauber verlesen", text: "KRUSTENZAUBER\nGesdienkgutsdiein\nFÜR UNSERE BACKWELT\n25 €", value: 25),
        Case(id: "Preisliste mit mehreren Beträgen", text: "Brot 4,50 €\nBrötchen 0,60 €\nKuchen 3,20 €", value: 4.5, voucher: false),
        // Einzelner Betrag, aber Preis/Werbung/Karte (Befund Runde 10): kein Gutschein.
        Case(id: "Preisschild", text: "BIO-HONIG\nnur 7,99 €\nje 500 g", value: 7.99, voucher: false),
        Case(id: "Tageskarte", text: "Tageskarte\nSchnitzel mit Pommes\n12 €", value: 12, voucher: false),
        Case(id: "Werbung", text: "SOMMER SALE\nJetzt kaufen\nab 49 €", voucher: false),
        Case(id: "Plakat Eintritt", text: "STADTFEST\nEintritt 10 €", value: 10, voucher: false),
        Case(id: "v12 Stadtgutschein", text: "Kassel Stadtgutschein\nWert 10 Euro\nSeriennummer KS-2026-004711\nGültigkeit: 24 Monate",
             merchant: "stadtgutschein", value: 10, number: "KS-2026-004711", expires: [2028, 9, 27]),
    ]

    @Test("Regel-Parser liest die Testgutscheine", arguments: cases)
    func golden(_ c: Case) {
        let d = ScanDraft.merge(text: c.text, smart: nil, now: Self.now)
        #expect(d.merchantID == c.merchant)
        #expect(d.value == c.value)
        #expect(d.percent == c.percent)
        #expect(d.number?.replacingOccurrences(of: " ", with: "") == c.number)
        #expect(d.pin == c.pin)
        if let e = c.expires {
            let got = d.expires.map { Calendar.current.dateComponents([.year, .month, .day], from: $0) }
            #expect([got?.year, got?.month, got?.day] == e.map(Optional.some))
        }
        #expect(ScanDraft.looksLikeVoucher(d, text: c.text, hasBarcode: false) == c.voucher)
    }

    @Test("Markante Überschrift wird Ladenname, wenn kein Laden bekannt ist")
    func headline() {
        #expect(ScanDraft.merge(text: "KRUSTEN\nZAUBER\nKRUSTENZAUBER\nFÜR UNSERE BACKWELT\n25 €", smart: nil).customName == "Krustenzauber")
        #expect(ScanDraft.merge(text: "KRUSTENZAUBER\nFÜR UNSERE BACKWELT\n25 €", smart: nil).customName == "Krustenzauber")
        #expect(ScanDraft.merge(text: "GUTSCHEIN\ncafé sonnenschein\nüber 30, - Euro", smart: nil).customName == "Café Sonnenschein")
        #expect(ScanDraft.merge(text: "DOUGLAS\nGeschenkkarte 50 €", smart: nil).customName == nil)
        // Auch über Apple Intelligence: Versalien des Schriftzugs werden normal geschrieben, Kürzel nicht.
        #expect(ScanDraft.merge(text: "KRUSTENZAUBER\nGeschenkgutschein\n25 €", smart: CardDraft(customName: "KRUSTENZAUBER")).customName == "Krustenzauber")
        #expect(ScanDraft.merge(text: "KFC\nGutschein 10 €", smart: CardDraft(customName: "KFC")).customName == "KFC")
    }
}
