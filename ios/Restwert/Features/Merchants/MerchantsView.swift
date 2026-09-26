import SwiftUI
import RestwertKit

/// Wo geht es ohne Plastikkarte? Recherche-Tabelle mit eigenen Kassentests.
struct MerchantsView: View {
    @Environment(Store.self) private var store
    @State private var query = ""
    @State private var category: MerchantCategory?

    private var items: [Merchant] {
        Merchant.all
            .filter { category == nil || $0.category == category }
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
            .sorted {
                let a = MerchantCategory.allCases.firstIndex(of: $0.category) ?? 0
                let b = MerchantCategory.allCases.firstIndex(of: $1.category) ?? 0
                return a == b ? $0.name.localizedCompare($1.name) == .orderedAscending : a < b
            }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                Text("Recherche vom 25.09.2026 zu rund 45 Karten in Deutschland. Offiziell bestätigt kein Händler, dass ein Foto der Plastikkarte reicht.")
                    .font(.system(size: 14)).foregroundStyle(Color.muted)
                filters
                ForEach(items) { merchant in
                    row(merchant)
                        .scrollTransition { content, phase in
                            content.opacity(phase.isIdentity ? 1 : 0.4).scaleEffect(phase.isIdentity ? 1 : 0.96)
                        }
                }
                if items.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 30)
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
            Text(title).font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(Color.ink)
                .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .glassEffect(on ? .regular.tint(Color.brandYellow).interactive() : .regular.interactive(), in: .capsule)
    }

    private func row(_ m: Merchant) -> some View {
        let mine = store.tests.filter { $0.merchantID == m.id && !$0.isExample }
        let ok = mine.filter(\.success).count
        let good = ok * 2 >= mine.count
        return HStack(alignment: .top, spacing: 14) {
            LetterTile(text: m.name, color: Pastel.color(for: m.id))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(m.name).font(.system(size: 16, weight: .bold))
                    Chip(text: m.category.label, fg: m.category.tint, bg: m.category.soft)
                    if !mine.isEmpty {
                        Chip(text: "Dein Test \(ok)/\(mine.count)", fg: good ? .good : .bad, bg: good ? .goodSoft : .badSoft)
                    }
                }
                Text(m.tip).font(.system(size: 13.5)).foregroundStyle(Color.ink2)
                if let url = m.balanceURL {
                    Link(destination: url) {
                        Label("Guthaben-Seite", systemImage: "arrow.up.right").font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(Color.ink)
                } else {
                    Text("Guthaben nur an der Kasse").font(.system(size: 13)).foregroundStyle(Color.muted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12).cardSurface(radius: 20)
    }
}
