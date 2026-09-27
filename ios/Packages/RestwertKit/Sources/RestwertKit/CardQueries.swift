import Foundation

/// Sortierung, Summen und Status über viele Gutscheine; rein und testbar.
public enum CardQueries {
    public static func sorted(_ cards: [GiftCard], by order: CardSortOrder) -> [GiftCard] {
        cards.sorted { a, b in
            // Offene Gutscheine zuerst, Eingelöste und Abgelaufene ans Ende
            if a.isActive != b.isActive { return a.isActive }
            switch order {
            case .expiry: return a.expires < b.expires
            case .value: return a.balance > b.balance
            case .shop: return a.name.localizedCompare(b.name) == .orderedAscending
            }
        }
    }

    /// Offener Restwert aller Gutscheine, die zur Summe zählen (``GiftCard/countsTowardTotal(now:)``).
    /// Als eingelöst gestempelte Gutscheine zählen nie, auch wenn sie inzwischen eine wertbasierte Art haben.
    public static func openTotal(_ cards: [GiftCard], now: Date = .now) -> Double {
        cards.filter { $0.countsTowardTotal(now: now) }.reduce(0) { $0 + $1.balance }
    }

    public static func originalTotal(_ cards: [GiftCard], now: Date = .now) -> Double {
        cards.filter { $0.countsTowardTotal(now: now) }.reduce(0) { $0 + $1.value }
    }

    public static func expiringSoon(_ cards: [GiftCard], warnDays: Int) -> [GiftCard] {
        cards.filter { !$0.isArchived && $0.status(warnDays: warnDays) == .expiringSoon }.sorted { $0.expires < $1.expires }
    }

    public static func bonLines(_ cards: [GiftCard]) -> [BonLine] {
        cards.flatMap { c in c.history.map { BonLine(cardID: c.id, cardName: c.name, merchantID: c.merchantID, redemption: $0) } }
            .sorted { $0.redemption.date > $1.redemption.date }
    }

    /// Summe echter Abzüge (positive Beträge). Aufladungen und Korrekturen nach oben zählen nicht mit; nie negativ.
    public static func redeemedTotal(_ lines: [BonLine]) -> Double {
        (lines.reduce(0) { $0 + max(0, $1.redemption.amount) } * 100).rounded() / 100
    }

    /// Summe der Aufladungen (negative Verlaufsbeträge), als positiver Betrag.
    public static func toppedUpTotal(_ lines: [BonLine]) -> Double {
        (lines.reduce(0) { $0 + max(0, -$1.redemption.amount) } * 100).rounded() / 100
    }

    // MARK: CSV

    /// Tabelle für Excel und Numbers: Semikolon, CRLF, deutsche Zahlen unabhängig von der Gerätesprache,
    /// Felder in Anführungszeichen, Kartennummern als Text (="…"), damit Excel keine Stellen abschneidet.
    public static func csv(_ cards: [GiftCard], warnDays: Int, now: Date = .now) -> String {
        let head = ["Laden", "Für", "Art", "Startwert", "Guthaben", "Gültig bis", "Code", "Status"].map(csvText)
        let rows = cards.filter { !$0.isExample }.map { c in
            [csvText(c.name), csvText(c.owner), csvText(c.kind.label),
             c.kind.isValueBased ? csvNumber(c.value) : csvText(c.headline),
             c.kind.isValueBased ? csvNumber(c.balance) : "",
             csvText(c.expires.dayMonthYear), csvCode(c.number),
             csvText(c.isArchived ? "archiviert" : c.status(warnDays: warnDays, now: now).label)]
                .joined(separator: ";")
        }
        return ([head.joined(separator: ";")] + rows).joined(separator: "\r\n") + "\r\n"
    }

    /// Betrag mit Komma, ohne Tausenderpunkt: „1234,50“.
    static func csvNumber(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(2)).grouping(.never).locale(Locale(identifier: "de_DE")))
    }

    /// Text in Anführungszeichen, innere verdoppelt. Beginnt er wie eine Formel, wird ein ' vorangestellt.
    static func csvText(_ s: String) -> String {
        var t = s
        if let f = t.first, "=+-@\t\r".contains(f) { t = "'" + t }
        return "\"" + t.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Nummer als Excel-Textformel ="…" (im Feld maskiert); Anführungszeichen und Zeilenumbrüche fliegen raus.
    static func csvCode(_ s: String) -> String {
        let clean = s.filter { $0 != "\"" && !$0.isNewline }
        return clean.isEmpty ? "" : "\"=\"\"" + clean + "\"\"\""
    }

    /// Radius im Ablauf-Radar (0 = Mitte = heute). Ringe bei 30 Tagen, 90 Tagen, 6 Monaten, 1 Jahr.
    public static let radarRings: [(days: Double, fraction: Double, label: String)] = [
        (30, 0.32, "30 T"), (90, 0.52, "90 T"), (180, 0.72, "6 M"), (365, 0.92, "1 J"),
    ]

    public static func radarFraction(forDays d: Int) -> Double {
        if d <= 0 { return 0.1 }
        var prevDays = 0.0, prevF = 0.14
        for r in radarRings {
            if Double(d) <= r.days {
                return prevF + (r.fraction - prevF) * (Double(d) - prevDays) / (r.days - prevDays)
            }
            prevDays = r.days
            prevF = r.fraction
        }
        return 0.98
    }
}
