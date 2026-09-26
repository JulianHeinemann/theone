import Foundation
import Observation
import UserNotifications
import RestwertKit

/// Lokaler Datenbestand: Gutscheine, Kassentests und Löschungen. Speichert als Datei mit Dateischutz.
@Observable
final class Store {
    private(set) var cards: [GiftCard] = []
    private(set) var tests: [TestResult] = []
    /// IDs gelöschter Gutscheine, damit sie beim Sync nicht wieder auftauchen.
    private(set) var deletedIDs: Set<UUID> = []
    /// Wird nach jeder lokalen Änderung aufgerufen (z. B. um zu synchronisieren).
    @ObservationIgnored var onChange: (() -> Void)?

    @ObservationIgnored private let fileURL: URL

    private struct Snapshot: Codable {
        var cards: [GiftCard]
        var tests: [TestResult]
        var deleted: [UUID]?
    }

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let dir = URL.applicationSupportDirectory
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.fileURL = dir.appending(path: "restwert.json")
        }
        load()
    }

    // MARK: Persistenz

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            seedExamples()
            return
        }
        cards = snap.cards
        tests = snap.tests
        deletedIDs = Set(snap.deleted ?? [])
    }

    private func save(notify: Bool = true) {
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

    /// Was auf den Server geht: ohne Fotos, PINs und Beispiele.
    var syncPayload: SyncData { .outgoing(cards: cards, tests: tests, deleted: deletedIDs) }

    /// Server-Stand einmischen (neuere Änderung gewinnt, Löschungen gelten überall).
    func merge(_ remote: SyncData) {
        let result = SyncMerge.merge(localCards: cards, localTests: tests, localDeleted: deletedIDs, remote: remote)
        cards = result.cards
        tests = result.tests
        deletedIDs = result.deleted
        save(notify: false)
    }

    // MARK: Abfragen

    var warnDays: Int { UserDefaults.standard.object(forKey: "warnDays") as? Int ?? 30 }
    var activeCards: [GiftCard] { CardQueries.sorted(cards, by: .expiry).filter(\.isActive) }
    var total: Double { CardQueries.openTotal(cards) }
    var totalValue: Double { CardQueries.originalTotal(cards) }
    var bonLines: [BonLine] { CardQueries.bonLines(cards) }
    var hasExamples: Bool { cards.contains(where: \.isExample) || tests.contains(where: \.isExample) }

    func cards(sortedBy order: CardSortOrder) -> [GiftCard] { CardQueries.sorted(cards, by: order) }
    func soonCount(warnDays: Int) -> Int { CardQueries.expiringSoon(cards, warnDays: warnDays).count }
    func card(_ id: UUID) -> GiftCard? { cards.first { $0.id == id } }

    // MARK: Änderungen

    private func update(_ id: UUID, _ change: (inout GiftCard) -> Void) {
        guard let i = cards.firstIndex(where: { $0.id == id }) else { return }
        change(&cards[i])
        cards[i].modifiedAt = .now
        save()
    }

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

    func redeem(_ id: UUID, amount: Double, store storeName: String = "", note: String = "") {
        guard amount > 0 else { return }
        update(id) { _ = $0.redeem(amount, store: storeName, note: note) }
    }

    /// Rabattcodes und Coupons: als Ganzes einlösen und stempeln.
    func markRedeemed(_ id: UUID, store storeName: String = "") {
        update(id) { $0.markRedeemed(store: storeName) }
    }

    func setLocation(_ id: UUID, _ location: StorageLocation, note: String) {
        update(id) {
            $0.location = location
            $0.locationNote = note
        }
    }

    func addTest(card: GiftCard, success: Bool, store storeName: String, note: String, amount: Double?) {
        if success, let amount, amount > 0 {
            redeem(card.id, amount: min(amount, card.balance), store: storeName, note: "Kassentest")
        }
        tests.append(TestResult(cardID: card.id, merchantID: card.merchantID, merchantName: card.name, date: .now,
                                success: success, store: storeName, note: note, format: card.format, amount: amount))
        save()
    }

    func clearExamples() {
        cards.removeAll(where: \.isExample)
        tests.removeAll(where: \.isExample)
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
        let safe = cards.map { c -> GiftCard in
            var x = c
            x.photo = nil
            x.pin = c.pin.isEmpty ? "" : "(gesetzt)"
            return x
        }
        let enc = APICoding.encoder
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(Export(cards: safe, tests: tests)) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Beispiele

    private func seedExamples() {
        let cal = Calendar.current
        let y = cal.component(.year, from: .now)
        func d(_ y: Int, _ m: Int, _ day: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: day)) ?? .now }
        func inDays(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: .now) ?? .now }

        var thalia = GiftCard(merchantID: "thalia", number: "6300981274561234", format: .code128, pin: "4821", value: 25, balance: 25,
                              received: d(y - 1, 12, 20), expires: d(y + 2, 12, 31), isExample: true)
        thalia.redeem(12.60, store: "Thalia Beispielstadt", at: inDays(-12))
        var douglas = GiftCard(merchantID: "douglas", number: "4099875102233441", format: .code128, pin: "1337", value: 40, balance: 40,
                               received: d(y - 1, 6, 2), expires: d(y + 1, 3, 31), isExample: true)
        douglas.redeem(16.15, store: "Douglas Beispielstadt", at: inDays(-40))
        let discount = GiftCard(kind: .discountCode, merchantID: "zalando", number: "HERBST15-K7Q2", format: .text, value: 0, balance: 0,
                                percent: 15, received: d(y, 9, 1), expires: inDays(12), location: .inbox,
                                locationNote: "Newsletter vom 1.9.", isExample: true)
        cards = [
            discount,
            GiftCard(merchantID: "ikea", number: "6275980123456789012", format: .code128, value: 50, balance: 50,
                     received: d(y - 3, 5, 11), expires: inDays(24), isExample: true),
            thalia,
            douglas,
            GiftCard(merchantID: "amazon", number: "AQ7K-9XWP-3HTR", format: .text, value: 30, balance: 30,
                     received: d(y, 2, 14), expires: d(y + 3, 12, 31), location: .phone, isExample: true),
            GiftCard(merchantID: "stadtgutschein", number: "SG-2291-7730", format: .qr, value: 20, balance: 20,
                     received: d(y, 1, 5), expires: inDays(140), location: .wallet, isExample: true),
        ]
        tests = [
            TestResult(merchantID: "thalia", merchantName: "Thalia", date: .now, success: true, store: "Beispielstadt",
                       format: .code128, amount: 12.60, isExample: true),
            TestResult(merchantID: "douglas", merchantName: "Douglas", date: .now, success: false, store: "Beispielstadt",
                       note: "Kasse wollte Plastikkarte", format: .code128, isExample: true),
        ]
    }

    // MARK: Erinnerungen

    func requestNotifications() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        await scheduleReminders()
    }

    func scheduleReminders() async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard UserDefaults.standard.object(forKey: "reminders") as? Bool ?? true else { return }
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }
        let cal = Calendar.current
        for c in cards where c.isActive && !c.isExample {
            for days in [30, 7] {
                guard let fire = cal.date(byAdding: .day, value: -days, to: c.expires), fire > .now else { continue }
                var comps = cal.dateComponents([.year, .month, .day], from: fire)
                comps.hour = 10
                let content = UNMutableNotificationContent()
                content.title = "\(c.name): noch \(days) Tage"
                content.body = "\(c.headline) verfällt am \(c.expires.dayMonthYear). Jetzt einlösen."
                content.sound = .default
                let request = UNNotificationRequest(identifier: "\(c.id.uuidString)-\(days)", content: content,
                                                    trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
                try? await center.add(request)
            }
        }
    }
}
