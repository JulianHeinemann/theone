import Foundation
import Observation
import UserNotifications

@MainActor
@Observable
final class Store {
    var cards: [GiftCard] = []
    var tests: [TestResult] = []
    /// Datei, die über „Teilen → Restwert“ oder „Öffnen in“ angekommen ist.
    var incomingURL: URL?
    /// IDs gelöschter Gutscheine, damit sie beim Sync nicht wieder auftauchen.
    var deletedIDs: Set<UUID> = []
    /// Wird nach jeder lokalen Änderung aufgerufen (z. B. um zu synchronisieren).
    @ObservationIgnored var onChange: (@MainActor () -> Void)?

    private let fileURL: URL

    private struct Snapshot: Codable {
        var cards: [GiftCard]
        var tests: [TestResult]
        var deleted: [UUID]?
    }

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("restwert.json")
        load()
    }

    // MARK: Persistence

    private func load() {
        if let data = try? Data(contentsOf: fileURL),
           let snap = try? JSONDecoder().decode(Snapshot.self, from: data) {
            cards = snap.cards
            tests = snap.tests
            deletedIDs = Set(snap.deleted ?? [])
        } else {
            seedExamples()
        }
    }

    func save(notify: Bool = true) {
        do {
            let data = try JSONEncoder().encode(Snapshot(cards: cards, tests: tests, deleted: Array(deletedIDs)))
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            print("Restwert: Speichern fehlgeschlagen:", error)
        }
        Task { await scheduleReminders() }
        if notify { onChange?() }
    }

    // MARK: Sync

    struct SyncData: Codable {
        var cards: [GiftCard]
        var tests: [TestResult]
        var deleted: [UUID]
    }

    /// Was auf den Server geht: ohne Fotos und PINs, ohne Beispiele.
    func syncPayload() -> SyncData {
        let safe = cards.filter { !$0.isExample }.map { c -> GiftCard in
            var x = c
            x.photo = nil
            x.pin = ""
            return x
        }
        return SyncData(cards: safe, tests: tests.filter { !$0.isExample }, deleted: Array(deletedIDs))
    }

    /// Server-Stand einmischen: neuere Änderung gewinnt, Löschungen gelten überall, PIN und Foto bleiben lokal.
    func merge(_ remote: SyncData) {
        deletedIDs.formUnion(remote.deleted)
        var byID = Dictionary(cards.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for r in remote.cards {
            if let local = byID[r.id] {
                if r.modifiedAt > local.modifiedAt {
                    var merged = r
                    merged.pin = local.pin
                    merged.photo = local.photo
                    byID[r.id] = merged
                }
            } else {
                byID[r.id] = r
            }
        }
        cards = byID.values.filter { !deletedIDs.contains($0.id) }.sorted { $0.expires < $1.expires }
        let knownTests = Set(tests.map(\.id))
        tests += remote.tests.filter { !knownTests.contains($0.id) }
        save(notify: false)
    }

    // MARK: Queries

    var warnDays: Int { UserDefaults.standard.object(forKey: "warnDays") as? Int ?? 30 }

    var sortedCards: [GiftCard] { cards(sortedBy: .expiry) }
    var activeCards: [GiftCard] { sortedCards.filter { $0.isOpen && $0.daysLeft >= 0 } }
    var total: Double { cards.filter { $0.kind.isValueBased && $0.daysLeft >= 0 }.reduce(0) { $0 + $1.balance } }
    var totalValue: Double { cards.filter { $0.kind.isValueBased && $0.daysLeft >= 0 }.reduce(0) { $0 + $1.value } }
    func soonCount(warnDays: Int) -> Int { cards.filter { $0.status(warnDays: warnDays) == .expiringSoon }.count }
    var soonCount: Int { soonCount(warnDays: warnDays) }

    func cards(sortedBy order: CardSortOrder) -> [GiftCard] {
        cards.sorted { a, b in
            // Offene Gutscheine zuerst, Eingelöste und Abgelaufene ans Ende
            let ra = a.isOpen && a.daysLeft >= 0, rb = b.isOpen && b.daysLeft >= 0
            if ra != rb { return ra }
            switch order {
            case .expiry: return a.expires < b.expires
            case .value: return a.balance > b.balance
            case .shop: return a.name.localizedCompare(b.name) == .orderedAscending
            }
        }
    }
    var hasExamples: Bool { cards.contains { $0.isExample } || tests.contains { $0.isExample } }

    var bonLines: [BonLine] {
        cards.flatMap { c in c.history.map { BonLine(cardID: c.id, cardName: c.name, merchantID: c.merchantID, redemption: $0) } }
            .sorted { $0.redemption.date > $1.redemption.date }
    }

    func card(_ id: UUID) -> GiftCard? { cards.first { $0.id == id } }

    // MARK: Mutations

    private func touch(_ i: Int) { cards[i].modifiedAt = .now }

    func upsert(_ card: GiftCard) {
        var c = card
        c.isExample = false
        c.modifiedAt = .now
        if let i = cards.firstIndex(where: { $0.id == c.id }) { cards[i] = c } else { cards.append(c) }
        save()
    }

    func delete(_ id: UUID) {
        cards.removeAll { $0.id == id }
        deletedIDs.insert(id)
        save()
    }

    @discardableResult
    func redeem(_ id: UUID, amount: Double, store storeName: String = "", note: String = "") -> Double? {
        guard let i = cards.firstIndex(where: { $0.id == id }), amount > 0 else { return nil }
        let newBalance = max(0, ((cards[i].balance - amount) * 100).rounded() / 100)
        cards[i].balance = newBalance
        touch(i)
        cards[i].history.append(Redemption(date: .now, amount: amount, store: storeName, note: note, balanceAfter: newBalance))
        save()
        return newBalance
    }

    /// Rabattcodes und Coupons: als Ganzes einlösen und stempeln.
    func markRedeemed(_ id: UUID, store storeName: String = "") {
        guard let i = cards.firstIndex(where: { $0.id == id }) else { return }
        cards[i].redeemedAt = .now
        touch(i)
        cards[i].history.append(Redemption(date: .now, amount: 0, store: storeName, note: "\(cards[i].kind.label) eingelöst", balanceAfter: cards[i].balance))
        save()
    }

    func setLocation(_ id: UUID, _ location: StorageLocation, note: String) {
        guard let i = cards.firstIndex(where: { $0.id == id }) else { return }
        cards[i].location = location
        cards[i].locationNote = note
        touch(i)
        save()
    }

    func addTest(card: GiftCard, success: Bool, store storeName: String, note: String, amount: Double?) {
        if success, let amount, amount > 0 {
            redeem(card.id, amount: amount, store: storeName, note: "Kassentest")
        }
        tests.append(TestResult(cardID: card.id, merchantID: card.merchantID, merchantName: card.name, date: .now,
                                success: success, store: storeName, note: note, format: card.format, amount: amount))
        save()
    }

    func clearExamples() {
        cards.removeAll { $0.isExample }
        tests.removeAll { $0.isExample }
        save()
    }

    func resetAll() {
        deletedIDs.formUnion(cards.filter { !$0.isExample }.map(\.id))
        cards = []
        tests = []
        save()
    }

    func exportJSON() -> String {
        struct Export: Codable { var cards: [GiftCard]; var tests: [TestResult] }
        let safe = cards.map { c -> GiftCard in var x = c; x.photo = nil; x.pin = c.pin.isEmpty ? "" : "(gesetzt)"; return x }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(Export(cards: safe, tests: tests)) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Examples

    private func seedExamples() {
        let cal = Calendar.current
        let y = cal.component(.year, from: .now)
        func d(_ y: Int, _ m: Int, _ day: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: day)) ?? .now }
        var thalia = GiftCard(merchantID: "thalia", number: "6300981274561234", format: .code128, pin: "4821", value: 25, balance: 12.40,
                              received: d(y - 1, 12, 20), expires: d(y + 2, 12, 31), isExample: true)
        thalia.history = [Redemption(date: cal.date(byAdding: .day, value: -12, to: .now) ?? .now, amount: 12.60, store: "Thalia Beispielstadt", balanceAfter: 12.40)]
        var douglas = GiftCard(merchantID: "douglas", number: "4099875102233441", format: .code128, pin: "1337", value: 40, balance: 23.85,
                               received: d(y - 1, 6, 2), expires: d(y + 1, 3, 31), isExample: true)
        douglas.history = [Redemption(date: cal.date(byAdding: .day, value: -40, to: .now) ?? .now, amount: 16.15, store: "Douglas Beispielstadt", balanceAfter: 23.85)]
        let rabatt = GiftCard(kind: .discountCode, merchantID: "zalando", number: "HERBST15-K7Q2", format: .text, value: 0, balance: 0, percent: 15,
                              received: d(y, 9, 1), expires: cal.date(byAdding: .day, value: 12, to: .now) ?? .now, location: .inbox, locationNote: "Newsletter vom 1.9.", isExample: true)
        cards = [
            rabatt,
            GiftCard(merchantID: "ikea", number: "6275980123456789012", format: .code128, value: 50, balance: 50,
                     received: d(y - 3, 5, 11), expires: cal.date(byAdding: .day, value: 24, to: .now) ?? .now, isExample: true),
            thalia,
            douglas,
            GiftCard(merchantID: "amazon", number: "AQ7K-9XWP-3HTR", format: .text, value: 30, balance: 30,
                     received: d(y, 2, 14), expires: d(y + 3, 12, 31), isExample: true),
            GiftCard(merchantID: "stadtgutschein", number: "SG-2291-7730", format: .qr, value: 20, balance: 20,
                     received: d(y, 1, 5), expires: cal.date(byAdding: .day, value: 140, to: .now) ?? .now, isExample: true),
        ]
        tests = [
            TestResult(merchantID: "thalia", merchantName: "Thalia", date: .now, success: true, store: "Beispielstadt", note: "", format: .code128, amount: 12.60, isExample: true),
            TestResult(merchantID: "douglas", merchantName: "Douglas", date: .now, success: false, store: "Beispielstadt", note: "Kasse wollte Plastikkarte", format: .code128, amount: nil, isExample: true),
        ]
    }

    // MARK: Reminders

    func requestNotifications() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        await scheduleReminders()
    }

    func scheduleReminders() async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        let enabled = UserDefaults.standard.object(forKey: "reminders") as? Bool ?? true
        guard enabled else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let cal = Calendar.current
        for c in cards where c.balance > 0 && !c.isExample {
            for days in [30, 7] {
                guard let fire = cal.date(byAdding: .day, value: -days, to: c.expires), fire > .now else { continue }
                var comps = cal.dateComponents([.year, .month, .day], from: fire)
                comps.hour = 10
                let content = UNMutableNotificationContent()
                content.title = "\(c.name): noch \(days) Tage"
                content.body = "\(c.balance.euro) verfallen am \(c.expires.dayMonthYear). Jetzt einlösen."
                content.sound = .default
                let request = UNNotificationRequest(identifier: "\(c.id.uuidString)-\(days)", content: content,
                                                    trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
                try? await center.add(request)
            }
        }
    }
}
