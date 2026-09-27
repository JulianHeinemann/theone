import SwiftUI
import RestwertKit

/// Wo geht es ohne Plastikkarte? Liste der Läden mit eigenen Kassentests.
struct MerchantsView: View {
    @Environment(Store.self) private var store
    @State private var query = ""
    @State private var category: MerchantCategory?

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Nur Buchstaben und Ziffern, ohne Akzente: „Müller“ → „muller“, „H&M“ → „hm“.
    private static func folded(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
            .filter { $0.isLetter || $0.isNumber }
    }

    /// Tolerant: ohne Akzente und Sonderzeichen, zusätzlich über die ID („mueller“ findet Müller).
    private func matches(_ m: Merchant) -> Bool {
        let q = trimmedQuery
        guard !q.isEmpty else { return true }
        if m.name.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil { return true }
        let f = Self.folded(q)
        return !f.isEmpty && (Self.folded(m.name).contains(f) || Self.folded(m.id).contains(f))
    }

    private var items: [Merchant] {
        Merchant.all
            .filter { category == nil || $0.category == category }
            .filter(matches)
            .sorted {
                let a = MerchantCategory.allCases.firstIndex(of: $0.category) ?? 0
                let b = MerchantCategory.allCases.firstIndex(of: $1.category) ?? 0
                return a == b ? $0.name.localizedCompare($1.name) == .orderedAscending : a < b
            }
    }

    /// Händler, von denen man selbst Karten hat, zuerst. Nur ohne Filter und Suche, sonst doppelt.
    private var mine: [Merchant] {
        guard category == nil, trimmedQuery.isEmpty else { return [] }
        let ids = Set(store.cards.filter(\.isActive).map(\.merchantID))
        return Merchant.all.filter { ids.contains($0.id) }.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Layout.group) {
                filters
                if !mine.isEmpty {
                    header("Deine Läden").padding(.top, Layout.group)
                    ForEach(mine) { row($0) }
                    header("Alle Läden").padding(.top, Layout.group)
                }
                ForEach(items) { merchant in
                    row(merchant)
                }
                if items.isEmpty {
                    ContentUnavailableView.search(text: trimmedQuery)
                }
            }
            .padding(.horizontal, Layout.page).padding(.bottom, Layout.section)
            .animation(.smooth, value: category)
        }
        .scrollIndicators(.hidden)
        .pageBackground()
        .navigationTitle("Läden")
        // Titel und Suchfeld bleiben beim Scrollen oben stehen.
        .toolbarTitleDisplayMode(.inlineLarge)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Laden suchen")
    }

    private var filters: some View {
        // Dieselben Chips wie auf dem Start: Tinte = aktiv, Fläche = inaktiv.
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                segment("Alle", category == nil) { category = nil }
                ForEach(MerchantCategory.allCases) { c in segment(c.label, category == c) { category = c } }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .sensoryFeedback(.selection, trigger: category)
    }

    private func segment(_ title: String, _ on: Bool, _ action: @escaping () -> Void) -> some View {
        FilterChip(title: title, on: on) { withAnimation(.snappy) { action() } }
    }

    private func header(_ title: String) -> some View {
        Text(title).font(.scaled(15, weight: .semibold)).foregroundStyle(Color.ink2)
            .accessibilityAddTraits(.isHeader)
    }

    private func row(_ m: Merchant) -> some View {
        let mine = store.tests.filter { $0.merchantID == m.id && !$0.isExample }
        let ok = mine.filter(\.success).count
        // Klare Mehrheit grün, klare Minderheit rot, Gleichstand neutral.
        let tint: Color = ok * 2 > mine.count ? .good : ok * 2 < mine.count ? .bad : .ink2
        return HStack(alignment: .top, spacing: 14) {
            MerchantMark(merchantID: m.id, name: m.name)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(m.name).font(.scaled(16, weight: .semibold))
                    Spacer(minLength: 4)
                    if !mine.isEmpty {
                        Text("Selbst getestet \(ok)/\(mine.count)").font(.scaled(12, weight: .medium))
                            .foregroundStyle(tint)
                    }
                }
                Label(m.category.label, systemImage: m.category.symbol)
                    .font(.scaled(13, weight: .medium)).foregroundStyle(m.category.tint)
                Text(m.tip).font(.scaled(15)).foregroundStyle(Color.ink2).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let url = m.balanceURL, let label = m.balanceCheck.linkLabel {
                    Link(destination: url) {
                        Label(label, systemImage: "arrow.up.right").font(.scaled(13, weight: .medium))
                    }
                    .foregroundStyle(Color.ink)
                } else {
                    Text("Guthaben nur an der Kasse").font(.scaled(13)).foregroundStyle(Color.muted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Layout.inset).background(Color.surface, in: .rect(cornerRadius: Layout.cardRadius, style: .continuous))
    }
}
