import Foundation
import WidgetKit
import OSLog
import RestwertKit

/// Schreibt eine kleine Zusammenfassung für das Widget in die App Group (nur Namen, Beträge, Ablaufdaten – keine Codes oder PINs).
/// Gleiche Struktur wie `WidgetSnapshot` im Widget-Target. Tage und Summe rechnet das Widget zur Anzeigezeit selbst.
enum WidgetBridge {
    private struct Snapshot: Codable {
        struct Item: Codable {
            var id: String
            var name: String
            var headline: String
            var expires: Date
            /// Restwert in Euro, nur bei wertbasierten Gutscheinen (für die Summe).
            var amount: Double?
        }
        var items: [Item]
        var updated: Date
    }

    /// `total` wird nicht mehr verwendet: Die Summe entsteht aus denselben Karten wie die Liste.
    static func update(cards: [GiftCard], total: Double = 0) {
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.de.restwert.app") else {
            Logger(subsystem: "de.restwert.app", category: "widget").error("App Group nicht verfügbar")
            return
        }
        // Beispielkarten nur, solange es noch keine eigenen gibt.
        let own = cards.filter { !$0.isExample }
        let active = (own.isEmpty ? cards : own).filter { $0.isActive && !$0.forGifting }.sorted { $0.expires < $1.expires }
        let snap = Snapshot(items: active.prefix(200).map {
                                .init(id: $0.id.uuidString, name: $0.name, headline: $0.headline, expires: $0.expires,
                                      amount: $0.kind.isValueBased ? $0.balance : nil)
                            },
                            updated: .now)
        guard let data = try? JSONEncoder().encode(snap) else { return }
        do {
            try data.write(to: dir.appending(path: "widget.json"), options: .atomic)
        } catch {
            Logger(subsystem: "de.restwert.app", category: "widget").error("Widget-Daten: \(error.localizedDescription, privacy: .public)")
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
