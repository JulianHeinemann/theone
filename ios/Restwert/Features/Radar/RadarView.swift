import SwiftUI
import RestwertKit

/// Ablauf-Radar: Je näher ein Punkt an der Mitte, desto früher verfällt der Gutschein.
/// Ringe: 30 Tage, 90 Tage, 6 Monate, 1 Jahr. Punktgröße = Restguthaben.
struct RadarChart: View {
    let cards: [GiftCard]
    @Binding var selected: UUID?
    var compact = false
    @State private var appeared = false

    var body: some View {
        GeometryReader { geo in
            let radius = min(geo.size.width, geo.size.height) / 2
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let maxBalance = max(cards.map(\.balance).max() ?? 1, 1)
            ZStack {
                rings(radius: radius, center: center)
                sweep(radius: radius, center: center)
                Circle().fill(Color.ink).frame(width: 6, height: 6).position(center)
                if !compact {
                    Text("Heute").font(.system(size: 10, weight: .heavy)).foregroundStyle(Color.ink)
                        .position(x: center.x, y: center.y + 12)
                }
                ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                    dot(card, index: index, radius: radius, center: center, maxBalance: maxBalance)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear { appeared = true }
    }

    private func rings(radius: CGFloat, center: CGPoint) -> some View {
        ZStack {
            let warn = CardQueries.radarRings[0].fraction
            Circle().fill(Color.warnSoft.opacity(0.7))
                .frame(width: radius * 2 * warn, height: radius * 2 * warn)
                .position(center)
            ForEach(CardQueries.radarRings, id: \.days) { ring in
                Circle().stroke(Color.line, style: StrokeStyle(lineWidth: 1, dash: ring.days == 365 ? [] : [4, 5]))
                    .frame(width: radius * 2 * ring.fraction, height: radius * 2 * ring.fraction)
                    .position(center)
                if !compact {
                    Text(ring.label).font(.system(size: 10, weight: .bold)).foregroundStyle(Color.muted)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.surface, in: .capsule)
                        .position(x: center.x, y: center.y - radius * ring.fraction)
                }
            }
        }
    }

    /// Radar-Strahl, zeitgesteuert statt Endlos-Animation: läuft flüssig und stoppt, wenn die Ansicht verschwindet.
    private func sweep(radius: CGFloat, center: CGPoint) -> some View {
        TimelineView(.animation) { timeline in
            let angle = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 5) / 5 * 360
            Circle()
                .fill(AngularGradient(colors: [Color.brandYellow.opacity(0.6), Color.brandYellow.opacity(0)],
                                      center: .center, startAngle: .degrees(0), endAngle: .degrees(70)))
                .frame(width: radius * 2 * 0.92, height: radius * 2 * 0.92)
                .rotationEffect(.degrees(angle))
                .position(center)
                .blendMode(.multiply)
        }
        .allowsHitTesting(false)
    }

    private func dot(_ card: GiftCard, index: Int, radius: CGFloat, center: CGPoint, maxBalance: Double) -> some View {
        let fraction = CardQueries.radarFraction(forDays: card.daysLeft)
        let angle = Double(index) * 137.5 * .pi / 180 - .pi / 2
        let base: CGFloat = compact ? 10 : 16
        let range: CGFloat = compact ? 10 : 22
        let size = base + range * CGFloat(sqrt(max(card.balance, 1) / maxBalance))
        let distance = appeared ? radius * CGFloat(fraction) : 0
        let point = CGPoint(x: center.x + CGFloat(cos(angle)) * distance, y: center.y + CGFloat(sin(angle)) * distance)
        let urgent = card.daysLeft <= 30
        let isSelected = selected == card.id
        return Button { withAnimation(.snappy) { selected = card.id } } label: {
            ZStack {
                Circle().fill(Pastel.color(for: card))
                Circle().stroke(urgent ? Color.bad : Color.ink, lineWidth: isSelected ? 3 : 1.5)
                if !compact && size > 26 {
                    Text(card.name.initials).font(.system(size: size * 0.3, weight: .heavy)).foregroundStyle(Color.ink)
                }
            }
            .frame(width: size, height: size)
            .scaleEffect(isSelected ? 1.2 : 1)
            .phaseAnimator(urgent && !compact ? [1.0, 1.12] : [1.0]) { content, pulse in
                content.scaleEffect(pulse)
            } animation: { _ in .easeInOut(duration: 0.9) }
        }
        .buttonStyle(.plain)
        .disabled(compact)
        .position(point)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(duration: 0.8, bounce: 0.35).delay(Double(index) * 0.06), value: appeared)
        .accessibilityLabel("\(card.name), \(card.headline), \(card.daysLeft < 0 ? "abgelaufen" : "noch \(card.daysLeft) Tage")")
    }
}

struct RadarTeaser: View {
    let cards: [GiftCard]
    @State private var none: UUID?

    var body: some View {
        HStack(spacing: 16) {
            RadarChart(cards: cards, selected: $none, compact: true).frame(width: 112, height: 112)
            VStack(alignment: .leading, spacing: 6) {
                Text("Ablauf-Radar").font(.system(size: 18, weight: .bold))
                if let next = cards.min(by: { $0.expires < $1.expires }) {
                    Text(next.daysLeft < 0 ? "\(next.name) ist abgelaufen" : "\(next.name) verfällt in \(next.daysLeft) Tagen")
                        .font(.system(size: 14)).foregroundStyle(Color.ink2)
                    Text(next.headline).font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(next.daysLeft <= 30 ? Color.bad : Color.ink)
                } else {
                    Text("Keine offenen Gutscheine").font(.system(size: 14)).foregroundStyle(Color.muted)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold)).foregroundStyle(Color.muted)
        }
        .foregroundStyle(Color.ink)
        .padding(16)
        .cardSurface()
    }
}

struct RadarView: View {
    @Environment(Store.self) private var store
    @AppStorage("warnDays") private var warnDays = 30
    @State private var selected: UUID?

    private var months: [(key: Date, cards: [GiftCard])] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: store.activeCards) {
            cal.date(from: cal.dateComponents([.year, .month], from: $0.expires)) ?? $0.expires
        }
        return groups.keys.sorted().map { key in (key, (groups[key] ?? []).sorted { $0.expires < $1.expires }) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(spacing: 14) {
                    RadarChart(cards: store.activeCards, selected: $selected).padding(8)
                    HStack(spacing: 14) {
                        legend(Color.warnSoft, "unter 30 Tagen")
                        legend(Color.line, "Ringe: 30 T · 90 T · 6 M · 1 J")
                    }
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.muted)
                    if let id = selected, let card = store.card(id) {
                        NavigationLink(value: Route.card(card.id)) { CardRow(card: card, warnDays: warnDays) }
                            .buttonStyle(.plain)
                            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.ink, lineWidth: 1.5))
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                            .id(card.id)
                    } else {
                        Text("Tippe auf einen Punkt. Je näher an der Mitte, desto früher verfällt der Gutschein.")
                            .font(.system(size: 14)).foregroundStyle(Color.muted).multilineTextAlignment(.center)
                    }
                }
                .padding(16)
                .cardSurface(radius: 30)
                .animation(.snappy, value: selected)

                SectionHeader(title: "Zeitstrahl") {
                    Text(CardQueries.openTotal(store.activeCards).euro)
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(Color.muted)
                }
                .padding(.top, 8)
                timeline
            }
            .padding(.horizontal, 16).padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .pageBackground()
        .navigationTitle("Ablauf-Radar")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(text)
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            if months.isEmpty {
                Text("Keine offenen Gutscheine.").foregroundStyle(Color.muted)
            }
            ForEach(Array(months.enumerated()), id: \.element.key) { index, group in
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(group.cards.contains { $0.daysLeft <= 30 } ? Color.bad : Color.ink)
                            .frame(width: 12, height: 12).padding(.top, 5)
                        if index < months.count - 1 {
                            Rectangle().fill(Color.line).frame(width: 2).frame(maxHeight: .infinity)
                        }
                    }
                    .frame(width: 12)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(group.key.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "de_DE"))))
                                .font(.system(size: 16, weight: .heavy))
                            Spacer()
                            Text(CardQueries.openTotal(group.cards).euro)
                                .font(.system(size: 14, weight: .bold)).foregroundStyle(Color.muted)
                        }
                        ForEach(group.cards) { card in
                            NavigationLink(value: Route.card(card.id)) { CardRow(card: card, warnDays: warnDays) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 22)
                }
                .scrollTransition { content, phase in
                    content.opacity(phase.isIdentity ? 1 : 0.4).offset(x: phase.isIdentity ? 0 : 24)
                }
            }
        }
    }
}
