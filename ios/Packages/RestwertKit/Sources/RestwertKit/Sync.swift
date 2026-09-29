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
            x.photoBack = nil
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

    /// Zeitstempel gelten erst ab 1 ms Unterschied als verschieden, weil gespeicherte Zeiten auf Millisekunden gerundet sind.
    public static func isNewer(_ a: Date, than b: Date) -> Bool {
        a.timeIntervalSince(b) >= 0.001
    }

    /// Neuere Änderung gewinnt, Löschungen gelten überall, PIN und Foto bleiben lokal.
    /// `deleted` enthält IDs gelöschter Gutscheine, Kassentests und zurückgenommener Verlaufseinträge;
    /// Tests gelöschter Gutscheine fallen mit weg. Buchungen beider Seiten bleiben erhalten (``unite(_:_:deleted:)``).
    public static func merge(localCards: [GiftCard], localTests: [TestResult], localDeleted: Set<UUID>, remote: SyncData) -> Result {
        let deleted = localDeleted.union(remote.deleted)
        var byID = Dictionary(localCards.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for r in remote.cards {
            if let local = byID[r.id] {
                if isNewer(r.modifiedAt, than: local.modifiedAt) {
                    var merged = unite(r, local, deleted: deleted)
                    if merged.pin.isEmpty { merged.pin = local.pin }
                    if merged.photo == nil { merged.photo = local.photo }
                    if merged.photoBack == nil { merged.photoBack = local.photoBack }
                    byID[r.id] = merged
                } else {
                    byID[r.id] = unite(local, r, deleted: deleted)
                }
            } else {
                byID[r.id] = unite(r, r, deleted: deleted)
            }
        }
        for (id, c) in byID where c.history.contains(where: { deleted.contains($0.id) }) {
            byID[id] = unite(c, c, deleted: deleted)
        }
        let cards = byID.values.filter { !deleted.contains($0.id) }.sorted { $0.expires < $1.expires }
        let known = Set(localTests.map(\.id))
        let tests = (localTests + remote.tests.filter { !known.contains($0.id) })
            .filter { t in !deleted.contains(t.id) && !(t.cardID.map(deleted.contains) ?? false) }
        return Result(cards: cards, tests: tests, deleted: deleted)
    }

    /// Gleichzeitige Buchungen zusammenführen: Die neuere Fassung (`winner`) bleibt die Grundlage; Verlaufseinträge,
    /// die nur die andere Fassung kennt, werden nachgebucht (Guthaben entsprechend verrechnet). Zurückgenommene
    /// Einträge (ID in `deleted`) fallen heraus und ihr Betrag wird wieder gutgeschrieben.
    /// Ein gesetzter Stand (``Redemption/isBalanceSet``, „laut Bon“) ist absolut: Er schließt alle früheren Buchungen
    /// ein, verrechnet werden nur Buchungen danach. Ist der jüngste gesetzte Stand von der anderen Seite, wird ab ihm
    /// neu gerechnet (spätere Formular-Korrekturen der Gewinner-Seite ohne Verlaufseintrag gehen dann unter).
    /// Hat sich dadurch etwas geändert, rückt `modifiedAt` 2 ms weiter, damit der vereinigte Stand wieder hochgeht.
    /// Einschränkung: Eine Guthaben-Korrektur im Formular ohne Verlaufseintrag kann nicht verrechnet werden.
    public static func unite(_ winner: GiftCard, _ other: GiftCard, deleted: Set<UUID>) -> GiftCard {
        var c = winner
        let known = Set(winner.history.map(\.id))
        let extra = other.history.filter { !known.contains($0.id) && !deleted.contains($0.id) }
        let undone = winner.history.filter { deleted.contains($0.id) }
        guard !extra.isEmpty || !undone.isEmpty else { return winner }
        c.history = (winner.history.filter { !deleted.contains($0.id) } + extra).sorted { $0.date < $1.date }
        var balance = c.balance
        if let s = c.history.lastIndex(where: \.isBalanceSet) {
            let set = c.history[s]
            if extra.contains(where: { $0.id == set.id }) {
                // Jüngster Stand laut Bon kommt von der anderen Seite: ab ihm neu rechnen.
                balance = set.balanceAfter
                for e in c.history[(s + 1)...] { balance -= e.amount }
            } else {
                // Eigener Stand ist der jüngste: nur, was danach kam oder danach zurückgenommen wurde.
                for e in undone where e.date > set.date { balance += e.amount }
                for e in extra where e.date > set.date { balance -= e.amount }
            }
        } else {
            for e in undone { balance += e.amount }
            for e in extra { balance -= e.amount }
        }
        c.balance = max(0, (balance * 100).rounded() / 100)
        if c.balance > c.value { c.value = c.balance }
        // Eingelöst-Stempel eines Codes/Coupons von der anderen Seite übernehmen …
        let card = c
        if c.redeemedAt == nil, let stamp = extra.first(where: { card.isStamp($0) }) {
            c.redeemedAt = stamp.date
        }
        // … und einen zurückgenommenen Stempel auch hier zurücknehmen (sonst „eingelöst“ ohne Verlaufseintrag).
        if c.redeemedAt != nil, undone.contains(where: { card.isStamp($0) }),
           !c.history.contains(where: { card.isStamp($0) }) {
            c.redeemedAt = nil
        }
        c.modifiedAt = max(winner.modifiedAt, other.modifiedAt).addingTimeInterval(0.002)
        return c
    }

    /// Sicherung vorbereiten: Gutscheine, die hier schon gelöscht wurden, bekommen eine neue ID,
    /// damit Löschvermerke (lokal und in iCloud) sie nicht sofort wieder entfernen. Ihre Tests ziehen mit.
    public static func revive(cards: [GiftCard], tests: [TestResult], deleted: Set<UUID>, now: Date = .now)
        -> (cards: [GiftCard], tests: [TestResult]) {
        var newIDs: [UUID: UUID] = [:]
        let outCards = cards.map { c -> GiftCard in
            guard deleted.contains(c.id) else { return c }
            var x = c
            x.id = UUID()
            x.isExample = false
            x.modifiedAt = now
            newIDs[c.id] = x.id
            return x
        }
        let outTests = tests.compactMap { t -> TestResult? in
            if let cid = t.cardID, let nid = newIDs[cid] {
                var x = t
                x.id = UUID()
                x.cardID = nid
                return x
            }
            guard !deleted.contains(t.id) else {
                var x = t
                x.id = UUID()
                return x
            }
            return t
        }
        return (outCards, outTests)
    }
}

/// PIN-Abgleich über den iCloud-Schlüsselbund: je Gutschein ein Eintrag mit Zeitpunkt der letzten Änderung.
/// Eine leere PIN mit Zeitpunkt heißt „bewusst gelöscht“ und bleibt gelöscht.
public struct PinEntry: Codable, Sendable, Equatable {
    public var pin: String
    public var changedAt: Date

    public init(pin: String, changedAt: Date) {
        self.pin = pin
        self.changedAt = changedAt
    }

    /// Gespeicherte Form; ältere Einträge sind nur die PIN als Text (Zeitpunkt unbekannt).
    public var data: Data { (try? JSONEncoder().encode(self)) ?? Data(pin.utf8) }

    public init?(data: Data) {
        if let e = try? JSONDecoder().decode(PinEntry.self, from: data) { self = e; return }
        guard let s = String(data: data, encoding: .utf8) else { return nil }
        self.init(pin: s, changedAt: .distantPast)
    }

    public enum Action: Equatable, Sendable {
        case keep
        /// Wert aus dem Schlüsselbund übernehmen.
        case adopt(PinEntry)
        /// Lokalen Stand in den Schlüsselbund schreiben.
        case publish(PinEntry)
    }

    /// Neuere Änderung gewinnt. Ohne lokale Änderung (`localChangedAt == nil`) füllt der Schlüsselbund eine leere PIN auf.
    public static func resolve(localPin: String, localChangedAt: Date?, vault: PinEntry?) -> Action {
        let local = localChangedAt ?? .distantPast
        guard let vault else {
            return localPin.isEmpty ? .keep : .publish(PinEntry(pin: localPin, changedAt: local))
        }
        if vault.pin == localPin { return .keep }
        if SyncMerge.isNewer(vault.changedAt, than: local) { return .adopt(vault) }
        if localChangedAt == nil, localPin.isEmpty { return .adopt(vault) }
        if SyncMerge.isNewer(local, than: vault.changedAt) { return .publish(PinEntry(pin: localPin, changedAt: local)) }
        return .keep
    }
}

/// JSON-Kodierung für die API und iCloud (ISO 8601 mit Millisekunden; mit und ohne Sekundenbruchteile lesbar).
public enum APICoding {
    public static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
        }
        return e
    }

    public static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            if let date = try? Date(s, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) { return date }
            if let date = try? Date(s, strategy: .iso8601) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unbekanntes Datumsformat: \(s)")
        }
        return d
    }
}
