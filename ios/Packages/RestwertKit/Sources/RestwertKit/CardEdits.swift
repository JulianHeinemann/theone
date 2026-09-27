import Foundation

// MARK: - Ablaufdatum als Kalendertag

/// Ablaufdaten sind Kalendertage, keine Zeitpunkte. Gespeichert wird der Tag als 12:00 Uhr UTC; verglichen wird
/// Tag gegen Tag (``GiftCard/daysLeft(now:calendar:)``). So verschiebt keine Zeitzone und kein erneutes Laden
/// den Tag. Die Anzeige über `Calendar.current` stimmt in allen Zonen von UTC−11 bis UTC+11; für Anzeigen,
/// die auch in Neuseeland/Tonga stimmen sollen, ``local(_:calendar:)`` benutzen.
public enum CalendarDay {
    public static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!
        return c
    }()

    /// Liegt schon auf 12:00 UTC (gespeicherte Form)?
    public static func isStored(_ date: Date) -> Bool {
        abs(date.timeIntervalSince1970.truncatingRemainder(dividingBy: 86_400) - 43_200) < 0.001
    }

    /// Kalendertag des Ablaufdatums: gespeicherte Form in UTC, ältere Stände (Mitternacht oder 12:00 Ortszeit) in `calendar`.
    public static func day(_ date: Date, calendar: Calendar = .current) -> DateComponents {
        let cal = isStored(date) ? utc : calendar
        let d = cal.dateComponents([.year, .month, .day], from: date)
        return DateComponents(year: d.year, month: d.month, day: d.day)
    }

    /// In die gespeicherte Form bringen (12:00 UTC desselben Kalendertags). Idempotent: Schon gespeicherte Daten
    /// bleiben unverändert, auch wenn das Gerät inzwischen in einer anderen Zeitzone ist.
    public static func noon(_ date: Date, calendar: Calendar = .current) -> Date {
        if isStored(date) { return date }
        var d = day(date, calendar: calendar)
        d.hour = 12
        return utc.date(from: d) ?? date
    }

    /// Derselbe Kalendertag als 12:00 Uhr in `calendar` (Ortszeit) – für Anzeige, Erinnerungen und das Widget.
    public static func local(_ date: Date, calendar: Calendar = .current) -> Date {
        var d = day(date, calendar: calendar)
        d.hour = 12
        return calendar.date(from: d) ?? date
    }

    /// Ganze Kalendertage von `now` (Ortszeit) bis zum Ablauftag.
    public static func days(from now: Date, to expiry: Date, calendar: Calendar = .current) -> Int {
        let t = calendar.dateComponents([.year, .month, .day], from: now)
        guard let a = utc.date(from: DateComponents(year: t.year, month: t.month, day: t.day, hour: 12)),
              let b = utc.date(from: { var d = day(expiry, calendar: calendar); d.hour = 12; return d }())
        else { return 0 }
        return utc.dateComponents([.day], from: a, to: b).day ?? 0
    }
}

// MARK: - Bereinigen vor dem Speichern

extension Double {
    /// Nicht-endliche oder negative Beträge (NaN, ∞) würden das Kodieren abbrechen: auf 0 setzen, sonst auf Cent runden.
    var sanitizedMoney: Double { isFinite ? max(0, (self * 100).rounded() / 100) : 0 }
    /// Wie oben, aber Vorzeichen erlaubt (Aufladungen stehen negativ im Verlauf).
    var sanitizedSigned: Double { isFinite ? (self * 100).rounded() / 100 : 0 }
}

extension GiftCard {
    /// Ohne NaN/∞: JSONEncoder wirft sonst und nichts wird mehr gespeichert.
    public var sanitized: GiftCard {
        guard !isFiniteEverywhere else { return self }
        var c = self
        c.value = value.sanitizedMoney
        c.balance = balance.sanitizedMoney
        c.percent = percent.flatMap { $0.isFinite ? $0 : nil }
        c.history = history.map { r in
            var x = r
            x.amount = r.amount.sanitizedSigned
            x.balanceAfter = r.balanceAfter.sanitizedMoney
            return x
        }
        return c
    }

    /// Alle Beträge endlich (sonst wirft JSONEncoder).
    public var isFiniteEverywhere: Bool {
        value.isFinite && balance.isFinite && (percent?.isFinite ?? true)
            && history.allSatisfy { $0.amount.isFinite && $0.balanceAfter.isFinite }
    }
}

extension TestResult {
    public var sanitized: TestResult {
        guard let amount, !amount.isFinite else { return self }
        var t = self
        t.amount = nil
        return t
    }
}

// MARK: - Rückgängig nach einem Abzug

/// Zustand vor einem Abzug, damit „Rückgängig“ ihn exakt wiederherstellt.
public struct RedemptionUndo: Sendable, Equatable {
    public var value: Double
    public var balance: Double
    public var pendingSince: Date?
    public var redeemedAt: Date?

    public init(_ prior: GiftCard) {
        value = prior.value
        balance = prior.balance
        pendingSince = prior.pendingSince
        redeemedAt = prior.redeemedAt
    }
}

extension GiftCard {
    /// Verlaufseintrag zurücknehmen. Beim letzten Eintrag mit gemerktem Zustand wird exakt der alte Stand
    /// hergestellt – aber nur, wenn das Guthaben noch genau dem Stand nach dieser Buchung entspricht. Hat ein
    /// Sync inzwischen eine fremde Buchung eingemischt, wird stattdessen der gebuchte Betrag zurückgerechnet
    /// (nie unter 0), damit die fremde Buchung nicht verloren geht. Gibt `false` zurück, wenn es den Eintrag nicht (mehr) gibt.
    @discardableResult
    public mutating func undo(entry: UUID, restoring state: RedemptionUndo?) -> Bool {
        guard let i = history.firstIndex(where: { $0.id == entry }) else { return false }
        let isLast = i == history.count - 1
        let untouched = abs(balance - history[i].balanceAfter) < 0.005
        if let state, isLast, untouched {
            value = state.value
            balance = state.balance
            pendingSince = state.pendingSince
            redeemedAt = state.redeemedAt
        } else {
            balance = max(0, ((balance + history[i].amount) * 100).rounded() / 100)
        }
        let removed = history.remove(at: i)
        // Eingelöst-Stempel ohne gemerkten Zustand: Stempel mit zurücknehmen.
        if isStamp(removed), !history.contains(where: { isStamp($0) }) { redeemedAt = nil }
        return true
    }

    /// Verlaufseintrag „… eingelöst“ eines Rabattcodes oder Coupons (``markRedeemed(store:at:)``).
    public func isStamp(_ entry: Redemption) -> Bool {
        !kind.isValueBased && entry.amount == 0 && entry.note == "\(kind.label) eingelöst"
    }

    /// Art gewechselt: Der Einlöse-Status bleibt erhalten, damit ein Gutschein nie zugleich „eingelöst“ ist
    /// und in der Summe zählt.
    /// - Eingelöster Rabattcode/Coupon → wertbasiert: aufgebraucht (Guthaben 0), statt Stempel.
    /// - Aufgebrauchter wertbasierter Gutschein → Code/Coupon: als eingelöst gestempelt.
    public mutating func carryRedemptionState(from old: GiftCard, now: Date = .now) {
        guard old.kind.isValueBased != kind.isValueBased else { return }
        if kind.isValueBased, old.redeemedAt != nil {
            redeemedAt = nil
            balance = 0
        } else if !kind.isValueBased, old.redeemedAt == nil, old.balance <= 0, old.value > 0 || !old.history.isEmpty {
            redeemedAt = old.history.last?.date ?? now
        }
    }
}

// MARK: - Liste bearbeiten (Store-Logik, rein und testbar)

public enum CardEdits {
    /// Anlegen oder ersetzen. Ein neuer eigener Gutschein räumt die Beispiele ab (wie im Einstieg versprochen).
    public static func upsert(_ card: GiftCard, cards: inout [GiftCard], tests: inout [TestResult], now: Date = .now) {
        var c = card
        c.isExample = false
        c.modifiedAt = now
        c.expires = CalendarDay.noon(c.expires)
        if let i = cards.firstIndex(where: { $0.id == c.id }) {
            c.carryRedemptionState(from: cards[i], now: now)
            cards[i] = c
        } else {
            cards.removeAll(where: \.isExample)
            tests.removeAll(where: \.isExample)
            cards.append(c)
        }
    }

    /// Entfernen. Beispiele bekommen keinen Löschvermerk: Sie gehen nie in die iCloud.
    @discardableResult
    public static func delete(_ id: UUID, cards: inout [GiftCard], deleted: inout Set<UUID>) -> GiftCard? {
        guard let i = cards.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = cards.remove(at: i)
        if !removed.isExample { deleted.insert(id) }
        return removed
    }

    /// „Rückgängig“ nach dem Entfernen. Beispiele kommen unverändert als Beispiel zurück (andere Beispiele bleiben).
    /// Eigene Gutscheine kommen mit neuer ID zurück, damit der Löschvermerk (auch in iCloud) sie nicht gleich
    /// wieder entfernt. Gibt die ID des wiederhergestellten Gutscheins zurück.
    @discardableResult
    public static func restoreDeleted(_ card: GiftCard, cards: inout [GiftCard], tests: inout [TestResult],
                                      now: Date = .now) -> UUID {
        if card.isExample {
            if !cards.contains(where: { $0.id == card.id }) { cards.append(card) }
            return card.id
        }
        var c = card
        c.id = UUID()
        // Kassentests ziehen mit, sonst verwirft der Sync sie wegen des Löschvermerks der alten ID.
        for i in tests.indices where tests[i].cardID == card.id { tests[i].cardID = c.id }
        upsert(c, cards: &cards, tests: &tests, now: now)
        return c.id
    }
}

// MARK: - Löschvermerke begrenzen

public enum Tombstones {
    /// Löschvermerke werden nach 180 Tagen vergessen. Ein Gerät, das länger offline war, könnte einen gelöschten
    /// Gutschein zurückbringen – das ist der bewusste Preis für eine nicht endlos wachsende Liste.
    public static let maxAge: TimeInterval = 180 * 86_400

    /// Nur Vermerke, die jünger als `maxAge` sind.
    public static func pruned(_ dates: [UUID: Date], now: Date = .now) -> [UUID: Date] {
        let cutoff = now.addingTimeInterval(-maxAge)
        return dates.filter { $0.value >= cutoff }
    }

    /// Vermerke zusammenführen: bekannte behalten ihr (früheres) Datum, neue bekommen das angegebene oder `now`.
    public static func merged(_ local: [UUID: Date], ids: some Sequence<UUID>, dates remote: [UUID: Date] = [:],
                              now: Date = .now) -> [UUID: Date] {
        var out = local
        for id in ids {
            let date = remote[id] ?? now
            out[id] = min(out[id] ?? date, date)
        }
        return out
    }
}
