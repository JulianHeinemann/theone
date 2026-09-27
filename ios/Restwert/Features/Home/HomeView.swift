import SwiftUI
import RestwertKit

struct HomeView: View {
    let zoom: Namespace.ID
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @AppStorage("sortOrder") private var sortRaw = CardSortOrder.expiry.rawValue
    @AppStorage("warnDays") private var warnDays = 30

    @State private var query = ""
    @State private var filter: CardFilter = .all
    @State private var showDone = false
    @State private var deleting: GiftCard?

    private var order: CardSortOrder { CardSortOrder(rawValue: sortRaw) ?? .expiry }

    var body: some View {
        // Alle Listen einmal pro Durchlauf, nicht pro Abschnitt oder Karte.
        let lists = HomeLists(cards: store.cards, order: order, warnDays: warnDays, filter: filter, query: query)
        ScrollView {
            VStack(alignment: .leading, spacing: Layout.section) {
                // Der Kopf beschreibt immer den ganzen Bestand, unabhängig von Filter und Suche.
                TotalHeader(total: store.total, cards: lists.active.filter { !$0.forGifting }, soon: lists.dueSoonCount,
                            saved: lists.saved, examples: lists.examplesOnly)
                if store.cards.isEmpty {
                    EmptyState { router.tab = .scan }
                } else {
                    // Dringendes zuerst, damit es ohne Scrollen sichtbar ist. Die Suche wirkt hier, die Chips erst darunter.
                    section("Läuft bald ab", cards: lists.dueSoon)
                    if !lists.active.isEmpty {
                        ExpiryRadarSection(items: lists.active.map { RadarItem(card: $0) },
                                           onSelect: { router.homePath.append(.card($0.id)) },
                                           onShowAll: { router.homePath.append(.radar) })
                    }
                    if lists.showFilters { filterBar(lists) }
                    if lists.searchEmpty {
                        ContentUnavailableView.search(text: lists.query)
                    } else if lists.filterEmpty {
                        ContentUnavailableView(lists.query.isEmpty ? "Keine Gutscheine in diesem Filter" : "Keine Treffer in diesem Filter",
                                               systemImage: "line.3.horizontal.decrease.circle")
                    }
                    // Mit Filter zeigt die Liste alles Passende, auch was oben unter „Läuft bald ab“ steht.
                    // Der Zoom-Übergang hängt dann nur an der oberen Zeile, sonst gäbe es zwei Quellen mit derselben ID.
                    section(listTitle(lists), cards: lists.list, sortable: true,
                            zoomSkip: lists.activeFilter == .all ? [] : Set(lists.dueSoon.map(\.id)))
                    NavigationLink(value: Route.radar) {
                        Label("Alle Ablauftermine", systemImage: "calendar")
                            .font(.scaled(16, weight: .semibold)).foregroundStyle(Color.ink)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(Color.surface, in: .rect(cornerRadius: Layout.cardRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    if !lists.done.isEmpty { doneSection(lists.done) }
                }
            }
            .padding(.horizontal, Layout.page)
            .padding(.top, 4)
            .padding(.bottom, Layout.section)
        }
        .scrollIndicators(.hidden)
        // Solange der Rückgängig-Hinweis über der Tab-Leiste steht, lässt sich das Listenende darüber schieben.
        .safeAreaPadding(.bottom, router.toast == nil ? 0 : 88)
        .pageBackground()
        .navigationTitle("Restwert")
        .toolbarTitleDisplayMode(.inline)
        // Wortmarke und Suchfeld stehen fest oben und bleiben beim Scrollen sichtbar.
        .toolbar {
            ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) }
            // Das Toolbar-Element bringt rund 4 pt Eigenabstand mit; zurückgeschoben fluchtet die Marke mit Suchfeld und Ticket (16 pt).
            ToolbarItem(placement: .topBarLeading) { Wordmark(size: 28).fixedSize().offset(x: -4) }
                .sharedBackgroundVisibility(.hidden)
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Gutschein, Code oder Notiz")
        .onChange(of: lists.offered) { _, offered in
            if !offered.contains(filter) { withAnimation(.snappy) { filter = .all } }
        }
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

    private func listTitle(_ lists: HomeLists) -> String {
        if lists.activeFilter != .all { return chipTitle(lists.activeFilter) }
        return lists.dueSoon.isEmpty ? "Deine Gutscheine" : "Weitere"
    }

    @ViewBuilder
    private func section(_ title: String, cards: [GiftCard], sortable: Bool = false, zoomSkip: Set<UUID> = []) -> some View {
        if !cards.isEmpty {
            VStack(alignment: .leading, spacing: Layout.group) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.scaled(15, weight: .semibold)).foregroundStyle(Color.ink2)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    if sortable { sortMenu }
                }
                VStack(spacing: 0) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { i, c in
                        if i > 0 { Divider().padding(.leading, 72) }
                        HStack(spacing: 0) {
                            NavigationLink(value: Route.card(c.id)) {
                                if zoomSkip.contains(c.id) {
                                    CardRow(card: c, warnDays: warnDays)
                                } else {
                                    CardRow(card: c, warnDays: warnDays).matchedTransitionSource(id: c.id, in: zoom)
                                }
                            }
                            .buttonStyle(.plain)
                            // Sichtbarer Weg zu Kasse, Bearbeiten, Archivieren, Entfernen (nicht nur langes Drücken).
                            Menu { rowMenu(c) } label: {
                                Image(systemName: "ellipsis").font(.scaled(15, weight: .semibold)).foregroundStyle(Color.ink2)
                                    .frame(width: Layout.tap, height: Layout.tap).contentShape(.rect)
                            }
                            .accessibilityLabel("Aktionen für \(c.name)")
                            .padding(.trailing, 4)
                        }
                        .contextMenu { rowMenu(c) }
                    }
                }
                .background(Color.surface, in: .rect(cornerRadius: Layout.cardRadius, style: .continuous))
            }
            .animation(.snappy, value: cards.map(\.id))
        }
    }

    private func filterBar(_ lists: HomeLists) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(lists.offered, id: \.self) { value in
                    FilterChip(title: chipTitle(value), on: lists.activeFilter == value) {
                        withAnimation(.snappy) { filter = value }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        // Chips dürfen beim Scrollen bis zum Rand laufen, ohne die Spalte breiter zu machen.
        .scrollClipDisabled()
        .sensoryFeedback(.selection, trigger: lists.activeFilter)
    }

    private func chipTitle(_ value: CardFilter) -> String {
        switch value {
        case .all: "Alle"
        case .balance: "Guthaben"
        case .codes: "Rabattcodes"
        case .gifts: "Zum Verschenken"
        case .owner(let name): "Für \(name)"
        }
    }

    @ViewBuilder
    private func rowMenu(_ c: GiftCard) -> some View {
        if c.isActive {
            Button("An der Kasse zeigen", systemImage: "barcode") { router.homePath.append(.checkout(c.id)) }
        }
        Button("Bearbeiten", systemImage: "pencil") { router.editing = c }
        Button(c.isArchived ? "Wiederherstellen" : "Archivieren", systemImage: c.isArchived ? "tray.and.arrow.up" : "archivebox") {
            let archive = !c.isArchived
            withAnimation(.snappy) { store.setArchived(c.id, archive) }
            if archive {
                router.showUndo("„\(c.name)“ archiviert") { withAnimation(.snappy) { store.setArchived(c.id, false) } }
            }
        }
        Button("Entfernen", systemImage: "trash", role: .destructive) { deleting = c }
    }

    /// Aufgebrauchte, abgelaufene und archivierte Gutscheine, eingeklappt, damit die Liste ruhig bleibt.
    private func doneSection(_ done: [GiftCard]) -> some View {
        VStack(alignment: .leading, spacing: Layout.group) {
            Button {
                withAnimation(.snappy) { showDone.toggle() }
            } label: {
                HStack {
                    Text("Erledigt & archiviert (\(done.count))")
                        .font(.scaled(15, weight: .semibold)).foregroundStyle(Color.ink2)
                    Spacer()
                    Image(systemName: "chevron.down").rotationEffect(.degrees(showDone ? 180 : 0))
                        .font(.scaled(13, weight: .semibold)).foregroundStyle(Color.muted)
                }
                .frame(minHeight: Layout.tap).contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(showDone ? "aufgeklappt" : "eingeklappt")
            if showDone {
                VStack(spacing: 0) {
                    ForEach(Array(done.enumerated()), id: \.element.id) { i, c in
                        if i > 0 { Divider().padding(.leading, 72) }
                        HStack(spacing: 0) {
                            NavigationLink(value: Route.card(c.id)) { CardRow(card: c, warnDays: warnDays) }
                                .buttonStyle(.plain)
                            Button("Entfernen", systemImage: "trash") { deleting = c }
                                .labelStyle(.iconOnly).accessibilityLabel("\(c.name) entfernen").foregroundStyle(Color.bad)
                                .frame(width: Layout.tap, height: Layout.tap).padding(.trailing, 4)
                        }
                        .contextMenu { rowMenu(c) }
                    }
                }
                .background(Color.surface, in: .rect(cornerRadius: Layout.cardRadius, style: .continuous))
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sortierung", selection: $sortRaw) {
                ForEach(CardSortOrder.allCases) { Text($0.label).tag($0.rawValue) }
            }
        } label: {
            HStack(spacing: 4) {
                Text(order.label)
                Image(systemName: "chevron.up.chevron.down").font(.scaled(12, weight: .semibold))
            }
            .font(.scaled(15)).foregroundStyle(Color.muted)
            .frame(minHeight: Layout.tap).contentShape(.rect)
        }
        .accessibilityLabel("Sortierung: \(order.label)")
    }
}

// MARK: - Listen

/// Alles, was die Startseite aus dem Bestand ableitet. Restlaufzeiten werden je Karte einmal gerechnet,
/// nicht in jedem Sortiervergleich neu (dort kostet jede Kalenderrechnung).
private struct HomeLists {
    /// Aktive Gutscheine nach Ablauf – für Kopf und Radar, ohne Filter.
    private(set) var active: [GiftCard] = []
    /// Bald ablaufend (ohne Verschenken), mit Suche, ohne Chip-Filter.
    private(set) var dueSoon: [GiftCard] = []
    /// Bald ablaufend im ganzen Bestand, für den Kopf.
    private(set) var dueSoonCount = 0
    /// Hauptliste: ohne Filter alles Übrige, mit Filter alles Passende.
    private(set) var list: [GiftCard] = []
    private(set) var done: [GiftCard] = []
    private(set) var offered: [CardFilter] = [.all]
    private(set) var activeFilter: CardFilter = .all
    private(set) var showFilters = false
    /// Summe echter Abzüge aus dem Verlauf, ohne Beispiele.
    private(set) var saved: Double = 0
    private(set) var examplesOnly = false
    let query: String

    var searchEmpty: Bool { !query.isEmpty && dueSoon.isEmpty && list.isEmpty && done.isEmpty }
    var filterEmpty: Bool { activeFilter != .all && list.isEmpty && done.isEmpty }

    private struct Entry {
        let card: GiftCard
        let days: Int
        let active: Bool
        let name: String
    }

    init(cards: [GiftCard], order: CardSortOrder, warnDays: Int, filter: CardFilter, query rawQuery: String, now: Date = .now) {
        query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let entries = cards.map { c in
            let d = c.daysLeft(now: now)
            return Entry(card: c, days: d, active: c.isOpen && d >= 0 && !c.isArchived, name: c.name)
        }
        // Wie CardQueries.sorted: offene zuerst, dann nach gewählter Ordnung.
        let sorted = entries.sorted { a, b in
            if a.active != b.active { return a.active }
            switch order {
            case .expiry: return a.card.expires < b.card.expires
            case .value: return a.card.balance > b.card.balance
            case .shop: return a.name.localizedCompare(b.name) == .orderedAscending
            }
        }
        let activeEntries = order == .expiry
            ? sorted.filter(\.active)
            : entries.filter(\.active).sorted { $0.card.expires < $1.card.expires }
        active = activeEntries.map(\.card)

        // Chips, sobald es mehr als eine Art gibt; bei ganz wenigen Karten wären sie nur Ballast.
        let owners = Set(cards.map(\.owner).filter { !$0.isEmpty }).sorted()
        let hasBalance = cards.contains { $0.kind.isValueBased && !$0.forGifting }
        let hasCodes = cards.contains { !$0.kind.isValueBased }
        let hasGifts = cards.contains(where: \.forGifting)
        let kinds = [hasBalance, hasCodes, hasGifts].filter { $0 }.count + owners.count
        showFilters = cards.count > 3 && kinds > 1
        if showFilters {
            var f: [CardFilter] = [.all]
            if hasBalance { f.append(.balance) }
            if hasCodes { f.append(.codes) }
            if hasGifts { f.append(.gifts) }
            offered = f + owners.map { .owner($0) }
        }
        // Verschwindet der Chip des gewählten Filters, gilt wieder „Alle“, sonst bliebe die Liste ohne Ausweg leer.
        activeFilter = offered.contains(filter) ? filter : .all

        let search = Search(query)
        let chip = activeFilter
        func passesChip(_ c: GiftCard) -> Bool {
            switch chip {
            case .all: true
            case .balance: c.kind.isValueBased && !c.forGifting
            case .codes: !c.kind.isValueBased
            case .gifts: c.forGifting
            case .owner(let name): c.owner == name
            }
        }

        let due = activeEntries.filter { $0.days <= warnDays && !$0.card.forGifting }
        dueSoonCount = due.count
        dueSoon = due.map(\.card).filter(search.matches)
        let dueIDs = Set(dueSoon.map(\.id))
        list = sorted.compactMap { e in
            guard e.active, search.matches(e.card) else { return nil }
            if chip == .all { return dueIDs.contains(e.card.id) ? nil : e.card }
            return passesChip(e.card) ? e.card : nil
        }
        done = sorted.compactMap { e in !e.active && search.matches(e.card) && passesChip(e.card) ? e.card : nil }

        let real = cards.filter { !$0.isExample }
        saved = (real.reduce(0) { sum, c in sum + c.history.reduce(0) { $0 + max(0, $1.amount) } } * 100).rounded() / 100
        examplesOnly = !cards.isEmpty && real.isEmpty
    }

    /// Suche über Name, „für wen“, Ort und Notiz, Art, Betrag/Prozent und Kartennummer.
    private struct Search {
        let text: String
        /// Ohne Leerzeichen, damit „1234 5678“ und „12345678“ gleich gefunden werden.
        let compact: String

        init(_ query: String) {
            text = query
            compact = query.filter { !$0.isWhitespace }
        }

        func matches(_ c: GiftCard) -> Bool {
            guard !text.isEmpty else { return true }
            for field in [c.name, c.owner, c.locationNote, c.location.label, c.kind.label]
            where field.localizedCaseInsensitiveContains(text) { return true }
            // „15 %“ und „15%“ gleich behandeln, ebenso Beträge wie „12,40 €“.
            if c.headline.filter({ !$0.isWhitespace }).localizedCaseInsensitiveContains(compact) { return true }
            // Nummern erst ab drei Zeichen, sonst trifft jede Ziffer fast jede Karte.
            if compact.count >= 3, c.number.filter({ !$0.isWhitespace && $0 != "-" }).localizedCaseInsensitiveContains(compact.filter { $0 != "-" }) {
                return true
            }
            return false
        }
    }
}

// MARK: - Bausteine

/// Offenes Guthaben als ruhige Zahl, ohne Deko.
private struct TotalHeader: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let total: Double
    let cards: [GiftCard]
    let soon: Int
    /// Schon eingelöst (echte Abzüge aus dem Verlauf), klein im Fuß – nur wenn es etwas gibt.
    var saved: Double = 0
    var examples = false
    @State private var tearY: CGFloat = 110

    /// Die Summe enthält nur Euro-Guthaben. Rabattcodes stehen extra, damit die Rechnung aufgeht.
    private var caption: String {
        let value = cards.filter(\.kind.isValueBased).count
        var parts = [value == 1 ? "1 Gutschein" : "\(value) Gutscheine"]
        if soon > 0 { parts.append(soon == 1 ? "1 läuft bald ab" : "\(soon) laufen bald ab") }
        return parts.joined(separator: " · ")
    }

    private var codesNote: String? {
        let codes = cards.filter { !$0.kind.isValueBased }.count
        guard codes > 0 else { return nil }
        return codes == 1 ? "+ 1 Rabattcode, nicht in der Summe" : "+ \(codes) Rabattcodes, nicht in der Summe"
    }

    var body: some View {
        let big = !typeSize.isAccessibilitySize
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Noch drauf").font(.scaled(15, weight: .semibold)).opacity(0.75)
                AmountText(value: total, size: big ? 60 : 36)
                    .animation(.snappy, value: total)
            }
            .padding(.horizontal, Layout.ticketInset).padding(.top, Layout.ticketInset).padding(.bottom, Layout.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Gemessen, damit die Kerben bei jeder Schriftgröße genau auf der Abrisslinie sitzen.
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { tearY = $0 }
            // Abrisslinie auf Höhe der Kerben: oben der Betrag, unten der Abschnitt.
            TearLine(color: .sumText).padding(.horizontal, Layout.inset)
            VStack(alignment: .leading, spacing: 2) {
                Text(caption).font(.scaled(15, weight: .semibold))
                if let codesNote { Text(codesNote).font(.scaled(13)).opacity(0.75) }
                if saved > 0 { Text("\(saved.euro) schon eingelöst").font(.scaled(13)).opacity(0.75) }
                if examples { Text("Nur Beispiele – dein erster Gutschein ersetzt sie").font(.scaled(13)).opacity(0.75) }
            }
            .padding(.horizontal, Layout.ticketInset).padding(.vertical, Layout.group)
        }
        .foregroundStyle(Color.sumText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sumFill, in: TicketShape(radius: Layout.cardRadius, notchRadius: 9, notchFromTop: tearY + 0.5))
        .accessibilityElement(children: .combine)
    }
}


private struct EmptyState: View {
    let onScan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Noch keine Gutscheine").font(.scaled(17, weight: .semibold))
            Text("Fotografier deinen Gutschein, füg eine Gutschein-Mail ein oder tipp den Code ab.")
                .font(.scaled(15)).foregroundStyle(Color.ink2)
            Button("Ersten Gutschein erfassen", action: onScan).buttonStyle(.accent)
        }
        .padding(20)
        .background(Color.surface, in: .rect(cornerRadius: Layout.cardRadius, style: .continuous))
    }
}

enum CardFilter: Hashable {
    case all, balance, codes, gifts
    case owner(String)
}
