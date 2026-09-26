import Foundation
import CryptoKit

/// Verschlüsselte Nutzlast für die iCloud-Synchronisation.
///
/// Gutscheine verlassen das Gerät nur als AES-GCM-verschlüsselter Block. Der Schlüssel liegt
/// im iCloud-Schlüsselbund des Nutzers, nicht in der Datenbank. Weder wir noch Apple können
/// die Inhalte in iCloud lesen, auch ohne „Erweiterten Datenschutz“.
public enum CloudPayload {
    public enum Failure: Error, Equatable {
        case wrongKeyOrDamaged
    }

    /// Neuer zufälliger 256-Bit-Schlüssel.
    public static func newKey() -> SymmetricKey { SymmetricKey(size: .bits256) }

    public static func keyData(_ key: SymmetricKey) -> Data { key.withUnsafeBytes { Data($0) } }
    public static func key(from data: Data) -> SymmetricKey { SymmetricKey(data: data) }

    /// Gutschein ohne Foto und PIN verschlüsseln. PINs synchronisieren getrennt über den Schlüsselbund.
    public static func seal(_ card: GiftCard, key: SymmetricKey) throws -> Data {
        var safe = card
        safe.photo = nil
        safe.pin = ""
        return try seal(APICoding.encoder.encode(safe), key: key)
    }

    public static func seal(_ test: TestResult, key: SymmetricKey) throws -> Data {
        try seal(APICoding.encoder.encode(test), key: key)
    }

    public static func openCard(_ blob: Data, key: SymmetricKey) throws -> GiftCard {
        try APICoding.decoder.decode(GiftCard.self, from: open(blob, key: key))
    }

    public static func openTest(_ blob: Data, key: SymmetricKey) throws -> TestResult {
        try APICoding.decoder.decode(TestResult.self, from: open(blob, key: key))
    }

    static func seal(_ plain: Data, key: SymmetricKey) throws -> Data {
        guard let combined = try AES.GCM.seal(plain, using: key).combined else { throw Failure.wrongKeyOrDamaged }
        return combined
    }

    static func open(_ blob: Data, key: SymmetricKey) throws -> Data {
        do {
            return try AES.GCM.open(AES.GCM.SealedBox(combined: blob), using: key)
        } catch {
            throw Failure.wrongKeyOrDamaged
        }
    }
}

/// Was die Synchronisation hochladen bzw. löschen muss, ausgehend vom lokalen und entfernten Stand.
public enum CloudPlan {
    public struct Upload: Sendable, Equatable {
        public var cards: [GiftCard]
        public var tests: [TestResult]
        public var tombstones: [UUID]
    }

    /// Lokale Karten, die in iCloud fehlen oder dort älter sind; Tests, die fehlen; Löschungen, die noch nicht oben sind.
    public static func upload(localCards: [GiftCard], localTests: [TestResult], localDeleted: Set<UUID>,
                              remoteModified: [UUID: Date], remoteTests: Set<UUID>, remoteTombstones: Set<UUID>) -> Upload {
        let cards = localCards.filter { c in
            guard !c.isExample, !localDeleted.contains(c.id) else { return false }
            guard let remote = remoteModified[c.id] else { return true }
            return c.modifiedAt > remote
        }
        let tests = localTests.filter { !$0.isExample && !remoteTests.contains($0.id) }
        let tombstones = localDeleted.subtracting(remoteTombstones).sorted { $0.uuidString < $1.uuidString }
        return Upload(cards: cards, tests: tests, tombstones: tombstones)
    }
}
