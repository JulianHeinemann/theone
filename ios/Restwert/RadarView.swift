import SwiftUI

/// Ablauf-Radar: Je näher ein Punkt an der Mitte, desto früher verfällt die Karte.
/// Ringe: 30 Tage, 90 Tage, 6 Monate, 1 Jahr. Punktgröße = Restguthaben.
struct RadarChart: View {
    let cards: [GiftCard]
    @Binding var selected: UUID?
    var compact = false
    @State private var sweep = 0.0

    static let rings: [(days: Double, fraction: Double, label: String)] = [
        (30, 0.32, "30 T"), (90, 0.52, "90 T"), (180, 0.72, "6 M"), (365, 0.92, "1 J"),
    ]

    static func fraction(forDays d: Int) -> Double {
        if d <= 0 { return 0.1 }
        var prevDays = 0.0, prevF = 0.14
        for r in rings {
            if Double(d) <= r.days {
                return prevF + (r.fraction - prevF) * (Double(d) - prevDays) / (r.days - prevDays)
            }
            prevDays = r.days; prevF = r.fraction
        }
        return 0.98
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let radius = size / 2
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let maxBalance = max(cards.map(\.balance).max() ?? 1, 1)
            ZStack {
                // Warnzone innerhalb von 30 Tagen
                Circle().fill(Color.warnSoft.opacity(0.7))
                    .frame(width: radius * 2 * Self.rings[0].fraction, height: radius * 2 * Self.rings[0].fraction)
                    .position(center)
                ForEach(Self.rings, id: \.days) { r in
                    Circle().stroke(Color.line, style: StrokeStyle(lineWidth: 1, dash: r.days == 365 ? [] : [4, 5]))
                        .frame(width: radius * 2 * r.fraction, height: radius * 2 * r.fraction)
                        .position(center)
                    if !compact {
                        Text(r.label).font(.system(size: 10, weight: .bold)).foregroundStyle(Color.muted)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.surface, in: Capsule())
                            .position(x: center.x, y: center.y - radius * r.fraction)
                    }
                }
                // Radar-Strahl
                Circle()
                    .fill(AngularGradient(colors: [Color.brandYellow.opacity(0.55), Color.brandYellow.opacity(0)],
                                          center: .center, startAngle: .degrees(0), endAngle: .degrees(70)))
                    .frame(width: radius * 2 * 0.92, height: radius * 2 * 0.92)
                    .rotationEffect(.degrees(sweep))
                    .position(center)
                    .blendMode(.multiply)
                Circle().fill(Color.ink).frame(width: 6, height: 6).position(center)
                if !compact {
                    Text("Heute").font(.system(size: 10, weight: .heavy)).foregroundStyle(Color.ink)
                        .position(x: center.x, y: center.y + 12)
                }
                ForEach(Array(cards.enumerated()), id: \.element.id) { idx, card in
                    let f = Self.fraction(forDays: card.daysLeft)
                    let angle: Double = Double(idx) * 137.5 * Double.pi / 180 - Double.pi / 2
                    let dotBase: CGFloat = compact ? 10 : 16
                    let dotRange: CGFloat = compact ? 10 : 22
                    let dot: CGFloat = dotBase + dotRange * CGFloat(sqrt(card.balance / maxBalance))
                    let px: CGFloat = center.x + CGFloat(cos(angle)) * radius * CGFloat(f)
                    let py: CGFloat = center.y + CGFloat(sin(angle)) * radius * CGFloat(f)
                    let urgent = card.daysLeft <= 30
                    Button { withAnimation(.snappy) { selected = card.id } } label: {
                        ZStack {
                            Circle().fill(Pastel.color(for: card))
                            Circle().stroke(urgent ? Color.bad : Color.ink, lineWidth: selected == card.id ? 3 : 1.5)
                            if !compact && dot > 26 {
                                Text(card.name.initials).font(.system(size: dot * 0.3, weight: .heavy)).foregroundStyle(Color.ink)
                            }
                        }
                        .frame(width: dot, height: dot)
                        .scaleEffect(selected == card.id ? 1.18 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(compact)
                    .position(x: px, y: py)
                    .accessibilityLabel("\(card.name), \(card.balance.euro), \(card.daysLeft < 0 ? "abgelaufen" : "noch \(card.daysLeft) Tage")")
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear {
            withAnimation(.linear(duration: 5).repeatForever(autoreverses: false)) { sweep = 360 }
        }
    }
}

struct RadarTeaser: View {
    let cards: [GiftCard]
    var open: () -> Void
    @State private var none: UUID?

    var body: some View {
        Button(action: open) {
            HStack(spacing: 16) {
                RadarChart(cards: cards, selected: $none, compact: true).frame(width: 112, height: 112)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ablauf-Radar").font(.system(size: 18, weight: .bold))
                    if let next = cards.min(by: { $0.expires < $1.expires }) {
                        Text(next.daysLeft < 0 ? "\(next.name) ist abgelaufen" : "\(next.name) verfällt in \(next.daysLeft) Tagen")
                            .font(.system(size: 14)).foregroundStyle(Color.ink2)
                        Text(next.balance.euro).font(.system(size: 20, weight: .heavy)).foregroundStyle(next.daysLeft <= 30 ? Color.bad : Color.ink)
                    } else {
                        Text("Noch keine Karten").font(.system(size: 14)).foregroundStyle(Color.muted)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold)).foregroundStyle(Color.muted)
            }
            .foregroundStyle(Color.ink)
            .padding(16)
            .cardSurface()
        }
        .buttonStyle(.plain)
    }
}

struct RadarView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var path: NavigationPath
    @State private var selected: UUID?

    private var months: [(key: Date, cards: [GiftCard])] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: store.activeCards) { cal.date(from: cal.dateComponents([.year, .month], from: $0.expires)) ?? $0.expires }
        return groups.keys.sorted().map { ($0, groups[$0]!.sorted { $0.expires < $1.expires }) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    CircleButton(systemImage: "arrow.left", label: "Zurück") { dismiss() }
                    Spacer()
                    Text("Ablauf-Radar").font(.system(size: 21, weight: .bold))
                    Spacer()
                    Color.clear.frame(width: 48, height: 48)
                }
                VStack(spacing: 14) {
                    RadarChart(cards: store.activeCards, selected: $selected)
                        .padding(8)
                    HStack(spacing: 14) {
                        legend(Color.warnSoft, "unter 30 Tagen")
                        legend(Color.line, "Ringe: 30 T · 90 T · 6 M · 1 J")
                    }
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.muted)
                    if let id = selected, let c = store.card(id) {
                        Button { path.append(Route.card(c.id)) } label: { CardRow(card: c) }.buttonStyle(.plain)
                            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.ink, lineWidth: 1.5))
                    } else {
                        Text("Tippe auf einen Punkt. Je näher an der Mitte, desto früher verfällt die Karte.")
                            .font(.system(size: 14)).foregroundStyle(Color.muted).multilineTextAlignment(.center)
                    }
                }
                .padding(16)
                .cardSurface(radius: 30)

                SectionHeader(title: "Zeitstrahl", trailing: store.activeCards.reduce(0) { $0 + $1.balance }.euro)
                    .padding(.top, 8)
                timeline
            }
            .padding(.horizontal, 16).padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background(Color.page.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 6) { Circle().fill(c).frame(width: 10, height: 10); Text(t) }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            if months.isEmpty {
                Text("Keine offenen Gutscheine.").foregroundStyle(Color.muted)
            }
            ForEach(Array(months.enumerated()), id: \.element.key) { index, group in
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 0) {
                        Circle().fill(group.cards.contains { $0.daysLeft <= 30 } ? Color.bad : Color.ink).frame(width: 12, height: 12).padding(.top, 5)
                        if index < months.count - 1 {
                            Rectangle().fill(Color.line).frame(width: 2).frame(maxHeight: .infinity)
                        }
                    }
                    .frame(width: 12)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(group.key.formatted(.dateTime.month(.wide).year())).font(.system(size: 16, weight: .heavy))
                            Spacer()
                            Text(group.cards.reduce(0) { $0 + $1.balance }.euro).font(.system(size: 14, weight: .bold)).foregroundStyle(Color.muted)
                        }
                        ForEach(group.cards) { c in
                            Button { path.append(Route.card(c.id)) } label: { CardRow(card: c) }.buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 22)
                }
            }
        }
    }
}
