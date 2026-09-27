import SwiftUI
import RestwertKit

/// Ein Punkt auf dem Verfallsradar. Eigener Typ, damit auch das Onboarding Beispieldaten zeigen kann.
struct RadarItem: Identifiable {
    let id: UUID
    let merchantID: String?
    let name: String
    let expires: Date
    var urgent = false

    init(id: UUID = UUID(), merchantID: String?, name: String, expires: Date, urgent: Bool = false) {
        self.id = id
        self.merchantID = merchantID
        self.name = name
        self.expires = expires
        self.urgent = urgent
    }

    init(card: GiftCard, warnDays: Int = 14) {
        self.init(id: card.id, merchantID: card.merchantID, name: card.name, expires: card.expires,
                  urgent: card.daysLeft <= warnDays)
    }
}

/// Verfallsradar: Zeitachse ab heute, jeder Gutschein als Ladenkachel an seinem Ablauftag.
/// Die Achse skaliert mit: Sie reicht bis zum spätesten Gutschein (3 bis 48 Monate) und wechselt dabei
/// von Monats- über Quartals- zu Jahresstrichen. Bei langen Spannen ist die Zeit gestaucht (Wurzelskala),
/// damit die nächsten Wochen breit bleiben. Kacheln und Abstände wachsen mit der Schriftgröße.
/// Kacheln, die sich überschneiden, stapeln sich. Nur was nach 48 Monaten abläuft, steht als „+N später“.
struct ExpiryRadar: View {
    let items: [RadarItem]
    /// Feste Spanne in Monaten; `nil` = automatisch bis zum spätesten Gutschein.
    var months: Int? = nil
    var onSelect: ((RadarItem) -> Void)? = nil
    /// Bei `true` fallen die Kacheln nacheinander auf die Achse (Onboarding, erster Auftritt).
    var animateIn = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var landed = false

    // Wächst mit „Größerer Text“, aber gedeckelt, damit die Achse nicht nur aus Kacheln besteht.
    @ScaledMetric(relativeTo: .body) private var tileBase: CGFloat = 32
    @ScaledMetric(relativeTo: .caption) private var flagSpace: CGFloat = 30
    @ScaledMetric(relativeTo: .caption) private var labelSpace: CGFloat = 30
    private var tile: CGFloat { min(tileBase, 46) }
    private var laneStep: CGFloat { tile * 0.7 }
    private let lanes = 3
    private static let maxMonths = 48   // gesetzliche Frist: bis zu 4 Jahre

    /// Spanne in Monaten: bis zum spätesten Gutschein (höchstens 36), mindestens 3.
    private var span: Int {
        if let months { return months }
        let cal = Calendar.current
        let latest = items.map(\.expires).max() ?? .now
        let m = (cal.dateComponents([.month], from: cal.startOfDay(for: .now), to: latest).month ?? 0) + 1
        return min(max(m, 3), Self.maxMonths)
    }

    /// Achse beginnt knapp vor heute, damit „Heute“ links steht und der Platz der Zukunft gehört.
    private var range: (start: Date, end: Date) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let lead = max(4, span * 30 / 25)   // Vorlauf wächst mit der Spanne, damit „Heute“ nie am Rand klebt
        let start = cal.date(byAdding: .day, value: -lead, to: today) ?? today
        return (start, cal.date(byAdding: .month, value: span, to: today) ?? today)
    }

    /// Strichabstand je nach Spanne: Monate, Quartale oder Jahre.
    private var tickStep: Int { span <= 8 ? 1 : span <= 18 ? 3 : 12 }

    private var visible: [RadarItem] { items.filter { $0.expires < range.end }.sorted { $0.expires < $1.expires } }
    private var later: Int { items.count - visible.count }

    var body: some View {
        let chartHeight = tile + laneStep * CGFloat(lanes - 1) + flagSpace
        GeometryReader { geo in
            let w = geo.size.width
            let axisY = chartHeight
            ZStack(alignment: .topLeading) {
                axis(width: w, y: axisY)
                todayMarker(width: w, axisY: axisY)
                ForEach(Array(placed(width: w).enumerated()), id: \.element.item.id) { i, p in
                    marker(p.item)
                        .position(x: p.x, y: axisY - tile / 2 - 6 - CGFloat(p.lane) * laneStep)
                        .offset(y: landed || reduceMotion || !animateIn ? 0 : -40)
                        .opacity(landed || reduceMotion || !animateIn ? 1 : 0)
                        .animation(.spring(duration: 0.5, bounce: 0.35).delay(0.08 * Double(i)), value: landed)
                        .zIndex(Double(lanes - p.lane))
                }
            }
        }
        .frame(height: chartHeight + labelSpace)
        .onAppear { landed = true }
        .animation(.smooth, value: span)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Verfallsradar, nächste \(span) Monate")
    }

    /// Kopfzeile mit Titel und „+N später“ – als eigener View, damit Home sie wie andere Abschnitte setzen kann.
    var laterLabel: String? { later > 0 ? "+\(later) später" : nil }

    // MARK: Teile

    private func xPos(_ date: Date, width: CGFloat) -> CGFloat {
        let (start, end) = range
        let linear = date.timeIntervalSince(start) / end.timeIntervalSince(start)
        // Ab 9 Monaten Spanne gestaucht: nahe Termine bekommen mehr Platz als ferne.
        let t = span > 8 ? pow(min(max(linear, 0), 1), 0.55) : linear
        // Rand lassen, damit Kacheln am Anfang und Ende nicht abgeschnitten werden.
        let inset = tile / 2 + 2
        return inset + CGFloat(min(max(t, 0), 1)) * (width - inset * 2)
    }

    /// Kacheln in Spuren verteilen: unterste freie Spur, sonst die mit dem größten Abstand.
    private func placed(width: CGFloat) -> [(item: RadarItem, x: CGFloat, lane: Int)] {
        var lastX = Array(repeating: -CGFloat.infinity, count: lanes)
        return visible.map { item in
            let x = xPos(item.expires, width: width)
            let lane = lastX.firstIndex { x - $0 >= tile * 0.8 } ?? (lastX.enumerated().min { $0.element < $1.element }?.offset ?? 0)
            lastX[lane] = x
            return (item, x, lane)
        }
    }

    private func axis(width: CGFloat, y: CGFloat) -> some View {
        let cal = Calendar.current
        // Striche an Monats-, Quartals- oder Jahresanfängen innerhalb der Achse.
        let first = cal.date(from: cal.dateComponents([.year, .month], from: range.start)) ?? range.start
        let ticks = (1...span + 1).compactMap { cal.date(byAdding: .month, value: $0, to: first) }
            .filter { $0 < range.end && (cal.component(.month, from: $0) - 1) % tickStep == 0 }
        return ZStack(alignment: .topLeading) {
            Capsule().fill(Color.ink).frame(width: width, height: 2).offset(y: y - 1)
            ForEach(ticks, id: \.self) { d in
                let x = xPos(d, width: width)
                Capsule().fill(Color.ink).frame(width: 2, height: 8).offset(x: x - 1, y: y - 8)
                Text(tickLabel(d))
                    .font(.scaled(12, weight: .medium)).foregroundStyle(Color.muted)
                    .fixedSize()
                    .frame(width: 64)
                    .offset(x: x - 32, y: y + 8)
            }
        }
        .accessibilityHidden(true)
    }

    private func todayMarker(width: CGFloat, axisY: CGFloat) -> some View {
        let x = xPos(.now, width: width)
        return ZStack(alignment: .topLeading) {
            // Heute: gelbes Fähnchen mit gestrichelter Linie bis zur Achse – Gelb ist die App.
            DashLine(dash: 3, gap: 3).fill(Color.ink.opacity(0.5))
                .frame(width: axisY - flagSpace * 0.65, height: 1)
                .rotationEffect(.degrees(90), anchor: .topLeading)
                .offset(x: x + 0.5, y: flagSpace * 0.65)
            Text("Heute")
                .font(.scaled(12, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.onBrand)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.brandYellow, in: .capsule)
                .overlay(Capsule().strokeBorder(Color.onBrand.opacity(0.15), lineWidth: 1))
                .fixedSize()
                .offset(x: max(0, x - 8))
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func marker(_ item: RadarItem) -> some View {
        let mark = MerchantMark(merchantID: item.merchantID, name: item.name, size: tile)
            .overlay(RoundedRectangle(cornerRadius: tile * 0.24, style: .continuous).strokeBorder(Color.surface, lineWidth: 2))
            .overlay {
                // Dringend (bis 14 Tage): roter Ring als zweite Kante.
                if item.urgent {
                    RoundedRectangle(cornerRadius: tile * 0.24 + 3, style: .continuous)
                        .strokeBorder(Color.warn, lineWidth: 2).padding(-3)
                }
            }
            .shadow(color: Color.shade, radius: 4, y: 2)
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now),
                                                    to: Calendar.current.startOfDay(for: item.expires)).day ?? 0
        let label = "\(item.name), läuft \(days == 0 ? "heute" : days == 1 ? "morgen" : "in \(days) Tagen") ab"
        if let onSelect {
            Button { onSelect(item) } label: { mark.frame(width: Layout.tap, height: Layout.tap).contentShape(.rect) }
                .buttonStyle(.plain)
                .accessibilityLabel(label)
        } else {
            mark.accessibilityLabel(label)
        }
    }

    /// „Okt“ bei Monaten, „Jan 27“ bei Quartalen im Januar, „2027“ bei Jahren.
    private func tickLabel(_ d: Date) -> String {
        let de = Locale(identifier: "de_DE")
        if tickStep == 12 { return d.formatted(.dateTime.year().locale(de)) }
        let month = d.formatted(.dateTime.month(.abbreviated).locale(de)).replacingOccurrences(of: ".", with: "")
        if tickStep == 3 && Calendar.current.component(.month, from: d) == 1 {
            return "\(month) \(d.formatted(.dateTime.year(.twoDigits).locale(de)))"
        }
        return month
    }
}

/// Radar mit Abschnittskopf wie die anderen Abschnitte auf dem Start, in einer Karte.
struct ExpiryRadarSection: View {
    let items: [RadarItem]
    var onSelect: ((RadarItem) -> Void)? = nil
    var onShowAll: (() -> Void)? = nil
    var animateIn = true

    var body: some View {
        let radar = ExpiryRadar(items: items, onSelect: onSelect, animateIn: animateIn)
        VStack(alignment: .leading, spacing: Layout.group) {
            HStack(alignment: .firstTextBaseline) {
                Text("Verfallsradar").font(.scaled(15, weight: .semibold)).foregroundStyle(Color.ink2)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if let later = radar.laterLabel {
                    if let onShowAll {
                        Button(later, action: onShowAll)
                            .font(.scaled(15)).foregroundStyle(Color.muted)
                            .frame(minHeight: Layout.tap)
                    } else {
                        Text(later).font(.scaled(15)).foregroundStyle(Color.muted)
                    }
                }
            }
            radar
                .padding(.horizontal, Layout.inset).padding(.top, Layout.inset).padding(.bottom, 4)
                .background(Color.surface, in: .rect(cornerRadius: Layout.cardRadius, style: .continuous))
        }
    }
}
