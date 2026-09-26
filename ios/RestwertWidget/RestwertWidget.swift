import WidgetKit
import SwiftUI

/// Kleine Zusammenfassung, die die App in die gemeinsame App Group schreibt.
/// Gleiche Struktur wie `WidgetSnapshot` in der App (bewusst doppelt, das Widget bindet RestwertKit nicht ein).
struct WidgetSnapshot: Codable {
    struct Item: Codable, Identifiable {
        var id: String
        var name: String
        var headline: String
        var daysLeft: Int
    }
    var total: String
    var count: Int
    var next: [Item]
    var updated: Date

    static let groupID = "group.de.restwert.app"

    static func load() -> WidgetSnapshot? {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appending(path: "widget.json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    static let sample = WidgetSnapshot(total: "136,25 €", count: 5, next: [
        Item(id: "", name: "Zalando", headline: "15 %", daysLeft: 12),
        Item(id: "", name: "IKEA", headline: "50,00 €", daysLeft: 24),
        Item(id: "", name: "Stadtgutschein", headline: "20,00 €", daysLeft: 140),
    ], updated: .now)
}

struct Entry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now, snapshot: .sample) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: .now, snapshot: context.isPreview ? .sample : WidgetSnapshot.load() ?? .sample))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        // Einmal täglich neu, damit „noch X Tage“ stimmt; die App löst bei Änderungen sofort ein Update aus.
        let tomorrow = Calendar.current.startOfDay(for: .now.addingTimeInterval(86_400))
        completion(Timeline(entries: [Entry(date: .now, snapshot: WidgetSnapshot.load())], policy: .after(tomorrow)))
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
                Text(snap.next.first.map { "\($0.name) \(dueText($0.daysLeft))" } ?? snap.total)
            case .systemMedium: medium(snap)
            default: small(snap)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Restwert").font(.headline)
                Text("Öffne die App einmal, dann erscheint hier dein Guthaben.").font(.caption)
            }
            .foregroundStyle(onBrand)
        }
    }

    private func small(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Guthaben").font(.caption.weight(.medium)).opacity(0.7)
            Text(s.total).font(.system(size: 26, weight: .bold)).minimumScaleFactor(0.6).lineLimit(1)
            Spacer(minLength: 4)
            if let n = s.next.first {
                Text(n.name).font(.caption.weight(.semibold)).lineLimit(1)
                Text("läuft \(dueText(n.daysLeft)) ab").font(.caption2).opacity(0.75)
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
                            Text(dueText(n.daysLeft)).font(.caption2).opacity(0.75)
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
                Text("\(n.name) läuft \(dueText(n.daysLeft)) ab").font(.caption).lineLimit(1)
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
