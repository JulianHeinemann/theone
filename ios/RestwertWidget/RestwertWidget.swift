import WidgetKit
import SwiftUI
import UIKit

/// Kleine Zusammenfassung, die die App in die gemeinsame App Group schreibt.
/// Gleiche Struktur wie `WidgetSnapshot` in der App (bewusst doppelt, das Widget bindet RestwertKit nicht ein).
struct WidgetSnapshot: Codable {
    struct Item: Codable, Identifiable {
        var id: String
        var name: String
        var headline: String
        var expires: Date
        var amount: Double?
        /// Ladenfarbe (RRGGBB) wie die Kachel in der App; fehlt bei älteren Daten.
        var color: String?

        /// Tage bis zum Ablauf, gerechnet vom Anzeigezeitpunkt aus.
        func daysLeft(at date: Date) -> Int {
            let cal = Calendar.current
            return cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: expires)).day ?? 0
        }
    }
    var items: [Item]
    var updated: Date
    /// App-Sperre oder Code-Schutz: die App schreibt dann keine Beträge. Fehlt bei älteren Daten.
    var isLocked: Bool? = nil

    /// Nur, was zum Zeitpunkt noch gültig ist.
    func valid(at date: Date) -> WidgetSnapshot {
        WidgetSnapshot(items: items.filter { $0.daysLeft(at: date) >= 0 }, updated: updated, isLocked: isLocked)
    }

    var next: [Item] { items }
    var count: Int { items.count }
    /// Mit App-Sperre schreibt die App keine Beträge: dann keine Summe von 0 € vortäuschen.
    /// Eigenes Feld; nur ältere Daten ohne Feld werden noch am Platzhalter „••••“ erkannt.
    var locked: Bool { isLocked ?? (!items.isEmpty && items.allSatisfy { $0.headline == "••••" }) }
    var total: String {
        if locked { return "Gesperrt" }
        return items.reduce(0) { $0 + ($1.amount ?? 0) }.formatted(.currency(code: "EUR").locale(Locale(identifier: "de_DE")))
    }

    static let groupID = "group.de.restwert.app"

    static func load() -> WidgetSnapshot? {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appending(path: "widget.json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    static var sample: WidgetSnapshot {
        let day = { (d: Double) in Date.now.addingTimeInterval(d * 86_400) }
        return WidgetSnapshot(items: [
            Item(id: "", name: "Zalando", headline: "15\u{00A0}%", expires: day(12), color: "FF6900"),
            Item(id: "", name: "IKEA", headline: "50,00\u{00A0}€", expires: day(24), amount: 50, color: "0058A3"),
            Item(id: "", name: "Stadtgutschein", headline: "20,00\u{00A0}€", expires: day(140), amount: 20, color: "52525B"),
        ], updated: .now)
    }
}

struct Entry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now, snapshot: .sample) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: .now, snapshot: (context.isPreview ? .sample : WidgetSnapshot.load() ?? .sample).valid(at: .now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        // Ein Eintrag je Tag (ab Mitternacht), damit „in X Tagen“ herunterzählt und Abgelaufenes verschwindet.
        // Die App löst bei Änderungen sofort ein Update aus.
        let snap = WidgetSnapshot.load()
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let entries = (0..<8).map { offset -> Entry in
            let date = offset == 0 ? Date.now : cal.date(byAdding: .day, value: offset, to: today) ?? today
            return Entry(date: date, snapshot: snap?.valid(at: date))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

/// Wie in der App (Theme.swift): Gelb #FFD84D hell, #F5CE3E dunkel; Schrift darauf Tinte #111111.
private let brandYellow = Color(light: 0xFFD84D, dark: 0xF5CE3E)
private let onBrand = Color(hex: 0x111111)

private extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }

    init(light: UInt32, dark: UInt32) {
        func ui(_ hex: UInt32) -> UIColor {
            UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
    }

    /// „0058A3“ → Farbe; nil bei ungültigem Wert.
    init?(hexString: String?) {
        guard let hexString, hexString.count == 6, let v = UInt32(hexString, radix: 16) else { return nil }
        self.init(hex: v)
    }
}

/// Kleine Kachel in Ladenfarbe vor dem Namen, wie in der App. Rein schmückend (für VoiceOver ausgeblendet).
private struct BrandDot: View {
    let hex: String?

    var body: some View {
        if let color = Color(hexString: hex) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color)
                .frame(width: 10, height: 10)
                .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(onBrand.opacity(0.25), lineWidth: 0.5))
                .accessibilityHidden(true)
        }
    }
}

private func dueText(_ d: Int) -> String {
    d <= 0 ? "heute" : d == 1 ? "morgen" : "in \(d)\u{00A0}Tagen"
}

struct RestwertWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry

    var body: some View {
        if let snap = entry.snapshot {
            switch family {
            case .accessoryRectangular: lockScreen(snap)
            case .accessoryInline:
                Text(snap.next.first.map { "\($0.name) \(dueText($0.daysLeft(at: entry.date)))" } ?? snap.total)
            case .systemMedium: medium(snap)
            default: small(snap)
            }
        } else {
            switch family {
            case .accessoryInline:
                Text("Restwert: App öffnen")
            case .accessoryRectangular:
                // Sperrbildschirm: Systemfarbe statt festem Schwarz, sonst im Vibrant-Modus kaum sichtbar.
                VStack(alignment: .leading, spacing: 1) {
                    Text("Restwert").font(.headline).widgetAccentable()
                    Text("App einmal öffnen").font(.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                VStack(alignment: .leading, spacing: 4) {
                    Text("Restwert").font(.headline)
                    Text("Öffne die App einmal, dann erscheint hier dein Guthaben.").font(.caption)
                }
                .foregroundStyle(onBrand)
            }
        }
    }

    private func small(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Guthaben").font(.caption.weight(.medium)).opacity(0.7)
            Text(s.total).font(.system(size: 26, weight: .bold)).minimumScaleFactor(0.6).lineLimit(1)
            Spacer(minLength: 4)
            if let n = s.next.first {
                HStack(spacing: 5) {
                    BrandDot(hex: n.color)
                    Text(n.name).font(.caption.weight(.semibold)).lineLimit(1)
                }
                Text("läuft \(dueText(n.daysLeft(at: entry.date))) ab").font(.caption2).opacity(0.75)
            } else {
                Text("\(s.count) Gutscheine").font(.caption)
            }
        }
        .foregroundStyle(onBrand)
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(s.next.first.flatMap { URL(string: "restwert://card/\($0.id)") })
    }

    private func medium(_ s: WidgetSnapshot) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Guthaben").font(.caption.weight(.medium)).opacity(0.7)
                Text(s.total).font(.system(size: 28, weight: .bold)).minimumScaleFactor(0.6).lineLimit(1)
                Text("\(s.count) Gutscheine").font(.caption).opacity(0.75)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                Text("Als Nächstes").font(.caption.weight(.medium)).opacity(0.7)
                ForEach(s.next.prefix(3)) { n in
                    Link(destination: URL(string: "restwert://card/\(n.id)")!) {
                        HStack(spacing: 5) {
                            BrandDot(hex: n.color)
                            Text(n.name).font(.caption.weight(.semibold)).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(dueText(n.daysLeft(at: entry.date))).font(.caption2).opacity(0.75)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(onBrand)
    }

    private func lockScreen(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(s.total).font(.headline).widgetAccentable()
            if let n = s.next.first {
                Text("\(n.name) läuft \(dueText(n.daysLeft(at: entry.date))) ab").font(.caption).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(s.next.first.flatMap { URL(string: "restwert://card/\($0.id)") })
    }
}

struct RestwertWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RestwertSummary", provider: Provider()) { entry in
            RestwertWidgetView(entry: entry)
                .containerBackground(brandYellow, for: .widget)
        }
        .configurationDisplayName("Restwert")
        .description("Dein Guthaben und was als Nächstes abläuft.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct RestwertWidgets: WidgetBundle {
    var body: some Widget { RestwertWidget() }
}
