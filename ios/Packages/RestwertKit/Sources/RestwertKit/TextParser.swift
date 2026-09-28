import Foundation

// MARK: - Text parsing (E-Mail, PDF, Handschrift)

public struct CardDraft: Sendable, Equatable {
    public var merchantID: String?
    public var number: String?
    public var pin: String?
    public var value: Double?
    public var expires: Date?
    /// Rabatt in Prozent, wenn der Text nach Rabattcode aussieht.
    public var percent: Double?
    /// Shopname, der in keiner Händlerliste steht (z. B. von Apple Intelligence gelesen).
    public var customName: String?
    /// Beschenkte Person aus einer eigenen Zeile wie „für Oma Gisela“.
    public var recipient: String?
    /// Ablaufdatum aus einer Laufzeit berechnet („3 Jahre gültig“), nicht wörtlich gelesen.
    public var expiresIsEstimate = false
    /// Die gelesene Laufzeit, damit das Formular bei geändertem „Erhalten am“ neu rechnen kann.
    public var validity: Validity?
    /// Mindestbestellwert („ab 50 € Einkauf“, „Mindestbestellwert 50 €“).
    public var minOrder: Double?

    public init(merchantID: String? = nil, number: String? = nil, pin: String? = nil, value: Double? = nil, expires: Date? = nil, percent: Double? = nil, customName: String? = nil) {
        self.merchantID = merchantID; self.number = number; self.pin = pin; self.value = value; self.expires = expires; self.percent = percent
        self.customName = customName
    }

    /// Heuristik: Rabattcode statt Wertgutschein.
    public var isDiscount: Bool { percent != nil }
}

/// Laufzeit eines Gutscheins, z. B. „3 Jahre ab Ende des Jahres“.
public struct Validity: Sendable, Equatable {
    public var months: Int
    /// Frist beginnt am Ende des Ausstellungsjahres (wie §§ 195, 199 BGB), nicht am Ausstellungstag.
    public var fromYearEnd: Bool

    /// Ausstellungsjahr, falls genannt („ab Ende des Jahres 2026“).
    public var baseYear: Int?

    public init(months: Int, fromYearEnd: Bool, baseYear: Int? = nil) {
        self.months = months; self.fromYearEnd = fromYearEnd; self.baseYear = baseYear
    }

    /// Ablaufdatum für einen Gutschein, der an `start` ausgestellt oder erhalten wurde.
    public func expiry(from start: Date) -> Date? {
        let cal = Calendar.current
        var base = cal.startOfDay(for: start)
        if fromYearEnd, let end = cal.date(from: DateComponents(year: baseYear ?? cal.component(.year, from: start), month: 12, day: 31)) {
            base = end
        }
        return cal.date(byAdding: .month, value: months, to: base)
    }
}

public enum TextParser {
    public static func parse(_ text: String, now: Date = .now) -> CardDraft {
        var d = CardDraft()
        let t = text.replacingOccurrences(of: "\u{00A0}", with: " ")
        d.merchantID = merchant(in: t)
        d.pin = firstMatch(#"(?i)\bPIN(?:[-\s]?(?:Code|Nr\.?|Nummer))?\s*[:#]?\s*([0-9]{3,8})\b"#, in: t)
        d.value = amount(in: t)
        if let e = expiryDetail(in: t, now: now) {
            d.expires = e.date
            d.expiresIsEstimate = e.estimated
            if e.estimated { d.validity = validity(in: t) }
        }
        d.percent = percent(in: t)
        d.recipient = recipient(in: t)
        d.minOrder = minOrder(in: t)
        d.number = code(in: t, excluding: d.pin)
        return d
    }

    private static func regex(_ p: String) -> NSRegularExpression? { try? NSRegularExpression(pattern: p) }

    private static func matches(_ p: String, in s: String) -> [[String]] {
        guard let re = regex(p) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { m in
            (0..<m.numberOfRanges).map { i in
                let r = m.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
        }
    }

    private static func firstMatch(_ p: String, in s: String) -> String? {
        matches(p, in: s).first.flatMap { $0.count > 1 ? $0[1] : nil }
    }

    public static func merchant(in s: String) -> String? {
        for m in Merchant.all {
            let name = NSRegularExpression.escapedPattern(for: m.name)
            if !matches("(?i)(?<![A-Za-z0-9])\(name)(?![A-Za-z0-9])", in: s).isEmpty { return m.id }
        }
        return nil
    }

    /// Text ohne Steuerangaben („inkl. 19 % MwSt“, „MwSt. 19 %“): Prozent darin ist kein Rabatt.
    static func withoutTax(_ s: String) -> String {
        // „19 % MwSt“, „7 % ermäßigte MwSt“, „MwSt. 19 %“, „Enthaltene MwSt: 19 %“, „USt (19%)“, „inkl. 19 % USt.“
        let tax = #"\b(?:MwSt|USt|Mehrwertsteuer|Umsatzsteuer|VAT)\b\.?"#
        let pct = #"\d{1,2}(?:[.,]\d{1,2})?\s?%"#
        let adj = #"(?:(?:ermäßigte|ermaessigte|reduzierte|volle|enthaltene|gesetzliche|inkl\.?|zzgl\.?)\s+)*"#
        return s.replacingOccurrences(of: "(?i)" + pct + #"\s*"# + adj + tax, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "(?i)" + adj + tax + #"[\s:(]*"# + pct + #"\)?"#, with: " ", options: .regularExpression)
    }

    public static func percent(in s: String) -> Double? {
        // Steuersätze („19 % MwSt“, „inkl. MwSt. 19 %“) sind kein Rabatt: ganze Steuerzeilen überspringen.
        let untaxed = withoutTax(s)
        let hits = matches(#"(?i)(\d{1,2}(?:[.,]\d)?)\s?%"#, in: untaxed)
            .compactMap { parseMoney($0[1]) }.filter { $0 > 0 && $0 <= 90 }
        guard let first = hits.first else { return nil }
        // Nur mit Rabatt-Kontext; „Code“ steht in fast jedem Gutscheintext und zählt nicht
        let signal = #"(?i)\b(?:rabatt\w*|nachlass|sparen|spare|off|reduziert)\b"#
        return matches(signal, in: untaxed).isEmpty ? nil : first
    }

    /// Mindestbestellwert: „ab 50 €“, „Mindestbestellwert 50 €“, „MBW: 50 EUR“, „Mindesteinkaufswert von 50 €“,
    /// „bei einem Einkauf ab/über 100 €“. „ab“ zählt nur mit Währung (sonst wäre „ab 12.10.“ ein Betrag).
    public static func minOrder(in s: String) -> Double? {
        // Wie bei Beträgen: mit Tausenderpunkt („ab 1.000 €“), sonst läse man 1 €.
        let n = number
        let cur = #"\s?(?:€|EUR\b|Euro\b)"#
        let patterns = [
            #"(?i)\b(?:Mindest\w*wert|MBW)\s*:?\s*(?:von\s*)?(?:€|EUR)?\s?"# + n,
            #"(?i)\b(?:Einkauf|Bestellung|Einkaufswert|Bestellwert)\s+(?:ab|über|von)\s*(?:€|EUR)?\s?"# + n,
            #"(?i)\bab\s+(?:€|EUR)\s?"# + n,
            #"(?i)\bab\s+"# + n + cur,
        ]
        for p in patterns {
            if let hit = matches(p, in: s).first.flatMap({ parseMoney($0[1]) }), hit > 0, hit <= 5000 { return hit }
        }
        return nil
    }

    /// Zahl mit optionalen Tausenderpunkten und Nachkommastellen, z. B. 1.234,56 oder 12,5 oder 20.
    private static let number = #"(\d{1,3}(?:\.\d{3})+(?:,\d{1,2})?|\d{1,4}(?:[.,]\d{1,2})?)"#

    public static func amount(in text: String) -> Double? {
        // Kurzschreibweise auf Papiergutscheinen: „20,-“, „20,–“, „20.- EUR“ bedeutet 20,00.
        let text = text.replacingOccurrences(of: #"(\d)[.,]\s?[-–—]{1,2}(?!\d)"#, with: "$1,00", options: .regularExpression)
        // Mindestbestellwerte („ab 50 €“, „Mindestbestellwert 50 €“) sind nicht der Gutscheinwert
        let s = text.replacingOccurrences(of: #"(?i)\b(?:ab|Mindest\w*wert|MBW|(?:Einkauf|Bestellung|Einkaufswert|Bestellwert)\s+(?:ab|über|von))\s*:?\s*(?:von\s*)?(?:€|EUR)?\s?\d[\d.,]*\s?(?:€|EUR|Euro)?"#,
                                          with: " ", options: .regularExpression)
        // „30,– Euro“ und „30, - Euro“ (Handschrift-Erkennung) zählen wie „30 Euro“.
        let p = #"(?i)(?:€|EUR)\s?"# + number + #"|"# + number + #"(?:\s?,\s?[-–])?\s?(?:€|EUR\b|Euro\b)"#
        let values = matches(p, in: s).compactMap { g -> Double? in
            let raw = g[1].isEmpty ? g[2] : g[1]
            return parseMoney(raw)
        }.filter { $0 > 0 && $0 <= 5000 }
        // Beträge nahe „Wert“, „Betrag“, „Guthaben“ bevorzugen; nur ganze Wörter, keine Datumsteile
        // Keine Laufzeiten („Guthaben ist 10 Jahre gültig“) und keine Prozente.
        let labeled = #"(?i)\b(?:Wert|Betrag|Guthaben|Gutscheinwert|Value)\b[^\d\n]{0,20}"# + number
            + #"(?![.,]?\d)(?!\s*(?:Jahre?n?|Monate?n?|Tage?n?|Wochen?|years?|months?|days?|%|Prozent|Personen|Person|Pers\.?|Stück|Stk\.?|x|mal)\b)"#
        // Steht irgendwo ein Betrag mit Währung, gewinnt eine Beschriftung nur, wenn sie auch einer davon ist.
        if let hit = matches(labeled, in: s).compactMap({ parseMoney($0[1]) }).first(where: { $0 > 0 && $0 <= 5000 }),
           values.isEmpty || values.contains(hit) {
            return hit
        }
        return values.max()
    }

    /// Ablaufdatum aus freiem Text. Versteht:
    /// - 31.12.2027, 31.12.27, 31/12/2027, 31-12-2027, 2027-12-31
    /// - 31. Dezember 2027, 31. Dez. 27, Dec 31, 2027
    /// - nur Monat und Jahr hinter „gültig bis“: 12/27, 12/2027, 12.2027, Dezember 2027 → Monatsende
    /// - „bis Ende 2027“ → 31.12.2027
    /// - „3 Jahre gültig“, „Gültigkeit: 24 Monate“ → ab heute gerechnet
    /// Beschriftete Daten („gültig bis …“) gewinnen; bei „vom … bis …“ das spätere. Sonst das späteste künftige Datum.
    public static func expiry(in s: String, now: Date = .now) -> Date? {
        expiryDetail(in: s, now: now)?.date
    }

    /// Wie ``expiry(in:now:)``; `estimated` ist wahr, wenn das Datum aus einer Laufzeit berechnet wurde.
    public static func expiryDetail(in s: String, now: Date = .now) -> (date: Date, estimated: Bool)? {
        let label = #"(?:gültig|gueltig|bis|ablauf|verfällt|verfaellt|einlösbar|einloesbar|valid|expires?|expiry|exp\.?|thru)"#
        let lead = label + #"[^\d\n]{0,25}?"#
        // „3 Jahre gültig ab Ende des Jahres 2026“: 2026 ist das Ausstellungsjahr, nicht das Ablaufdatum.
        if let v = validity(in: s), v.baseYear != nil, let date = v.expiry(from: now) { return (date, true) }
        var labeled: [Date] = []
        for (pattern, make) in fullDatePatterns {
            labeled += matches("(?i)" + lead + pattern, in: s).compactMap { make(Array($0.dropFirst())) }
        }
        // Nur Monat und Jahr, nur mit Beschriftung (sonst zu leicht mit Beträgen verwechselt).
        labeled += matches("(?i)" + lead + #"(\d{1,2})\s*[/.]\s*(\d{4}|\d{2})\b(?![./]\d)"#, in: s).compactMap {
            monthEnd(month: Int($0[1]), year: Int($0[2]))
        }
        labeled += matches("(?i)" + lead + #"([A-Za-zÄäÖöÜü]{3,9})\.?\s+(\d{4})\b"#, in: s).compactMap {
            monthEnd(month: month(named: $0[1]), year: Int($0[2]))
        }
        labeled += matches(#"(?i)\bEnde\s+(?:des\s+Jahres\s+)?(\d{4})\b"#, in: s).compactMap {
            monthEnd(month: 12, year: Int($0[1]))
        }
        if let latest = labeled.filter(plausible).max() { return (latest, false) }
        if let relative = relativeExpiry(in: s, now: now) { return (relative, true) }
        // Ohne Beschriftung: das späteste vollständige Datum in der Zukunft.
        var all: [Date] = []
        for (pattern, make) in fullDatePatterns {
            all += matches(#"(?i)(?<![\d.])"# + pattern, in: s).compactMap { make(Array($0.dropFirst())) }
        }
        return all.filter { $0 > now && plausible($0) }.max().map { ($0, false) }
    }

    /// Vollständige Daten in allen üblichen Schreibweisen, jeweils mit Umrechnung der Gruppen.
    private static let fullDatePatterns: [(String, @Sendable ([String]) -> Date?)] = [
        (#"(\d{1,2})\s*[./-]\s*(\d{1,2})\s*[./-]\s*(\d{4}|\d{2})\b"#, { g in day(Int(g[0]), Int(g[1]), Int(g[2])) }),
        (#"(\d{4})-(\d{2})-(\d{2})\b"#, { g in day(Int(g[2]), Int(g[1]), Int(g[0])) }),
        (#"(\d{1,2})\.?\s+([A-Za-zÄäÖöÜü]{3,9})\.?\s+(\d{4}|\d{2})\b"#, { g in day(Int(g[0]), month(named: g[1]), Int(g[2])) }),
        (#"([A-Za-z]{3,9})\.?\s+(\d{1,2}),?\s+(\d{4})\b"#, { g in day(Int(g[1]), month(named: g[0]), Int(g[2])) }),
    ]

    private static func day(_ d: Int?, _ m: Int?, _ y: Int?) -> Date? {
        guard let d, let m, var y, (1...31).contains(d), (1...12).contains(m) else { return nil }
        if y < 100 { y += 2000 }
        let comps = DateComponents(year: y, month: m, day: d)
        guard let date = Calendar.current.date(from: comps),
              Calendar.current.component(.day, from: date) == d else { return nil }   // 31.02. ablehnen
        return date
    }

    private static func monthEnd(month m: Int?, year y: Int?) -> Date? {
        guard let m, var y, (1...12).contains(m) else { return nil }
        if y < 100 { y += 2000 }
        let cal = Calendar.current
        guard let first = cal.date(from: DateComponents(year: y, month: m, day: 1)),
              let next = cal.date(byAdding: .month, value: 1, to: first) else { return nil }
        return cal.date(byAdding: .day, value: -1, to: next)
    }

    private static func plausible(_ d: Date) -> Bool {
        let y = Calendar.current.component(.year, from: d)
        return (2000...2100).contains(y)
    }

    /// Monatsname auf Deutsch oder Englisch, ausgeschrieben oder abgekürzt.
    static func month(named raw: String) -> Int? {
        let n = raw.lowercased().replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "ä", with: "ae")
        let names: [String: Int] = [
            "januar": 1, "january": 1, "jan": 1, "jänner": 1, "jaenner": 1,
            "februar": 2, "february": 2, "feb": 2,
            "maerz": 3, "march": 3, "maer": 3, "mrz": 3, "mar": 3,
            "april": 4, "apr": 4,
            "mai": 5, "may": 5,
            "juni": 6, "june": 6, "jun": 6,
            "juli": 7, "july": 7, "jul": 7,
            "august": 8, "aug": 8,
            "september": 9, "sep": 9, "sept": 9,
            "oktober": 10, "october": 10, "okt": 10, "oct": 10,
            "november": 11, "nov": 11,
            "dezember": 12, "december": 12, "dez": 12, "dec": 12,
        ]
        return names[n]
    }

    /// „3 Jahre gültig“, „gültig für drei Jahre“, „Gültigkeit: 24 Monate“ – ab heute gerechnet.
    private static func relativeExpiry(in s: String, now: Date) -> Date? {
        validity(in: s)?.expiry(from: now)
    }

    /// „3 Jahre gültig“, „Gültigkeit: 24 Monate“, „3 Jahre ab Ende des Jahres“ als Laufzeit.
    public static func validity(in s: String) -> Validity? {
        let number = #"(\d{1,2}|ein|einem|eins|zwei|drei|vier|fünf|fuenf|one|two|three|four|five)"#
        let unit = #"(Jahre?n?|Monate?n?|years?|months?)"#
        let valid = #"(?:gültig|gueltig|einlösbar|einloesbar|valid|Gültigkeit|Gueltigkeit)"#
        let found = matches("(?i)" + number + #"\s+"# + unit + #"\s+(?:lang\s+|ab\s+[^\n]{1,40}?\s+)?"# + valid, in: s).first
            ?? matches("(?i)" + valid + #"[:\s]+(?:für|fuer|for|von)?\s*"# + number + #"\s+"# + unit, in: s).first
        guard let g = found else { return nil }
        let words = ["ein": 1, "einem": 1, "eins": 1, "one": 1, "zwei": 2, "two": 2, "drei": 3, "three": 3,
                     "vier": 4, "four": 4, "fünf": 5, "fuenf": 5, "five": 5]
        let raw = g[1].lowercased()
        guard let n = Int(raw) ?? words[raw], n > 0 else { return nil }
        let years = g[2].lowercased().hasPrefix("j") || g[2].lowercased().hasPrefix("y")
        // „ab Ende des (Kalender-/Kauf-/Ausstellungs-)Jahres“, „zum Jahresende“, „Schluss des Jahres“.
        let yearEnd = #"(?i)\b(?:(?:Ende|Schluss)\s+(?:des|eines)\s+(?:\w+\s+)?\w*jahres|\w*jahres(?:ende|schluss)|end\s+of\s+(?:the\s+)?(?:calendar\s+)?year)\b"#
        // Nur neben der Laufzeit (gleiche oder nächste Zeile), nicht irgendwo im Text (z. B. „Aktion bis Jahresende“).
        let lines = s.components(separatedBy: .newlines)
        let at = lines.firstIndex { $0.contains(g[0]) } ?? lines.firstIndex { $0.localizedCaseInsensitiveContains(g[1] + " " + g[2]) }
        let near = at.map { lines[$0...min($0 + 1, lines.count - 1)].joined(separator: " ") } ?? s
        let fromYearEnd = !matches(yearEnd, in: near).isEmpty
        let base = fromYearEnd ? matches(#"(?i)jahres\s+(20\d{2})\b"#, in: near).first.flatMap { Int($0[1]) } : nil
        return Validity(months: years ? n * 12 : n, fromYearEnd: fromYearEnd, baseYear: base)
    }

    /// „für Oma Gisela“ als eigene Zeile. Anreden wie „für dich“ oder „für alle“ zählen nicht.
    public static func recipient(in s: String) -> String? {
        let name = #"[A-ZÄÖÜ][a-zäöüß]+(?:-[A-ZÄÖÜ][a-zäöüß]+)?"#
        // Verwandtschaft auch klein geschrieben („für oma Gisela“ aus der Handschrift-Erkennung).
        let relation = #"(?:[Oo]ma|[Oo]pa|[Mm]ama|[Pp]apa|[Tt]ante|[Oo]nkel|[Bb]ruder|[Ss]chwester|[Nn]ichte|[Nn]effe|[Pp]ate|[Pp]atin)"#
        let hits = matches(#"(?m)^\s*[Ff](?:ü|ue)r\s+((?:"# + relation + "|" + name + #")(?:\s+"# + name + #"){0,2})\s*[!.]?\s*$"#, in: s)
        let stop: Set<String> = ["dich", "mich", "ihn", "sie", "euch", "uns", "alle", "alles", "jeden", "jede", "den", "die", "das",
                                 "dein", "deine", "deinen", "ihr", "ihre", "ihren", "mein", "meine", "meinen", "unser", "unsere",
                                 "kinder", "erwachsene", "personen", "einkäufe", "einkauf", "zwei", "drei", "vier",
                                 "weihnachten", "ostern", "geburtstag", "muttertag", "vatertag", "hochzeit", "jubiläum",
                                 "valentinstag", "online", "online-einkäufe", "zuhause", "unterwegs", "später", "sie!"]
        for h in hits {
            let first = h[1].split(separator: " ").first.map { $0.lowercased() } ?? ""
            if first.split(separator: "-").contains(where: { stop.contains(String($0)) }) { continue }
            if !stop.contains(first) {
                // Erstes Wort groß: „oma Gisela“ → „Oma Gisela“.
                return h[1].prefix(1).uppercased() + h[1].dropFirst()
            }
        }
        return nil
    }

    public static func code(in s: String, excluding pin: String?) -> String? {
        let value = #"\s*[:#]?\s*([A-Z0-9][A-Z0-9 \-]{5,40})"#
        // Spezifische Beschriftungen zuerst, dann „Code“/„Nummer“ als ganzes Wort (nicht Kunden-/Bestellnummer)
        let specific = #"(?i)\b(?:Gutscheincode|Gutschein-Code|Gutscheinnummer|Kartennummer|Karten-Nr\.?|Kartennr\.?|Card number|Seriennummer)"# + value
        let generic = #"(?i)(?<!Kunden-|Bestell-|Rechnungs-|Auftrags-)\b(?:Code|Nummer)"# + value
        for pattern in [specific, generic] {
            for g in matches(pattern, in: s) {
                let cleaned = clean(g[1])
                if cleaned.count >= 6, cleaned != pin, cleaned.contains(where: \.isNumber) { return cleaned }
            }
        }
        let foreign = Set(matches(#"(?i)\b(?:Kunden|Bestell|Rechnungs|Auftrags)-?(?:nummer|nr\.?)\s*[:#]?\s*([A-Z0-9\-]{6,40})"#, in: s)
            .map { $0[1].uppercased() })
        let candidates = matches(#"\b[A-Z0-9][A-Z0-9\-]{7,30}\b"#, in: s.uppercased())
            .map { $0[0] }
            .filter { $0.filter(\.isNumber).count >= 4 && $0 != pin && !foreign.contains($0) }
        return candidates.max { $0.count < $1.count }
    }

    /// Ziffernblöcke zusammenziehen, Wörter am Ende abschneiden.
    private static func clean(_ raw: String) -> String {
        let firstLine = raw.split(whereSeparator: \.isNewline).first.map(String.init) ?? raw
        let parts = firstLine.split(separator: " ")
        var kept: [Substring] = []
        for p in parts {
            // „PIN“ beendet die Nummer; Kartennummern haben höchstens 19 Ziffern (sonst klebte eine PIN daran).
            if p.range(of: #"(?i)^PIN"#, options: .regularExpression) != nil { break }
            let digits = (kept.map(String.init).joined() + p).filter(\.isNumber).count
            if digits > 19 && kept.contains(where: { $0.contains(where: \.isNumber) }) { break }
            if p.contains(where: \.isNumber) || (p.count >= 3 && p.uppercased() == p && p.contains("-")) { kept.append(p) } else { break }
        }
        let joined = kept.joined(separator: kept.allSatisfy { $0.allSatisfy(\.isNumber) } ? "" : " ")
        return joined.trimmingCharacters(in: .whitespaces)
    }
}
