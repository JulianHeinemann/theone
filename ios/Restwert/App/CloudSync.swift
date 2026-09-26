import Foundation
import CloudKit
import CryptoKit
import Observation
import Security
import RestwertKit

enum APIConfig {
    /// Nur noch für Datenschutz- und Impressumsseiten. Gutscheine gehen nicht mehr an diesen Server.
    static let baseURL = URL(string: "https://api-production-9130.up.railway.app")!
}

/// Synchronisation über die private iCloud-Datenbank des Nutzers.
///
/// - Kein eigenes Konto, keine eigene Datenbank: Die Daten liegen im iCloud des Nutzers.
/// - Jeder Gutschein wird vor dem Hochladen mit AES-GCM verschlüsselt (``CloudPayload``).
///   Der Schlüssel liegt im iCloud-Schlüsselbund, synchronisiert Ende-zu-Ende verschlüsselt zwischen den Geräten.
/// - PINs gehen gar nicht in die Datenbank, sondern einzeln in den iCloud-Schlüsselbund (``PinVault``).
@Observable
final class CloudSync {
    enum State: Equatable {
        case off
        case idle
        case syncing
        case waitingForKey
        case unavailable(String)
        case failed(String)
    }

    private(set) var state: State = .off
    private(set) var lastSync: Date?

    /// Beobachtet, damit die Oberfläche sofort folgt; gespiegelt in UserDefaults („iCloudSync“, liest auch der Store).
    var isEnabled: Bool = UserDefaults.standard.bool(forKey: "iCloudSync") {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "iCloudSync")
            state = isEnabled ? .idle : .off
            if isEnabled { Task { await syncNow() } }
        }
    }

    static let containerID = "iCloud.de.restwert.app"
    private static let zone = CKRecordZone.ID(zoneName: "Restwert", ownerName: CKCurrentUserDefaultName)

    @ObservationIgnored private weak var store: Store?
    @ObservationIgnored private var pushTask: Task<Void, Never>?
    @ObservationIgnored private var running = false
    /// Während eines laufenden Abgleichs angefordert: danach noch einmal abgleichen.
    @ObservationIgnored private var resyncRequested = false
    /// iCloud-Daten werden gerade gelöscht: kein Abgleich, der die Zone wieder anlegen könnte.
    @ObservationIgnored private var deleting = false
    @ObservationIgnored private lazy var database = CKContainer(identifier: Self.containerID).privateCloudDatabase

    init() {
        lastSync = UserDefaults.standard.object(forKey: "iCloudLastSync") as? Date
        state = isEnabled ? .idle : .off
    }

    func attach(_ store: Store) {
        self.store = store
        store.onChange = { [weak self] in self?.schedulePush() }
    }

    /// Nach einer Änderung kurz warten und dann abgleichen, damit schnelle Folgeänderungen gebündelt werden.
    private func schedulePush() {
        guard isEnabled else { return }
        pushTask?.cancel()
        pushTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await syncNow()
        }
    }

    @MainActor
    func syncNow() async {
        guard isEnabled, !deleting, let store else { return }
        // Läuft schon ein Abgleich, danach noch einmal, damit Änderungen von währenddessen hochgehen.
        guard !running else { resyncRequested = true; return }
        store.reloadIfNeeded()
        guard store.isLoaded else { return }
        running = true
        resyncRequested = false
        defer {
            running = false
            if resyncRequested {
                resyncRequested = false
                Task { await syncNow() }
            }
        }
        state = .syncing
        do {
            let status = try await CKContainer(identifier: Self.containerID).accountStatus()
            guard status == .available else {
                state = .unavailable(status == .noAccount
                    ? "Auf diesem iPhone ist niemand bei iCloud angemeldet."
                    : "iCloud ist gerade nicht erreichbar.")
                return
            }
            do {
                try await pass(store)
            } catch let error as CKError where Self.zoneIsGone(error) && isEnabled && !deleting {
                // Zone wurde gelöscht (anderes Gerät, Apple-ID, iCloud-Einstellungen): neu anlegen und einmal wiederholen.
                UserDefaults.standard.removeObject(forKey: "iCloudZoneReady")
                try await pass(store)
            }
            if resyncRequested { return }
            lastSync = .now
            UserDefaults.standard.set(lastSync, forKey: "iCloudLastSync")
            state = .idle
        } catch is WaitingForKey {
            state = .waitingForKey
        } catch {
            state = .failed(Self.describe(error))
        }
    }

    private struct WaitingForKey: Error {}

    /// Ein Durchgang: Zone sicherstellen, lesen, einmischen, hochladen.
    @MainActor
    private func pass(_ store: Store) async throws {
        try await ensureZone()
        let remote = try await fetchAll()
        guard let key = SyncKey.current(remoteHasData: !remote.blobs.isEmpty) else {
            // Daten sind schon in iCloud, aber der Schlüssel ist noch nicht per Schlüsselbund angekommen.
            throw WaitingForKey()
        }
        let decoded = decode(remote, key: key)
        store.merge(SyncData(cards: decoded.cards, tests: decoded.tests, deleted: Array(remote.tombstones)))
        let plan = CloudPlan.upload(localCards: store.cards, localTests: store.tests, localDeleted: store.deletedIDs,
                                    remoteModified: decoded.modified, remoteTests: Set(decoded.tests.map(\.id)),
                                    remoteTombstones: remote.tombstones)
        try await upload(plan, key: key)
    }

    private static func zoneIsGone(_ error: CKError) -> Bool {
        if error.code == .zoneNotFound || error.code == .userDeletedZone { return true }
        guard error.code == .partialFailure, let items = error.partialErrorsByItemID?.values else { return false }
        return items.contains { ($0 as? CKError).map { $0.code == .zoneNotFound || $0.code == .userDeletedZone } ?? false }
    }

    /// Alles in iCloud löschen (Zone entfernen) und den Sync ausschalten. Lokale Daten und PINs bleiben.
    /// Mit `includingKeychain` (Standard) verschwinden auch Sync-Schlüssel und alle PINs aus dem iCloud-Schlüsselbund –
    /// auf allen Geräten. Beim erneuten Einschalten entstehen Zone und Schlüssel neu und alles wird wieder hochgeladen.
    @MainActor
    func deleteCloudData(includingKeychain: Bool = true) async throws {
        pushTask?.cancel()
        // Sperren, damit kein laufender Abgleich die Zone gleich wieder anlegt.
        deleting = true
        defer { deleting = false }
        do {
            _ = try await database.modifyRecordZones(saving: [], deleting: [Self.zone])
        } catch let error as CKError where Self.zoneIsGone(error) {
            // Schon weg: auch gut.
        }
        UserDefaults.standard.removeObject(forKey: "iCloudZoneReady")
        if includingKeychain { SyncedKeychain.deleteAll() }
        lastSync = nil
        UserDefaults.standard.removeObject(forKey: "iCloudLastSync")
        isEnabled = false
    }

    // MARK: CloudKit

    private struct Remote {
        var blobs: [(type: String, id: UUID, blob: Data, modified: Date)] = []
        var tombstones: Set<UUID> = []
    }

    private func ensureZone() async throws {
        guard !UserDefaults.standard.bool(forKey: "iCloudZoneReady") else { return }
        _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: Self.zone)], deleting: [])
        UserDefaults.standard.set(true, forKey: "iCloudZoneReady")
    }

    /// Ganze Zone lesen. Für die Datenmenge einer Gutschein-App (wenige hundert Einträge) reicht das.
    private func fetchAll() async throws -> Remote {
        var out = Remote()
        var token: CKServerChangeToken?
        repeat {
            let changes = try await database.recordZoneChanges(inZoneWith: Self.zone, since: token)
            for (_, result) in changes.modificationResultsByID {
                guard case .success(let mod) = result else { continue }
                let r = mod.record
                let name = r.recordID.recordName
                if r.recordType == "Tombstone" {
                    if let id = UUID(uuidString: String(name.dropFirst("del-".count))) { out.tombstones.insert(id) }
                } else if let id = UUID(uuidString: name), let blob = r["blob"] as? Data {
                    out.blobs.append((r.recordType, id, blob, r["modified"] as? Date ?? .distantPast))
                }
            }
            token = changes.changeToken
            if !changes.moreComing { break }
        } while true
        return out
    }

    private func decode(_ remote: Remote, key: SymmetricKey) -> (cards: [GiftCard], tests: [TestResult], modified: [UUID: Date]) {
        var cards: [GiftCard] = [], tests: [TestResult] = [], modified: [UUID: Date] = [:]
        for item in remote.blobs {
            switch item.type {
            case "Card":
                if let c = try? CloudPayload.openCard(item.blob, key: key) {
                    cards.append(c)
                    modified[c.id] = c.modifiedAt
                }
            case "Test":
                if let t = try? CloudPayload.openTest(item.blob, key: key) { tests.append(t) }
            default: break
            }
        }
        return (cards, tests, modified)
    }

    private func upload(_ plan: CloudPlan.Upload, key: SymmetricKey) async throws {
        var records: [CKRecord] = []
        for c in plan.cards {
            let r = CKRecord(recordType: "Card", recordID: CKRecord.ID(recordName: c.id.uuidString, zoneID: Self.zone))
            r["blob"] = try CloudPayload.seal(c, key: key)
            r["modified"] = c.modifiedAt
            records.append(r)
        }
        for t in plan.tests {
            let r = CKRecord(recordType: "Test", recordID: CKRecord.ID(recordName: t.id.uuidString, zoneID: Self.zone))
            r["blob"] = try CloudPayload.seal(t, key: key)
            records.append(r)
        }
        // Gelöschte Karten: Karten-Datensatz entfernen und einen Grabstein („del-…“) ablegen,
        // damit andere Geräte die Karte ebenfalls löschen.
        for id in plan.tombstones {
            records.append(CKRecord(recordType: "Tombstone", recordID: CKRecord.ID(recordName: "del-\(id.uuidString)", zoneID: Self.zone)))
        }
        var deleting = plan.tombstones.map { CKRecord.ID(recordName: $0.uuidString, zoneID: Self.zone) }
        guard !records.isEmpty else { return }
        for chunk in stride(from: 0, to: records.count, by: 300).map({ Array(records[$0..<min($0 + 300, records.count)]) }) {
            let (saved, deleted) = try await database.modifyRecords(saving: chunk, deleting: deleting,
                                                                    savePolicy: .allKeys, atomically: false)
            deleting = []   // Löschungen nur mit dem ersten Paket
            // Fehler einzelner Datensätze nicht als Erfolg melden.
            for case .failure(let error) in saved.values { throw error }
            for case .failure(let error) in deleted.values where (error as? CKError)?.code != .unknownItem { throw error }
        }
    }

    private static func describe(_ error: Error) -> String {
        if let ck = error as? CKError {
            switch ck.code {
            case .networkUnavailable, .networkFailure: return "Keine Internetverbindung. Wird später abgeglichen."
            case .notAuthenticated: return "Bitte in den iPhone-Einstellungen bei iCloud anmelden."
            case .quotaExceeded: return "Dein iCloud-Speicher ist voll."
            default: return "iCloud-Fehler (\(ck.code.rawValue)). Wird später erneut versucht."
            }
        }
        return error.localizedDescription
    }
}

// MARK: - Schlüsselbund

/// Generischer Zugriff auf den iCloud-Schlüsselbund (synchronisiert zwischen den Geräten des Nutzers).
enum SyncedKeychain {
    private static let service = "de.restwert.app.sync"

    static func get(_ account: String) -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecAttrSynchronizable as String: true,
                                    kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    static func set(_ data: Data?, for account: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: account, kSecAttrSynchronizable as String: true]
        SecItemDelete(base as CFDictionary)
        guard let data else { return }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    /// Alle Einträge von Restwert (Sync-Schlüssel und PINs) aus dem iCloud-Schlüsselbund entfernen.
    static func deleteAll() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                       kSecAttrSynchronizable as String: true] as CFDictionary)
    }
}

/// Der Schlüssel, mit dem alle Gutscheine in iCloud verschlüsselt sind.
enum SyncKey {
    /// Vorhandenen Schlüssel nehmen; nur einen neuen anlegen, wenn in iCloud noch nichts liegt.
    static func current(remoteHasData: Bool) -> SymmetricKey? {
        if let data = SyncedKeychain.get("cloud-key") { return CloudPayload.key(from: data) }
        guard !remoteHasData else { return nil }
        let key = CloudPayload.newKey()
        SyncedKeychain.set(CloudPayload.keyData(key), for: "cloud-key")
        return key
    }
}

/// PINs einzeln im iCloud-Schlüsselbund, damit sie nie in der iCloud-Datenbank liegen.
/// Jeder Eintrag trägt den Zeitpunkt der Änderung (``PinEntry``); eine leere PIN heißt „gelöscht“.
enum PinVault {
    static func entry(for id: UUID) -> PinEntry? {
        SyncedKeychain.get(account(id)).flatMap(PinEntry.init(data:))
    }

    static func pin(for id: UUID) -> String? {
        entry(for: id).flatMap { $0.pin.isEmpty ? nil : $0.pin }
    }

    static func store(_ entry: PinEntry, for id: UUID) {
        guard self.entry(for: id) != entry else { return }
        SyncedKeychain.set(entry.data, for: account(id))
    }

    /// Eintrag ganz entfernen (Gutschein gelöscht).
    static func remove(for id: UUID) {
        SyncedKeychain.set(nil, for: account(id))
    }

    private static func account(_ id: UUID) -> String { "pin-\(id.uuidString)" }
}
