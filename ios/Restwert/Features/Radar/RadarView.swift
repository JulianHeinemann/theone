import SwiftUI
import RestwertKit

/// Ablauftermine nach Monat gruppiert. Früher ein animiertes Radar, jetzt eine schlichte Liste,
/// weil die Frage immer dieselbe ist: Was muss ich wann einlösen?
struct RadarView: View {
    @Environment(Store.self) private var store
    @AppStorage("warnDays") private var warnDays = 30
    /// Namespace des Zoom-Übergangs zum Detail. Ohne ihn keine Quelle, dann blendet das Detail normal ein.
    var zoom: Namespace.ID? = nil

    private var months: [(key: Date, cards: [GiftCard])] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: store.activeCards) {
            cal.date(from: cal.dateComponents([.year, .month], from: $0.expires)) ?? $0.expires
        }
        return groups.keys.sorted().map { key in (key, (groups[key] ?? []).sorted { $0.expires < $1.expires }) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if months.isEmpty {
                    Text("Keine offenen Gutscheine.").foregroundStyle(Color.muted).padding(.top, 20)
                }
                ForEach(months, id: \.key) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(group.key.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "de_DE"))))
                                .font(.scaled(15, weight: .semibold)).foregroundStyle(Color.ink2)
                            Spacer()
                            // Summe der sichtbaren Euro-Guthaben, Geschenk-Gutscheine eingeschlossen, damit sie zu den Zeilen passt.
                            let total = group.cards.filter(\.kind.isValueBased).reduce(0) { $0 + $1.balance }
                            if total > 0 {
                                Text("\(total.euro) Guthaben")
                                    .font(.scaled(14)).monospacedDigit().foregroundStyle(Color.muted)
                                    .accessibilityLabel("\(total.euro) Guthaben laufen in diesem Monat ab")
                            }
                        }
                        .padding(.horizontal, 4)
                        VStack(spacing: 0) {
                            ForEach(Array(group.cards.enumerated()), id: \.element.id) { i, card in
                                if i > 0 { Divider().padding(.leading, 72) }
                                NavigationLink(value: Route.card(card.id)) {
                                    if let zoom {
                                        CardRow(card: card, warnDays: warnDays).matchedTransitionSource(id: card.id, in: zoom)
                                    } else {
                                        CardRow(card: card, warnDays: warnDays)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .background(Color.surface, in: .rect(cornerRadius: 18, style: .continuous))
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .pageBackground()
        .toolbar(.hidden, for: .tabBar)
        .navigationTitle("Ablauftermine")
        .navigationBarTitleDisplayMode(.inline)
    }
}
