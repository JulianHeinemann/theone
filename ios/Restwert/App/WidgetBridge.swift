import Foundation
import SwiftUI
import UIKit
import WidgetKit
import OSLog
import RestwertKit

/// Schreibt eine kleine Zusammenfassung für das Widget in die App Group (nur Namen, Beträge, Ablaufdaten und
/// Ladenfarben – keine Codes oder PINs). Gleiche Struktur wie `WidgetSnapshot` im Widget-Target.
/// Tage und Summe rechnet das Widget zur Anzeigezeit selbst. Läuft ohne Main Thread (der Store ruft es im Hintergrund).
nonisolated enum WidgetBridge {
    private struct Snapshot: Codable {
        struct Item: Codable {
            var id: String
            var name: String
            var headline: String
            var expires: Date
            /// Restwert in Euro, nur bei wertbasierten Gutscheinen (für die Summe).
            var amount: Double?
            /// Ladenfarbe als Hex (RRGGBB), nach denselben Regeln wie die Kacheln in der App (``MerchantBrand``).
            var color: String?

            var fingerprint: String { "\(id)|\(name)|\(headline)|\(expires.timeIntervalSince1970)|\(amount ?? -1)|\(color ?? "")" }
        }
        var items: [Item]
        var updated: Date
    }

    /// Eine serielle Queue: Aufrufe kehren sofort zurück (auch vom Main Thread aus, z. B. beim Aktivwerden),
    /// die Arbeit läuft nacheinander im Hintergrund. Doppelte Aufrufe mit gleichem Stand schreiben nichts
    /// und lösen keine zweite Zeitleisten-Aktualisierung aus (Vergleich unten).
    private static let queue = DispatchQueue(label: "de.restwert.widget", qos: .utility)

    /// `total` wird nicht mehr verwendet: Die Summe entsteht aus denselben Karten wie die Liste.
    static func update(cards: [GiftCard], total: Double = 0) {
        queue.async { write(cards) }
    }

    private static func write(_ cards: [GiftCard]) {
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.de.restwert.app") else {
            Logger(subsystem: "de.restwert.app", category: "widget").error("App Group nicht verfügbar")
            return
        }
        // Beispielkarten nur, solange es noch keine eigenen gibt.
        let own = cards.filter { !$0.isExample }
        let active = (own.isEmpty ? cards : own).filter { $0.isActive && !$0.forGifting }.sorted { $0.expires < $1.expires }
        let snap = Snapshot(items: active.prefix(200).map {
                                // Kalendertag als 12:00 Ortszeit: Das Widget rechnet Tage mit Calendar.current.
                                .init(id: $0.id.uuidString, name: $0.name, headline: $0.headline,
                                      expires: CalendarDay.local($0.expires),
                                      amount: $0.kind.isValueBased ? $0.balance : nil, color: brandHex($0))
                            },
                            updated: .now)
        guard let data = try? JSONEncoder().encode(snap) else { return }
        let url = dir.appending(path: "widget.json")
        // Unverändert (bis auf den Zeitstempel): Datei und Zeitleiste in Ruhe lassen.
        if let old = try? Data(contentsOf: url), let prev = try? JSONDecoder().decode(Snapshot.self, from: old),
           prev.items.map(\.fingerprint) == snap.items.map(\.fingerprint),
           Calendar.current.isDate(prev.updated, inSameDayAs: snap.updated) {
            return
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            Logger(subsystem: "de.restwert.app", category: "widget").error("Widget-Daten: \(error.localizedDescription, privacy: .public)")
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Kachelfarbe wie in der App: bekannte Läden in Hausfarbe, eigene Läden mit fester Farbe aus dem Namen.
    private static func brandHex(_ card: GiftCard) -> String? {
        let brand = MerchantBrand.forID(card.merchantID) ?? (card.name.isEmpty ? .neutral : MerchantBrand.fallback(for: card.name))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(brand.background).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "%02X%02X%02X", byte(r), byte(g), byte(b))
    }
}
