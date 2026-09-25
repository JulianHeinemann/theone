import Foundation
import Testing
@testable import RestwertKit

private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
}

private func card(_ merchant: String = "thalia", kind: VoucherKind = .giftCard, value: Double = 50, balance: Double? = nil,
                  expires: Date = date(2030, 12, 31), modified: Date = date(2026, 1, 1)) -> GiftCard {
    GiftCard(kind: kind, merchantID: merchant, number: "6300981274561234", format: .code128, value: value,
             balance: balance ?? value, received: date(2026, 1, 1), expires: expires, modifiedAt: modified)
}

@Suite("Textparser")
struct TextParserTests {
    @Test("Gutschein-E-Mail: Shop, Wert, Code, PIN, Ablauf")
    func email() {
        let mail = """
        Hallo Julia,
        vielen Dank für deinen Einkauf bei Thalia! Hier ist dein Geschenkgutschein.
        Gutscheinwert: 25,00 €
        Gutscheincode: 6300 9812 7456 1234
        PIN: 4821
        Gültig bis 31.12.2029
        """
        let d = TextParser.parse(mail, now: date(2026, 9, 25))
        #expect(d.merchantID == "thalia")
        #expect(d.value == 25)
        #expect(d.number == "6300981274561234")
        #expect(d.pin == "4821")
        #expect(d.expires.map { Calendar.current.component(.year, from: $0) } == 2029)
        #expect(!d.isDiscount)
    }

    @Test("Rabattcode wird erkannt")
    func discount() {
        let d = TextParser.parse("Spare 15 % bei Zalando mit dem Code HERBST15-K7Q2, gültig bis 30.11.2026", now: date(2026, 9, 25))
        #expect(d.merchantID == "zalando")
        #expect(d.percent == 15)
        #expect(d.isDiscount)
        #expect(d.number == "HERBST15-K7Q2")
    }

    @Test("Handschrift-ähnlicher OCR-Text ohne Beschriftungen")
    func handwritten() {
        let ocr = "Gutschein\nüber 30 Euro\nfür Anna\nBuchhandlung am Markt\nNr 20260917"
        let d = TextParser.parse(ocr, now: date(2026, 9, 25))
        #expect(d.value == 30)
        #expect(d.number == "20260917")
        #expect(d.merchantID == nil)
    }

    @Test("Kurze Händlernamen nur als ganzes Wort", arguments: [("Einkauf bei dm am Markt", "dm"), ("Admin-Bereich", nil)])
    func wordBoundary(text: String, expected: String?) {
        #expect(TextParser.merchant(in: text) == expected)
    }

    @Test("Beträge", arguments: [("Wert: 1.234,56 €", 1234.56), ("EUR 20", 20.0), ("Betrag 12,5 EUR", 12.5)])
    func amounts(text: String, expected: Double) {
        #expect(TextParser.amount(in: text) == expected)
    }
}

@Suite("Barcodes")
struct BarcodeTests {
    @Test("EAN-13: gültige Prüfziffer kodiert 95 Module")
    func ean13() throws {
        let mods = try #require(BarcodeEncoder.ean13("4006381333931"))
        #expect(mods.count == 95)
        #expect(BarcodeEncoder.hasValidChecksum("4006381333931", format: .ean13) == true)
        #expect(BarcodeEncoder.hasValidChecksum("4006381333932", format: .ean13) == false)
        #expect(BarcodeEncoder.ean13("4006381333932") == nil)
    }

    @Test("EAN-13 ergänzt fehlende Prüfziffer")
    func ean13CheckDigit() {
        #expect(BarcodeEncoder.ean13("400638133393") == BarcodeEncoder.ean13("4006381333931"))
    }

    @Test("EAN-8 hat 67 Module")
    func ean8() {
        #expect(BarcodeEncoder.ean8("96385074")?.count == 67)
    }

    @Test("ITF füllt ungerade Länge mit führender 0")
    func itf() {
        #expect(BarcodeEncoder.itf("123") == BarcodeEncoder.itf("0123"))
        #expect(BarcodeEncoder.itf("12AB") == nil)
    }

    @Test("Code 39 lehnt unbekannte Zeichen ab")
    func code39() {
        #expect(BarcodeEncoder.code39("ABC-123") != nil)
        #expect(BarcodeEncoder.code39("abc") == nil)
        #expect(BarcodeEncoder.modules(for: "abc", format: .code39) != nil)
    }
}

@Suite("Gutscheine")
struct GiftCardTests {
    @Test("Gesetzliche Frist: 31.12. des dritten Folgejahres")
    func legalExpiry() {
        let e = GiftCard.legalExpiry(from: date(2026, 5, 11))
        let c = Calendar.current.dateComponents([.year, .month, .day], from: e)
        #expect(c.year == 2029 && c.month == 12 && c.day == 31)
    }

    @Test("Status nach Warnfrist")
    func status() {
        let now = date(2026, 9, 25)
        #expect(card(expires: date(2026, 10, 10)).status(warnDays: 30, now: now) == .expiringSoon)
        #expect(card(expires: date(2027, 10, 10)).status(warnDays: 30, now: now) == .valid)
        #expect(card(expires: date(2026, 9, 1)).status(warnDays: 30, now: now) == .expired)
        #expect(card(balance: 0).status(warnDays: 30, now: now) == .redeemed)
    }

    @Test("Teileinlösung schreibt Verlauf und rundet auf Cent")
    func redeem() {
        var c = card(value: 25)
        c.redeem(12.6, store: "Thalia Köln")
        c.redeem(100)
        #expect(c.balance == 0)
        #expect(c.history.count == 2)
        #expect(c.history.first?.balanceAfter == 12.4)
    }

    @Test("Rabattcode stempeln")
    func stamp() {
        var c = card("zalando", kind: .discountCode, value: 0, balance: 0)
        #expect(c.isOpen)
        c.markRedeemed()
        #expect(!c.isOpen)
        #expect(c.status(warnDays: 30) == .redeemed)
        #expect(c.history.count == 1)
    }

    @Test("Altes JSON ohne neue Felder bleibt lesbar")
    func tolerantDecoding() throws {
        let json = #"{"merchantID":"ikea","number":"123","value":50,"received":"2026-01-01T00:00:00Z","expires":"2029-12-31T00:00:00Z"}"#
        let c = try APICoding.decoder.decode(GiftCard.self, from: Data(json.utf8))
        #expect(c.kind == .giftCard)
        #expect(c.balance == 50)
        #expect(c.location == .drawer)
        #expect(c.format == .code128)
    }

    @Test("API-Datum mit Sekundenbruchteilen")
    func fractionalDates() throws {
        let json = #"{"merchantID":"ikea","number":"1","value":5,"received":"2026-01-01T10:00:00.123Z","expires":"2029-12-31T00:00:00Z"}"#
        let c = try APICoding.decoder.decode(GiftCard.self, from: Data(json.utf8))
        #expect(Calendar(identifier: .gregorian).component(.year, from: c.received) == 2026)
    }

    @Test("Sortierung: offene zuerst, dann nach Wert")
    func sorting() {
        let a = card("ikea", value: 10)
        let b = card("thalia", value: 40)
        let spent = card("douglas", value: 90, balance: 0)
        let sorted = CardQueries.sorted([spent, a, b], by: .value)
        #expect(sorted.map(\.merchantID) == ["thalia", "ikea", "douglas"])
    }

    @Test("Radar: näher an der Mitte = früher fällig")
    func radar() {
        #expect(CardQueries.radarFraction(forDays: 10) < CardQueries.radarFraction(forDays: 100))
        #expect(CardQueries.radarFraction(forDays: 30) == 0.32)
        #expect(CardQueries.radarFraction(forDays: 5000) == 0.98)
    }
}

@Suite("Sync")
struct SyncTests {
    @Test("Neuere Änderung gewinnt, PIN bleibt lokal")
    func newerWins() {
        var local = card(modified: date(2026, 1, 1))
        local.pin = "1234"
        var remote = local
        remote.balance = 10
        remote.pin = ""
        remote.modifiedAt = date(2026, 2, 1)
        let r = SyncMerge.merge(localCards: [local], localTests: [], localDeleted: [], remote: SyncData(cards: [remote], tests: [], deleted: []))
        #expect(r.cards.first?.balance == 10)
        #expect(r.cards.first?.pin == "1234")
    }

    @Test("Ältere Server-Version überschreibt nichts")
    func olderLoses() {
        let local = card(balance: 5, modified: date(2026, 3, 1))
        var remote = local
        remote.balance = 50
        remote.modifiedAt = date(2026, 2, 1)
        let r = SyncMerge.merge(localCards: [local], localTests: [], localDeleted: [], remote: SyncData(cards: [remote], tests: [], deleted: []))
        #expect(r.cards.first?.balance == 5)
    }

    @Test("Gelöschte Gutscheine tauchen nicht wieder auf")
    func deletions() {
        let a = card("ikea")
        let b = card("thalia")
        let r = SyncMerge.merge(localCards: [a], localTests: [], localDeleted: [], remote: SyncData(cards: [b], tests: [], deleted: [a.id]))
        #expect(r.cards.map(\.id) == [b.id])
        #expect(r.deleted.contains(a.id))
    }

    @Test("Ausgehende Daten ohne PIN, Foto und Beispiele")
    func outgoing() {
        var c = card()
        c.pin = "9999"
        c.photo = Data([1, 2, 3])
        var example = card("ikea")
        example.isExample = true
        let out = SyncData.outgoing(cards: [c, example], tests: [], deleted: [])
        #expect(out.cards.count == 1)
        #expect(out.cards[0].pin.isEmpty)
        #expect(out.cards[0].photo == nil)
    }

    @Test("Roundtrip über die API-Kodierung")
    func roundTrip() throws {
        var c = card()
        c.redeem(5, store: "Test")
        let data = try APICoding.encoder.encode(SyncData(cards: [c], tests: [], deleted: []))
        let back = try APICoding.decoder.decode(SyncData.self, from: data)
        #expect(back.cards.first?.history.first?.amount == 5)
        #expect(back.cards.first?.balance == 45)
    }
}
