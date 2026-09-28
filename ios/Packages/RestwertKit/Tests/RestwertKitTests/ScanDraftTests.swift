import Foundation
import Testing
@testable import RestwertKit

private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
}

private func ymd(_ date: Date?) -> [Int] {
    guard let date else { return [] }
    let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
    return [c.year!, c.month!, c.day!]
}

/// Texte der Testgutscheine aus docs/evaluation/testgutscheine (Runde Scan + Login, 27.09.2026).
@Suite("Scan: KI-Ergebnis prüfen und zusammenführen")
struct ScanDraftTests {
    let now = day(2026, 9, 27)

    @Test("Einkaufsliste: erfundener Laden und Code der KI werden verworfen, kein Gutschein")
    func shoppingList() {
        let text = "Einkaufsliste\nMilch, Brot, Äpfel"
        let smart = CardDraft(number: "Milch", customName: "Milch")
        let d = ScanDraft.merge(text: text, smart: smart, now: now)
        #expect(d.number == nil)
        #expect(d.customName == nil || d.customName == "Milch")
        #expect(!ScanDraft.looksLikeVoucher(d, text: text, hasBarcode: false))
    }

    @Test("Ganze Wörter statt Teilstrings: dm nicht in „und mehr“, Otto nicht in „Lotto“")
    func wordBoundaries() {
        let text = "Lottoschein und mehr\nZiehung am Samstag"
        let d = ScanDraft.merge(text: text, smart: CardDraft(merchantID: "otto"), now: now)
        #expect(d.merchantID == nil)
        #expect(!ScanDraft.onOneLine("dm", in: ["und mehr"]))
        #expect(ScanDraft.onOneLine("IK-9934-2281-4410", in: ["Code: IK 9934 2281 4410"]))
        #expect(!ScanDraft.onOneLine("12345678", in: ["1234", "5678"]))
    }

    @Test("PIN nur aus einer Zeile mit „PIN“, nicht aus der Kartennummer")
    func pinNeedsLabel() {
        let text = "Kartennr. 6280 1234 5678 9012\nGuthaben 25 €"
        let d = ScanDraft.merge(text: text, smart: CardDraft(pin: "5678"), now: now)
        #expect(d.pin == nil)
        let ok = ScanDraft.merge(text: "PIN: 4821", smart: CardDraft(pin: "4821"), now: now)
        #expect(ok.pin == "4821")
    }

    @Test("Betrag der KI braucht Währung oder Beschriftung, nicht Datum oder Filiale")
    func amountNeedsCurrency() {
        let text = "Gutschein\nFiliale 12\ngültig bis 12.12.2027"
        #expect(ScanDraft.merge(text: text, smart: CardDraft(value: 12), now: now).value == nil)
        #expect(ScanDraft.merge(text: "Gutschein über 30,– Euro", smart: CardDraft(value: 30), now: now).value == 30)
    }

    @Test("Keine Gutschein-Wörter in Speisekarte, Wertstoffhof, Kassenbon, Visitenkarte",
          arguments: ["Speisekarte\nSchnitzel 12,50", "Wertstoffhof\nÖffnungszeiten", "Visitenkarte\nMax Muster"])
    func notVoucherWords(_ text: String) {
        #expect(!ScanDraft.looksLikeVoucher(CardDraft(), text: text, hasBarcode: false))
    }

    @Test("8- und 12-stellige Nummern lösen keinen Prüfziffer-Alarm aus")
    func noFalseAlarm() {
        #expect(ScanDraft.retailCheck("12345678") == nil)
        #expect(ScanDraft.retailCheck("123456789012") == nil)
    }

    @Test("Jahresende in vielen Schreibweisen", arguments: [
        "3 Jahre gültig ab Ende des Kalenderjahres", "3 Jahre gültig, gerechnet ab Schluss des Jahres",
        "Gültigkeit: 3 Jahre zum Jahresende", "3 Jahre gültig ab Ende des Ausstellungsjahres"])
    func yearEndVariants(_ text: String) {
        #expect(TextParser.validity(in: text)?.fromYearEnd == true)
        #expect(ymd(TextParser.parse(text, now: now).expires) == [2029, 12, 31])
    }

    @Test("Jahresende nur neben der Laufzeit, nicht aus einer anderen Zeile")
    func yearEndOnlyNearby() {
        let text = "Herbstaktion bis Jahresende\nMehr Infos im Laden\nGutschein 20 €\nGültigkeit: 3 Jahre"
        #expect(TextParser.validity(in: text)?.fromYearEnd == false)
    }

    @Test("Laufzeit ist kein Betrag: „Guthaben ist 10 Jahre gültig“")
    func durationIsNoAmount() {
        let d = TextParser.parse("Geschenkkarte 25 €\nGuthaben ist 10 Jahre gültig", now: now)
        #expect(d.value == 25)
    }

    @Test("Belege, Ausweise, Tickets sind keine Gutscheine, auch mit Betrag, Nummer oder Barcode", arguments: [
        "REWE Markt\nKassenbon\nSumme 23,45 €\nBeleg Nr 1234567890",
        "Max Muster\nVisitenkarte\nTel 0561 123456",
        "Deutsche Bahn Fahrkarte\nKassel – Berlin 49,90 €\nAuftragsnummer 123456789",
        "Personalausweis\nIDD L01X00T47 1234567",
        "PERSONALAUSWEIS\nL01X00T47\ngültig bis 12.03.2031",
        "Deutsche Bahn Fahrkarte\nKassel – Berlin 49,90 €\ngültig am 28.09.2026",
        "Parkschein 3,50 €\ngültig bis 14:30",
        "REWE\nMilch 1,19\nRabatt -0,20\nGESAMT 12,40 EUR",
        "Parkschein 3,50 €\nNr 00123456",
        "Speisekarte\nSchnitzel 12,50 €"])
    func otherDocuments(_ text: String) {
        let d = ScanDraft.merge(text: text, smart: nil, now: now)
        #expect(!ScanDraft.looksLikeVoucher(d, text: text, hasBarcode: true))
    }

    @Test("Karte nur mit Nummer und PIN, ohne Gutschein-Wort, zählt als Gutschein")
    func bareCard() {
        let text = "6280 1234 5678 9012\nPIN-Code: 4821"
        let d = ScanDraft.merge(text: text, smart: nil, now: now)
        #expect(d.pin == "4821")
        #expect(ScanDraft.looksLikeVoucher(d, text: text, hasBarcode: false))
    }

    @Test("Zusammengesetzte Gutschein-Wörter schlagen Beleg-Wörter", arguments: [
        "Einkaufsgutschein\nWert 20 €\ninkl. 19 % MwSt",
        "Warengutschein\nSumme 15,00 €",
        "Weihnachtsgeschenkkarte\nTicket-Nr 4711\n25 €"])
    func compounds(_ text: String) {
        #expect(ScanDraft.looksLikeVoucher(ScanDraft.merge(text: text, smart: nil, now: now), text: text, hasBarcode: false))
    }

    @Test("Kontoauszug mit Gutschrift und Prepaid-Aufladung sind keine Gutscheine", arguments: [
        "Kontoauszug\nGutschrift 120,00 €\nIBAN DE12 3456",
        "Prepaid Aufladung\nGuthaben 15,00 €\nNr 0170 1234567"])
    func bank(_ text: String) {
        #expect(!ScanDraft.looksLikeVoucher(ScanDraft.merge(text: text, smart: nil, now: now), text: text, hasBarcode: true))
    }

    @Test("Steuerangaben in vielen Schreibweisen sind kein Rabatt", arguments: [
        "Rabattcode SPAR10\nEnthaltene MwSt: 19 %", "Rabatt nur heute\nUSt (19%)", "Rabatt\n7 % ermäßigte MwSt"])
    func taxVariants(_ text: String) {
        #expect(TextParser.parse(text, now: now).percent == nil)
    }

    @Test("„August“ ist keine Umsatzsteuer")
    func august() {
        #expect(TextParser.parse("15 % Rabatt im August", now: now).percent == 15)
    }

    @Test("Mindesteinkauf und Einkaufswert sind kein Guthaben", arguments: [
        "Gutschein 10 €\nMindesteinkaufswert von 50 €", "Gutschein 10 €\nbei einem Einkauf über 100 €"])
    func minimums(_ text: String) {
        #expect(TextParser.parse(text, now: now).value == 10)
    }

    @Test("PIN klebt nicht an der Kartennummer")
    func pinNotGlued() {
        let d = TextParser.parse("Kartennummer 6280 1234 5678 9012 4821", now: now)
        #expect(d.number == "6280123456789012")
        #expect(TextParser.parse("Kartennummer 6280 1234 5678 9012 PIN 4821", now: now).number == "6280123456789012")
    }

    @Test("Warengutschrift auf einem Bon ist ein Gutschein")
    func storeCredit() {
        let text = "REWE Markt\nWarengutschrift\nBetrag 12,40 €\nNr 7788 1234 5566"
        #expect(ScanDraft.looksLikeVoucher(ScanDraft.merge(text: text, smart: nil, now: now), text: text, hasBarcode: false))
    }

    @Test("Beschriftung ohne Währung verliert gegen echten Betrag: „Wert für 2 Personen“")
    func labelWithoutCurrency() {
        #expect(TextParser.parse("Gutschein\nWert für 2 Personen\n50 €", now: now).value == 50)
        #expect(TextParser.parse("Gutschein\nWert: 30", now: now).value == 30)
    }

    @Test("„inkl. MwSt. 19 %“ ist kein Rabatt")
    func vatBefore() {
        #expect(TextParser.parse("Gutschein 50 €\ninkl. MwSt. 19 %\nRabatt nicht kombinierbar", now: now).percent == nil)
    }

    @Test("19 % MwSt ist kein Rabatt, auch nicht von der KI")
    func vatNoPercent() {
        let d = ScanDraft.merge(text: "Gutschein 50 €\ninkl. 19 % MwSt", smart: CardDraft(percent: 19), now: now)
        #expect(d.percent == nil)
    }

    @Test("KI-Datum braucht Tag, Monat und Jahr (oder Monatsende)")
    func smartDateStrict() {
        let aiDate = Calendar.current.date(from: DateComponents(year: 2028, month: 3, day: 15, hour: 12))!
        #expect(ScanDraft.merge(text: "Gutschein 20 €\nMärz 2028 Aktion", smart: CardDraft(expires: aiDate), now: now).expires == nil)
        #expect(ScanDraft.merge(text: "Gutschein 20 €\nverwendbar 15. März 2028", smart: CardDraft(expires: aiDate), now: now).expires != nil)
    }

    @Test("„3 Jahre ab Ende des Jahres gültig“ und Ausstellungsjahr")
    func yearEndPhrasing() {
        #expect(ymd(TextParser.parse("3 Jahre ab Ende des Jahres gültig", now: now).expires) == [2029, 12, 31])
        #expect(ymd(TextParser.parse("3 Jahre gültig ab Ende des Jahres 2025", now: now).expires) == [2028, 12, 31])
    }

    @Test("Anlässe sind keine Beschenkten", arguments: ["für Weihnachten", "Für Online-Einkäufe", "für Geburtstag"])
    func occasions(_ line: String) {
        #expect(TextParser.recipient(in: "Gutschein\n\(line)") == nil)
    }

    @Test("Zifferngruppen ohne einzelne Restziffer")
    func grouping() {
        #expect("4006381333931".grouped == "4006 3813 33931")
        #expect("6280123456789012".grouped == "6280 1234 5678 9012")
        #expect("12345".grouped == "12345")
        #expect("123456".grouped == "1234 56")
        #expect("AQ7K-2ZPM".grouped == "AQ7K-2ZPM")
    }

    @Test("Mindestbestellwert wird erkannt", arguments: [
        ("15 % Rabatt auf alles - ab 50 € Mindestbestellwert", 50.0), ("Mindestbestellwert: 30,00 EUR", 30),
        ("MBW 25 €", 25), ("gültig bei einem Einkauf über 100 €", 100), ("Mindesteinkaufswert von 40 €", 40),
        ("10 % Rabatt ab 1.000 € Einkaufswert", 1000)])
    func minOrder(_ text: String, _ expected: Double) {
        #expect(TextParser.parse(text, now: now).minOrder == expected)
    }

    @Test("Kein Mindestbestellwert ohne Hinweis", arguments: ["Gutschein 50 €", "gültig ab 12.10.2026", "ab sofort einlösbar"])
    func noMinOrder(_ text: String) {
        #expect(TextParser.parse(text, now: now).minOrder == nil)
    }

    @Test("Codes für eigene Gutscheine: Präfix, eindeutig, ohne verwechselbare Zeichen")
    func issuedCodes() {
        let a = IssuedVoucher.makeCode(for: "Café am Markt")
        #expect(a.hasPrefix("CAFE-"))
        #expect(a.count == 14)
        #expect(!a.dropFirst(5).contains { "01OIL".contains($0) })
        var seen: Set<String> = []
        for _ in 0..<500 { seen.insert(IssuedVoucher.makeCode(for: "X", existing: seen)) }
        #expect(seen.count == 500)
    }

    @Test("Laufzeit lässt sich ab anderem Erhalt-Datum neu rechnen")
    func validityFromReceived() {
        let v = TextParser.parse("3 Jahre gültig ab Ende des Jahres", now: now).validity
        #expect(ymd(v?.expiry(from: day(2025, 3, 1))) == [2028, 12, 31])
        let plain = TextParser.parse("Gültigkeit: 24 Monate", now: now).validity
        #expect(ymd(plain?.expiry(from: day(2026, 1, 15))) == [2028, 1, 15])
    }

    @Test("Pronomen und Mengen sind keine Beschenkten", arguments: ["für Ihn", "Für Mich", "für Deine Liebsten", "für Kinder", "für Zwei Personen"])
    func pronouns(_ line: String) {
        #expect(TextParser.recipient(in: "Gutschein\n\(line)") == nil)
    }

    @Test("KI-Angaben, die nicht im Text stehen, werden nicht übernommen")
    func ungroundedSmart() {
        let text = "GUTSCHEIN\nCafé Sonnenschein\nüber 30,– Euro"
        let smart = CardDraft(number: "AB12CD34", pin: "9999", value: 45, customName: "Bäckerei Schmidt")
        let d = ScanDraft.merge(text: text, smart: smart, now: now)
        #expect(d.number == nil)
        #expect(d.pin == nil)
        #expect(d.value != 45)
        #expect(d.customName == nil)
    }

    @Test("Handschrift: Name in Originalschreibweise, Betrag und Beschenkte übernommen")
    func handwriting() {
        let text = "GUTSCHEIN\nCafé Sonnenschein\nüber 30,– Euro\nfür Oma Gisela\ngültig bis Ende 2027"
        let smart = CardDraft(value: 30, customName: "café sonnenschein")
        let d = ScanDraft.merge(text: text, smart: smart, now: now)
        #expect(d.customName == "Café Sonnenschein")
        #expect(d.value == 30)
        #expect(d.recipient == "Oma Gisela")
        #expect(ymd(d.expires) == [2027, 12, 31])
        #expect(ScanDraft.looksLikeVoucher(d, text: text, hasBarcode: false))
    }

    @Test("Originalschreibweise auch über Zeilenumbruch, sonst wenigstens groß")
    func casing() {
        #expect(ScanDraft.original("café sonnenschein", in: "GUTSCHEIN\nCafé\nSonnenschein") == "Café Sonnenschein")
        #expect(ScanDraft.original("café sonnenschein", in: "Caté Sonnenschein") == "Café Sonnenschein")
    }

    @Test("Echter Handschrift-OCR-Text (Vision, Testgutschein v04)")
    func realHandwritingOCR() {
        let text = "GUTSCHEIN\ncafé sonnenschein\nüber 30, - Euro\nfür oma Gisela\ngültig bis Ende 2027"
        let d = ScanDraft.merge(text: text, smart: CardDraft(value: 30, customName: "café sonnenschein"), now: now)
        #expect(d.value == 30)
        #expect(d.customName == "Café Sonnenschein")
        #expect(d.recipient == "Oma Gisela")
        #expect(ymd(d.expires) == [2027, 12, 31])
    }

    @Test("Anreden sind keine Beschenkten", arguments: ["für dich", "Für Sie!", "für alle Einkäufe"])
    func notRecipient(_ line: String) {
        #expect(TextParser.recipient(in: "Gutschein\n\(line)\n20 €") == nil)
    }

    @Test("„3 Jahre gültig, ab Ende des Jahres“ endet am 31.12.")
    func yearEndAnchor() {
        let d = TextParser.parse("Der Gutschein ist 3 Jahre gültig, gerechnet ab Ende des Jahres der Ausstellung.", now: now)
        #expect(ymd(d.expires) == [2029, 12, 31])
        #expect(d.expiresIsEstimate)
    }

    @Test("Laufzeit ohne Jahresende rechnet ab heute und gilt als geschätzt")
    func relativeFromToday() {
        let d = TextParser.parse("IKEA Gutschein 100,00 EUR\n3 Jahre gültig ab Ausstellung", now: now)
        #expect(ymd(d.expires) == [2029, 9, 27])
        #expect(d.expiresIsEstimate)
        let exact = TextParser.parse("gültig bis 31.12.2029", now: now)
        #expect(!exact.expiresIsEstimate)
    }

    @Test("Prüfziffer auch für Nummern aus dem Text")
    func retailChecksum() {
        #expect(ScanDraft.retailCheck("4006 3813 3393 1")?.format == .ean13)
        #expect(ScanDraft.retailCheck("4006381333931")?.valid == true)
        #expect(ScanDraft.retailCheck("4006381333934")?.valid == false)
        #expect(ScanDraft.retailCheck("6280123456789012") == nil)
        #expect(ScanDraft.retailCheck("12345678") == nil)
        #expect(ScanDraft.retailCheck("ZAL15SOMMER26") == nil)
    }

    @Test("Code der KI braucht Ziffern und muss im Text stehen")
    func plausibleCode() {
        #expect(!ScanDraft.isPlausibleCode("Milch"))
        #expect(!ScanDraft.isPlausibleCode("12"))
        #expect(ScanDraft.isPlausibleCode("7GHK 2M9P XQ41"))
        let text = "Gutscheincode: 7GHK 2M9P XQ41"
        let d = ScanDraft.merge(text: text, smart: CardDraft(number: "7GHK2M9PXQ41"), now: now)
        #expect(d.number?.replacingOccurrences(of: " ", with: "") == "7GHK2M9PXQ41")
    }

    @Test("Betrag mit Tausenderpunkt wird im Text gefunden")
    func thousands() {
        let d = ScanDraft.merge(text: "amazon.de Gutschein\nBetrag: 1.250,00 €", smart: CardDraft(value: 1250), now: now)
        #expect(d.value == 1250)
    }

    @Test("Automatisches Format: Online-Händler und Rabattcodes als Text, sonst Händlerformat")
    func automaticFormat() {
        #expect(CodeFormat.automatic(kind: .giftCard, merchantID: "zalando") == .text)
        #expect(CodeFormat.automatic(kind: .discountCode, merchantID: "douglas") == .text)
        #expect(CodeFormat.automatic(kind: .giftCard, merchantID: nil) == .code128)
    }
}
