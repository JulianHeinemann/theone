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
        // PINs zusätzlich in den iCloud-Schlüsselbund, damit sie auf neuen Geräten ankommen, ohne je in iCloud-Datenbank zu liegen.
        if UserDefaults.standard.bool(forKey: "iCloudSync") {
            for c in cards where !c.isExample && !c.pin.isEmpty { PinVault.store(c.pin, for: c.id) }
        }
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

    /// iCloud-Stand einmischen (neuere Änderung gewinnt, Löschungen gelten überall).
    func merge(_ remote: SyncData) {
        let result = SyncMerge.merge(localCards: cards, localTests: tests, localDeleted: deletedIDs, remote: remote)
        cards = result.cards.map { c in
            guard c.pin.isEmpty, let pin = PinVault.pin(for: c.id) else { return c }
            var x = c
            x.pin = pin
            return x
        }
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

    /// Zieht ab und gibt die ID des Verlaufseintrags zurück, damit man es rückgängig machen kann.
    @discardableResult
    func redeem(_ id: UUID, amount: Double, store storeName: String = "", note: String = "") -> UUID? {
        guard amount > 0 else { return nil }
        update(id) { _ = $0.redeem(amount, store: storeName, note: note) }
        return card(id)?.history.last?.id
    }

    /// Letzten Abzug zurücknehmen: Eintrag entfernen, Betrag wieder gutschreiben.
    func undoRedemption(_ cardID: UUID, entry: UUID) {
        update(cardID) { c in
            guard let i = c.history.firstIndex(where: { $0.id == entry }) else { return }
            c.balance = ((c.balance + c.history[i].amount) * 100).rounded() / 100
            c.history.remove(at: i)
        }
    }

    /// Rabattcodes und Coupons: als Ganzes einlösen und stempeln.
    func markRedeemed(_ id: UUID, store storeName: String = "") {
        update(id) { $0.markRedeemed(store: storeName) }
    }

    func setArchived(_ id: UUID, _ archived: Bool) {
        update(id) { $0.archivedAt = archived ? .now : nil }
        Task { await scheduleReminders() }
    }

    func setReminder(_ id: UUID, _ date: Date?) {
        update(id) { $0.reminderAt = date }
        Task { await scheduleReminders() }
    }

    func setLocation(_ id: UUID, _ location: StorageLocation, note: String) {
        update(id) {
            $0.location = location
            $0.locationNote = note
        }
    }

    @discardableResult
    func addTest(card: GiftCard, success: Bool, store storeName: String, note: String, amount: Double?) -> UUID? {
        var entry: UUID?
        if success, let amount, amount > 0 {
            entry = redeem(card.id, amount: min(amount, card.balance), store: storeName, note: "An der Kasse")
        }
        tests.append(TestResult(cardID: card.id, merchantID: card.merchantID, merchantName: card.name, date: .now,
                                success: success, store: storeName, note: note, format: card.format, amount: amount))
        save()
        return entry
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

    // MARK: Sicherung

    private struct Backup: Codable { var cards: [GiftCard]; var tests: [TestResult] }

    /// Vollständige Sicherung als Datei (mit PINs, ohne Fotos), zum Aufbewahren in Dateien oder iCloud Drive.
    func backupFile() -> URL? {
        let own = cards.filter { !$0.isExample }.map { c -> GiftCard in var x = c; x.photo = nil; return x }
        let enc = APICoding.encoder
        guard let data = try? enc.encode(Backup(cards: own, tests: tests.filter { !$0.isExample })) else { return nil }
        let url = URL.temporaryDirectory.appending(path: "Restwert-Sicherung-\(Date.now.formatted(.iso8601.year().month().day())).restwert.json")
        return (try? data.write(to: url, options: .completeFileProtection)).map { url }
    }

    /// Lesbare Liste für Tabellen (ohne PINs).
    func csvFile() -> URL? {
        let head = "Händler;Für;Art;Startwert;Guthaben;Gültig bis;Code;Status"
        let rows = cards.filter { !$0.isExample }.map { c in
            [c.name, c.owner, c.kind.label,
             c.kind.isValueBased ? c.value.formatted(.number.precision(.fractionLength(2))) : c.headline,
             c.kind.isValueBased ? c.balance.formatted(.number.precision(.fractionLength(2))) : "",
             c.expires.dayMonthYear, c.number,
             c.isArchived ? "archiviert" : c.status(warnDays: warnDays).label]
                .map { $0.replacingOccurrences(of: ";", with: ",") }.joined(separator: ";")
        }
        let url = URL.temporaryDirectory.appending(path: "Restwert-Gutscheine.csv")
        let text = ([head] + rows).joined(separator: "\n")
        return (try? Data(("\u{FEFF}" + text).utf8).write(to: url)).map { url }
    }

    /// Sicherung einspielen; neuere Stände gewinnen, nichts wird doppelt angelegt. Gibt die Zahl der Gutscheine zurück.
    func restore(from url: URL) throws -> Int {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let backup = try APICoding.decoder.decode(Backup.self, from: Data(contentsOf: url))
        merge(SyncData(cards: backup.cards, tests: backup.tests, deleted: []))
        save()
        return backup.cards.count
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
        let leadDays = ReminderPrefs.days
        let hour = ReminderPrefs.hour
        for c in cards where c.isActive && !c.isExample {
            for days in leadDays {
                guard let fire = cal.date(byAdding: .day, value: -days, to: c.expires), fire > .now else { continue }
                var comps = cal.dateComponents([.year, .month, .day], from: fire)
                comps.hour = hour
                let content = UNMutableNotificationContent()
                content.title = days == 1 ? "\(c.name): läuft morgen ab" : "\(c.name): noch \(days) Tage"
                content.body = "\(c.headline) verfällt am \(c.expires.dayMonthYear). Jetzt einlösen."
                content.sound = .default
                let request = UNNotificationRequest(identifier: "\(c.id.uuidString)-\(days)", content: content,
                                                    trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
                try? await center.add(request)
            }
            if let custom = c.reminderAt, custom > .now {
                let content = UNMutableNotificationContent()
                content.title = "\(c.name): deine Erinnerung"
                content.body = "\(c.headline) übrig, gültig bis \(c.expires.dayMonthYear)."
                content.sound = .default
                let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: custom)
                let request = UNNotificationRequest(identifier: "\(c.id.uuidString)-custom", content: content,
                                                    trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
                try? await center.add(request)
            }
        }
    }
}

/// Wann vor dem Ablauf erinnert wird. Gespeichert in UserDefaults, damit Einstellungen und Store dieselben Werte sehen.
enum ReminderPrefs {
    static let choices = [60, 30, 14, 7, 1]
    static let daysKey = "reminderDays"
    static let hourKey = "reminderHour"

    static var days: [Int] {
        let raw = UserDefaults.standard.string(forKey: daysKey) ?? "30,7"
        return raw.split(separator: ",").compactMap { Int($0) }.sorted(by: >)
    }

    static var hour: Int { UserDefaults.standard.object(forKey: hourKey) as? Int ?? 10 }

    static func describe(days: [Int], hour: Int) -> String {
        guard !days.isEmpty else { return "Keine Vorlaufzeit gewählt" }
        let list = days.sorted(by: >).map { $0 == 1 ? "1 Tag" : "\($0) Tage" }
        return list.formatted(.list(type: .and)) + " vorher, um \(hour) Uhr"
    }
}
