import SwiftUI
import RestwertKit

/// Ablauftermine nach Monat gruppiert, darüber das Verfallsradar.
/// Die Frage ist immer dieselbe: Was muss ich wann einlösen – und wie viel hängt daran?
struct RadarView: View {
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("warnDays") private var warnDays = 30
    /// Namespace des Zoom-Übergangs zum Detail. Ohne ihn keine Quelle, dann blendet das Detail normal ein.
    var zoom: Namespace.ID? = nil

    @State private var deleting: GiftCard?

    private static func monthKey(_ d: Date) -> Date {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: d)) ?? d
    }

    /// Eigene Fristen: selbst ausgegebene Gutscheine (Café) laufen beim Kunden ab, nicht hier.
    private var own: [GiftCard] { store.activeCards.filter { !$0.issuedByMe } }

    private var months: [(key: Date, cards: [GiftCard])] {
        let groups = Dictionary(grouping: own) { Self.monthKey($0.expires) }
        return groups.keys.sorted().map { key in (key, (groups[key] ?? []).sorted { $0.expires < $1.expires }) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Layout.section) {
                    if !own.isEmpty {
                        ExpiryRadarSection(items: own.map { RadarItem(card: $0) },
                                           onSelect: { router.homePath.append(.card($0.id)) },
                                           onBundle: { items in
                                               // Bündel: zum Monat des frühesten Termins springen.
                                               guard let first = items.map(\.expires).min() else { return }
                                               withAnimation(reduceMotion ? nil : .snappy) {
                                                   proxy.scrollTo(Self.monthKey(first), anchor: .top)
                                               }
                                           })
                    }
                    if months.isEmpty {
                        Text("Keine offenen Gutscheine.").foregroundStyle(Color.muted).padding(.top, 20)
                    }
                    ForEach(months, id: \.key) { group in
                        monthSection(group.key, cards: group.cards).id(group.key)
                    }
                }
                .padding(.horizontal, Layout.page).padding(.top, 8).padding(.bottom, Layout.section)
            }
        }
        .scrollIndicators(.hidden)
        .pageBackground()
        .readableWidth()
        .toolbar(.hidden, for: .tabBar)
        .navigationTitle("Ablauftermine")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("„\(deleting?.name ?? "")“ endgültig entfernen?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Entfernen", role: .destructive) {
                if let c = deleting {
                    withAnimation(.snappy) { store.delete(c.id) }
                    router.showUndo("„\(c.name)“ entfernt") { withAnimation(.snappy) { store.undoDelete(c) } }
                }
                deleting = nil
            }
        }
    }

    private func monthSection(_ key: Date, cards: [GiftCard]) -> some View {
        VStack(alignment: .leading, spacing: Layout.group) {
            HStack(alignment: .firstTextBaseline) {
                Text(key.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "de_DE"))))
                    .font(.scaled(15, weight: .semibold)).foregroundStyle(Color.ink2)
                Spacer(minLength: 8)
                // Summe der sichtbaren Euro-Guthaben, Geschenk-Gutscheine eingeschlossen, damit sie zu den Zeilen passt.
                let total = cards.filter(\.kind.isValueBased).reduce(0) { $0 + $1.balance }
                if total > 0 {
                    Text("\(total.euro) Guthaben")
                        .font(.scaled(15)).monospacedDigit().foregroundStyle(Color.muted)
                        .accessibilityLabel("\(total.euro) Guthaben laufen in diesem Monat ab")
                }
            }
            // Summe fluchtet mit den Beträgen der Zeilen (Zeilenrand + „…“-Knopf); gestapelte Zeilen haben keine Spalte.
            .padding(.trailing, typeSize.isAccessibilitySize ? 0 : Layout.tap + 8)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { i, card in
                    if i > 0 { Divider().padding(.leading, 72) }
                    // Aufbau wie auf dem Start: Zeile, daneben „…“ – so fluchten die Beträge.
                    HStack(spacing: 0) {
                        NavigationLink(value: Route.card(card.id)) {
                            if let zoom {
                                CardRow(card: card, warnDays: warnDays).matchedTransitionSource(id: card.id, in: zoom)
                            } else {
                                CardRow(card: card, warnDays: warnDays)
                            }
                        }
                        .buttonStyle(.plain)
                        Menu { rowMenu(card) } label: {
                            Image(systemName: "ellipsis").font(.scaled(15, weight: .semibold)).foregroundStyle(Color.ink2)
                                .frame(width: Layout.tap, height: Layout.tap).contentShape(.rect)
                        }
                        .accessibilityLabel("Aktionen für \(card.name)")
                        .padding(.trailing, 4)
                    }
                    .contextMenu { rowMenu(card) }
                }
            }
            .background(Color.surface, in: .rect(cornerRadius: Layout.cardRadius, style: .continuous)).modifier(ContrastEdge())
        }
        .animation(.snappy, value: cards.map(\.id))
    }

    /// Dieselben Aktionen wie auf dem Start.
    @ViewBuilder
    private func rowMenu(_ c: GiftCard) -> some View {
        if c.isActive {
            Button("An der Kasse zeigen", systemImage: "barcode") { router.homePath.append(.checkout(c.id)) }
        }
        Button("Bearbeiten", systemImage: "pencil") {
            // Im Formular steht der Code offen: bei Code-Schutz erst entsperren.
            if DeviceSecurity.codeLockActive {
                Task { if await DeviceSecurity.revealCode(of: c.name) { router.editing = c } }
            } else {
                router.editing = c
            }
        }
        Button(c.isArchived ? "Wiederherstellen" : "Archivieren", systemImage: c.isArchived ? "tray.and.arrow.up" : "archivebox") {
            let archive = !c.isArchived
            withAnimation(.snappy) { store.setArchived(c.id, archive) }
            if archive {
                router.showUndo("„\(c.name)“ archiviert") { withAnimation(.snappy) { store.setArchived(c.id, false) } }
            }
        }
        Button("Entfernen", systemImage: "trash", role: .destructive) { deleting = c }
    }
}
