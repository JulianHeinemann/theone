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

    /// Offener Restwert aller wertbasierten, nicht abgelaufenen Gutscheine.
    public static func openTotal(_ cards: [GiftCard]) -> Double {
        cards.filter { $0.kind.isValueBased && $0.daysLeft >= 0 }.reduce(0) { $0 + $1.balance }
    }

    public static func originalTotal(_ cards: [GiftCard]) -> Double {
        cards.filter { $0.kind.isValueBased && $0.daysLeft >= 0 }.reduce(0) { $0 + $1.value }
    }

    public static func expiringSoon(_ cards: [GiftCard], warnDays: Int) -> [GiftCard] {
        cards.filter { $0.status(warnDays: warnDays) == .expiringSoon }.sorted { $0.expires < $1.expires }
    }

    public static func bonLines(_ cards: [GiftCard]) -> [BonLine] {
        cards.flatMap { c in c.history.map { BonLine(cardID: c.id, cardName: c.name, merchantID: c.merchantID, redemption: $0) } }
            .sorted { $0.redemption.date > $1.redemption.date }
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
