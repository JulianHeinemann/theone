import WidgetKit
import SwiftUI

/// Kleine Zusammenfassung, die die App in die gemeinsame App Group schreibt.
/// Gleiche Struktur wie `WidgetSnapshot` in der App (bewusst doppelt, das Widget bindet RestwertKit nicht ein).
struct WidgetSnapshot: Codable {
    struct Item: Codable, Identifiable {
        var id: String
        var name: String
        var headline: String
        var expires: Date
        var amount: Double?

        /// Tage bis zum Ablauf, gerechnet vom Anzeigezeitpunkt aus.
        func daysLeft(at date: Date) -> Int {
            let cal = Calendar.current
            return cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: expires)).day ?? 0
        }
    }
    var items: [Item]
    var updated: Date

    /// Nur, was zum Zeitpunkt noch gültig ist.
    func valid(at date: Date) -> WidgetSnapshot {
        WidgetSnapshot(items: items.filter { $0.daysLeft(at: date) >= 0 }, updated: updated)
    }

    var next: [Item] { items }
    var count: Int { items.count }
    var total: String {
        items.reduce(0) { $0 + ($1.amount ?? 0) }.formatted(.currency(code: "EUR").locale(Locale(identifier: "de_DE")))
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
            Item(id: "", name: "Zalando", headline: "15 %", expires: day(12)),
            Item(id: "", name: "IKEA", headline: "50,00 €", expires: day(24), amount: 50),
            Item(id: "", name: "Stadtgutschein", headline: "20,00 €", expires: day(140), amount: 20),
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

private let brandYellow = Color(red: 1, green: 0.882, blue: 0.302)
private let onBrand = Color(red: 0.055, green: 0.055, blue: 0.063)

private func dueText(_ d: Int) -> String {
    d <= 0 ? "heute" : d == 1 ? "morgen" : "in \(d) Tagen"
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
                Text(n.name).font(.caption.weight(.semibold)).lineLimit(1)
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
                        HStack {
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
