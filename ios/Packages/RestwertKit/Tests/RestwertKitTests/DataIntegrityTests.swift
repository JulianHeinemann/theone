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
    @Test("Ablaufdatum bleibt derselbe Kalendertag nach Zeitzonenwechsel")
    func expiryStaysSameDay() {
        let berlin = TimeZone(identifier: "Europe/Berlin")!
        var calBerlin = Calendar(identifier: .gregorian)
        calBerlin.timeZone = berlin
        // Im DatePicker gewählt: Mitternacht in Berlin → auf 12:00 normalisiert.
        let picked = day(2027, 3, 31, hour: 0, in: berlin)
        let stored = CalendarDay.noon(picked, calendar: calBerlin)
        var c = voucher()
        c.expires = stored
        for id in ["America/New_York", "America/Los_Angeles", "Asia/Tokyo", "Europe/London", "Asia/Kolkata"] {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: id)!
            let comps = cal.dateComponents([.year, .month, .day], from: c.expires)
            #expect(comps.day == 31 && comps.month == 3, "Zeitzone \(id)")
            let now = cal.date(from: DateComponents(year: 2027, month: 3, day: 30, hour: 23))!
            #expect(c.daysLeft(now: now, calendar: cal) == 1, "Zeitzone \(id)")
        }
        // Ohne Normalisierung wäre es in New York noch der 30.
        var ny = Calendar(identifier: .gregorian)
        ny.timeZone = TimeZone(identifier: "America/New_York")!
        #expect(ny.component(.day, from: picked) == 30)
    }

    @Test("Speichern normalisiert das Ablaufdatum auf 12:00 Uhr")
    func upsertNormalizes() {
        var c = voucher()
        c.expires = day(2027, 3, 31, hour: 0)
        var cards: [GiftCard] = []
        var tests: [TestResult] = []
        CardEdits.upsert(c, cards: &cards, tests: &tests)
        #expect(Calendar.current.component(.hour, from: cards[0].expires) == 12)
        #expect(Calendar.current.component(.day, from: cards[0].expires) == 31)
        #expect(Calendar.current.component(.hour, from: GiftCard.legalExpiry(from: .now)) == 12)
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
