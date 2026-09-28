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

    @Test("Mindestbestellwert und Datum sind nicht der Gutscheinwert", arguments: [
        ("Ihr Amazon Gutschein über 10 € – einlösbar ab einem Mindestbestellwert. Gültig bis 31.12.2026", 10.0),
        ("Zalando Gutschein 10 € ab 50 € Mindestbestellwert", 10.0),
        ("Gutschein über 1.000 € Otto", 1000.0),
    ])
    func amountsWithNoise(text: String, expected: Double) {
        #expect(TextParser.amount(in: text) == expected)
    }

    @Test("Tausenderpunkt ohne Nachkommastellen", arguments: [("1.000", 1000.0), ("12.345", 12345.0), ("12.50", 12.5), ("12.5", 12.5)])
    func thousands(text: String, expected: Double) {
        #expect(parseMoney(text) == expected)
    }

    @Test("MwSt-Satz und „Gutscheincode“ machen keinen Rabattcode")
    func vatIsNoDiscount() {
        let d = TextParser.parse("Gutscheincode: AQ12-BCDE-FG34\n25,00 € inkl. 19 % MwSt.", now: date(2026, 9, 25))
        #expect(d.percent == nil)
        #expect(!d.isDiscount)
        #expect(d.value == 25)
        #expect(TextParser.percent(in: "Noch 10 % offen, Code ABC") == nil)
        #expect(TextParser.percent(in: "20 % Rabatt, inkl. 19 % MwSt") == 20)
    }

    @Test("Kunden- und Bestellnummer sind kein Gutscheincode", arguments: [
        ("Kundennummer: 12345678\nIhr Gutscheincode: XK9P-44TT-ZZ81\nWert: 25,00 €", "XK9P-44TT-ZZ81"),
        ("Bestellnummer: 302-1234567-7654321\nGutscheincode: AQ12-BCDE-FG34", "AQ12-BCDE-FG34"),
        ("Bestellnummer: 302-1234567-7654321\nCode: ZX81-7788", "ZX81-7788"),
    ])
    func customerNumber(text: String, expected: String) {
        #expect(TextParser.parse(text, now: date(2026, 9, 25)).number == expected)
    }

    @Test("„gültig vom X bis Y“ ergibt das Enddatum")
    func validityRange() throws {
        let d = try #require(TextParser.expiry(in: "Gutschein gültig vom 01.10.2026 bis 31.12.2026. Code: ABCD1234EF", now: date(2026, 9, 25)))
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        #expect(c.year == 2026 && c.month == 12 && c.day == 31)
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

    @Test("ITF nur mit gerader Ziffernzahl, nie still mit 0 aufgefüllt (der Scanner läse sonst einen anderen Code)")
    func itf() {
        #expect(BarcodeEncoder.itf("123") == nil)
        #expect(BarcodeEncoder.itf("0123") != nil)
        #expect(BarcodeEncoder.itf("12AB") == nil)
    }

    @Test("Prüfziffer nur bei EAN/UPC; sonst keine Aussage")
    func checksumOnlyForEANUPC() {
        #expect(BarcodeEncoder.hasValidChecksum("AB12-CD34", format: .code128) == nil)
        #expect(BarcodeEncoder.hasValidChecksum("https://example.com/g/123", format: .qr) == nil)
        #expect(BarcodeEncoder.hasValidChecksum("6300981274561234", format: .code128) == nil)
        #expect(BarcodeEncoder.hasValidChecksum("AB12", format: .ean13) == false)
    }

    @Test("UPC-E wird zu UPC-A erweitert", arguments: [
        ("01234565", "012345000065"), ("123456", "012345000065"), ("04252614", "042100005264"), ("01234133", "012300000413"),
    ])
    func upce(raw: String, expected: String) {
        #expect(BarcodeEncoder.expandUPCE(raw) == expected)
        #expect(BarcodeEncoder.hasValidChecksum(expected, format: .upca) == true)
        #expect(BarcodeEncoder.modules(for: expected, format: .upca)?.count == 95)
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

    @Test("Archiv und eigene Erinnerung überstehen den Roundtrip, Archiv zählt nicht zur Summe")
    func archiveRoundTrip() throws {
        var c = card()
        c.archivedAt = Date(timeIntervalSince1970: 1_800_000_000)
        c.reminderAt = Date(timeIntervalSince1970: 1_900_000_000)
        let data = try APICoding.encoder.encode(SyncData(cards: [c], tests: [], deleted: []))
        let back = try APICoding.decoder.decode(SyncData.self, from: data).cards[0]
        #expect(back.isArchived)
        #expect(back.reminderAt == c.reminderAt)
        #expect(!back.isActive)
        #expect(CardQueries.openTotal([back, card("ikea")]) == 50)
    }

    @Test("Besitzer und Verschenken überstehen den Roundtrip, Verschenken zählt nicht zur Summe")
    func ownerRoundTrip() throws {
        var c = card()
        c.owner = "Mia"
        c.forGifting = true
        let data = try APICoding.encoder.encode(SyncData(cards: [c], tests: [], deleted: []))
        let back = try APICoding.decoder.decode(SyncData.self, from: data).cards[0]
        #expect(back.owner == "Mia")
        #expect(back.forGifting)
        #expect(CardQueries.openTotal([back, card("ikea")]) == 50)
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

@Suite("Korrektur und Aufladen")
struct BalanceTests {
    @Test("Neuer Stand laut Bon: Differenz im Verlauf, Aufladung erhöht den Startwert")
    func setBalance() {
        var c = card(value: 50)
        c.setBalance(37.5)
        #expect(c.balance == 37.5)
        #expect(c.history.last?.amount == 12.5)
        c.setBalance(80)
        #expect(c.balance == 80)
        #expect(c.value == 80)
        #expect(c.history.last?.amount == -42.5)
        #expect(c.history.last?.note == "Aufgeladen")
        let before = c.history.count
        c.setBalance(80)
        #expect(c.history.count == before)
    }
}

@Suite("iCloud-Nutzlast")
struct CloudPayloadTests {
    @Test("Verschlüsselt, ohne Klartext, PIN und Foto; mit richtigem Schlüssel lesbar")
    func sealAndOpen() throws {
        var c = card()
        c.pin = "4821"
        c.photo = Data([9, 9, 9])
        let key = CloudPayload.newKey()
        let blob = try CloudPayload.seal(c, key: key)
        #expect(blob.range(of: Data("6300981274561234".utf8)) == nil)
        #expect(blob.range(of: Data("thalia".utf8)) == nil)
        let back = try CloudPayload.openCard(blob, key: key)
        #expect(back.id == c.id)
        #expect(back.number == c.number)
        #expect(back.balance == c.balance)
        #expect(back.pin.isEmpty)
        #expect(back.photo == nil)
    }

    @Test("Falscher Schlüssel oder beschädigte Daten werden abgelehnt")
    func wrongKey() throws {
        let blob = try CloudPayload.seal(card(), key: CloudPayload.newKey())
        #expect(throws: CloudPayload.Failure.wrongKeyOrDamaged) { try CloudPayload.openCard(blob, key: CloudPayload.newKey()) }
        var broken = blob
        broken[broken.count - 1] ^= 0xFF
        #expect(throws: CloudPayload.Failure.wrongKeyOrDamaged) { try CloudPayload.openCard(broken, key: CloudPayload.newKey()) }
    }

    @Test("Schlüssel lässt sich speichern und wiederherstellen")
    func keyRoundTrip() throws {
        let key = CloudPayload.newKey()
        let data = CloudPayload.keyData(key)
        #expect(data.count == 32)
        let blob = try CloudPayload.seal(card(), key: key)
        #expect(throws: Never.self) { try CloudPayload.openCard(blob, key: CloudPayload.key(from: data)) }
    }

    @Test("Upload-Plan: nur Neues, Neueres und fehlende Löschungen; keine Beispiele")
    func plan() {
        let old = Date(timeIntervalSince1970: 1_000)
        let new = Date(timeIntervalSince1970: 2_000)
        var a = card("ikea"); a.modifiedAt = new
        var b = card("thalia"); b.modifiedAt = old
        let c = card("douglas")
        var ex = card("zara"); ex.isExample = true
        let gone = UUID()
        let plan = CloudPlan.upload(localCards: [a, b, c, ex], localTests: [], localDeleted: [gone],
                                    remoteModified: [a.id: old, b.id: new], remoteTests: [], remoteTombstones: [])
        #expect(Set(plan.cards.map(\.id)) == [a.id, c.id])
        #expect(plan.tombstones == [gone])
    }
}

@Suite("Datenschicht")
struct DataLayerTests {
    @Test("Zeitstempel überstehen iCloud-Nutzlast mit Millisekunden; kein erneuter Upload")
    func timestampPrecision() throws {
        var c = card()
        c.modifiedAt = Date(timeIntervalSince1970: 1_800_000_000.734_512)
        let key = CloudPayload.newKey()
        let back = try CloudPayload.openCard(CloudPayload.seal(c, key: key), key: key)
        #expect(abs(back.modifiedAt.timeIntervalSince(c.modifiedAt)) < 0.001)
        let plan = CloudPlan.upload(localCards: [c], localTests: [], localDeleted: [], remoteModified: [c.id: back.modifiedAt],
                                    remoteTests: [], remoteTombstones: [])
        #expect(plan.cards.isEmpty)
        // Innerhalb derselben Sekunde gewinnt die tatsächlich neuere Änderung.
        var newer = back
        newer.balance = 1
        newer.modifiedAt = c.modifiedAt.addingTimeInterval(0.2)
        let r = SyncMerge.merge(localCards: [c], localTests: [], localDeleted: [], remote: SyncData(cards: [newer], tests: [], deleted: []))
        #expect(r.cards.first?.balance == 1)
    }

    @Test("Tests gelöschter Gutscheine und gelöschte Tests kommen nicht zurück")
    func deletedTests() {
        let a = card()
        let t1 = TestResult(cardID: a.id, merchantID: "thalia", merchantName: "Thalia", date: .now, success: true, format: .code128)
        let t2 = TestResult(merchantID: "ikea", merchantName: "IKEA", date: .now, success: false, format: .code128)
        let t3 = TestResult(merchantID: "dm", merchantName: "dm", date: .now, success: true, format: .code128)
        let r = SyncMerge.merge(localCards: [], localTests: [], localDeleted: [a.id, t2.id],
                                remote: SyncData(cards: [a], tests: [t1, t2, t3], deleted: []))
        #expect(r.cards.isEmpty)
        #expect(r.tests.map(\.id) == [t3.id])
    }

    @Test("Wiederherstellen: gelöschte Gutscheine bekommen neue IDs, Tests ziehen mit")
    func revive() {
        let gone = card("ikea")
        let kept = card("thalia")
        let t = TestResult(cardID: gone.id, merchantID: "ikea", merchantName: "IKEA", date: .now, success: true, format: .code128)
        let out = SyncMerge.revive(cards: [gone, kept], tests: [t], deleted: [gone.id])
        #expect(out.cards.count == 2)
        #expect(out.cards[0].id != gone.id)
        #expect(out.cards[1].id == kept.id)
        #expect(out.tests.first?.cardID == out.cards[0].id)
        #expect(out.tests.first?.id != t.id)
        let r = SyncMerge.merge(localCards: [], localTests: [], localDeleted: [gone.id],
                                remote: SyncData(cards: out.cards, tests: out.tests, deleted: []))
        #expect(r.cards.count == 2)
        #expect(r.tests.count == 1)
    }

    @Test("PIN: neuere gewinnt, Löschen bleibt gelöscht, alte Einträge füllen leere PIN")
    func pinResolve() throws {
        let old = Date(timeIntervalSince1970: 1_000)
        let new = Date(timeIntervalSince1970: 2_000)
        // Auf dem anderen Gerät geändert
        #expect(PinEntry.resolve(localPin: "1111", localChangedAt: old, vault: PinEntry(pin: "2222", changedAt: new))
                == .adopt(PinEntry(pin: "2222", changedAt: new)))
        // Hier geändert: hochschreiben, nicht zurückholen
        #expect(PinEntry.resolve(localPin: "2222", localChangedAt: new, vault: PinEntry(pin: "1111", changedAt: old))
                == .publish(PinEntry(pin: "2222", changedAt: new)))
        // Hier gelöscht: Löschung geht raus
        #expect(PinEntry.resolve(localPin: "", localChangedAt: new, vault: PinEntry(pin: "4821", changedAt: old))
                == .publish(PinEntry(pin: "", changedAt: new)))
        // Anderswo gelöscht: bleibt gelöscht
        #expect(PinEntry.resolve(localPin: "4821", localChangedAt: old, vault: PinEntry(pin: "", changedAt: new))
                == .adopt(PinEntry(pin: "", changedAt: new)))
        // Neues Gerät, alter Eintrag nur als Text
        let legacy = try #require(PinEntry(data: Data("9999".utf8)))
        #expect(legacy.changedAt == .distantPast)
        #expect(PinEntry.resolve(localPin: "", localChangedAt: nil, vault: legacy) == .adopt(legacy))
        #expect(PinEntry.resolve(localPin: "9999", localChangedAt: nil, vault: legacy) == .keep)
        // Kein Eintrag, keine PIN: nichts tun
        #expect(PinEntry.resolve(localPin: "", localChangedAt: nil, vault: nil) == .keep)
        let e = PinEntry(pin: "12", changedAt: new)
        #expect(PinEntry(data: e.data) == e)
    }

    @Test("Bon-Summe: nur echte Abzüge, Aufladungen getrennt, nie negativ")
    func bonTotals() {
        var c = card(value: 20)
        c.redeem(5)
        c.setBalance(100)
        let lines = CardQueries.bonLines([c])
        #expect(CardQueries.redeemedTotal(lines) == 5)
        #expect(CardQueries.toppedUpTotal(lines) == 85)
        #expect(CardQueries.redeemedTotal(lines.filter { $0.redemption.amount < 0 }) == 0)
    }

    @Test("CSV: Nummern als Text, deutsche Zahlen, Felder maskiert")
    func csv() {
        var c = card(value: 1234.5)
        c.number = "0036730012345678901"
        c.owner = "\"Oma\" Erna; Tante\nLisa"
        c.customName = "=HYPERLINK(1)"
        c.merchantID = "other"
        let text = CardQueries.csv([c], warnDays: 30, now: date(2026, 6, 1))
        let lines = text.components(separatedBy: "\r\n")
        #expect(lines.count == 3 && lines[2].isEmpty)
        #expect(lines[1].contains("\"=\"\"0036730012345678901\"\"\""))
        #expect(lines[1].contains(";1234,50;"))
        #expect(lines[1].contains("\"\"\"Oma\"\" Erna; Tante\nLisa\""))
        #expect(lines[1].hasPrefix("\"'=HYPERLINK(1)\""))
    }
}

@Suite("Ablaufdatum in allen Schreibweisen")
struct ExpiryFormats {
    private let now = date(2026, 9, 27)

    private func ymd(_ text: String) -> [Int]? {
        TextParser.expiry(in: text, now: now).map {
            let c = Calendar.current.dateComponents([.year, .month, .day], from: $0)
            return [c.year ?? 0, c.month ?? 0, c.day ?? 0]
        }
    }

    @Test("Erkannte Formate", arguments: [
        ("Gültig bis 31.12.2027", [2027, 12, 31]),
        ("gültig bis 31.12.27", [2027, 12, 31]),
        ("Ablauf: 31/12/2027", [2027, 12, 31]),
        ("expires 2027-12-31", [2027, 12, 31]),
        ("Gültig bis 31. Dezember 2027", [2027, 12, 31]),
        ("einlösbar bis 1. März 2028", [2028, 3, 1]),
        ("gültig bis 15. Okt. 2027", [2027, 10, 15]),
        ("Valid until Dec 31, 2027", [2027, 12, 31]),
        ("gültig bis 12/27", [2027, 12, 31]),
        ("Gültig bis 02/2028", [2028, 2, 29]),
        ("gültig bis Juni 2027", [2027, 6, 30]),
        ("Einlösbar bis Ende 2028", [2028, 12, 31]),
        ("Dieser Gutschein ist 3 Jahre gültig.", [2029, 9, 27]),
        ("Gültigkeit: 24 Monate ab Ausstellung", [2028, 9, 27]),
        ("Gutschein gültig für drei Jahre", [2029, 9, 27]),
        ("Kaufdatum 12.03.2026, einlösbar im Laden. 31.12.2028", [2028, 12, 31]),
    ])
    func formats(_ text: String, _ expected: [Int]) {
        #expect(ymd(text) == expected)
    }

    @Test("Kein Datum, falsche Daten und Beträge werden nicht zum Ablaufdatum", arguments: [
        "Wert 25,00 € – danke für deinen Einkauf",
        "Kaufdatum 12.03.2026",            // Vergangenheit ohne Beschriftung
        "gültig bis 31.02.2027",           // gibt es nicht
        "Filiale 12/27 Hauptstraße",       // Monat/Jahr ohne Beschriftung
        "Marktplatz 3, 50667 Köln",
    ])
    func noDate(_ text: String) {
        #expect(ymd(text) == nil)
    }
}
