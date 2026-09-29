import Foundation
import Testing
@testable import RestwertKit

private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
}

private func coupon(kind: VoucherKind = .coupon) -> GiftCard {
    GiftCard(kind: kind, merchantID: "other", customName: "Café", number: "KAFFEE", format: .text, value: 0, balance: 0,
             received: day(2026, 9, 1), expires: day(2026, 12, 31))
}

@Suite("Coupons: Rabatt, Angebot und Code erkennen")
struct CouponParserTests {
    let now = day(2026, 9, 29)

    @Test("Prozent mit Minus oder „auf alles“ ist ein Rabatt, „Noch 10 % offen“ nicht")
    func percents() {
        #expect(TextParser.percent(in: "-15% auf alles") == 15)
        #expect(TextParser.percent(in: "Jetzt – 12,5 % sichern") == 12.5)
        #expect(TextParser.percent(in: "20 % auf den Einkauf") == 20)
        #expect(TextParser.percent(in: "10 % auf das gesamte Sortiment") == 10)
        #expect(TextParser.percent(in: "5 % Ermäßigung für Studierende") == 5)
        #expect(TextParser.percent(in: "Noch 10 % offen") == nil)
        #expect(TextParser.percent(in: "inkl. 19 % MwSt") == nil)
        #expect(TextParser.parse("-15% auf alles", now: now).isDiscount)
    }

    @Test("Fester Rabatt in Euro ist kein Guthaben")
    func fixedDiscount() {
        let d = TextParser.parse("10 € Rabatt ab 50 € Einkaufswert", now: now)
        #expect(d.discountValue == 10)
        #expect(d.value == nil)
        #expect(d.minOrder == 50)
        #expect(d.isDiscount)
        #expect(TextParser.parse("Rabatt von 10 € auf Ihren Einkauf", now: now).discountValue == 10)
        #expect(TextParser.parse("Spare 5 € bei deiner Bestellung", now: now).discountValue == 5)
        #expect(TextParser.parse("-5 € auf alle Schuhe", now: now).discountValue == 5)
        let voucher = TextParser.parse("Gutschein über 25 €", now: now)
        #expect(voucher.discountValue == nil && voucher.value == 25)
    }

    @Test("Angebote: „2 für 1“, „3 zum Preis von 2“, Gratis-Produkt")
    func benefits() {
        #expect(TextParser.benefit(in: "2 für 1 Pizza") == "2 für 1")
        #expect(TextParser.benefit(in: "3 für 2 auf alle Bücher") == "3 für 2")
        #expect(TextParser.benefit(in: "3 zum Preis von 2") == "3 für 2")
        #expect(TextParser.benefit(in: "Buy one get one free") == "2 für 1")
        #expect(TextParser.benefit(in: "Gratis Kaffee") == "Gratis Kaffee")
        #expect(TextParser.benefit(in: "Ein kostenloser Cappuccino") == "Gratis Cappuccino")
        #expect(TextParser.benefit(in: "1 Kaffee gratis zu jedem Frühstück") == "Gratis Kaffee")
        #expect(TextParser.benefit(in: "GRATIS KAFFEE") == "Gratis Kaffee")
    }

    @Test("Keine Angebote: Personen, Versand, Preise")
    func benefitNegatives() {
        #expect(TextParser.benefit(in: "Gutschein für 2 Personen") == nil)
        #expect(TextParser.benefit(in: "Menü 2 für 2 Personen") == nil)
        #expect(TextParser.benefit(in: "Versandkostenfrei ab 29 €") == nil)
        #expect(TextParser.benefit(in: "Kostenloser Versand ab 29 €") == nil)
        #expect(TextParser.benefit(in: "Gratis Lieferung") == nil)
        #expect(TextParser.benefit(in: "Kostenlose Rücksendung") == nil)
        #expect(TextParser.benefit(in: "3 für 10 €") == nil)
        #expect(TextParser.benefit(in: "Noch 10 % offen") == nil)
        #expect(TextParser.parse("Gutschein für 2 Personen\nWert 50 €", now: now).isDiscount == false)
    }

    @Test("Rabattcodes: Beschriftung zusammengeschrieben, auch reine Wörter")
    func codes() {
        #expect(TextParser.parse("Rabattcode SUMMER20", now: now).number == "SUMMER20")
        #expect(TextParser.parse("Dein Rabattcode: KAFFEE", now: now).number == "KAFFEE")
        #expect(TextParser.parse("Promo-Code: SAVE10 gilt bis 31.12.2026", now: now).number == "SAVE10")
        #expect(TextParser.parse("Coupon-Code WELCOME", now: now).number == "WELCOME")
        #expect(TextParser.parse("Aktionscode gilt online", now: now).number == nil)
        // Ohne Beschriftung bleibt ein reines Wort kein Code.
        #expect(TextParser.parse("KAFFEE\nbis 31.12.2026", now: now).number == nil)
        // Lange Nummern hinter „Gutscheincode“ weiter mit Leerzeichen-Blöcken.
        #expect(TextParser.parse("Gutscheincode: 1234 5678 9012", now: now).number == "123456789012")
    }

    @Test("KI-Code aus Buchstaben nur mit Beschriftung in derselben Zeile")
    func labeledSmartCode() {
        let text = "Café Sonne\nRabattcode: KAFFEE\n-10 % auf alles"
        #expect(ScanDraft.merge(text: text, smart: CardDraft(number: "KAFFEE"), now: now).number == "KAFFEE")
        #expect(ScanDraft.merge(text: "Café Sonne\nKAFFEE\n-10 %", smart: CardDraft(number: "KAFFEE"), now: now).number == nil)
    }

    @Test("KI-Wert wird bei festem Rabatt nicht zum Guthaben")
    func smartValueIgnoredForDiscount() {
        let d = ScanDraft.merge(text: "10 € Rabatt ab 50 € Einkaufswert", smart: CardDraft(value: 10), now: now)
        #expect(d.value == nil)
        #expect(d.discountValue == 10)
    }
}

@Suite("Coupons: Gutschein-Prüfung und Art")
struct CouponDraftTests {
    let now = day(2026, 9, 29)

    @Test("Aktionsgutscheine ohne Gutschein-Wort gelten als Gutschein, Bons nicht")
    func looksLikeVoucher() {
        for text in ["Gratis Kaffee\nbis 31.12.2026", "2 für 1 Pizza", "10 € Rabatt ab 50 € Einkaufswert"] {
            let d = ScanDraft.merge(text: text, smart: nil, now: now)
            #expect(ScanDraft.looksLikeVoucher(d, text: text, hasBarcode: false), "\(text)")
        }
        let receipt = "REWE\nRabatt -0,20\nGESAMT 12,40"
        #expect(!ScanDraft.looksLikeVoucher(ScanDraft.merge(text: receipt, smart: nil, now: now), text: receipt, hasBarcode: false))
    }

    @Test("Vorgeschlagene Art: Rabattcode mit Code, sonst Aktionsgutschein, sonst keine")
    func suggestedKind() {
        #expect(TextParser.parse("Rabattcode SUMMER20\n-20 %", now: now).suggestedKind == .discountCode)
        #expect(TextParser.parse("Rabattcode SUMMER20\n-20 %", now: now).suggestedKind(hasBarcode: true) == .coupon)
        #expect(TextParser.parse("Gratis Kaffee", now: now).suggestedKind == .coupon)
        #expect(TextParser.parse("Gutschein über 25 €", now: now).suggestedKind == nil)
    }

    @Test("Überschrift zeigt das Angebot, wenn weder Prozent noch Betrag gesetzt sind")
    func headline() {
        var c = coupon()
        #expect(c.headline == VoucherKind.coupon.label)
        c.benefit = "2 für 1"
        #expect(c.headline == "2 für 1")
        c.value = 5
        #expect(c.headline == 5.0.euro)
    }
}

@Suite("Vorder- und Rückseite")
struct FrontBackTests {
    let now = day(2026, 9, 29)

    @Test("Vorn Laden und Wert, hinten Nummer und PIN; „aufladbar bis 500 €“ gewinnt nicht")
    func combine() {
        let front = ScanDraft.merge(text: "Thalia\nGeschenkkarte\n25 €", smart: nil, now: now)
        let back = ScanDraft.merge(text: "Kartennummer 6300 9812 7456 1234\nPIN 4821\naufladbar bis 500 €\ngültig bis 31.12.2029", smart: nil, now: now)
        let d = ScanDraft.combine(front: front, back: back)
        #expect(d.merchantID == "thalia")
        #expect(d.value == 25)
        #expect(d.number == "6300981274561234")
        #expect(d.pin == "4821")
        #expect(d.expires != nil && !d.expiresIsEstimate)
    }

    @Test("Gedrucktes Datum schlägt geschätztes, vorn zuerst")
    func expiryPreference() {
        var front = CardDraft(expires: day(2029, 12, 31)); front.expiresIsEstimate = true
        let back = CardDraft(expires: day(2028, 6, 30))
        #expect(ScanDraft.combine(front: front, back: back).expires == day(2028, 6, 30))
        #expect(ScanDraft.combine(front: back, back: CardDraft(expires: day(2030, 1, 1))).expires == day(2028, 6, 30))
        var estimatedBack = CardDraft(expires: day(2030, 1, 1)); estimatedBack.expiresIsEstimate = true
        let combined = ScanDraft.combine(front: CardDraft(), back: estimatedBack)
        #expect(combined.expires == day(2030, 1, 1) && combined.expiresIsEstimate)
    }

    @Test("Lücken füllt die andere Seite")
    func fillsGaps() {
        var back = CardDraft(merchantID: "ikea", number: "123456789", value: 50, percent: nil)
        back.minOrder = 20
        back.recipient = "Oma Gisela"
        let d = ScanDraft.combine(front: CardDraft(), back: back)
        #expect(d.merchantID == "ikea" && d.value == 50 && d.minOrder == 20 && d.recipient == "Oma Gisela")
        let kept = ScanDraft.combine(front: CardDraft(number: "999999", value: 10), back: CardDraft(value: 500))
        #expect(kept.value == 10 && kept.number == "999999")
    }
}

@Suite("Rückseitenfoto und Angebot speichern")
struct BackPhotoStorageTests {
    @Test("Alte Stände ohne neue Felder bleiben lesbar")
    func decodesOldJSON() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","kind":"coupon","merchantID":"other","number":"X","format":"text","value":0,"balance":0}"#
        let c = try JSONDecoder().decode(GiftCard.self, from: Data(json.utf8))
        #expect(c.benefit == "")
        #expect(c.photoBack == nil)
    }

    @Test("Angebot und Rückseite überstehen den Roundtrip")
    func roundTrip() throws {
        var c = coupon()
        c.benefit = "Gratis Kaffee"
        c.photoBack = Data([4, 5, 6])
        let back = try APICoding.decoder.decode(GiftCard.self, from: APICoding.encoder.encode(c))
        #expect(back.benefit == "Gratis Kaffee")
        #expect(back.photoBack == Data([4, 5, 6]))
    }

    @Test("Sync und Cloud ohne Rückseitenfoto, lokales bleibt beim Zusammenführen")
    func syncStripsBackPhoto() throws {
        var c = coupon()
        c.photoBack = Data([1, 2, 3])
        #expect(SyncData.outgoing(cards: [c], tests: [], deleted: []).cards[0].photoBack == nil)
        let key = CloudPayload.newKey()
        #expect(try CloudPayload.openCard(CloudPayload.seal(c, key: key), key: key).photoBack == nil)
        var remote = c
        remote.photoBack = nil
        remote.benefit = "2 für 1"
        remote.modifiedAt = c.modifiedAt.addingTimeInterval(60)
        let r = SyncMerge.merge(localCards: [c], localTests: [], localDeleted: [], remote: SyncData(cards: [remote], tests: [], deleted: []))
        #expect(r.cards[0].photoBack == Data([1, 2, 3]))
        #expect(r.cards[0].benefit == "2 für 1")
    }

    @Test("Mindestbestellwert NaN wird bereinigt")
    func sanitizesMinOrder() {
        var c = coupon()
        c.minOrder = .nan
        #expect(!c.isFiniteEverywhere)
        #expect(c.sanitized.minOrder == nil)
    }
}

@Suite("Coupons – Befunde Beta-Runde 16")
struct CouponRound16Tests {
    @Test("Wertgutschein mit Werbezeile bleibt Wertgutschein (kein 5-€-Coupon)")
    func valueVoucherWithPromoLine() {
        let d = TextParser.parse("GESCHENKGUTSCHEIN\nBuchhandlung Seitenweise\nWert: 50,00 €\nJetzt Newsletter abonnieren und 5 € sparen")
        #expect(d.value == 50)
        #expect(!d.isDiscount)
        #expect(d.suggestedKind == nil)
    }

    @Test("Kein Coupon: kostenloses WLAN, gratis Parkplatz, Reservierung „4 für 2 Stunden“")
    func noBenefitForAmenities() {
        #expect(TextParser.benefit(in: "Kostenloses WLAN für Gäste") == nil)
        #expect(TextParser.benefit(in: "Gratis Parkplatz im Hof") == nil)
        #expect(TextParser.benefit(in: "Tisch für 4 für 2 Stunden reserviert") == nil)
        #expect(TextParser.benefit(in: "Gratis Kaffee zu jedem Kuchen") == "Gratis Kaffee")
        #expect(TextParser.benefit(in: "3 für 2 auf alle Bücher") == "3 für 2")
    }

    @Test("Angebote mit Tickets, Karten, Nächten bleiben erkannt; Reservierung nicht")
    func dealsKeepUnits() {
        #expect(TextParser.benefit(in: "2 für 1 Tickets") == "2 für 1")
        #expect(TextParser.benefit(in: "3 für 2 Karten im Kino") == "3 für 2")
        #expect(TextParser.benefit(in: "4 für 3 Nächte im Hotel") == "4 für 3")
        #expect(TextParser.benefit(in: "Tisch reserviert: 4 für 2") == nil)
    }

    @Test("Wertgutschein mit Prozent-Zusatz bleibt Wertgutschein")
    func valueVoucherWithPercent() {
        let d = TextParser.parse("GESCHENKGUTSCHEIN\nCafé Krone\nGutschein 50 € + 10 % Rabatt auf Torten")
        #expect(d.value == 50)
        #expect(!d.isDiscount)
    }

    @Test("Reservierungs-Filter nur mit Wortgrenze; Angebot mit Artikelwert bleibt Coupon")
    func round18() {
        #expect(TextParser.benefit(in: "Praktisch: 3 für 2 auf alle Hefte") == "3 für 2")
        #expect(TextParser.benefit(in: "2 für 1 – Reservierung empfohlen") == "2 für 1")
        #expect(TextParser.benefit(in: "Tisch reserviert: 4 für 2") == nil)
        let d = TextParser.parse("COUPON\nCafé Krone\nGratis Kaffee im Wert von 3,50 €")
        #expect(d.benefit == "Gratis Kaffee")
        #expect(d.isDiscount)
    }

    @Test("Aktionscode mit EUR bleibt Code, Betragszeile nicht")
    func eurCodes() {
        #expect(ScanDraft.isPlausibleCode("SOMMER50EUR"))
        #expect(ScanDraft.isPlausibleCode("XMAS10EUR-2026"))
        #expect(!ScanDraft.isPlausibleCode("30 EUR"))
        #expect(!ScanDraft.isPlausibleCode("über30,-Euro"))
        #expect(!ScanDraft.isPlausibleCode("25 €"))
    }

    @Test("Wertgutschein mit Beigabe bleibt Wertgutschein; Reservierungen ohne Angebot")
    func round19() {
        let a = TextParser.parse("WERTGUTSCHEIN\nCafé Krone\n50,00 €\nGratis Kaffee dazu")
        #expect(a.value == 50 && !a.isDiscount)
        let b = TextParser.parse("Geschenkgutschein 25 €\nBuchhandlung Seitenweise\n+ 2 für 1 auf Lesezeichen")
        #expect(b.value == 25 && !b.isDiscount)
        #expect(TextParser.benefit(in: "Tischreservierung: 4 für 2") == nil)
        #expect(TextParser.benefit(in: "Reservierung: 4 für 2") == nil)
        #expect(TextParser.benefit(in: "2 für 1 – Reservierung empfohlen") == "2 für 1")
    }

    @Test("Rückseite hervorheben: Geschenkkarte ja, Speisekarte/handschriftlich/Eintrittskarte mit Code nein")
    func suggestsBack() {
        #expect(ScanDraft.suggestsBack(text: "Buchhandlung Seitenweise\nGeschenkkarte\n25,00 €", hasCode: false, hasPin: false))
        #expect(ScanDraft.suggestsBack(text: "Gift Card 50 €", hasCode: false, hasPin: false))
        #expect(!ScanDraft.suggestsBack(text: "Café Krone\nSpeisekarte\nGutschein 20 €", hasCode: false, hasPin: false))
        #expect(!ScanDraft.suggestsBack(text: "Gutschein für Oma\n30 Euro\nvon Mia", hasCode: false, hasPin: false))
        #expect(!ScanDraft.suggestsBack(text: "Eintrittskarte\nCode 1234-5678", hasCode: true, hasPin: false))
        #expect(ScanDraft.suggestsBack(text: "Code 1234-5678\nPIN auf der Rückseite freirubbeln", hasCode: true, hasPin: false))
        #expect(!ScanDraft.suggestsBack(text: "Code 1234-5678\nPIN 4821", hasCode: true, hasPin: true))
    }
}
