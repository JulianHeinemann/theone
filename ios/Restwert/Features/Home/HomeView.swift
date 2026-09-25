import SwiftUI
import RestwertKit

struct HomeView: View {
    let zoom: Namespace.ID
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @AppStorage("sortOrder") private var sortRaw = CardSortOrder.expiry.rawValue
    @AppStorage("warnDays") private var warnDays = 30
    @State private var selected: UUID?

    private var order: CardSortOrder { CardSortOrder(rawValue: sortRaw) ?? .expiry }
    private var sorted: [GiftCard] { store.cards(sortedBy: order) }
    private var soon: Int { store.soonCount(warnDays: warnDays) }
    private var currentCard: GiftCard? { selected.flatMap { store.card($0) } ?? sorted.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HeroTotal(total: store.total, original: store.totalValue, count: store.cards.count, soon: soon)
                carousel.padding(.top, 22)
                dots.padding(.top, 12)
                quickActions.padding(.top, 22)
                NavigationLink(value: Route.radar) {
                    RadarTeaser(cards: store.activeCards)
                }
                .buttonStyle(.plain)
                .padding(.top, 24)
                list.padding(.top, 26)
                if store.hasExamples {
                    Button("Beispielkarten entfernen") { withAnimation(.smooth) { store.clearExamples() } }
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.muted)
                        .frame(maxWidth: .infinity).padding(.top, 20)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .pageBackground()
        .navigationTitle("Restwert")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: Route.radar) {
                    Image(systemName: soon > 0 ? "bell.badge" : "bell")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.warn, Color.ink)
                        .symbolEffect(.wiggle, value: soon)
                }
                .accessibilityLabel("\(soon) Gutscheine laufen bald ab")
            }
        }
    }

    // MARK: Karussell

    private var carousel: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 12) {
                if store.cards.isEmpty {
                    Button { router.tab = .scan } label: { EmptyCard() }
                        .buttonStyle(.plain)
                        .containerRelativeFrame(.horizontal)
                }
                ForEach(sorted) { card in
                    NavigationLink(value: Route.card(card.id)) {
                        FolderCardView(card: card, warnDays: warnDays)
                            .matchedTransitionSource(id: card.id, in: zoom)
                    }
                    .buttonStyle(.plain)
                    .containerRelativeFrame(.horizontal) { width, _ in width * 0.86 }
                    .scrollTransition(axis: .horizontal) { content, phase in
                        content
                            .scaleEffect(phase.isIdentity ? 1 : 0.9)
                            .rotation3DEffect(.degrees(phase.value * -12), axis: (x: 0, y: 1, z: 0))
                            .opacity(phase.isIdentity ? 1 : 0.7)
                    }
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
        .sensoryFeedback(.selection, trigger: selected)
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(sorted) { c in
                let active = c.id == currentCard?.id
                Capsule().fill(active ? Color.ink : Color.line)
                    .frame(width: active ? 22 : 6, height: 6)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.snappy, value: selected)
    }

    // MARK: Schnellaktionen

    private var quickActions: some View {
        GlassEffectContainer(spacing: 16) {
            HStack {
                QuickAction(icon: "plus", label: "Scannen", highlight: true) { router.tab = .scan }
                if let c = currentCard {
                    NavigationLink(value: Route.checkout(c.id)) { QuickActionLabel(icon: "barcode", label: "An der Kasse") }
                        .buttonStyle(.plain)
                    NavigationLink(value: Route.card(c.id)) { QuickActionLabel(icon: "scissors", label: "Einlösen") }
                        .buttonStyle(.plain)
                } else {
                    QuickAction(icon: "barcode", label: "An der Kasse") { router.tab = .scan }
                    QuickAction(icon: "scissors", label: "Einlösen") { router.tab = .scan }
                }
                NavigationLink(value: Route.tests) { QuickActionLabel(icon: "checkmark.seal", label: "Kassentest") }
                    .buttonStyle(.plain)
            }
        }
    }

    // MARK: Liste

    private var list: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Deine Gutscheine") {
                Menu {
                    Picker("Sortierung", selection: $sortRaw) {
                        ForEach(CardSortOrder.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                } label: {
                    Label("nach \(order.label)", systemImage: "arrow.up.arrow.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.muted)
                }
            }
            if store.cards.isEmpty {
                Text("Fotografier die Rückseite einer Gutscheinkarte, importier eine E-Mail oder scanne einen handgeschriebenen Gutschein.")
                    .font(.system(size: 15)).foregroundStyle(Color.muted)
            }
            ForEach(sorted) { c in
                NavigationLink(value: Route.card(c.id)) { CardRow(card: c, warnDays: warnDays) }
                    .buttonStyle(.plain)
                    .scrollTransition(.animated(.smooth)) { content, phase in
                        content
                            .opacity(phase.isIdentity ? 1 : 0.3)
                            .scaleEffect(phase.isIdentity ? 1 : 0.94)
                            .blur(radius: phase.isIdentity ? 0 : 2)
                    }
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                            removal: .scale(scale: 0.9).combined(with: .opacity)))
            }
        }
        .animation(.spring(duration: 0.45, bounce: 0.25), value: sorted.map(\.id))
    }
}

// MARK: - Bausteine

/// Gesamtguthaben auf einem lebendigen Pastell-Verlauf.
private struct HeroTotal: View {
    let total: Double
    let original: Double
    let count: Int
    let soon: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "de_DE"))))
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.ink.opacity(0.55))
            Text("Guthaben in deiner Schublade").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.ink2)
            Text(total.euro)
                .font(.system(size: 50, weight: .heavy)).kerning(-1.5).monospacedDigit()
                .contentTransition(.numericText(value: total))
                .animation(.snappy, value: total)
                .minimumScaleFactor(0.6).lineLimit(1)
            HStack(spacing: 28) {
                stat("\(count)", "Gutscheine", original > 0 ? "\(Int(total / original * 100)) % übrig" : nil)
                stat("\(soon)", "laufen bald ab", nil)
            }
            .padding(.top, 6)
        }
        .foregroundStyle(Color.ink)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { LivingMesh().clipShape(.rect(cornerRadius: 30, style: .continuous)) }
        .padding(.top, 4)
    }

    private func stat(_ big: String, _ label: String, _ extra: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(big).font(.system(size: 22, weight: .heavy)).contentTransition(.numericText())
            Text(extra.map { "\(label) · \($0)" } ?? label).font(.system(size: 13)).foregroundStyle(Color.ink2)
        }
    }
}

/// Sanft wabernder Mesh-Verlauf in den Markenfarben (hell, nie schwarz).
struct LivingMesh: View {
    var colors: [Color] = [
        Color(hex: 0xFFF1A8), Color(hex: 0xFFE14D), Color(hex: 0xF9D8E8),
        Color(hex: 0xE4D7FB), Color(hex: 0xFFF6D6), Color(hex: 0xCDEFE3),
        Color(hex: 0xD9E2FB), Color(hex: 0xFBE1CF), Color(hex: 0xFFF1A8),
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let dx = Float(sin(t * 0.6)) * 0.12
            let dy = Float(cos(t * 0.45)) * 0.1
            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.5 + dx, 0.5 + dy], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1],
            ], colors: colors)
        }
    }
}

private struct QuickActionLabel: View {
    let icon: String
    let label: String
    var highlight = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.ink)
                .frame(width: 62, height: 62)
                .glassEffect(highlight ? .regular.tint(Color.brandYellow).interactive() : .regular.interactive(), in: .circle)
            Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.ink)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct QuickAction: View {
    let icon: String
    let label: String
    var highlight = false
    let action: () -> Void

    var body: some View {
        Button(action: action) { QuickActionLabel(icon: icon, label: label, highlight: highlight) }
            .buttonStyle(.plain)
    }
}

private struct EmptyCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Noch leer").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.muted)
            Text(0.0.euro).font(.system(size: 32, weight: .heavy))
            Spacer()
            Label("Ersten Gutschein scannen", systemImage: "plus").font(.system(size: 16, weight: .bold))
        }
        .foregroundStyle(Color.ink)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .aspectRatio(1.72, contentMode: .fit)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(Color.muted.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6, 6])))
        .padding(.top, 16)
    }
}
