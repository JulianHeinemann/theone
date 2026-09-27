import AppIntents
import Foundation
import RestwertKit

// Siri, Kurzbefehle und Spotlight. Alles lokal: die Intents lesen nur die Datei des Stores, schreiben nie.

// MARK: - Daten (nur lesend)

/// Liest die Gutscheine direkt aus `restwert.json`, ohne `Store` anzulegen –
/// der würde bei fehlender Datei Beispiele anlegen und das Widget neu schreiben.
nonisolated enum IntentData {
    private struct Stored: Decodable {
        var cards: [GiftCard]

        private enum CodingKeys: String, CodingKey { case cards }
        private struct Lossy: Decodable {
            var card: GiftCard?
            init(from decoder: Decoder) throws { card = try? GiftCard(from: decoder) }
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // Einzelne kaputte Einträge überspringen, wie der Store.
            cards = try c.decode([Lossy].self, forKey: .cards).compactMap(\.card)
        }
    }

    /// Offene Gutscheine; Beispiele nur, solange es keine eigenen gibt (wie Widget und Start).
    /// Für „Gutschein öffnen“: Beispiele lassen sich wie in der App antippen.
    static func activeCards() throws -> [GiftCard] {
        let cards = try storedCards()
        let own = cards.filter { !$0.isExample }
        return (own.isEmpty ? cards : own).filter(\.isActive)
    }

    /// Für gesprochene Antworten: nur eigene Gutscheine. Beispiele nie als echtes Guthaben vorlesen,
    /// `onlyExamples` sagt, ob es bisher nur die Beispiele gibt.
    static func ownActiveCards() throws -> (cards: [GiftCard], onlyExamples: Bool) {
        let cards = try storedCards()
        let own = cards.filter { !$0.isExample }
        return (own.filter(\.isActive), own.isEmpty && !cards.isEmpty)
    }

    static var examplesDialog: IntentDialog {
        "Du hast noch keine eigenen Gutscheine, in Restwert liegen nur Beispiele. Füg deinen ersten Gutschein in der App hinzu."
    }

    private static func storedCards() throws -> [GiftCard] {
        let url = URL.applicationSupportDirectory.appending(path: "restwert.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            // Dateischutz: bei gesperrtem Gerät nicht lesbar.
            throw IntentError.locked
        }
        return (try? JSONDecoder().decode(Stored.self, from: data).cards) ?? []
    }

    /// Mit „App mit Face ID sperren“ keine Beträge oder Namen über Siri preisgeben.
    static var appLocked: Bool { UserDefaults.standard.bool(forKey: "appLock") }

    static func days(_ card: GiftCard) -> String {
        switch card.daysLeft {
        case 0: "heute"
        case 1: "morgen"
        case let d: "in \(d)\u{00A0}Tagen"
        }
    }
}

nonisolated enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case locked
    case notFound

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .locked: "Entsperre dein iPhone, damit Restwert deine Gutscheine lesen kann."
        case .notFound: "Diesen Gutschein gibt es nicht mehr."
        }
    }
}

// MARK: - Gutschein als Entität

nonisolated struct GiftCardEntity: AppEntity, Identifiable, Sendable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Gutschein", numericFormat: "\(placeholder: .int) Gutscheine")
    static let defaultQuery = GiftCardQuery()

    let id: UUID
    let name: String
    let headline: String
    let expires: Date
    /// Mit App-Sperre: nur die ID, keine Namen, Beträge oder Daten nach außen.
    let hidden: Bool

    init(_ card: GiftCard) {
        id = card.id
        name = card.name
        headline = card.headline
        expires = card.expires
        hidden = false
    }

    /// Platzhalter bei aktiver App-Sperre: „Gutschein öffnen“ funktioniert weiter, die App fragt dann Face ID ab.
    init(lockedID id: UUID) {
        self.id = id
        name = "Gutschein"
        headline = ""
        expires = .distantFuture
        hidden = true
    }

    var displayRepresentation: DisplayRepresentation {
        if hidden {
            return DisplayRepresentation(title: "Gutschein", subtitle: "Gesperrt – öffne Restwert", image: .init(systemName: "lock.fill"))
        }
        return DisplayRepresentation(title: "\(name)",
                                     subtitle: "\(headline) · bis \(expires.dayMonthYear)",
                                     image: .init(systemName: "ticket"))
    }
}

nonisolated struct GiftCardQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [GiftCardEntity] {
        let cards = try IntentData.activeCards().filter { identifiers.contains($0.id) }
        // App-Sperre: gespeicherte Kurzbefehle lassen sich weiter auflösen, zeigen aber nichts vom Inhalt.
        guard !IntentData.appLocked else { return cards.map { GiftCardEntity(lockedID: $0.id) } }
        return cards.map(GiftCardEntity.init)
    }

    /// Suche nach Name: „Zal“ findet Zalando, ohne Rücksicht auf Groß-/Kleinschreibung und Akzente.
    func entities(matching string: String) async throws -> [GiftCardEntity] {
        // Bei aktiver App-Sperre keine Suche: sie verriete Namen, Guthaben und Ablaufdaten.
        guard !IntentData.appLocked else { return [] }
        let query = string.trimmingCharacters(in: .whitespaces)
        return try IntentData.activeCards()
            .filter { query.isEmpty || $0.name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            .sorted { $0.expires < $1.expires }
            .map(GiftCardEntity.init)
    }

    func suggestedEntities() async throws -> [GiftCardEntity] {
        // Bei aktiver App-Sperre keine Namen in Siri-Vorschlägen.
        guard !IntentData.appLocked else { return [] }
        return try IntentData.activeCards().sorted { $0.expires < $1.expires }.map(GiftCardEntity.init)
    }
}

// MARK: - Intents

/// „Wie viel Guthaben habe ich?“ – Gesamtsumme und Anzahl.
nonisolated struct BalanceIntent: AppIntent {
    static let title: LocalizedStringResource = "Guthaben abfragen"
    static let description = IntentDescription("Sagt dir, wie viel Guthaben auf deinen offenen Gutscheinen steckt.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        guard !IntentData.appLocked else {
            return .result(value: 0, dialog: "Deine App-Sperre ist an. Öffne Restwert, um dein Guthaben zu sehen.")
        }
        let (all, onlyExamples) = try IntentData.ownActiveCards()
        if onlyExamples { return .result(value: 0, dialog: IntentData.examplesDialog) }
        let cards = all.filter { !$0.forGifting }
        let total = CardQueries.openTotal(cards)
        if cards.count == 1 {
            let card = cards[0]
            return .result(value: total, dialog: "Du hast einen offenen Gutschein: \(card.name) mit \(card.headline).")
        }
        let valueCount = cards.filter { $0.kind.isValueBased }.count
        let extra = cards.count - valueCount
        let head = switch valueCount {
        case 0 where extra == 0: "Du hast gerade keine offenen Gutscheine."
        case 0: "Du hast \(extra) offene Gutscheine, keiner davon mit Eurobetrag."
        case 1: "Du hast \(total.euro) Guthaben auf einem Gutschein."
        default: "Du hast \(total.euro) Guthaben auf \(valueCount) Gutscheinen."
        }
        let rest = valueCount == 0 || extra == 0 ? ""
            : extra == 1 ? " Dazu kommt ein Gutschein ohne Eurobetrag." : " Dazu kommen \(extra) Gutscheine ohne Eurobetrag."
        return .result(value: total, dialog: IntentDialog(stringLiteral: head + rest))
    }
}

/// „Was läuft bald ab?“ – die nächsten drei.
nonisolated struct ExpiringIntent: AppIntent {
    static let title: LocalizedStringResource = "Was läuft bald ab?"
    static let description = IntentDescription("Nennt die drei Gutscheine, die als Nächstes ablaufen.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    func perform() async throws -> some IntentResult & ReturnsValue<[GiftCardEntity]> & ProvidesDialog {
        guard !IntentData.appLocked else {
            return .result(value: [], dialog: "Deine App-Sperre ist an. Öffne Restwert, um deine Ablauftermine zu sehen.")
        }
        let (cards, onlyExamples) = try IntentData.ownActiveCards()
        if onlyExamples { return .result(value: [], dialog: IntentData.examplesDialog) }
        let next = cards.sorted { $0.expires < $1.expires }.prefix(3)
        guard !next.isEmpty else {
            return .result(value: [], dialog: "Gerade läuft nichts ab – du hast keine offenen Gutscheine.")
        }
        let lines = next.map { "\($0.name) mit \($0.headline) \(IntentData.days($0))" }
        let intro = next.count == 1 ? "Als Nächstes läuft ab: " : "Als Nächstes laufen ab: "
        return .result(value: next.map(GiftCardEntity.init),
                       dialog: IntentDialog(stringLiteral: intro + lines.formatted(.list(type: .and).locale(Locale(identifier: "de_DE"))) + "."))
    }
}

/// „Gutschein öffnen“ – zeigt den Gutschein in der App (wie `restwert://card/<id>`).
struct OpenCardIntent: OpenIntent {
    static let title: LocalizedStringResource = "Gutschein öffnen"
    static let description = IntentDescription("Öffnet einen Gutschein in Restwert.")

    @Parameter(title: "Gutschein")
    var target: GiftCardEntity

    @Dependency private var router: Router

    @MainActor
    func perform() async throws -> some IntentResult {
        router.showCard(target.id)
        return .result()
    }
}

// MARK: - Kurzbefehle

nonisolated struct RestwertShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: BalanceIntent(),
                    phrases: ["Wie viel Guthaben habe ich in \(.applicationName)",
                              "Mein Guthaben in \(.applicationName)",
                              "\(.applicationName) Guthaben",
                              "Wie viel ist noch auf meinen Gutscheinen in \(.applicationName)"],
                    shortTitle: "Guthaben",
                    systemImageName: "eurosign.circle")
        AppShortcut(intent: ExpiringIntent(),
                    phrases: ["Was läuft bald ab in \(.applicationName)",
                              "Welche Gutscheine laufen bald ab in \(.applicationName)",
                              "\(.applicationName) Ablauftermine"],
                    shortTitle: "Läuft bald ab",
                    systemImageName: "clock")
        AppShortcut(intent: OpenCardIntent(),
                    phrases: ["Öffne \(\.$target) in \(.applicationName)",
                              "Zeig mir \(\.$target) in \(.applicationName)",
                              "Gutschein in \(.applicationName) öffnen"],
                    shortTitle: "Gutschein öffnen",
                    systemImageName: "ticket")
    }
}
