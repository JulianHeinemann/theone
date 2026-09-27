import SwiftUI
import RestwertKit

/// Wo geht es ohne Plastikkarte? Liste der Läden mit eigenen Kassentests.
struct MerchantsView: View {
    @Environment(Store.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var query = ""
    @State private var category: MerchantCategory?

    /// Eigener Laden (nicht in der Händlerliste), aus den Gutscheinen gesammelt.
    private struct OwnShop: Identifiable {
        let name: String
        let count: Int
        let balance: Double
        var id: String { name.lowercased() }
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Nur Buchstaben und Ziffern, ohne Akzente: „Müller“ → „muller“, „H&M“ → „hm“.
    private static func folded(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
            .filter { $0.isLetter || $0.isNumber }
    }

    /// Tolerant: ohne Akzente und Sonderzeichen, zusätzlich über die ID („mueller“ findet Müller).
    private func matches(name: String, id: String) -> Bool {
        let q = trimmedQuery
        guard !q.isEmpty else { return true }
        if name.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil { return true }
        let f = Self.folded(q)
        return !f.isEmpty && (Self.folded(name).contains(f) || Self.folded(id).contains(f))
    }

    private var items: [Merchant] {
        Merchant.all
            .filter { category == nil || $0.category == category }
            .filter { matches(name: $0.name, id: $0.id) }
            .sorted {
                let a = MerchantCategory.allCases.firstIndex(of: $0.category) ?? 0
                let b = MerchantCategory.allCases.firstIndex(of: $1.category) ?? 0
                return a == b ? $0.name.localizedCompare($1.name) == .orderedAscending : a < b
            }
    }

    private var activeCards: [GiftCard] { store.cards.filter(\.isActive) }

    /// Händler, von denen man selbst Karten hat, zuerst. Nur ohne Filter und Suche, sonst doppelt.
    private func mine(_ cards: [GiftCard]) -> [Merchant] {
        guard category == nil, trimmedQuery.isEmpty else { return [] }
        let ids = Set(cards.map(\.merchantID))
        return Merchant.all.filter { ids.contains($0.id) }.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    /// Eigene Läden stehen nirgends sonst in der Liste, daher auch bei Suche sichtbar (nur nicht unter einem Kategorie-Filter).
    private func ownShops(_ cards: [GiftCard]) -> [OwnShop] {
        guard category == nil else { return [] }
        let own = cards.filter { $0.merchantID == "other" && !$0.customName.trimmingCharacters(in: .whitespaces).isEmpty }
        let groups = Dictionary(grouping: own) { $0.customName.trimmingCharacters(in: .whitespaces).lowercased() }
        return groups.values.compactMap { group -> OwnShop? in
            guard let first = group.first else { return nil }
            let name = first.customName.trimmingCharacters(in: .whitespaces)
            guard matches(name: name, id: name) else { return nil }
            let balance = group.filter(\.kind.isValueBased).reduce(0) { $0 + $1.balance }
            return OwnShop(name: name, count: group.count, balance: balance)
        }
        .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        let cards = activeCards
        let counts = Dictionary(grouping: cards, by: \.merchantID).mapValues(\.count)
        // Einmal pro Neuzeichnen gruppieren statt pro Zeile filtern.
        let tests = Dictionary(grouping: store.tests.filter { !$0.isExample }, by: \.merchantID)
        let known = mine(cards)
        let own = ownShops(cards)
        let list = items
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Layout.group) {
                filters
                if !known.isEmpty || !own.isEmpty {
                    header("Deine Läden").padding(.top, Layout.group)
                    ForEach(own) { ownRow($0) }
                    ForEach(known) { row($0, tests: tests[$0.id] ?? [], count: counts[$0.id]) }
                    if !list.isEmpty { header("Alle Läden").padding(.top, Layout.group) }
                }
                ForEach(list) { merchant in
                    row(merchant, tests: tests[merchant.id] ?? [], count: nil)
                }
                if list.isEmpty && own.isEmpty {
                    ContentUnavailableView.search(text: trimmedQuery)
                }
            }
            .padding(.horizontal, Layout.page).padding(.bottom, Layout.section)
            .animation(reduceMotion ? nil : .smooth, value: category)
        }
        .scrollIndicators(.hidden)
        .pageBackground()
        // Großer Titel wie Verlauf und Einstellungen, damit er beim Tabwechsel nicht springt. Suche bleibt immer sichtbar.
        .navigationTitle("Läden")
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
        FilterChip(title: title, on: on) { withAnimation(reduceMotion ? nil : .snappy) { action() } }
    }

    private func header(_ title: String) -> some View {
        Text(title).font(.scaled(15, weight: .semibold)).foregroundStyle(Color.ink2)
            .accessibilityAddTraits(.isHeader)
    }

    /// Bei sehr großer Schrift Kachel über den Text, damit der Text die volle Breite bekommt.
    private var rowLayout: AnyLayout {
        typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Layout.group))
                                     : AnyLayout(HStackLayout(alignment: .top, spacing: 14))
    }

    private static func countText(_ n: Int) -> String { n == 1 ? "1 Gutschein" : "\(n) Gutscheine" }

    private func row(_ m: Merchant, tests mine: [TestResult], count: Int?) -> some View {
        let ok = mine.filter(\.success).count
        // Klare Mehrheit grün, klare Minderheit rot, Gleichstand neutral.
        let tint: Color = ok * 2 > mine.count ? .good : ok * 2 < mine.count ? .bad : .ink2
        return rowLayout {
            MerchantMark(merchantID: m.id, name: m.name)
            VStack(alignment: .leading, spacing: 4) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        Text(m.name).font(.scaled(16, weight: .semibold))
                        Spacer(minLength: 4)
                        testedLabel(ok: ok, total: mine.count, tint: tint)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.name).font(.scaled(16, weight: .semibold))
                        testedLabel(ok: ok, total: mine.count, tint: tint)
                    }
                }
                if let count {
                    Text(Self.countText(count)).font(.scaled(13, weight: .medium)).foregroundStyle(Color.ink2)
                }
                Label(m.category.label, systemImage: m.category.symbol)
                    .font(.scaled(13, weight: .medium)).foregroundStyle(m.category.tint)
                // Nie abschneiden: gerade bei großer Schrift fehlt sonst genau diese Information.
                Text(m.redeemHowTo ?? m.tip).font(.scaled(15)).foregroundStyle(Color.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                if let url = m.balanceURL, let label = m.balanceCheck.linkLabel {
                    Link(destination: url) {
                        Label(label, systemImage: "arrow.up.right").font(.scaled(13, weight: .semibold))
                            .frame(minHeight: Layout.tap, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .foregroundStyle(Color.ink)
                    .accessibilityHint("Öffnet die Website von \(m.name)")
                } else {
                    Text("Guthaben nur an der Kasse").font(.scaled(13)).foregroundStyle(Color.ink2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Layout.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface, in: .rect(cornerRadius: Layout.cardRadius, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func testedLabel(ok: Int, total: Int, tint: Color) -> some View {
        if total > 0 {
            Text("Selbst getestet \(ok)/\(total)").font(.scaled(12, weight: .semibold))
                .foregroundStyle(tint)
                .accessibilityLabel("Selbst getestet: \(ok) von \(total) Mal geklappt")
        }
    }

    /// Eigener Laden: keine Kassen-Infos bekannt, dafür Anzahl und Guthaben der eigenen Gutscheine.
    private func ownRow(_ shop: OwnShop) -> some View {
        rowLayout {
            MerchantMark(merchantID: "other", name: shop.name)
            VStack(alignment: .leading, spacing: 4) {
                Text(shop.name).font(.scaled(16, weight: .semibold))
                Text(shop.balance > 0 ? "\(Self.countText(shop.count)) · \(shop.balance.euro) drauf" : Self.countText(shop.count))
                    .font(.scaled(13, weight: .medium)).foregroundStyle(Color.ink2)
                Label("Eigener Laden", systemImage: "storefront")
                    .font(.scaled(13, weight: .medium)).foregroundStyle(Color.ink2)
                Text("Papiergutschein? Nimm das Original mit, viele kleine Läden wollen es sehen. Ob die Kasse das Handy nimmt, zeigt dir ein Kassentest.")
                    .font(.scaled(15)).foregroundStyle(Color.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Layout.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface, in: .rect(cornerRadius: Layout.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

extension Merchant {
    /// Wo und wie man Gutscheine einlöst, die nicht an einen einzelnen Laden gebunden sind.
    var redeemHowTo: String? {
        switch id {
        case "stadtgutschein":
            "Gilt in den teilnehmenden Läden deiner Stadt. Welche mitmachen, steht auf der Website deiner Stadt oder des Gutschein-Anbieters. An der Kasse wird der QR-Code gescannt."
        case "wunschgutschein":
            "Erst auf der Website von Wunschgutschein in einen Gutschein eines Partner-Ladens umtauschen. Den neuen Code trägst du dann hier als neuen Gutschein für diesen Laden ein."
        default:
            nil
        }
    }
}
