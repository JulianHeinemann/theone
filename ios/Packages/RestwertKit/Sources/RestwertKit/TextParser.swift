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

    public init(merchantID: String? = nil, number: String? = nil, pin: String? = nil, value: Double? = nil, expires: Date? = nil, percent: Double? = nil) {
        self.merchantID = merchantID; self.number = number; self.pin = pin; self.value = value; self.expires = expires; self.percent = percent
    }

    /// Heuristik: Rabattcode statt Wertgutschein.
    public var isDiscount: Bool { percent != nil }
}

public enum TextParser {
    public static func parse(_ text: String, now: Date = .now) -> CardDraft {
        var d = CardDraft()
        let t = text.replacingOccurrences(of: "\u{00A0}", with: " ")
        d.merchantID = merchant(in: t)
        d.pin = firstMatch(#"(?i)\bPIN\s*[:#]?\s*([0-9]{3,8})\b"#, in: t)
        d.value = amount(in: t)
        d.expires = expiry(in: t, now: now)
        d.percent = percent(in: t)
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

    public static func percent(in s: String) -> Double? {
        let hits = matches(#"(\d{1,2}(?:[.,]\d)?)\s?%"#, in: s).compactMap { parseMoney($0[1]) }.filter { $0 > 0 && $0 <= 90 }
        guard let first = hits.first else { return nil }
        let lower = s.lowercased()
        let discountWords = ["rabatt", "code", "gutscheincode", "sparen", "spare", "off", "reduziert"]
        return discountWords.contains(where: lower.contains) ? first : nil
    }

    /// Zahl mit optionalen Tausenderpunkten und Nachkommastellen, z. B. 1.234,56 oder 12,5 oder 20.
    private static let number = #"(\d{1,3}(?:\.\d{3})+(?:,\d{1,2})?|\d{1,4}(?:[.,]\d{1,2})?)"#

    public static func amount(in s: String) -> Double? {
        let p = #"(?i)(?:€|EUR)\s?"# + number + #"|"# + number + #"\s?(?:€|EUR\b|Euro\b)"#
        let values = matches(p, in: s).compactMap { g -> Double? in
            let raw = g[1].isEmpty ? g[2] : g[1]
            return parseMoney(raw)
        }.filter { $0 > 0 && $0 <= 5000 }
        // Beträge nahe „Wert“, „Betrag“, „Guthaben“ bevorzugen
        let labeled = #"(?i)(?:Wert|Betrag|Guthaben|Gutscheinwert|Value)\D{0,20}"# + number
        if let hit = matches(labeled, in: s).compactMap({ parseMoney($0[1]) }).first(where: { $0 > 0 && $0 <= 5000 }) {
            return hit
        }
        return values.max()
    }

    public static func expiry(in s: String, now: Date = .now) -> Date? {
        let cal = Calendar.current
        func date(_ g: [String]) -> Date? {
            guard let d = Int(g[1]), let m = Int(g[2]), var y = Int(g[3]) else { return nil }
            if y < 100 { y += 2000 }
            return cal.date(from: DateComponents(year: y, month: m, day: d))
        }
        let labeled = matches(#"(?i)(?:gültig|gueltig|bis|ablauf|verfällt|valid|expires?)[^\d]{0,25}(\d{1,2})\.(\d{1,2})\.(\d{2,4})"#, in: s).compactMap(date)
        if let first = labeled.first { return first }
        let all = matches(#"\b(\d{1,2})\.(\d{1,2})\.(\d{2,4})\b"#, in: s).compactMap(date).filter { $0 > now }
        return all.max()
    }

    public static func code(in s: String, excluding pin: String?) -> String? {
        let labeled = #"(?i)(?:Gutscheincode|Gutschein-Code|Gutscheinnummer|Kartennummer|Karten-Nr\.?|Kartennr\.?|Code|Nummer|Card number|Seriennummer)\s*[:#]?\s*([A-Z0-9][A-Z0-9 \-]{5,40})"#
        for g in matches(labeled, in: s) {
            let cleaned = clean(g[1])
            if cleaned.count >= 6, cleaned != pin, cleaned.contains(where: \.isNumber) { return cleaned }
        }
        let candidates = matches(#"\b[A-Z0-9][A-Z0-9\-]{7,30}\b"#, in: s.uppercased())
            .map { $0[0] }
            .filter { $0.filter(\.isNumber).count >= 4 && $0 != pin }
        return candidates.max { $0.count < $1.count }
    }

    /// Ziffernblöcke zusammenziehen, Wörter am Ende abschneiden.
    private static func clean(_ raw: String) -> String {
        let firstLine = raw.split(whereSeparator: \.isNewline).first.map(String.init) ?? raw
        let parts = firstLine.split(separator: " ")
        var kept: [Substring] = []
        for p in parts {
            if p.contains(where: \.isNumber) || (p.count >= 3 && p.uppercased() == p && p.contains("-")) { kept.append(p) } else { break }
        }
        let joined = kept.joined(separator: kept.allSatisfy { $0.allSatisfy(\.isNumber) } ? "" : " ")
        return joined.trimmingCharacters(in: .whitespaces)
    }
}
