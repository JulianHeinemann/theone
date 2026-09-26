import Foundation
import Observation
import UIKit
import UserNotifications
import RestwertKit

/// Lokaler Datenbestand: Gutscheine, Kassentests und Löschungen. Speichert als Datei mit Dateischutz.
@Observable
final class Store {
    private(set) var cards: [GiftCard] = []
    private(set) var tests: [TestResult] = []
    /// IDs gelöschter Gutscheine und Kassentests, damit sie beim Sync nicht wieder auftauchen.
    private(set) var deletedIDs: Set<UUID> = []
    /// Wird nach jeder lokalen Änderung aufgerufen (z. B. um zu synchronisieren).
    @ObservationIgnored var onChange: (() -> Void)?
    /// Erst `true`, wenn die Datei gelesen wurde (oder noch nicht existiert). Vorher wird nichts gespeichert.
    @ObservationIgnored private(set) var isLoaded = false

    @ObservationIgnored private let fileURL: URL
    /// Datei war beschädigt oder nur teilweise lesbar: vor dem nächsten Schreiben eine Kopie ablegen.
    @ObservationIgnored private var keepCopyBeforeWrite = false
    @ObservationIgnored private var unlockObserver: NSObjectProtocol?
    /// Wann die PIN eines Gutscheins zuletzt auf diesem Gerät geändert wurde (für den Abgleich über den Schlüsselbund).
    @ObservationIgnored private var pinChangedAt: [UUID: Date] = [:]
    /// Zustand vor einem Abzug, je Verlaufseintrag, damit „Rückgängig“ ihn exakt wiederherstellt.
    @ObservationIgnored private var undoStates: [UUID: UndoState] = [:]

    private struct UndoState {
        var value: Double
        var pendingSince: Date?
        var redeemedAt: Date?
        var test: UUID?
    }

    private struct Snapshot: Codable {
        var cards: [GiftCard]
        var tests: [TestResult]
        var deleted: [UUID]?
        var pinChanged: [UUID: Date]?
        /// Einträge, die beim Lesen nicht dekodierbar waren und übersprungen wurden.
        var dropped = 0

        private enum CodingKeys: String, CodingKey { case cards, tests, deleted, pinChanged }

        init(cards: [GiftCard], tests: [TestResult], deleted: [UUID], pinChanged: [UUID: Date]) {
            self.cards = cards
            self.tests = tests
            self.deleted = deleted
            self.pinChanged = pinChanged
        }

        /// Einzelne kaputte Einträge überspringen statt die ganze Datei zu verwerfen.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let rawCards = try c.decode([Lossy<GiftCard>].self, forKey: .cards)
            let rawTests = try c.decodeIfPresent([Lossy<TestResult>].self, forKey: .tests) ?? []
            cards = rawCards.compactMap(\.value)
            tests = rawTests.compactMap(\.value)
            deleted = try? c.decodeIfPresent([UUID].self, forKey: .deleted)
            pinChanged = try? c.decodeIfPresent([UUID: Date].self, forKey: .pinChanged)
            dropped = rawCards.count - cards.count + rawTests.count - tests.count
        }
    }

    private struct Lossy<T: Decodable>: Decodable {
        var value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
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

    /// Beispiele nur, wenn die Datei wirklich fehlt. Ist sie da, aber nicht lesbar (Dateischutz bei gesperrtem Gerät),
    /// bleibt alles unangetastet und es wird nach dem Entsperren erneut geladen.
    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            seedExamples()
            finishLoad()
            return
        }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            print("Restwert: Datei noch nicht lesbar, später erneut:", error)
            retryWhenUnlocked()
            return
        }
        if let snap = try? JSONDecoder().decode(Snapshot.self, from: data) {
            cards = snap.cards
            tests = snap.tests
            deletedIDs = Set(snap.deleted ?? [])
            pinChangedAt = snap.pinChanged ?? [:]
            keepCopyBeforeWrite = snap.dropped > 0
        } else {
            // Nicht dekodierbar: ohne Beispiele leer starten, Original bleibt als .broken-Kopie erhalten.
            print("Restwert: Datei nicht lesbar, wird vor dem nächsten Speichern gesichert")
            keepCopyBeforeWrite = true
        }
        finishLoad()
    }

    private func finishLoad() {
        let late = unlockObserver != nil
        isLoaded = true
        if let unlockObserver { NotificationCenter.default.removeObserver(unlockObserver) }
        unlockObserver = nil
        WidgetBridge.update(cards: cards, total: total)
        if late {
            Task { await scheduleReminders() }
            onChange?()
        }
    }

    private func retryWhenUnlocked() {
        guard unlockObserver == nil else { return }
        unlockObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadIfNeeded() }
        }
    }

    /// Erneut laden, falls die Datei beim Start nicht lesbar war (z. B. beim Wechsel in den Vordergrund).
    func reloadIfNeeded() {
        guard !isLoaded else { return }
        load()
    }

    /// Kopie der Originaldatei neben ihr ablegen, ohne eine frühere Kopie zu überschreiben.
    private func keepBrokenCopy() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { return }
        var target = fileURL.appendingPathExtension("broken")
        if fm.fileExists(atPath: target.path) {
            let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
                .replacingOccurrences(of: ":", with: "-")
            target = fileURL.appendingPathExtension("\(stamp).broken")
        }
        try fm.copyItem(at: fileURL, to: target)
    }

    private func save(notify: Bool = true) {
        // Solange die vorhandene Datei nicht gelesen ist, nie mit einem unvollständigen Stand überschreiben.
        guard isLoaded else { return }
        if UserDefaults.standard.bool(forKey: "iCloudSync") { publishPins() }
        do {
            if keepCopyBeforeWrite {
                try keepBrokenCopy()
                keepCopyBeforeWrite = false
            }
            let snap = Snapshot(cards: cards, tests: tests, deleted: Array(deletedIDs), pinChanged: pinChangedAt)
            let data = try JSONEncoder().encode(snap)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            print("Restwert: Speichern fehlgeschlagen:", error)
        }
        Task { await scheduleReminders() }
        WidgetBridge.update(cards: cards, total: total)
        if notify { onChange?() }
    }

    // MARK: PINs im Schlüsselbund

    /// Lokal geänderte PINs in den iCloud-Schlüsselbund; nie ältere Stände über neuere schreiben.
    private func publishPins() {
        for c in cards where !c.isExample {
            if case .publish(let entry) = PinEntry.resolve(localPin: c.pin, localChangedAt: pinChangedAt[c.id],
                                                           vault: PinVault.entry(for: c.id)) {
                PinVault.store(entry, for: c.id)
            }
        }
    }

    /// Neuere PINs (auch gelöschte) aus dem Schlüsselbund übernehmen.
    private func adoptPins() {
        for i in cards.indices where !cards[i].isExample {
            let id = cards[i].id
            if case .adopt(let entry) = PinEntry.resolve(localPin: cards[i].pin, localChangedAt: pinChangedAt[id],
                                                         vault: PinVault.entry(for: id)) {
                cards[i].pin = entry.pin
                pinChangedAt[id] = entry.changedAt
            }
        }
    }

    /// Reste entfernter Gutscheine aufräumen: PIN im Schlüsselbund, Nachfragen und vertagte Erinnerungen.
    private func forget(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        for id in ids {
            PinVault.remove(for: id)
            pinChangedAt[id] = nil
        }
        clearFollowUps(ids, snooze: true)
    }

    /// „Betrag offen“-Nachfrage (-later) und optional vertagte Erinnerungen (-snooze) entfernen.
    private func clearFollowUps(_ ids: [UUID], snooze: Bool) {
        let keys = ids.flatMap { id in snooze ? ["\(id.uuidString)-later", "\(id.uuidString)-snooze"] : ["\(id.uuidString)-later"] }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: keys)
        center.removeDeliveredNotifications(withIdentifiers: keys)
    }

    // MARK: Sync

    /// iCloud-Stand einmischen (neuere Änderung gewinnt, Löschungen gelten überall).
    func merge(_ remote: SyncData) {
        guard isLoaded else { return }
        let before = Set(cards.map(\.id))
        let result = SyncMerge.merge(localCards: cards, localTests: tests, localDeleted: deletedIDs, remote: remote)
        cards = result.cards
        tests = result.tests
        deletedIDs = result.deleted
        adoptPins()
        forget(before.subtracting(cards.map(\.id)).filter(deletedIDs.contains).map { $0 })
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
        let wasPending = cards[i].pendingSince != nil
        change(&cards[i])
        cards[i].modifiedAt = .now
        // „Betrag offen“ erledigt: geplante Nachfrage mit entfernen.
        if wasPending && cards[i].pendingSince == nil { clearFollowUps([id], snooze: false) }
        save()
    }

    func upsert(_ card: GiftCard) {
        var c = card
        c.isExample = false
        c.modifiedAt = .now
        if (self.card(c.id)?.pin ?? "") != c.pin { pinChangedAt[c.id] = .now }
        if let i = cards.firstIndex(where: { $0.id == c.id }) { cards[i] = c } else { cards.append(c) }
        save()
    }

    func delete(_ id: UUID) {
        cards.removeAll { $0.id == id }
        deletedIDs.insert(id)
        forget([id])
        save()
    }

    /// „Rückgängig“ nach dem Entfernen: Der Gutschein kommt mit neuer ID zurück,
    /// damit der Löschvermerk (auch in iCloud) ihn nicht gleich wieder entfernt.
    func undoDelete(_ card: GiftCard) {
        var c = card
        c.id = UUID()
        c.modifiedAt = .now
        upsert(c)
    }

    /// Nach einer Änderung mit neuem Verlaufseintrag den vorherigen Zustand für „Rückgängig“ merken.
    private func remember(_ prior: GiftCard, historyCount: Int) -> UUID? {
        guard let c = card(prior.id), c.history.count > historyCount, let entry = c.history.last?.id else { return nil }
        undoStates[entry] = UndoState(value: prior.value, pendingSince: prior.pendingSince, redeemedAt: prior.redeemedAt)
        return entry
    }

    /// Zieht ab und gibt die ID des Verlaufseintrags zurück, damit man es rückgängig machen kann.
    @discardableResult
    func redeem(_ id: UUID, amount: Double, store storeName: String = "", note: String = "") -> UUID? {
        guard amount > 0, let prior = card(id) else { return nil }
        update(id) {
            _ = $0.redeem(amount, store: storeName, note: note)
            $0.pendingSince = nil
        }
        return remember(prior, historyCount: prior.history.count)
    }

    /// Neuen Stand setzen (laut Bon oder nach Aufladung); gibt den Verlaufseintrag für „Rückgängig“ zurück.
    @discardableResult
    func setBalance(_ id: UUID, to value: Double) -> UUID? {
        guard let prior = card(id) else { return nil }
        update(id) {
            $0.setBalance(value)
            $0.pendingSince = nil
        }
        return remember(prior, historyCount: prior.history.count)
    }

    /// „Später eintragen“ an der Kasse: merken und nachfragen. Zurücksetzen entfernt die Nachfrage.
    func setPending(_ id: UUID, _ pending: Bool) {
        update(id) { $0.pendingSince = pending ? .now : nil }
    }

    /// Abzug zurücknehmen: Eintrag entfernen, Betrag gutschreiben und Startwert, „Betrag offen“ und Einlösung
    /// wie vorher setzen. Ein zugehöriger Kassentest (`test` oder beim Abzug gemerkt) wird mit entfernt.
    func undoRedemption(_ cardID: UUID, entry: UUID, test: UUID? = nil) {
        let state = undoStates.removeValue(forKey: entry)
        if let t = test ?? state?.test { removeTest(t) }
        update(cardID) { c in
            guard let i = c.history.firstIndex(where: { $0.id == entry }) else { return }
            let isLast = i == c.history.count - 1
            c.balance = max(0, ((c.balance + c.history[i].amount) * 100).rounded() / 100)
            c.history.remove(at: i)
            // Nur beim letzten Eintrag: sonst würden spätere Änderungen überschrieben.
            if let state, isLast {
                c.value = state.value
                c.pendingSince = state.pendingSince
                c.redeemedAt = state.redeemedAt
            }
        }
    }

    /// Kassentest entfernen; war er schon in iCloud, sorgt der Löschvermerk dafür, dass er dort auch verschwindet.
    private func removeTest(_ id: UUID) {
        guard tests.contains(where: { $0.id == id }) else { return }
        tests.removeAll { $0.id == id }
        deletedIDs.insert(id)
    }

    /// Rabattcodes und Coupons: als Ganzes einlösen und stempeln.
    func markRedeemed(_ id: UUID, store storeName: String = "") {
        _ = markRedeemedEntry(id, store: storeName)
    }

    private func markRedeemedEntry(_ id: UUID, store storeName: String) -> UUID? {
        guard let prior = card(id), prior.redeemedAt == nil else { return nil }
        update(id) {
            $0.markRedeemed(store: storeName)
            $0.pendingSince = nil
        }
        return remember(prior, historyCount: prior.history.count)
    }

    /// „Eingelöst“ zurücknehmen: Stempel und zugehörigen Verlaufseintrag entfernen.
    func undoMarkRedeemed(_ id: UUID) {
        guard let c = card(id), c.redeemedAt != nil else { return }
        let stamp = "\(c.kind.label) eingelöst"
        if let entry = c.history.last(where: { $0.amount == 0 && $0.note == stamp })?.id {
            undoRedemption(id, entry: entry)
        }
        if card(id)?.redeemedAt != nil { update(id) { $0.redeemedAt = nil } }
    }

    func setArchived(_ id: UUID, _ archived: Bool) {
        if archived { clearFollowUps([id], snooze: true) }
        update(id) { $0.archivedAt = archived ? .now : nil }
    }

    func setReminder(_ id: UUID, _ date: Date?) {
        update(id) { $0.reminderAt = date }
    }

    func setLocation(_ id: UUID, _ location: StorageLocation, note: String) {
        update(id) {
            $0.location = location
            $0.locationNote = note
        }
    }

    /// Kassentest festhalten. Bei Erfolg: Wertgutscheine um den Betrag kürzen, Codes und Coupons als eingelöst stempeln.
    /// Gibt den Verlaufseintrag für „Rückgängig“ zurück.
    @discardableResult
    func addTest(card: GiftCard, success: Bool, store storeName: String, note: String, amount: Double?) -> UUID? {
        recordTest(card: card, success: success, store: storeName, note: note, amount: amount).entry
    }

    /// Wie `addTest`, liefert zusätzlich die ID des angelegten Kassentests.
    @discardableResult
    func recordTest(card: GiftCard, success: Bool, store storeName: String, note: String,
                    amount: Double?) -> (entry: UUID?, test: UUID) {
        let current = self.card(card.id) ?? card
        var entry: UUID?
        if success {
            if current.kind.isValueBased {
                if let amount, amount > 0, current.balance > 0 {
                    entry = redeem(card.id, amount: min(amount, current.balance), store: storeName, note: "An der Kasse")
                }
            } else {
                entry = markRedeemedEntry(card.id, store: storeName)
            }
        }
        // Kassentest entschieden: „Betrag offen“ erledigt.
        if self.card(card.id)?.pendingSince != nil { update(card.id) { $0.pendingSince = nil } }
        let test = TestResult(cardID: card.id, merchantID: card.merchantID, merchantName: card.name, date: .now,
                              success: success, store: storeName, note: note, format: card.format, amount: amount)
        tests.append(test)
        if let entry { undoStates[entry]?.test = test.id }
        save()
        return (entry, test.id)
    }

    func clearExamples() {
        cards.removeAll(where: \.isExample)
        tests.removeAll(where: \.isExample)
        save()
    }

    func resetAll() {
        let own = cards.filter { !$0.isExample }.map(\.id)
        deletedIDs.formUnion(own)
        deletedIDs.formUnion(tests.filter { !$0.isExample }.map(\.id))
        forget(own)
        cards = []
        tests = []
        undoStates = [:]
        save()
    }

    // MARK: Sicherung

    private struct Backup: Codable { var cards: [GiftCard]; var tests: [TestResult] }

    /// Vollständige Sicherung als Datei (mit PINs und Fotos), zum Aufbewahren in Dateien oder iCloud Drive.
    func backupFile() -> URL? {
        let own = cards.filter { !$0.isExample }
        let enc = APICoding.encoder
        guard let data = try? enc.encode(Backup(cards: own, tests: tests.filter { !$0.isExample })) else { return nil }
        let url = URL.temporaryDirectory.appending(path: "Restwert-Sicherung-\(Date.now.formatted(.iso8601.year().month().day())).restwert.json")
        return (try? data.write(to: url, options: .completeFileProtection)).map { url }
    }

    /// Lesbare Liste für Tabellen (ohne PINs), Excel-tauglich mit deutschen Zahlen.
    func csvFile() -> URL? {
        let url = URL.temporaryDirectory.appending(path: "Restwert-Gutscheine.csv")
        let text = CardQueries.csv(cards, warnDays: warnDays)
        return (try? Data(("\u{FEFF}" + text).utf8).write(to: url)).map { url }
    }

    /// Sicherung einspielen; neuere Stände gewinnen, nichts wird doppelt angelegt. Hier bereits entfernte Gutscheine
    /// kommen mit neuer ID zurück. Gibt die Zahl der tatsächlich übernommenen (neuen oder aktualisierten) Gutscheine zurück.
    func restore(from url: URL) throws -> Int {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let backup = try APICoding.decoder.decode(Backup.self, from: Data(contentsOf: url))
        guard isLoaded else { throw CocoaError(.fileReadNoPermission) }
        let revived = SyncMerge.revive(cards: backup.cards, tests: backup.tests, deleted: deletedIDs)
        let before = Dictionary(cards.map { ($0.id, $0.modifiedAt) }, uniquingKeysWith: { a, _ in a })
        let result = SyncMerge.merge(localCards: cards, localTests: tests, localDeleted: deletedIDs,
                                     remote: SyncData(cards: revived.cards, tests: revived.tests, deleted: []))
        cards = result.cards
        tests = result.tests
        deletedIDs = result.deleted
        let restored = Set(revived.cards.map(\.id))
        var taken = 0
        for c in cards where restored.contains(c.id) {
            if let old = before[c.id], !SyncMerge.isNewer(c.modifiedAt, than: old) { continue }
            taken += 1
            // PIN aus der Sicherung gilt als neue Änderung, damit sie auch in den Schlüsselbund geht.
            if !c.pin.isEmpty { pinChangedAt[c.id] = .now }
        }
        save()
        return taken
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
        // Empfangsdaten relativ zu heute, damit sie nie in der Zukunft liegen.
        let newsletter = inDays(-25)
        let discount = GiftCard(kind: .discountCode, merchantID: "zalando", number: "HERBST15-K7Q2", format: .text, value: 0, balance: 0,
                                percent: 15, received: newsletter, expires: inDays(12), location: .inbox,
                                locationNote: "Newsletter vom \(newsletter.formatted(.dateTime.day().month(.defaultDigits).locale(Locale(identifier: "de_DE"))))",
                                isExample: true)
        cards = [
            discount,
            GiftCard(merchantID: "ikea", number: "6275980123456789012", format: .code128, value: 50, balance: 50,
                     received: d(y - 3, 5, 11), expires: inDays(24), isExample: true),
            thalia,
            douglas,
            GiftCard(merchantID: "amazon", number: "AQ7K-9XWP-3HTR", format: .text, value: 30, balance: 30,
                     received: inDays(-200), expires: d(y + 3, 12, 31), location: .phone, isExample: true),
            GiftCard(merchantID: "stadtgutschein", number: "SG-2291-7730", format: .qr, value: 20, balance: 20,
                     received: inDays(-260), expires: inDays(140), location: .wallet, isExample: true),
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
        // Ohne gelesene Datei ist `cards` leer: dann nichts entfernen und nichts planen.
        guard isLoaded else { return }
        let center = UNUserNotificationCenter.current()
        let enabled = UserDefaults.standard.object(forKey: "reminders") as? Bool ?? true
        let active = Dictionary(cards.filter { $0.isActive && !$0.isExample }.map { ($0.id.uuidString, $0) },
                                uniquingKeysWith: { a, _ in a })
        // Ablauf-Erinnerungen neu planen. „Betrag offen“-Nachfragen bleiben nur für aktive Gutscheine mit offenem Betrag,
        // vertagte Erinnerungen nur, solange Erinnerungen an sind und der Gutschein noch aktiv ist.
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { id in
            let card = active[String(id.prefix(36))]
            if id.hasSuffix("-later") { return card?.pendingSince == nil }
            if id.hasSuffix("-snooze") { return !enabled || card == nil || card?.forGifting == true }
            return true
        }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard enabled else { return }
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }
        center.setNotificationCategories([ReminderPrefs.category])
        let cal = Calendar.current
        let hour = ReminderPrefs.hour
        let leadDays = ReminderPrefs.days
        let firedBefore = ReminderPrefs.fallbacks
        var fallbacks: [String: Date] = [:]
        for c in cards where c.isActive && !c.isExample && !c.forGifting {
            var planned = 0
            for days in leadDays {
                guard let day = cal.date(byAdding: .day, value: -days, to: c.expires),
                      let fire = cal.date(bySettingHour: hour, minute: 0, second: 0, of: day), fire > .now else { continue }
                await add(center, c, id: "\(days)", at: fire,
                          title: days == 1 ? "\(c.name): läuft morgen ab" : "\(c.name): noch \(days) Tage")
                planned += 1
            }
            // Kurzfristig angelegt und alle Vorläufe schon vorbei: trotzdem genau einmal erinnern.
            // Ohne gewählte Vorlaufzeit gibt es keine Ablauf-Erinnerung.
            if planned == 0, !leadDays.isEmpty {
                let key = "\(c.id.uuidString)|\(Int(c.expires.timeIntervalSince1970))"
                let fire = firedBefore[key] ?? ReminderPrefs.fallback(expires: c.expires, hour: hour)
                if let fire {
                    fallbacks[key] = fire
                    if fire > .now {
                        await add(center, c, id: "fallback", at: fire,
                                  title: cal.isDate(fire, inSameDayAs: c.expires) ? "\(c.name): läuft heute ab" : "\(c.name): läuft bald ab")
                    }
                }
            }
            if let custom = c.reminderAt, custom > .now {
                await add(center, c, id: "custom", at: custom, title: "\(c.name): deine Erinnerung")
            }
        }
        ReminderPrefs.fallbacks = fallbacks
    }

    private func add(_ center: UNUserNotificationCenter, _ c: GiftCard, id: String, at date: Date, title: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = "\(c.headline) gültig bis \(c.expires.dayMonthYear). Jetzt einlösen."
        content.sound = .default
        content.categoryIdentifier = ReminderPrefs.category.identifier
        // Name und Ablauf mitgeben: „Morgen erinnern“ braucht sie auch bei gesperrtem Gerät (Datei dann nicht lesbar).
        content.userInfo = ["card": c.id.uuidString, "name": c.name, "expires": c.expires.timeIntervalSince1970]
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let request = UNNotificationRequest(identifier: "\(c.id.uuidString)-\(id)", content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
        try? await center.add(request)
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

    /// Einmal vergebene Ersatztermine je Gutschein und Ablaufdatum, damit die Ersatzerinnerung nur einmal kommt.
    static var fallbacks: [String: Date] {
        get { UserDefaults.standard.dictionary(forKey: "reminderFallbacks") as? [String: Date] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "reminderFallbacks") }
    }

    /// Mitteilung mit „Morgen erinnern“.
    static let category = UNNotificationCategory(
        identifier: "expiry",
        actions: [UNNotificationAction(identifier: "snooze", title: "Morgen erinnern", options: [])],
        intentIdentifiers: [])

    /// Nächster sinnvoller Termin, wenn alle Vorläufe vorbei sind: heute zur Uhrzeit, sonst morgen,
    /// am Ablauftag notfalls in einer Stunde – aber nie nach dem Ablauf und nie nachts.
    static func fallback(expires: Date, hour: Int, now: Date = .now) -> Date? {
        let cal = Calendar.current
        guard let end = cal.date(bySettingHour: 21, minute: 0, second: 0, of: expires), end > now else { return nil }
        if let today = cal.date(bySettingHour: hour, minute: 0, second: 0, of: now), today > now, today <= end { return today }
        if let next = cal.date(byAdding: .day, value: 1, to: now),
           let tomorrow = cal.date(bySettingHour: hour, minute: 0, second: 0, of: next), tomorrow <= end { return tomorrow }
        let soon = now.addingTimeInterval(3600)
        return soon <= end && cal.component(.hour, from: soon) >= 8 ? soon : nil
    }

    static func describe(days: [Int], hour: Int) -> String {
        guard !days.isEmpty else { return "Keine Vorlaufzeit gewählt" }
        let list = days.sorted(by: >).map { $0 == 1 ? "1 Tag" : "\($0) Tage" }
        return list.formatted(.list(type: .and)) + " vorher, um \(hour) Uhr"
    }
}
