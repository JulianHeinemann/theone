import SwiftUI
import RestwertKit

/// Wo geht es ohne Plastikkarte? Händlerliste mit eigenen Kassentests.
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
            LazyVStack(alignment: .leading, spacing: 10) {
                Text("Wo du Gutscheine am Handy vorzeigen kannst und wo du die Karte brauchst.")
                    .font(.scaled(15)).foregroundStyle(Color.ink2)
                filters
                if !mine.isEmpty {
                    Text("Deine Händler").font(.scaled(15, weight: .semibold)).foregroundStyle(Color.ink2).padding(.top, 4)
                    ForEach(mine) { row($0) }
                    Text("Alle Händler").font(.scaled(15, weight: .semibold)).foregroundStyle(Color.ink2).padding(.top, 8)
                }
                ForEach(items) { merchant in
                    row(merchant)
                }
                if items.isEmpty {
                    ContentUnavailableView.search(text: trimmedQuery)
                }
            }
            .padding(.horizontal, Layout.page).padding(.bottom, 30)
            .animation(.smooth, value: category)
        }
        .scrollIndicators(.hidden)
        .pageBackground()
        .navigationTitle("Händler")
        .searchable(text: $query, prompt: "Händler suchen")
    }

    private var filters: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    segment("Alle", category == nil) { category = nil }
                    ForEach(MerchantCategory.allCases) { c in segment(c.label, category == c) { category = c } }
                }
                .padding(.vertical, 4)
            }
        }
        .scrollIndicators(.hidden)
        .sensoryFeedback(.selection, trigger: category)
    }

    private func segment(_ title: String, _ on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.scaled(14.5, weight: .semibold))
                .foregroundStyle(on ? Color.onInk : Color.ink)
                .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .glassEffect(on ? .regular.tint(Color.ink).interactive() : .regular.interactive(), in: .capsule)
        .accessibilityAddTraits(on ? .isSelected : [])
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
                Text(m.tip).font(.scaled(14)).foregroundStyle(Color.ink2).lineLimit(2)
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
        .padding(14).background(Color.surface, in: .rect(cornerRadius: Layout.cardRadius, style: .continuous))
    }
}
