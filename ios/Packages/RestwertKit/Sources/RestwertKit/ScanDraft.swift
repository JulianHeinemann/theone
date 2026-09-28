import Foundation

// MARK: - Scan-Ergebnis zusammenführen und prüfen

/// Führt Regel-Parser und Apple-Intelligence-Ergebnis zusammen und prüft, ob überhaupt ein Gutschein vorliegt.
///
/// Die KI darf nur Lücken füllen, und nur mit Angaben, die wirklich im gelesenen Text stehen.
/// Sonst erfindet sie z. B. aus einer Einkaufsliste den „Laden Milch“ mit dem Code „Milch“.
public enum ScanDraft {
    public static func merge(text: String, smart: CardDraft?, now: Date = .now) -> CardDraft {
        var d = TextParser.parse(text, now: now)
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        guard let smart else {
            // Ohne KI: markante Überschrift als Vorschlag für den Ladennamen (nur bei Gutscheinen, siehe merge-Aufrufer).
            if d.merchantID == nil, d.customName == nil { d.customName = headlineName(in: lines) }
            return d
        }

        if d.merchantID == nil, let id = smart.merchantID, onOneLine(Merchant.byID[id]?.name ?? id, in: lines) {
            d.merchantID = id
        }
        if d.merchantID == nil, let name = smart.customName, name.filter(\.isLetter).count >= 3, onOneLine(name, in: lines) {
            // Schreibweise aus dem Original übernehmen (die KI liefert manchmal alles klein).
            let found = original(name, in: text) ?? name
            // Auch das Original ist oft klein (Handschrift): dann Wörter groß beginnen.
            d.customName = found == found.lowercased() ? found.capitalized(with: Locale(identifier: "de_DE")) : found
        }
        if d.value == nil, let v = smart.value, amountAppears(v, in: text) { d.value = v }
        if d.percent == nil, let p = smart.percent, percentAppears(p, in: text) { d.percent = p }
        // PIN nur, wenn sie in einer Zeile mit „PIN“ steht (sonst wäre jeder Ziffernblock der Kartennummer eine „PIN“).
        if d.pin == nil, let pin = smart.pin, pin.contains(where: \.isNumber),
           lines.contains(where: { $0.range(of: #"(?i)\bPIN\b"#, options: .regularExpression) != nil && onOneLine(pin, in: [$0]) }) {
            d.pin = pin
        }
        if d.expires == nil, let e = smart.expires, dateAppears(e, in: lines) { d.expires = e }
        if d.merchantID == nil, d.customName == nil { d.customName = headlineName(in: lines) }
        if let n = smart.number, isPlausibleCode(n), onOneLine(n, in: lines), n != d.pin,
           d.number == nil || (d.number?.count ?? 0) < n.count {
            d.number = n
        }
        return d
    }

    /// Wörter, die auf einen Gutschein hindeuten, nur als ganze Wörter (nicht „Speisekarte“, „Wertstoffhof“).
    /// Eindeutige Gutschein-Wörter: schlagen auch Beleg-Wörter („Warengutschrift“ auf einem Bon ist ein Gutschein).
    /// Auch zusammengesetzt: Einkaufsgutschein, Warengutschein, Weihnachtsgeschenkkarte.
    private static let voucherWords = #"(?i)\b(\w*gutschein\w*|\w*geschenkkarte\w*|gift\s?cards?|\w*voucher|guthabenkarte|gutscheincode|\w*gutschrift)\b"#
    /// Bank- und Prepaid-Belege: „Gutschrift“ auf dem Kontoauszug, „Guthaben“ nach dem Aufladen – nie ein Gutschein.
    private static let bankDocuments = #"(?i)\b(kontoauszug|buchungstag|valuta|saldo|iban|bic|überweisung|lastschrift|aufladung|aufgeladen|prepaid|mobilfunk|restguthaben\s+handy)\b"#
    /// Schwache Wörter: stehen auch auf Ausweisen, Fahrkarten und Bons („gültig bis“, „Rabatt“).
    private static let weakVoucherWords = #"(?i)\b(einlösbar|einloesbar|gültig\w*|gueltig\w*|valid|rabatt\w*|guthaben|coupons?)\b"#

    /// Belege und Dokumente, die Betrag, Nummer oder Barcode haben, aber kein Gutschein sind.
    private static let otherDocuments = #"(?i)\b(kassenbon|kassenbeleg|quittung|rechnung|beleg\s?nr|summe|zwischensumme|bar\s?gegeben|rückgeld|gesamt|gesamtbetrag|bonnummer|bon-nr|beleg-nr|belegnummer|tse|kartenzahlung|ec-cash|mwst|ust\.?|fahrkarte|fahrschein|ticket|boarding\s?pass|bordkarte|personalausweis|reisepass|ausweis\w*|führerschein|parkschein|parkticket|speisekarte|getränkekarte|visitenkarte|mitgliedsausweis|krankenversicherung|versichertenkarte|iban|bic)\b"#

    /// Reicht das Gelesene für einen Gutschein?
    /// Gutschein-Wörter zählen immer. Belege, Ausweise, Tickets und Karten ohne Gutschein-Wort nicht,
    /// auch wenn sie Betrag, Nummer oder Barcode haben. Sonst genügt ein Barcode, ein Rabatt, eine PIN oder Betrag und Code zusammen.
    public static func looksLikeVoucher(_ d: CardDraft, text: String, hasBarcode: Bool) -> Bool {
        if text.range(of: bankDocuments, options: .regularExpression) != nil { return false }
        if text.range(of: voucherWords, options: .regularExpression) != nil || hasGarbledVoucherWord(text) { return true }
        // Kassenbon von REWE, Fahrkarte der Bahn, Ausweis „gültig bis“: kein Gutschein, auch mit bekanntem Laden.
        if text.range(of: otherDocuments, options: .regularExpression) != nil { return false }
        if d.merchantID != nil || text.range(of: weakVoucherWords, options: .regularExpression) != nil { return true }
        // Gestalteter Gutschein ohne lesbares Gutschein-Wort (Schreibschrift, Foto): genau ein Betrag mit Währung,
        // keine Beleg-Wörter (oben schon ausgeschlossen). Listen und Bons haben mehrere Beträge.
        if d.value != nil, currencyAmounts(in: text) == 1 { return true }
        return hasBarcode || d.percent != nil || d.pin != nil || (d.value != nil && d.number != nil)
    }

    /// Verlesenes Gutschein-Wort aus Schreibschrift oder unscharfem Foto („Gesdienkgutsdiein“, „Gutscbein“).
    static func hasGarbledVoucherWord(_ text: String) -> Bool {
        let targets = ["gutschein", "geschenkgutschein", "geschenkkarte", "geschenkgutscheine"]
        for raw in text.split(whereSeparator: { !$0.isLetter }) {
            let word = compact(String(raw))
            guard word.count >= 7 else { continue }
            if word.contains("gutsch") || word.contains("utschein") { return true }
            for t in targets where abs(t.count - word.count) <= 3 && distance(word, t) <= (t.count >= 13 ? 3 : 2) { return true }
        }
        return false
    }

    /// Wie viele Beträge mit Währung im Text stehen („25 €“, „EUR 40“, „30,- Euro“).
    static func currencyAmounts(in text: String) -> Int {
        let p = #"(?i)(?:€|EUR)\s?\d|\d(?:[\d.,]*\d)?(?:\s?,\s?[-–])?\s?(?:€|EUR\b|Euro\b)"#
        guard let re = try? NSRegularExpression(pattern: p) else { return 0 }
        return re.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    /// Markante Überschrift als Ladenname, wenn kein Laden erkannt wurde: längste der ersten Zeilen mit einem bis drei Wörtern,
    /// ohne Ziffern und ohne Gutschein-/Füllwörter („KRUSTENZAUBER“ → „Krustenzauber“).
    static func headlineName(in lines: [String]) -> String? {
        let filler = #"(?i)\b(gutschein\w*|geschenk\w*|gift|voucher|für|fuer|for|über|ueber|wert|gültig\w*|einlösbar|guthaben|von|an|zum|zur|dein\w*|ihr\w*|liebe\w*|herzlich\w*|alles\s+gute)\b"#
        var best: String?
        for line in lines.prefix(5) {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let words = t.split(separator: " ")
            guard (1...3).contains(words.count), t.filter(\.isLetter).count >= 4, t.count <= 30,
                  !t.contains(where: \.isNumber), t.range(of: filler, options: .regularExpression) == nil,
                  !hasGarbledVoucherWord(t) else { continue }
            // Die längste Überschrift gewinnt (Anhänger „KRUSTEN“/„ZAUBER“ vor „KRUSTENZAUBER“).
            if t.filter(\.isLetter).count > (best?.filter(\.isLetter).count ?? 0) { best = t }
        }
        guard let t = best else { return nil }
        return t == t.uppercased() || t == t.lowercased() ? t.capitalized(with: Locale(identifier: "de_DE")) : t
    }

    /// Editierdistanz (Levenshtein) für kurze Wörter.
    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var row = Array(0...b.count)
        for i in 1...max(a.count, 1) where !a.isEmpty {
            var prev = row[0]; row[0] = i
            for j in 1...max(b.count, 1) where !b.isEmpty {
                let cur = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, prev + (a[i - 1] == b[j - 1] ? 0 : 1))
                prev = cur
            }
        }
        return a.isEmpty ? b.count : row[b.count]
    }

    /// Code muss nach Code aussehen: mindestens 4 Zeichen und eine Ziffer.
    public static func isPlausibleCode(_ n: String) -> Bool {
        let c = n.replacingOccurrences(of: " ", with: "")
        return c.count >= 4 && c.contains(where: \.isNumber)
    }

    /// Nur 13 Ziffern wie ein EAN-13-Barcode: Format und ob die Prüfziffer stimmt.
    /// 8- und 12-stellige Nummern sind bei Gutscheinen häufig normale Kartennummern und werden nicht geprüft.
    public static func retailCheck(_ number: String) -> (format: CodeFormat, valid: Bool)? {
        let c = number.replacingOccurrences(of: " ", with: "")
        guard c.count == 13, c.allSatisfy(\.isNumber) else { return nil }
        return (.ean13, BarcodeEncoder.hasValidChecksum(c, format: .ean13) == true)
    }

    // MARK: Hilfen

    /// Nur Buchstaben und Ziffern, klein, ohne Akzente: robust gegen Leerzeichen und Groß-/Kleinschreibung.
    static func compact(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
            .filter { $0.isLetter || $0.isNumber }
    }

    /// Steht der Wert als zusammenhängende ganze Wörter/Zahlen in einer Zeile? („dm“ nicht in „und mehr“, „Otto“ nicht in „Lotto“,
    /// Nummern nicht über Zeilen verklebt.) Leerzeichen und Bindestriche im Code dürfen fehlen oder anders stehen.
    static func onOneLine(_ value: String, in lines: [String]) -> Bool {
        let target = compact(value)
        guard !target.isEmpty else { return false }
        for line in lines {
            let tokens = line.split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map { compact(String($0)) }.filter { !$0.isEmpty }
            for i in tokens.indices {
                var joined = ""
                for token in tokens[i...] {
                    joined += token
                    if joined == target { return true }
                    if joined.count >= target.count || !target.hasPrefix(joined) { break }
                }
            }
        }
        return false
    }

    /// Schreibweise aus dem Originaltext, auch über Zeilenumbrüche und doppelte Leerzeichen hinweg.
    /// Steht der Name so nicht im Text, wenigstens nicht komplett klein lassen.
    static func original(_ value: String, in text: String) -> String? {
        let words = value.split(whereSeparator: \.isWhitespace).map { NSRegularExpression.escapedPattern(for: String($0)) }
        if !words.isEmpty,
           let re = try? NSRegularExpression(pattern: words.joined(separator: #"\s+"#), options: [.caseInsensitive]),
           let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let r = Range(m.range, in: text) {
            return text[r].split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        if let r = text.range(of: value, options: [.caseInsensitive, .diacriticInsensitive]) { return String(text[r]) }
        return value == value.lowercased() ? value.capitalized(with: Locale(identifier: "de_DE")) : nil
    }

    /// Schreibweisen eines Betrags: 50 → „50“, „50,00“; 1250 → „1.250“, „1250“.
    private static func amountForms(_ v: Double) -> [String] {
        let whole = Int(v.rounded(.down))
        var forms = [String(whole)]
        if whole >= 1000 { forms.append("\(whole / 1000).\(String(format: "%03d", whole % 1000))") }
        let fraction = Int(((v - Double(whole)) * 100).rounded())
        if fraction > 0 { forms = forms.flatMap { [$0 + "," + String(format: "%02d", fraction), $0 + "." + String(format: "%02d", fraction)] } }
        return forms.map { NSRegularExpression.escapedPattern(for: $0) }
    }

    /// Betrag steht mit Währung oder Beschriftung im Text („50 €“, „EUR 40“, „Wert: 30“), nicht bloß als Zahl
    /// (sonst zählten Datum, Filialnummer oder Hausnummer).
    private static func amountAppears(_ v: Double, in text: String) -> Bool {
        let n = "(?:" + amountForms(v).joined(separator: "|") + ")"
        // „30,–“, „30,-“, „30, - Euro“ (Handschrift-Erkennung setzt oft Leerzeichen), „30,00“.
        let tail = #"(?:\s?[.,]\s?(?:[-–]|0{1,2}))?"#
        let patterns = [
            #"(?i)(?<![\d.,])"# + n + tail + #"\s?(?:€|EUR\b|Euro\b)"#,
            #"(?i)(?:€|EUR)\s?"# + n + #"(?![\d])"#,
            #"(?i)\b(?:Wert|Betrag|Guthaben|Gutscheinwert|Value)\b[^\d\n]{0,20}"# + n + #"(?![\d])"#,
        ]
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    private static func percentAppears(_ p: Double, in text: String) -> Bool {
        let n = "(?:" + amountForms(p).joined(separator: "|") + ")"
        // Steuersätze („19 % MwSt“) sind kein Rabatt.
        return TextParser.withoutTax(text).range(of: #"(?<![\d.,])"# + n + #"\s?%"#, options: .regularExpression) != nil
    }

    /// Datum der KI steht so im Text: Tag, Monat und Jahr zusammen in einer Zeile
    /// (als Zahlen oder mit Monatsnamen). Nur Monatsende darf ohne Tag stehen („12/28“, „Ende 2027“).
    private static func dateAppears(_ date: Date, in lines: [String]) -> Bool {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard let year = c.year, let month = c.month, let day = c.day else { return false }
        let isMonthEnd = Calendar.current.range(of: .day, in: .month, for: date)?.count == day
        let y = "(?:\(year)|\(String(year).suffix(2)))"
        return lines.contains { line in
            let l = line.lowercased()
            // 31.12.2029, 31/12/29, 31-12-2029
            if l.range(of: #"(?<!\d)0?\#(day)\s*[./-]\s*0?\#(month)\s*[./-]\s*"# + y + #"(?!\d)"#, options: .regularExpression) != nil { return true }
            // 2029-12-31
            if l.range(of: #"\b\#(year)-0?\#(month)-0?\#(day)\b"#, options: .regularExpression) != nil { return true }
            let words = l.split(whereSeparator: { !$0.isLetter }).map(String.init)
            let named = words.contains { TextParser.month(named: $0) == month }
            // 31. Dezember 2029, Dec 31, 2029
            if named, l.range(of: #"(?<!\d)0?\#(day)(?!\d)"#, options: .regularExpression) != nil, l.contains(String(year)) { return true }
            guard isMonthEnd else { return false }
            // Monatsende ohne Tag: „12/28“, „Dezember 2029“, „Ende 2029“ (nur Dezember)
            if l.range(of: #"(?<!\d)0?\#(month)\s*[/.]\s*"# + y + #"(?![./\d])"#, options: .regularExpression) != nil { return true }
            if named && l.contains(String(year)) { return true }
            return month == 12 && l.range(of: #"\bende\s+(?:des\s+jahres\s+)?\#(year)\b"#, options: .regularExpression) != nil
        }
    }
}

public extension CodeFormat {
    /// Format ohne Scan oder Nutzerwahl: Rabatt- und Aktionscodes und reine Online-Händler als Text, sonst das Händlerformat.
    static func automatic(kind: VoucherKind, merchantID: String?) -> CodeFormat {
        guard kind.isValueBased else { return .text }
        guard let id = merchantID, let m = Merchant.byID[id] else { return .code128 }
        return m.category == .codeOnly ? .text : m.format
    }
}
