import Foundation

/// Was zwischen Gerät und Server ausgetauscht wird.
public struct SyncData: Codable, Sendable, Equatable {
    public var cards: [GiftCard]
    public var tests: [TestResult]
    public var deleted: [UUID]

    public init(cards: [GiftCard], tests: [TestResult], deleted: [UUID]) {
        self.cards = cards
        self.tests = tests
        self.deleted = deleted
    }

    /// Für den Server: ohne Fotos, PINs und Beispiele.
    public static func outgoing(cards: [GiftCard], tests: [TestResult], deleted: Set<UUID>) -> SyncData {
        let safe = cards.filter { !$0.isExample }.map { c -> GiftCard in
            var x = c
            x.photo = nil
            x.pin = ""
            return x
        }
        return SyncData(cards: safe, tests: tests.filter { !$0.isExample }, deleted: deleted.sorted { $0.uuidString < $1.uuidString })
    }
}

public enum SyncMerge {
    public struct Result: Sendable, Equatable {
        public var cards: [GiftCard]
        public var tests: [TestResult]
        public var deleted: Set<UUID>
    }

    /// Neuere Änderung gewinnt, Löschungen gelten überall, PIN und Foto bleiben lokal.
    public static func merge(localCards: [GiftCard], localTests: [TestResult], localDeleted: Set<UUID>, remote: SyncData) -> Result {
        let deleted = localDeleted.union(remote.deleted)
        var byID = Dictionary(localCards.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for r in remote.cards {
            if let local = byID[r.id] {
                guard r.modifiedAt > local.modifiedAt else { continue }
                var merged = r
                if merged.pin.isEmpty { merged.pin = local.pin }
                if merged.photo == nil { merged.photo = local.photo }
                byID[r.id] = merged
            } else {
                byID[r.id] = r
            }
        }
        let cards = byID.values.filter { !deleted.contains($0.id) }.sorted { $0.expires < $1.expires }
        let known = Set(localTests.map(\.id))
        let tests = localTests + remote.tests.filter { !known.contains($0.id) }
        return Result(cards: cards, tests: tests, deleted: deleted)
    }
}

/// JSON-Kodierung für die API (ISO 8601, mit und ohne Sekundenbruchteile lesbar).
public enum APICoding {
    public static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    public static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            if let date = try? Date(s, strategy: .iso8601) { return date }
            if let date = try? Date(s, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unbekanntes Datumsformat: \(s)")
        }
        return d
    }
}
