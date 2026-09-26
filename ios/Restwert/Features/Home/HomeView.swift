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

    private var order: CardSortOrder { CardSortOrder(rawValue: sortRaw) ?? .expiry }
    private var sorted: [GiftCard] { store.cards(sortedBy: order).filter(matches) }
    private var dueSoon: [GiftCard] {
        store.activeCards.filter { $0.status(warnDays: warnDays) == .expiringSoon && !$0.forGifting }.filter(matches)
    }
    private var owners: [String] {
        Array(Set(store.cards.map(\.owner).filter { !$0.isEmpty })).sorted()
    }
    private var showFilters: Bool {
        !owners.isEmpty || store.cards.contains(where: \.forGifting) || store.cards.contains { !$0.kind.isValueBased }
    }

    private func matches(_ c: GiftCard) -> Bool {
        if !query.isEmpty && !c.name.localizedCaseInsensitiveContains(query) && !c.owner.localizedCaseInsensitiveContains(query) { return false }
        switch filter {
        case .all: return true
        case .balance: return c.kind.isValueBased && !c.forGifting
        case .codes: return !c.kind.isValueBased
        case .gifts: return c.forGifting
        case .owner(let name): return c.owner == name
        }
    }
    private var rest: [GiftCard] {
        let due = Set(dueSoon.map(\.id))
        return sorted.filter { $0.isActive && !due.contains($0.id) }
    }
    private var done: [GiftCard] { sorted.filter { !$0.isActive } }
    @State private var showDone = false
    @State private var deleting: GiftCard?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                TotalHeader(total: store.total, cards: store.activeCards.filter { !$0.forGifting }, soon: dueSoon.count)
                if showFilters { filterBar }
                if store.cards.isEmpty {
                    EmptyState { router.tab = .scan }
                } else {
                    if !dueSoon.isEmpty {
                        section("Läuft bald ab", cards: dueSoon)
                    }
                    section(dueSoon.isEmpty ? "Deine Gutscheine" : "Weitere", cards: rest, sortable: true)
                    NavigationLink(value: Route.radar) {
                        Label("Alle Ablauftermine", systemImage: "calendar")
                            .font(.scaled(16, weight: .semibold)).foregroundStyle(Color.ink)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Color.surface, in: .rect(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    if !done.isEmpty { doneSection }
                }
                if store.hasExamples {
                    Button("Beispielkarten entfernen") { withAnimation(.smooth) { store.clearExamples() } }
                        .font(.scaled(15, weight: .medium)).foregroundStyle(Color.muted)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .pageBackground()
        .navigationTitle("Restwert")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Gutschein suchen")
        .confirmationDialog("„\(deleting?.name ?? "")“ endgültig entfernen?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Entfernen", role: .destructive) {
                if let c = deleting { withAnimation(.snappy) { store.delete(c.id) } }
                deleting = nil
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, cards: [GiftCard], sortable: Bool = false) -> some View {
        if !cards.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.scaled(15, weight: .semibold)).foregroundStyle(Color.ink2)
                    Spacer()
                    if sortable { sortMenu }
                }
                .padding(.horizontal, 4)
                VStack(spacing: 0) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { i, c in
                        if i > 0 { Divider().padding(.leading, 72) }
                        NavigationLink(value: Route.card(c.id)) {
                            CardRow(card: c, warnDays: warnDays)
                                .matchedTransitionSource(id: c.id, in: zoom)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { rowMenu(c) }
                    }
                }
                .background(Color.surface, in: .rect(cornerRadius: 18, style: .continuous))
            }
            .animation(.snappy, value: cards.map(\.id))
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip("Alle", .all)
                chip("Guthaben", .balance)
                if store.cards.contains(where: { !$0.kind.isValueBased }) { chip("Rabattcodes", .codes) }
                if store.cards.contains(where: \.forGifting) { chip("Zum Verschenken", .gifts) }
                ForEach(owners, id: \.self) { chip("Für \($0)", .owner($0)) }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -16)
        .sensoryFeedback(.selection, trigger: filter)
    }

    private func chip(_ title: String, _ value: CardFilter) -> some View {
        let on = filter == value
        return Button { withAnimation(.snappy) { filter = value } } label: {
            Text(title).font(.scaled(14, weight: .semibold))
                .foregroundStyle(on ? Color.white : Color.ink)
                .padding(.horizontal, 14).frame(minHeight: 36)
                .background(on ? Color.ink : Color.surface, in: .capsule)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func rowMenu(_ c: GiftCard) -> some View {
        if c.isActive {
            Button("An der Kasse zeigen", systemImage: "barcode") { router.homePath.append(.checkout(c.id)) }
        }
        Button("Bearbeiten", systemImage: "pencil") { router.editing = c }
        Button(c.isArchived ? "Wiederherstellen" : "Archivieren", systemImage: c.isArchived ? "tray.and.arrow.up" : "archivebox") {
            withAnimation(.snappy) { store.setArchived(c.id, !c.isArchived) }
        }
        Button("Entfernen", systemImage: "trash", role: .destructive) { deleting = c }
    }

    /// Aufgebrauchte, abgelaufene und archivierte Gutscheine, eingeklappt, damit die Liste ruhig bleibt.
    private var doneSection: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                .padding(.horizontal, 4).contentShape(.rect)
            }
            .buttonStyle(.plain)
            if showDone {
                VStack(spacing: 0) {
                    ForEach(Array(done.enumerated()), id: \.element.id) { i, c in
                        if i > 0 { Divider().padding(.leading, 72) }
                        HStack(spacing: 0) {
                            NavigationLink(value: Route.card(c.id)) { CardRow(card: c, warnDays: warnDays) }
                                .buttonStyle(.plain)
                            Button("Entfernen", systemImage: "trash") { deleting = c }
                                .labelStyle(.iconOnly).foregroundStyle(Color.bad)
                                .frame(width: 44, height: 44).padding(.trailing, 8)
                        }
                        .contextMenu { rowMenu(c) }
                    }
                }
                .background(Color.surface, in: .rect(cornerRadius: 18, style: .continuous))
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
                Image(systemName: "chevron.up.chevron.down").font(.scaled(11, weight: .semibold))
            }
            .font(.scaled(14)).foregroundStyle(Color.muted)
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

    /// Die Summe enthält nur Euro-Guthaben. Rabattcodes stehen in einer eigenen Zeile, damit die Rechnung aufgeht.
    private var caption: String {
        let value = cards.filter(\.kind.isValueBased).count
        var parts = [value == 1 ? "1 Karte" : "\(value) Karten"]
        if soon > 0 { parts.append(soon == 1 ? "1 läuft bald ab" : "\(soon) laufen bald ab") }
        return parts.joined(separator: " · ")
    }

    private var full: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Guthaben auf allen Karten").font(.scaled(15, weight: .medium)).foregroundStyle(Color.ink.opacity(0.7))
            Text(total.euro)
                .font(.scaled(60, weight: .bold)).kerning(-2).monospacedDigit()
                .contentTransition(.numericText(value: total))
                .animation(.snappy, value: total)
                .minimumScaleFactor(0.6).lineLimit(1)
            Text(caption).font(.scaled(15, weight: .medium)).foregroundStyle(Color.ink.opacity(0.75))
            if let codesNote {
                Text(codesNote).font(.scaled(14)).foregroundStyle(Color.ink.opacity(0.75))
            }
        }
    }

    private var codesNote: String? {
        let codes = cards.filter { !$0.kind.isValueBased }.count
        guard codes > 0 else { return nil }
        return codes == 1 ? "dazu 1 Rabattcode (nicht in der Summe)" : "dazu \(codes) Rabattcodes (nicht in der Summe)"
    }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                // Bei sehr großer Schrift eine kompakte Summe, damit die Liste sichtbar bleibt.
                VStack(alignment: .leading, spacing: 2) {
                    Text(total.euro).font(.scaled(34, weight: .bold)).monospacedDigit()
                        .minimumScaleFactor(0.6).lineLimit(1)
                    Text(caption).font(.scaled(15, weight: .medium)).foregroundStyle(Color.ink.opacity(0.75))
                }
            } else {
                full
            }
        }
        .foregroundStyle(Color.ink)
        .padding(typeSize.isAccessibilitySize ? 14 : 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.brandYellow, in: .rect(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct EmptyState: View {
    let onScan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Noch keine Gutscheine").font(.scaled(17, weight: .semibold))
            Text("Fotografier die Rückseite einer Karte, füg eine Gutschein-Mail ein oder tipp den Code ab.")
                .font(.scaled(15)).foregroundStyle(Color.ink2)
            Button("Ersten Gutschein erfassen", action: onScan).buttonStyle(.accent)
        }
        .padding(20)
        .background(Color.surface, in: .rect(cornerRadius: 18, style: .continuous))
    }
}

enum CardFilter: Hashable {
    case all, balance, codes, gifts
    case owner(String)
}
