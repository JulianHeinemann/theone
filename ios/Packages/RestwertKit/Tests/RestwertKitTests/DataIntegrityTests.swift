import Foundation
import Testing
@testable import RestwertKit

private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12, in tz: TimeZone = .current) -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    return cal.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
}

private func voucher(_ kind: VoucherKind = .giftCard, value: Double = 50, balance: Double? = nil,
                     modified: Date = day(2026, 1, 1), example: Bool = false) -> GiftCard {
    GiftCard(kind: kind, merchantID: "thalia", number: "6300981274561234", format: .code128, value: value,
             balance: balance ?? value, received: day(2026, 1, 1), expires: day(2030, 12, 31),
             isExample: example, modifiedAt: modified)
}

@Suite("Beträge")
struct MoneyTests {
    @Test("Nur endliche, nicht negative Beträge bis 100.000 €",
          arguments: ["nan", "NaN", "inf", "-inf", "infinity", "-5", "-0,50", "100000,01", "1e9", "0x10", "abc", ""])
    func rejects(_ text: String) {
        #expect(parseMoney(text) == nil)
    }

    @Test("Gültige Beträge", arguments: [("0", 0.0), ("100.000", 100_000.0), ("99999,99", 99_999.99), ("12,", 12.0),
                                         ("12,50 €", 12.5), (",5", 0.5), ("12,50\u{00A0}€", 12.5)])
    func accepts(_ text: String, _ expected: Double) {
        #expect(parseMoney(text) == expected)
    }

    @Test("Bereinigen: NaN/∞ werden vor dem Speichern zu kodierbaren Werten")
    func sanitize() throws {
        var c = voucher()
        c.value = .nan
        c.balance = .infinity
        c.percent = -.infinity
        c.history = [Redemption(date: .now, amount: .nan, balanceAfter: .infinity)]
        #expect(throws: (any Error).self) { _ = try JSONEncoder().encode(c) }
        let clean = c.sanitized
        #expect(clean.value == 0 && clean.balance == 0 && clean.percent == nil)
        #expect(clean.history[0].amount == 0)
        _ = try JSONEncoder().encode(clean)
        var t = TestResult(merchantID: "x", merchantName: "X", date: .now, success: true, format: .code128, amount: .nan)
        t = t.sanitized
        #expect(t.amount == nil)
        // Saubere Karten bleiben unverändert.
        let ok = voucher()
        #expect(ok.sanitized == ok)
    }
}

@Suite("Rückgängig und Art-Wechsel")
struct UndoTests {
    @Test("Überzahlung bucht nur das Guthaben; Rückgängig stellt exakt den alten Stand her")
    func overpaymentUndo() {
        var c = voucher(value: 25, balance: 10)
        let state = RedemptionUndo(c)
        c.redeem(30)
        #expect(c.balance == 0)
        #expect(c.history.last?.amount == 10)
        let entry = c.history.last!.id
        let undone = c.undo(entry: entry, restoring: state)
        #expect(undone)
        #expect(c.balance == 10)
        #expect(c.value == 25)
        #expect(c.history.isEmpty)
    }

    @Test("Überzahlung ohne gemerkten Zustand (z. B. nach Neustart) erzeugt kein Guthaben")
    func overpaymentUndoWithoutState() {
        var c = voucher(value: 25, balance: 10)
        c.redeem(30)
        c.undo(entry: c.history.last!.id, restoring: nil)
        #expect(c.balance == 10)
    }

    @Test("Leeres Guthaben: kein Verlaufseintrag")
    func redeemEmpty() {
        var c = voucher(value: 25, balance: 0)
        c.redeem(5)
        #expect(c.history.isEmpty)
        c.redeem(.nan)
        #expect(c.history.isEmpty)
    }

    @Test("Beispielkarte löschen und zurückholen: bleibt Beispiel, andere Beispiele bleiben")
    func undoDeleteExample() {
        var a = voucher(example: true)
        a.merchantID = "ikea"
        let b = voucher(example: true)
        var cards = [a, b]
        var tests = [TestResult(merchantID: "thalia", merchantName: "Thalia", date: .now, success: true, format: .code128,
                                isExample: true)]
        var deleted: Set<UUID> = []
        let removed = CardEdits.delete(a.id, cards: &cards, deleted: &deleted)
        #expect(removed?.id == a.id)
        #expect(deleted.isEmpty)   // Beispiele gehen nie in die iCloud
        let id = CardEdits.restoreDeleted(removed!, cards: &cards, tests: &tests)
        #expect(id == a.id)
        #expect(cards.count == 2)
        #expect(cards.allSatisfy { $0.isExample })
        #expect(tests.count == 1)
    }

    @Test("Eigene Karte zurückholen: neue ID, Löschvermerk bleibt")
    func undoDeleteOwn() {
        let a = voucher()
        var cards = [a]
        var tests: [TestResult] = []
        var deleted: Set<UUID> = []
        CardEdits.delete(a.id, cards: &cards, deleted: &deleted)
        #expect(deleted == [a.id])
        let id = CardEdits.restoreDeleted(a, cards: &cards, tests: &tests)
        #expect(id != a.id)
        #expect(cards.map(\.id) == [id])
        #expect(!cards[0].isExample)
    }

    @Test("Eingelöster Rabattcode wird Wertgutschein: aufgebraucht, nicht in der Summe")
    func kindChangeCodeToValue() {
        var code = voucher(.discountCode, value: 0, balance: 0)
        code.markRedeemed()
        var cards = [code]
        var tests: [TestResult] = []
        var edited = code
        edited.kind = .valueVoucher
        edited.value = 20
        edited.balance = 20
        CardEdits.upsert(edited, cards: &cards, tests: &tests)
        let c = cards[0]
        #expect(c.redeemedAt == nil)
        #expect(c.balance == 0)
        #expect(c.status(warnDays: 30) == .redeemed)
        #expect(!c.isActive)
        #expect(CardQueries.openTotal(cards) == 0)
    }

    @Test("Summe zählt gestempelte Gutscheine nie mit, egal welche Art")
    func stampedNeverCounts() {
        var c = voucher(.valueVoucher, value: 20)
        c.redeemedAt = .now
        #expect(!c.countsTowardTotal())
        #expect(CardQueries.openTotal([c]) == 0)
        #expect(CardQueries.originalTotal([c]) == 0)
    }

    @Test("Aufgebrauchte Geschenkkarte wird Coupon: bleibt eingelöst")
    func kindChangeValueToCode() {
        var card = voucher(value: 10)
        card.redeem(10)
        var cards = [card]
        var tests: [TestResult] = []
        var edited = card
        edited.kind = .coupon
        edited.balance = 10
        CardEdits.upsert(edited, cards: &cards, tests: &tests)
        #expect(cards[0].redeemedAt != nil)
        #expect(!cards[0].isOpen)
    }
}

@Suite("Zeitzonen")
struct TimeZoneTests {
    private static let zones = ["Europe/Berlin", "America/New_York", "America/Los_Angeles", "Pacific/Honolulu",
                                "Pacific/Pago_Pago", "Asia/Tokyo", "Europe/London", "Asia/Kolkata",
                                "Pacific/Auckland", "Pacific/Tongatapu", "Pacific/Kiritimati"]

    private static func cal(_ id: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: id)!
        return c
    }

    @Test("Ablaufdatum bleibt derselbe Kalendertag, egal wo gewählt und wo geprüft (auch > 12 h Unterschied)",
          arguments: zones)
    func expiryStaysSameDay(_ from: String) {
        // Im DatePicker gewählt: Mitternacht bzw. 23:30 Ortszeit → Kalendertag in UTC gespeichert.
        let src = Self.cal(from)
        for hour in [0, 12, 23] {
            let picked = src.date(from: DateComponents(year: 2027, month: 3, day: 31, hour: hour, minute: hour == 23 ? 30 : 0))!
            var c = voucher()
            c.expires = CalendarDay.noon(picked, calendar: src)
            for to in Self.zones {
                let cal = Self.cal(to)
                #expect(CalendarDay.day(c.expires, calendar: cal) == DateComponents(year: 2027, month: 3, day: 31),
                        "\(from) → \(to)")
                let shown = cal.dateComponents([.month, .day], from: CalendarDay.local(c.expires, calendar: cal))
                #expect(shown.month == 3 && shown.day == 31, "\(from) → \(to)")
                let late = cal.date(from: DateComponents(year: 2027, month: 3, day: 30, hour: 23, minute: 59))!
                let early = cal.date(from: DateComponents(year: 2027, month: 3, day: 31, hour: 0, minute: 1))!
                let after = cal.date(from: DateComponents(year: 2027, month: 4, day: 1, hour: 0, minute: 1))!
                #expect(c.daysLeft(now: late, calendar: cal) == 1, "\(from) → \(to)")
                #expect(c.daysLeft(now: early, calendar: cal) == 0, "\(from) → \(to)")
                #expect(c.daysLeft(now: after, calendar: cal) == -1, "\(from) → \(to)")
            }
        }
    }

    @Test("Normalisieren ist idempotent: erneutes Laden in einer fernen Zone verschiebt nichts")
    func normalizeIsIdempotent() {
        let berlin = Self.cal("Europe/Berlin")
        let stored = CalendarDay.noon(day(2027, 1, 15, hour: 12, in: berlin.timeZone), calendar: berlin)
        #expect(CalendarDay.isStored(stored))
        // Neu laden in Tonga (+13) und New York (−5), dann zurück in Berlin.
        let tonga = CalendarDay.noon(stored, calendar: Self.cal("Pacific/Tongatapu"))
        let ny = CalendarDay.noon(tonga, calendar: Self.cal("America/New_York"))
        #expect(ny == stored)
        #expect(CalendarDay.day(ny, calendar: berlin) == DateComponents(year: 2027, month: 1, day: 15))
        // Alte Stände (12:00 Ortszeit in Berlin) werden einmal richtig übernommen.
        let legacy = day(2027, 1, 15, hour: 12, in: berlin.timeZone)
        #expect(!CalendarDay.isStored(legacy))
        #expect(CalendarDay.day(CalendarDay.noon(legacy, calendar: berlin), calendar: Self.cal("Pacific/Tongatapu"))
                == DateComponents(year: 2027, month: 1, day: 15))
    }

    @Test("Speichern bringt das Ablaufdatum in die gespeicherte Form (12:00 UTC)")
    func upsertNormalizes() {
        var c = voucher()
        c.expires = day(2027, 3, 31, hour: 0)
        var cards: [GiftCard] = []
        var tests: [TestResult] = []
        CardEdits.upsert(c, cards: &cards, tests: &tests)
        #expect(CalendarDay.isStored(cards[0].expires))
        #expect(CalendarDay.day(cards[0].expires) == DateComponents(year: 2027, month: 3, day: 31))
        #expect(CalendarDay.isStored(GiftCard.legalExpiry(from: .now)))
    }
}

@Suite("Sync: gleichzeitige Buchungen")
struct ConcurrentSyncTests {
    @Test("Einlösungen auf zwei Geräten gehen beide ein, in beide Richtungen")
    func bothRedemptionsSurvive() {
        let base = voucher(value: 50, modified: day(2026, 1, 1))
        var a = base
        a.redeem(10, at: day(2026, 2, 1))
        var b = base
        b.redeem(5, at: day(2026, 2, 2))
        // Gerät A mischt B ein (B ist neuer).
        let onA = SyncMerge.merge(localCards: [a], localTests: [], localDeleted: [], remote: SyncData(cards: [b], tests: [], deleted: []))
        #expect(onA.cards[0].balance == 35)
        #expect(onA.cards[0].history.count == 2)
        #expect(SyncMerge.isNewer(onA.cards[0].modifiedAt, than: b.modifiedAt))   // geht wieder hoch
        // Gerät B mischt A ein (lokal ist neuer).
        let onB = SyncMerge.merge(localCards: [b], localTests: [], localDeleted: [], remote: SyncData(cards: [a], tests: [], deleted: []))
        #expect(onB.cards[0].balance == 35)
        #expect(Set(onB.cards[0].history.map(\.id)) == Set(onA.cards[0].history.map(\.id)))
        // Danach stabil: noch einmal einmischen ändert nichts.
        let again = SyncMerge.merge(localCards: onA.cards, localTests: [], localDeleted: [],
                                    remote: SyncData(cards: onB.cards, tests: [], deleted: []))
        #expect(again.cards[0].balance == 35)
        #expect(again.cards[0].history.count == 2)
    }

    /// Beide Richtungen mischen und prüfen, dass beide Geräte beim selben Guthaben landen.
    private func mergedBalance(_ a: GiftCard, _ b: GiftCard) -> (onA: Double, onB: Double) {
        let onA = SyncMerge.merge(localCards: [a], localTests: [], localDeleted: [], remote: SyncData(cards: [b], tests: [], deleted: []))
        let onB = SyncMerge.merge(localCards: [b], localTests: [], localDeleted: [], remote: SyncData(cards: [a], tests: [], deleted: []))
        return (onA.cards[0].balance, onB.cards[0].balance)
    }

    @Test("Stand laut Bon auf beiden Geräten gleichzeitig: nicht doppelt abgezogen")
    func concurrentSetBalance() {
        let base = voucher(value: 30, modified: day(2026, 1, 1))
        var a = base
        a.setBalance(10, at: day(2026, 2, 1))
        var b = base
        b.setBalance(10, at: day(2026, 2, 2))
        let r = mergedBalance(a, b)
        #expect(r.onA == 10 && r.onB == 10)
    }

    @Test("Einlösung auf A, danach Stand laut Bon auf B: der Bon gilt")
    func redeemThenSetBalance() {
        let base = voucher(value: 30, modified: day(2026, 1, 1))
        var a = base
        a.redeem(10, at: day(2026, 2, 1))
        var b = base
        b.setBalance(10, at: day(2026, 2, 2))
        let r = mergedBalance(a, b)
        #expect(r.onA == 10 && r.onB == 10)
    }

    @Test("Stand laut Bon auf B, danach Einlösung auf A: Einlösung wird vom Bon-Stand abgezogen")
    func setBalanceThenRedeem() {
        let base = voucher(value: 30, modified: day(2026, 1, 1))
        var b = base
        b.setBalance(15, at: day(2026, 2, 1))
        var a = base
        a.redeem(10, at: day(2026, 2, 2))
        let r = mergedBalance(a, b)
        #expect(r.onA == 5 && r.onB == 5)
    }

    @Test("Rückgängig nach einem Sync verliert die eingemischte Buchung nicht")
    func undoAfterMergeKeepsForeignRedemption() {
        let base = voucher(value: 50, modified: day(2026, 1, 1))
        var b = base
        b.redeem(5, at: day(2026, 2, 1))
        var a = base
        let state = RedemptionUndo(a)
        a.redeem(10, at: day(2026, 2, 2))
        let mine = a.history.last!.id
        var merged = SyncMerge.merge(localCards: [a], localTests: [], localDeleted: [],
                                     remote: SyncData(cards: [b], tests: [], deleted: [])).cards[0]
        #expect(merged.balance == 35)
        #expect(merged.history.last?.id == mine)
        merged.undo(entry: mine, restoring: state)
        #expect(merged.balance == 45)
        #expect(merged.history.count == 1)
    }

    @Test("Zurückgenommene Buchung kommt über den Sync nicht zurück")
    func undoneStaysUndone() {
        var a = voucher(value: 50, modified: day(2026, 1, 1))
        a.redeem(10, at: day(2026, 2, 1))
        let entry = a.history[0].id
        // Gerät B hat die Buchung bekommen und nimmt sie zurück (neuer, mit Löschvermerk).
        var b = a
        b.undo(entry: entry, restoring: nil)
        b.modifiedAt = day(2026, 2, 3)
        let onA = SyncMerge.merge(localCards: [a], localTests: [], localDeleted: [],
                                  remote: SyncData(cards: [b], tests: [], deleted: [entry]))
        #expect(onA.cards[0].balance == 50)
        #expect(onA.cards[0].history.isEmpty)
        // Auch wenn A später etwas anderes ändert und damit „gewinnt“.
        var a2 = a
        a2.location = .wallet
        a2.modifiedAt = day(2026, 2, 5)
        let onB = SyncMerge.merge(localCards: [b], localTests: [], localDeleted: [entry],
                                  remote: SyncData(cards: [a2], tests: [], deleted: []))
        #expect(onB.cards[0].balance == 50)
        #expect(onB.cards[0].history.isEmpty)
        #expect(onB.cards[0].location == .wallet)
    }

    @Test("Ohne neue Buchungen bleibt die Gewinner-Fassung unverändert")
    func noChangeWithoutExtras() {
        var local = voucher(modified: day(2026, 1, 1))
        local.redeem(5, at: day(2026, 1, 2))
        var remote = local
        remote.location = .wallet
        remote.modifiedAt = day(2026, 3, 1)
        let r = SyncMerge.merge(localCards: [local], localTests: [], localDeleted: [], remote: SyncData(cards: [remote], tests: [], deleted: []))
        #expect(r.cards[0] == remote)
    }

    @Test("Eingelöst-Stempel eines Codes von der anderen Seite gilt")
    func stampFromOtherSide() {
        let base = voucher(.discountCode, value: 0, balance: 0, modified: day(2026, 1, 1))
        var a = base
        a.markRedeemed(at: day(2026, 2, 1))
        var b = base
        b.location = .wallet
        b.modifiedAt = day(2026, 2, 2)
        let r = SyncMerge.merge(localCards: [a], localTests: [], localDeleted: [], remote: SyncData(cards: [b], tests: [], deleted: []))
        #expect(r.cards[0].redeemedAt != nil)
        #expect(r.cards[0].location == .wallet)
    }
}

@Suite("Löschvermerke")
struct TombstoneTests {
    @Test("Älter als 180 Tage wird vergessen, neue behalten ihr frühestes Datum")
    func prune() {
        let now = day(2026, 9, 27)
        let old = UUID(), fresh = UUID(), incoming = UUID()
        let dates = [old: now.addingTimeInterval(-181 * 86_400), fresh: now.addingTimeInterval(-10 * 86_400)]
        #expect(Set(Tombstones.pruned(dates, now: now).keys) == [fresh])
        let merged = Tombstones.merged(dates, ids: [fresh, incoming], dates: [fresh: now], now: now)
        #expect(merged[fresh] == dates[fresh])
        #expect(merged[incoming] == now)
    }
}

@Suite("Fotos als Dateien")
struct PhotoFileTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "restwert-photos-\(UUID().uuidString)")
    }

    @Test("Alte Datei mit eingebettetem Foto: lesbar, beim Speichern umgezogen, danach wieder vollständig")
    func migrateAndRoundTrip() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        var withPhoto = voucher()
        withPhoto.photo = Data((0..<5000).map { UInt8($0 % 251) })
        let plain = voucher()
        // Altes Format: Foto eingebettet, nur `deleted` ohne Datum.
        let deletedID = UUID()
        let legacy = #"{"cards":\#(String(decoding: try JSONEncoder().encode([withPhoto, plain]), as: UTF8.self)),"tests":[],"deleted":["\#(deletedID.uuidString)"]}"#
        let old = try JSONDecoder().decode(StoredState.self, from: Data(legacy.utf8))
        #expect(old.cards.first?.photo == withPhoto.photo)
        #expect(old.photos == nil)
        let now = Date.now
        #expect(old.tombstones(now: now) == [deletedID: now])

        let files = PhotoFiles(directory: dir)
        let (disk, keep) = files.prepare(StoredState(cards: old.cards, tests: [], deletedAt: old.tombstones(now: now), pinChanged: [:]),
                                         pending: [])
        #expect(keep == [withPhoto.id])
        #expect(disk.cards.allSatisfy { $0.photo == nil })
        let json = try JSONEncoder().encode(disk)
        #expect(json.count < 2000)   // kein Base64 mehr in der Datei
        #expect(FileManager.default.fileExists(atPath: files.url(for: withPhoto.id).path))

        // Neu starten: JSON lesen, Fotos aus den Dateien nachladen.
        let back = try JSONDecoder().decode(StoredState.self, from: json)
        let loaded = PhotoFiles(directory: dir).load(back.photos ?? [])
        #expect(loaded[withPhoto.id] == withPhoto.photo)
        #expect(back.deletedAt?[deletedID] != nil)
    }

    @Test("Rückseitenfoto als eigene Datei: nicht in der JSON, nach Neustart wieder da, Verweis bleibt ohne Laden")
    func backPhotoFile() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        var a = voucher()
        a.photoBack = Data(repeating: 7, count: 4000)
        let files = PhotoFiles(directory: dir)
        let (disk, _) = files.prepare(StoredState(cards: [a], tests: [], deletedAt: [:], pinChanged: [:]), pending: [])
        #expect(disk.cards[0].photoBack == nil)
        #expect(disk.backPhotos == [a.id])
        let json = try JSONEncoder().encode(disk)
        #expect(json.count < 2000)
        let reread = try JSONDecoder().decode(StoredState.self, from: json)
        #expect(PhotoFiles(directory: dir).loadBacks(reread.backPhotos ?? [])[a.id] == a.photoBack)
        // Nicht geladen (z. B. Gerät gesperrt): Verweis bleibt, Datei wird beim Aufräumen nicht gelöscht.
        let again = PhotoFiles(directory: dir)
        let (disk2, keep2) = again.prepare(StoredState(cards: reread.cards, tests: [], deletedAt: [:], pinChanged: [:]), pending: [])
        #expect(disk2.backPhotos == [a.id])
        again.removeAll(except: keep2, removable: [a.id])
        #expect(FileManager.default.fileExists(atPath: again.backURL(for: a.id).path))
        // Gutschein gelöscht: Rückseite verschwindet beim Aufräumen.
        let (_, keep3) = again.prepare(StoredState(cards: [], tests: [], deletedAt: [a.id: .now], pinChanged: [:]), pending: [])
        again.removeAll(except: keep3, removable: [a.id])
        #expect(!FileManager.default.fileExists(atPath: again.backURL(for: a.id).path))
    }

    @Test("Noch nicht geladene Fotos bleiben erhalten; entfernte Fotos verschwinden erst nach dem Aufräumen")
    func pendingAndCleanup() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        var a = voucher()
        a.photo = Data([1, 2, 3])
        var b = voucher()
        b.photo = Data([4, 5, 6])
        let files = PhotoFiles(directory: dir)
        _ = files.prepare(StoredState(cards: [a, b], tests: [], deletedAt: [:], pinChanged: [:]), pending: [])
        // a noch nicht geladen (Foto nil, aber vorgemerkt), b entfernt.
        a.photo = nil
        b.photo = nil
        let (disk, keep) = files.prepare(StoredState(cards: [a, b], tests: [], deletedAt: [:], pinChanged: [:]), pending: [a.id])
        #expect(keep == [a.id])
        #expect(disk.photos == [a.id])
        files.removeAll(except: keep)
        #expect(FileManager.default.fileExists(atPath: files.url(for: a.id).path))
        #expect(!FileManager.default.fileExists(atPath: files.url(for: b.id).path))
    }

    @Test("Kaputter Eintrag wird übersprungen und gezählt")
    func lossy() throws {
        let good = try String(decoding: JSONEncoder().encode(voucher()), as: UTF8.self)
        let json = #"{"cards":[\#(good),{"id":"kein-uuid"}],"tests":[]}"#
        let s = try JSONDecoder().decode(StoredState.self, from: Data(json.utf8))
        #expect(s.cards.count == 1)
        #expect(s.dropped == 1)
    }
}

@Suite("Nachbesserung: Stempel, Rückholen, Fotos")
struct FollowUpTests {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "restwert-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("Zurückgenommener Stempel bleibt zurückgenommen, auch wenn die andere Seite neuer ist")
    func undoneStampStaysUndone() {
        var a = voucher(.discountCode, value: 0, balance: 0, modified: day(2026, 1, 1))
        a.markRedeemed(at: day(2026, 2, 1))
        let stamp = a.history[0].id
        // Gerät A nimmt den Stempel zurück (ohne gemerkten Zustand, z. B. nach Neustart).
        var undone = a
        undone.undo(entry: stamp, restoring: nil)
        undone.modifiedAt = day(2026, 2, 2)
        #expect(undone.redeemedAt == nil)
        // Gerät B ändert danach etwas anderes und ist damit neuer.
        var b = a
        b.location = .wallet
        b.modifiedAt = day(2026, 2, 5)
        let onA = SyncMerge.merge(localCards: [undone], localTests: [], localDeleted: [stamp],
                                  remote: SyncData(cards: [b], tests: [], deleted: []))
        #expect(onA.cards[0].redeemedAt == nil)
        #expect(onA.cards[0].history.isEmpty)
        #expect(onA.cards[0].location == .wallet)
        let onB = SyncMerge.merge(localCards: [b], localTests: [], localDeleted: [],
                                  remote: SyncData(cards: [undone], tests: [], deleted: [stamp]))
        #expect(onB.cards[0].redeemedAt == nil)
        #expect(onB.cards[0].isOpen)
    }

    @Test("Eigene Karte zurückholen: Kassentests ziehen mit und überstehen den Sync")
    func restoredCardKeepsTests() {
        let a = voucher()
        var cards = [a]
        var tests = [TestResult(cardID: a.id, merchantID: "thalia", merchantName: "Thalia", date: .now, success: true,
                                format: .code128, isExample: false)]
        var deleted: Set<UUID> = []
        CardEdits.delete(a.id, cards: &cards, deleted: &deleted)
        let id = CardEdits.restoreDeleted(a, cards: &cards, tests: &tests)
        #expect(tests[0].cardID == id)
        let r = SyncMerge.merge(localCards: cards, localTests: tests, localDeleted: deleted,
                                remote: SyncData(cards: [], tests: [], deleted: [a.id]))
        #expect(r.tests.count == 1)
        #expect(r.cards.map(\.id) == [id])
    }

    @Test("Fotos unbekannter Gutscheine bleiben liegen; nur fehlende Dateien gelten als erledigt")
    func photosOfUnknownCardsSurvive() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let files = PhotoFiles(directory: dir)
        let known = UUID(), unknown = UUID(), gone = UUID()
        _ = files.write([known: Data([1]), unknown: Data([2])])
        #expect(files.missing([known, unknown, gone]) == [gone])
        // Nur Gutscheine, die der Store kennt, dürfen aufgeräumt werden.
        files.removeAll(except: [], removable: [known])
        #expect(!FileManager.default.fileExists(atPath: files.url(for: known).path))
        #expect(FileManager.default.fileExists(atPath: files.url(for: unknown).path))
        // Umzug unter neue ID (Rückholen nach dem Löschen).
        let moved = UUID()
        files.move(from: unknown, to: moved)
        #expect(files.load([moved])[moved] == Data([2]))
    }
}
