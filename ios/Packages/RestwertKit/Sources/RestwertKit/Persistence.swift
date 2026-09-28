import Foundation

/// Gespeicherter Stand auf der Platte. Fotos liegen seit Version 2 als eigene Dateien daneben (``PhotoFiles``);
/// `photos` nennt die Gutscheine, deren Foto dort liegt. Ältere Dateien mit eingebetteten Fotos bleiben lesbar
/// und werden beim nächsten Speichern umgezogen.
public struct StoredState: Codable, Sendable {
    public var cards: [GiftCard]
    public var tests: [TestResult]
    public var deleted: [UUID]?
    /// Wann ein Löschvermerk entstand (zum Aufräumen nach 180 Tagen). Fehlt bei älteren Dateien.
    public var deletedAt: [UUID: Date]?
    public var pinChanged: [UUID: Date]?
    /// Gutscheine, deren Foto als Datei in `photos/` liegt.
    public var photos: [UUID]?
    /// Einträge, die beim Lesen nicht dekodierbar waren und übersprungen wurden.
    public var dropped = 0

    private enum CodingKeys: String, CodingKey { case cards, tests, deleted, deletedAt, pinChanged, photos }

    public init(cards: [GiftCard], tests: [TestResult], deletedAt: [UUID: Date], pinChanged: [UUID: Date], photos: [UUID] = []) {
        self.cards = cards
        self.tests = tests
        self.deleted = Array(deletedAt.keys)
        self.deletedAt = deletedAt
        self.pinChanged = pinChanged
        self.photos = photos
    }

    /// Einzelne kaputte Einträge überspringen statt die ganze Datei zu verwerfen.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawCards = try c.decode([Lossy<GiftCard>].self, forKey: .cards)
        let rawTests = try c.decodeIfPresent([Lossy<TestResult>].self, forKey: .tests) ?? []
        cards = rawCards.compactMap(\.value)
        tests = rawTests.compactMap(\.value)
        deleted = try? c.decodeIfPresent([UUID].self, forKey: .deleted)
        deletedAt = try? c.decodeIfPresent([UUID: Date].self, forKey: .deletedAt)
        pinChanged = try? c.decodeIfPresent([UUID: Date].self, forKey: .pinChanged)
        photos = try? c.decodeIfPresent([UUID].self, forKey: .photos)
        dropped = rawCards.count - cards.count + rawTests.count - tests.count
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(cards, forKey: .cards)
        try c.encode(tests, forKey: .tests)
        try c.encodeIfPresent(deleted, forKey: .deleted)
        try c.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try c.encodeIfPresent(pinChanged, forKey: .pinChanged)
        try c.encodeIfPresent(photos, forKey: .photos)
    }

    /// Löschvermerke mit Datum; ältere Dateien kennen nur die IDs, die gelten dann ab `now`.
    public func tombstones(now: Date = .now) -> [UUID: Date] {
        Tombstones.merged(deletedAt ?? [:], ids: deleted ?? [], now: now)
    }
}

/// Liest einen Eintrag, ohne bei einem kaputten Eintrag die ganze Liste zu verwerfen.
struct Lossy<T: Decodable>: Decodable {
    var value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

/// Fotos als einzelne Dateien (`<id>.jpg`, Dateischutz „vollständig“), damit sie nicht bei jedem Speichern
/// als Base64 in der großen JSON-Datei neu kodiert werden. Nicht thread-sicher: nur von einer seriellen Queue benutzen.
public final class PhotoFiles: @unchecked Sendable {
    public let directory: URL
    /// Zuletzt geschriebener bzw. gelesener Stand je Gutschein, damit nur Geänderte neu geschrieben werden.
    private var known: [UUID: Data] = [:]

    public init(directory: URL) {
        self.directory = directory
    }

    public func url(for id: UUID) -> URL { directory.appending(path: "\(id.uuidString).jpg") }

    /// Fotos lesen (fehlende Dateien werden übersprungen) und als bekannt merken.
    public func load(_ ids: some Sequence<UUID>) -> [UUID: Data] {
        var out: [UUID: Data] = [:]
        for id in ids {
            if let data = try? Data(contentsOf: url(for: id)) {
                out[id] = data
                known[id] = data
            }
        }
        return out
    }

    /// Auf iPhone/iPad nur bei entsperrtem Gerät lesbar. Auf dem Mac (nur Unit-Tests) ohne Dateischutz:
    /// macOS verweigert ihn bei gesperrtem Bildschirm, die Tests hingen sonst vom Zustand des Rechners ab.
    #if os(iOS)
    static let writeOptions: Data.WritingOptions = [.atomic, .completeFileProtection]
    #else
    static let writeOptions: Data.WritingOptions = [.atomic]
    #endif

    /// Geänderte Fotos schreiben. Gibt die IDs zurück, die nicht geschrieben werden konnten
    /// (die bleiben dann eingebettet in der JSON-Datei, damit nichts verloren geht).
    public func write(_ photos: [UUID: Data]) -> Set<UUID> {
        var failed: Set<UUID> = []
        if !photos.isEmpty {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        for (id, data) in photos where known[id] != data {
            do {
                try data.write(to: url(for: id), options: Self.writeOptions)
                known[id] = data
            } catch {
                failed.insert(id)
            }
        }
        return failed
    }

    /// IDs, deren Datei es nicht (mehr) gibt. Nur diese dürfen nach einem Ladeversuch als „erledigt“ gelten;
    /// war eine Datei bloß nicht lesbar (Gerät gesperrt, I/O-Fehler), wird es später erneut versucht.
    public func missing(_ ids: some Sequence<UUID>) -> Set<UUID> {
        Set(ids.filter { !FileManager.default.fileExists(atPath: url(for: $0).path) })
    }

    /// Foto einer Karte unter neuer ID weiterführen (z. B. „Rückgängig“ nach dem Löschen).
    public func move(from old: UUID, to new: UUID) {
        try? FileManager.default.moveItem(at: url(for: old), to: url(for: new))
        known[new] = known.removeValue(forKey: old)
    }

    /// Dateien entfernen, die kein Gutschein mehr braucht. Erst nach erfolgreichem Schreiben der JSON aufrufen.
    /// `removable`: nur diese IDs dürfen weg (Gutscheine, die der Store kennt, und alte Löschvermerke). Fotos
    /// unbekannter IDs – etwa von Einträgen einer beschädigten Datei – bleiben liegen, damit man sie retten kann.
    public func removeAll(except keep: Set<UUID>, removable: Set<UUID>? = nil) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "jpg" {
            guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent), !keep.contains(id),
                  removable?.contains(id) ?? true else { continue }
            try? fm.removeItem(at: file)
            known[id] = nil
        }
    }

    /// Stand für die Platte: Fotos aus den Karten lösen und als Dateien schreiben. Karten, deren Foto nicht
    /// geschrieben werden konnte, behalten es eingebettet. `pending` sind Fotos, die noch nicht geladen sind
    /// (Datei bleibt, Verweis bleibt). Gibt die zu speichernde Form und die zu behaltenden Foto-IDs zurück.
    public func prepare(_ state: StoredState, pending: Set<UUID>) -> (state: StoredState, keep: Set<UUID>) {
        var photos: [UUID: Data] = [:]
        for c in state.cards { if let p = c.photo { photos[c.id] = p } }
        let failed = write(photos)
        var out = state
        var refs: Set<UUID> = []
        out.cards = state.cards.map { c in
            var x = c
            if c.photo != nil {
                if !failed.contains(c.id) {
                    x.photo = nil
                    refs.insert(c.id)
                }
            } else if pending.contains(c.id) {
                refs.insert(c.id)
            }
            return x
        }
        out.photos = refs.sorted { $0.uuidString < $1.uuidString }
        return (out, refs)
    }
}
