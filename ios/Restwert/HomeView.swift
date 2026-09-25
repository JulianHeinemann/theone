import SwiftUI

struct HomeView: View {
    @Environment(Store.self) private var store
    @Binding var path: NavigationPath
    var onAdd: () -> Void
    @State private var selected: UUID?
    @AppStorage("sortOrder") private var sortRaw = CardSortOrder.expiry.rawValue
    @AppStorage("warnDays") private var warnDays = 30

    private var sorted: [GiftCard] { store.cards(sortedBy: CardSortOrder(rawValue: sortRaw) ?? .expiry) }
    private var soon: Int { store.soonCount(warnDays: warnDays) }

    private var currentCard: GiftCard? {
        store.card(selected ?? UUID()) ?? sorted.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                total.padding(.top, 22)
                carousel.padding(.top, 18)
                dots.padding(.top, 12)
                quickActions.padding(.top, 22)
                RadarTeaser(cards: store.activeCards) { path.append(Route.radar) }
                    .padding(.top, 24)
                list.padding(.top, 26)
                if store.hasExamples {
                    Button("Beispielkarten entfernen") { withAnimation { store.clearExamples() } }
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.muted)
                        .frame(maxWidth: .infinity).padding(.top, 20)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(Color.page.ignoresSafeArea())
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Restwert").font(.system(size: 17, weight: .bold))
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.system(size: 13)).foregroundStyle(Color.muted)
            }
            Spacer()
            ZStack(alignment: .topTrailing) {
                CircleButton(systemImage: "bell", label: "\(soon) Karten laufen bald ab") { path.append(Route.radar) }
                if soon > 0 {
                    Circle().fill(Color.brandYellow).frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color.surface, lineWidth: 2)).offset(x: -10, y: 10)
                }
            }
        }
        .padding(.top, 8)
    }

    private var total: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Guthaben in deiner Schublade").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.muted)
            Text(store.total.euro)
                .font(.system(size: 52, weight: .heavy)).kerning(-1.5).monospacedDigit()
                .contentTransition(.numericText())
                .minimumScaleFactor(0.6).lineLimit(1)
            HStack(spacing: 28) {
                stat("\(store.cards.count)", "Karten", "\(store.totalValue > 0 ? Int(store.total / store.totalValue * 100) : 0) % übrig")
                stat("\(soon)", "läuft bald ab", nil)
            }
            .padding(.top, 6)
        }
    }

    private func stat(_ big: String, _ label: String, _ extra: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(big).font(.system(size: 22, weight: .heavy))
            Text(extra.map { "\(label) · \($0)" } ?? label).font(.system(size: 13)).foregroundStyle(Color.muted)
        }
    }

    private var carousel: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 12) {
                if store.cards.isEmpty {
                    Button(action: onAdd) { EmptyCard() }.buttonStyle(.plain)
                        .containerRelativeFrame(.horizontal)
                }
                ForEach(sorted) { card in
                    Button { path.append(Route.card(card.id)) } label: { FolderCardView(card: card, warnDays: warnDays) }
                        .buttonStyle(.plain)
                        .containerRelativeFrame(.horizontal) { w, _ in w * 0.86 }
                        .id(card.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $selected)
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .padding(.horizontal, -16)
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(sorted) { c in
                Capsule().fill(c.id == (currentCard?.id) ? Color.ink : Color.line)
                    .frame(width: c.id == currentCard?.id ? 22 : 6, height: 6)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.snappy, value: selected)
    }

    private var quickActions: some View {
        HStack {
            quick("plus", "Scannen", highlight: true) { onAdd() }
            quick("barcode", "An der Kasse") { if let c = currentCard { path.append(Route.checkout(c.id)) } else { onAdd() } }
            quick("scissors", "Einlösen") { if let c = currentCard { path.append(Route.card(c.id)) } else { onAdd() } }
            quick("checkmark.seal", "Kassentest") { path.append(Route.tests) }
        }
    }

    private func quick(_ icon: String, _ label: String, highlight: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .frame(width: 62, height: 62)
                    .background(highlight ? Color.brandYellow : Color.surface, in: Circle())
                    .overlay(Circle().stroke(highlight ? Color.clear : Color.line, lineWidth: 1))
                Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.ink)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Deine Gutscheine", trailing: "nach " + (CardSortOrder(rawValue: sortRaw) ?? .expiry).label)
            if store.cards.isEmpty {
                Text("Fotografier die Rückseite einer Gutscheinkarte, importier eine E-Mail oder scanne einen handgeschriebenen Gutschein.")
                    .font(.system(size: 15)).foregroundStyle(Color.muted)
            }
            ForEach(sorted) { c in
                Button { path.append(Route.card(c.id)) } label: { CardRow(card: c, warnDays: warnDays) }.buttonStyle(.plain)
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .scale(scale: 0.9).combined(with: .opacity)))
            }
        }
        .animation(.spring(duration: 0.45, bounce: 0.25), value: sorted.map(\.id))
    }
}

struct CardRow: View {
    let card: GiftCard
    var warnDays: Int = 30

    var body: some View {
        HStack(spacing: 14) {
            LetterTile(text: card.name, color: Pastel.color(for: card))
            VStack(alignment: .leading, spacing: 2) {
                Text(card.name).font(.system(size: 16, weight: .bold)).foregroundStyle(Color.ink)
                HStack(spacing: 4) {
                    Image(systemName: card.location.symbol)
                    Text("bis \(card.expires.dayMonthYear)")
                    let st = card.status(warnDays: warnDays)
                    if st != .valid {
                        Text("· " + (st == .expiringSoon ? "noch \(card.daysLeft) T." : st.label))
                            .fontWeight(.bold).foregroundStyle(st == .expiringSoon ? Color.warn : (st == .expired ? Color.bad : Color.muted))
                    }
                }
                .font(.system(size: 13)).foregroundStyle(Color.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(card.headline).font(.system(size: 17, weight: .heavy)).monospacedDigit().foregroundStyle(Color.ink)
                Text(card.kind.isValueBased ? "von \(card.value.euro)" : card.kind.label).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.muted)
            }
        }
        .padding(12)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .opacity(card.isOpen && card.daysLeft >= 0 ? 1 : 0.6)
    }
}

private struct EmptyCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Noch leer").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.muted)
            Text("0,00 €").font(.system(size: 32, weight: .heavy))
            Spacer()
            Label("Erste Karte hinzufügen", systemImage: "plus").font(.system(size: 16, weight: .bold))
        }
        .foregroundStyle(Color.ink)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .aspectRatio(1.72, contentMode: .fit)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.muted.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6, 6])))
        .padding(.top, 16)
    }
}
