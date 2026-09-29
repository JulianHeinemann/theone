import SwiftUI
import UIKit
import RestwertKit

/// Ein Punkt auf dem Verfallsradar. Eigener Typ, damit auch das Onboarding Beispieldaten zeigen kann.
struct RadarItem: Identifiable {
    let id: UUID
    let merchantID: String?
    let name: String
    let expires: Date
    var urgent = false
    /// Kurzer Betrag für die Kachel („50 €“, „12,40 €“, „15 %“); `nil` = keiner.
    var amount: String? = nil
    /// Euro-Guthaben für Summen; nur bei wertbasierten Gutscheinen.
    var value: Double? = nil
    /// Ablaufdatum geschätzt (gesetzliche Frist), nicht vom Gutschein gelesen.
    var estimated = false

    init(id: UUID = UUID(), merchantID: String?, name: String, expires: Date, urgent: Bool = false,
         amount: String? = nil, value: Double? = nil, estimated: Bool = false) {
        self.id = id
        self.merchantID = merchantID
        self.name = name
        self.expires = expires
        self.urgent = urgent
        self.amount = amount
        self.value = value
        self.estimated = estimated
    }

    init(card: GiftCard, warnDays: Int = 14) {
        let amount: String? = if card.kind.isValueBased { Self.short(card.balance) }
            else if let p = card.percent, p > 0 { card.headline }
            else if card.value > 0 { Self.short(card.value) }
            else { nil }
        self.init(id: card.id, merchantID: card.merchantID, name: card.name, expires: card.expires,
                  urgent: card.daysLeft <= warnDays, amount: amount,
                  value: card.kind.isValueBased ? card.balance : nil, estimated: card.expiresEstimated)
    }

    /// „50 €“ statt „50,00 €“, Cent nur wenn es welche gibt – die Kachel ist schmal.
    static func short(_ v: Double) -> String {
        let whole = v == v.rounded()
        return v.formatted(.number.precision(.fractionLength(whole ? 0 : 2)).locale(Locale(identifier: "de_DE"))) + " €"
    }
}

// MARK: - Radar

/// Verfallsradar: ehrliche Zeitachse in zwei gekennzeichneten Zonen.
/// Zone A: „Heute“ am linken Rand, die nächsten 90 Tage linear mit Monatsstrichen und Warnband (0–14 / 15–30 Tage).
/// Danach ein sichtbarer Achsbruch, Zone B: spätere Kalenderjahre als gleich breite Spalten.
/// Höchstens zwei Spuren ohne Überdeckung; was nicht mehr passt, wird zum „+N“-Bündel.
/// Beschriftungen werden gemessen und bei Kollision weggelassen. Die Platzierung wird einmal je Aufbau berechnet.
struct ExpiryRadar: View {
    let items: [RadarItem]
    var onSelect: ((RadarItem) -> Void)? = nil
    /// Tipp auf ein „+N“-Bündel (z. B. Ablauftermine öffnen).
    var onBundle: (([RadarItem]) -> Void)? = nil
    /// Bei `true` fallen die Kacheln nacheinander auf die Achse (Onboarding, erster Auftritt).
    var animateIn = true
    /// Meldet die Höhe der Achse, damit die Hülle ihre Kerben dorthin setzen kann.
    var onAxis: ((CGFloat) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var landed = false
    @State private var width: CGFloat = 0

    /// Kachelgröße bei Standardschrift; auf der Startseite 36 pt (gut lesbar), sonst 28 pt.
    var baseTile: CGFloat = 28
    // Wächst mit „Größerer Text“, gedeckelt, damit die Achse nicht nur aus Kacheln besteht.
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1
    private var tile: CGFloat { min(baseTile * unit, baseTile * 1.5) }
    /// Beschriftungen wachsen bis Accessibility 1 (≈ 17 pt), danach nicht weiter.
    private static let maxType = DynamicTypeSize.accessibility1

    var body: some View {
        let plan = RadarPlan(items: items, width: width, tile: tile,
                             fonts: RadarFonts(min(typeSize, Self.maxType)), now: .now)
        ZStack(alignment: .topLeading) {
            chart(plan)
            labels(plan)
            ForEach(Array(plan.marks.enumerated()), id: \.element.id) { i, m in
                mark(m, plan: plan)
                    .position(x: m.x, y: plan.slotTop(m.lane) + plan.laneH[m.lane] / 2)
                    .offset(y: shown ? 0 : -30)
                    .opacity(shown ? 1 : 0)
                    .animation(.spring(duration: 0.5, bounce: 0.3).delay(0.06 * Double(min(i, 10))), value: landed)
                    // Chronologisch vorlesen, nicht nach Spur.
                    .accessibilitySortPriority(Double(plan.marks.count - i))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: plan.height)
        .dynamicTypeSize(...Self.maxType)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onChange(of: plan.axisY, initial: true) { _, y in onAxis?(y) }
        .onAppear { landed = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Verfallsradar")
    }

    private var shown: Bool { landed || reduceMotion || !animateIn }

    // MARK: Achse, Zonen, Band

    private func chart(_ p: RadarPlan) -> some View {
        Canvas { ctx, size in
            let top: CGFloat = 0
            let axis = p.axisY
            // Dezenter Punkteraster als Hintergrund (Millimeterpapier), nur über der Achse.
            let step: CGFloat = 14
            var dots = Path()
            var y = axis - step
            while y > top + 4 {
                var x: CGFloat = step / 2
                while x < size.width { dots.addEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)); x += step }
                y -= step
            }
            ctx.fill(dots, with: .color(Color.line.opacity(0.9)))
            // Keine farbigen Warnzonen auf der Achse (Wunsch): Dringendes zeigen roter Ring und roter Betrag an der Kachel.
            // Spaltengrenzen der Jahreszone: zart gestrichelt, damit sie nicht wie ein Stiel wirken.
            for c in p.columns.dropFirst() {
                var line = Path()
                line.move(to: CGPoint(x: c.x0, y: top + 8)); line.addLine(to: CGPoint(x: c.x0, y: axis - 8))
                ctx.stroke(line, with: .color(Color.line), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
            }
            // Stiele von der Kachel zur Achse, damit auch Spur 2 eindeutig auf ihrem Tag steht.
            for m in p.marks where !m.zoneB {
                let y0 = p.slotTop(m.lane) + p.tile + (m.showCaption ? 3 + p.captionH * CGFloat(m.lines) : 0)
                ctx.fill(Path(CGRect(x: m.x - 0.5, y: y0, width: 1, height: max(0, axis - y0))),
                         with: .color(Color.ink.opacity(0.3)))
            }
            // Achse Zone A: beginnt bei Heute.
            let a = Path(roundedRect: CGRect(x: p.todayX, y: axis - 1, width: max(0, p.zoneAEnd - p.todayX), height: 2), cornerRadius: 1)
            ctx.fill(a, with: .color(Color.ink))
            // Monatsstriche.
            for t in p.ticks {
                ctx.fill(Path(roundedRect: CGRect(x: t.x - 1, y: axis - 7, width: 2, height: 7), cornerRadius: 1), with: .color(Color.ink))
            }
            // Heute: runde gelbe Marke am Achsanfang, ohne schwarzen Rand; die Warnzonen beginnen mit Abstand dahinter.
            let mark = Path(ellipseIn: CGRect(x: p.todayX - 6, y: axis - 6, width: 12, height: 12))
            ctx.fill(mark, with: .color(Color.brandYellow))
            ctx.stroke(mark, with: .color(Color.surface), lineWidth: 2)
            if !p.columns.isEmpty {
                // Achsbruch: zwei schräge Striche in der Lücke.
                let mid = p.zoneAEnd + p.breakW / 2
                for dx in [-3.0, 3.0] {
                    var s = Path()
                    s.move(to: CGPoint(x: mid + dx - 3, y: axis + 5))
                    s.addLine(to: CGPoint(x: mid + dx + 3, y: axis - 5))
                    ctx.stroke(s, with: .color(Color.muted), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                }
                // Achse Zone B mit Strichen an den Jahresgrenzen.
                let b0 = p.zoneAEnd + p.breakW
                ctx.fill(Path(roundedRect: CGRect(x: b0, y: axis - 1, width: max(0, size.width - b0), height: 2), cornerRadius: 1),
                         with: .color(Color.ink))
                for c in p.columns.dropFirst() {
                    ctx.fill(Path(roundedRect: CGRect(x: c.x0 - 1, y: axis - 7, width: 2, height: 7), cornerRadius: 1), with: .color(Color.ink))
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(p.summary)
        .accessibilitySortPriority(Double(p.marks.count + 1))
    }

    private func labels(_ p: RadarPlan) -> some View {
        let y = p.axisY + 1 + RadarPlan.labelGap
        return ZStack(alignment: .topLeading) {
            Text("Heute")
                .font(.scaled(12, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.onBrand)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Color.brandYellow, in: .capsule)
                .fixedSize()
                .offset(x: 0, y: y)
            ForEach(p.ticks.filter { $0.label != nil }, id: \.x) { t in
                Text(t.label ?? "")
                    .font(.scaled(12, weight: .medium)).foregroundStyle(Color.muted)
                    .fixedSize()
                    .offset(x: t.x + 3, y: y + 2)
            }
            ForEach(p.columns.filter { $0.label != nil }, id: \.x0) { c in
                Text(c.label ?? "")
                    .font(.scaled(12, weight: .medium)).foregroundStyle(Color.muted)
                    .fixedSize()
                    .frame(width: c.x1 - c.x0)
                    .offset(x: c.x0, y: y + 2)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Kacheln

    @ViewBuilder
    private func mark(_ m: RadarPlan.Mark, plan: RadarPlan) -> some View {
        let face = m.items[0]
        let extra = m.items.count - 1
        let t = plan.tile
        let content = VStack(spacing: 3) {
            ZStack {
                // Bündel: eine zweite Kachel lugt leicht versetzt hervor – statt einer „+N“-Plakette auf der Kachel.
                if extra > 0 {
                    RoundedRectangle(cornerRadius: t * 0.24, style: .continuous)
                        .fill(Color.fill)
                        .overlay(RoundedRectangle(cornerRadius: t * 0.24, style: .continuous).strokeBorder(Color.line, lineWidth: 1))
                        .frame(width: t, height: t)
                        .offset(x: 4, y: -4)
                }
                MerchantMark(merchantID: face.merchantID, name: face.name, size: t)
                    .overlay(RoundedRectangle(cornerRadius: t * 0.24, style: .continuous).strokeBorder(Color.surface, lineWidth: 2))
                    .overlay {
                        // Dringend (bis 14 Tage): roter Ring; dazu der Betrag rot und fett (nicht nur Farbe).
                        if face.urgent {
                            RoundedRectangle(cornerRadius: t * 0.24 + 3, style: .continuous)
                                .strokeBorder(Color.warn, lineWidth: 2.5).padding(-3)
                        }
                    }
            }
            // Erst zu einer Ebene zusammenfassen, dann ein Schatten (flüssiger als je Element).
            .compositingGroup()
            .shadow(color: Color.shade, radius: 3, y: 1)
            if m.showCaption, let c = m.caption {
                let parts = c.split(separator: "\n").map(String.init)
                VStack(spacing: 0) {
                    Text(parts[0])
                        .font(.scaled(12, weight: face.urgent ? .heavy : .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(face.urgent ? Color.warn : Color.ink2)
                    if parts.count > 1 {
                        Text(parts[1]).font(.scaled(11, weight: .medium)).foregroundStyle(Color.muted)
                    }
                }
                .lineLimit(1).fixedSize()
            }
            Spacer(minLength: 0)
        }
        .frame(width: plan.hit, height: plan.laneH[m.lane], alignment: .top)
        .contentShape(.rect)

        let label = spoken(m.items)
        if extra > 0, let onBundle {
            Button { onBundle(m.items) } label: { content }
                .buttonStyle(.plain)
                .accessibilityLabel(label)
                .accessibilityHint("Zeigt diese Termine in den Ablaufterminen")
        } else if extra == 0, let onSelect {
            Button { onSelect(face) } label: { content }
                .buttonStyle(.plain)
                .accessibilityLabel(label)
        } else {
            content.accessibilityElement(children: .ignore).accessibilityLabel(label)
        }
    }

    /// „Zalando, 20 €, läuft am 9. Oktober 2026 ab (in 12 Tagen)“; Bündel zählen alle auf.
    private func spoken(_ items: [RadarItem]) -> String {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let de = Locale(identifier: "de_DE")
        let parts = items.map { item -> String in
            let days = max(0, cal.dateComponents([.day], from: today, to: cal.startOfDay(for: item.expires)).day ?? 0)
            let rel = days == 0 ? "heute" : days == 1 ? "morgen" : "in \(days)\u{00A0}Tagen"
            let date = item.expires.formatted(.dateTime.day().month(.wide).year().locale(de))
            let amount = item.amount.map { ", \($0)" } ?? ""
            let est = item.estimated ? " voraussichtlich" : ""
            return "\(item.name)\(amount), läuft\(est) am \(date) ab (\(rel))\(item.urgent ? ", dringend" : "")"
        }
        return items.count > 1 ? "\(items.count) Gutscheine: " + parts.joined(separator: "; ") : parts.joined()
    }
}

// MARK: - Platzierung

/// Schriften der Beschriftung als UIFont, damit Breiten vor dem Zeichnen gemessen werden können.
/// Entspricht `Font.scaled(12, …)`: Title 2 der aktuellen Größe, skaliert mit 12/22.
private struct RadarFonts {
    let label: UIFont
    let caption: UIFont
    let pill: UIFont

    init(_ size: DynamicTypeSize) {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(size))
        let s = UIFont.preferredFont(forTextStyle: .title2, compatibleWith: traits).pointSize * 12 / 22
        label = .systemFont(ofSize: s, weight: .medium)
        caption = Self.rounded(.monospacedDigitSystemFont(ofSize: s, weight: .semibold))
        pill = Self.rounded(.systemFont(ofSize: s, weight: .heavy))
    }

    private static func rounded(_ f: UIFont) -> UIFont {
        f.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: f.pointSize) } ?? f
    }

    func width(_ s: String, _ f: UIFont) -> CGFloat {
        ceil((s as NSString).size(withAttributes: [.font: f]).width) + 2
    }
}

/// Alle Positionen des Radars, einmal je Aufbau berechnet (sortieren O(N log N), sonst linear).
private struct RadarPlan {
    struct Mark: Identifiable {
        var items: [RadarItem]
        var x: CGFloat
        var lane: Int
        var zoneB: Bool
        var caption: String? = nil
        var captionW: CGFloat = 0
        var showCaption = false
        var lines = 1
        var id: UUID { items[0].id }
    }
    struct Tick { var x: CGFloat; var label: String? }
    struct Column { var x0: CGFloat; var x1: CGFloat; var label: String? }
    struct Band { var x0: CGFloat; var x1: CGFloat; var strong: Bool }

    static let horizon = 90
    /// Tage der linearen Zone: 90, oder bis Silvester, wenn das nur knapp dahinter liegt
    /// (sonst stünde nach „Nov Dez“ noch eine Spalte „2026“ – im September verwirrend).
    var horizon = 90
    static let labelGap: CGFloat = 10
    /// Luft über der obersten Spur für Warnring und „!“ (der Rest ragt in den Innenabstand der Hülle).
    static let topGap: CGFloat = 16
    /// Abstand zwischen Betrag der unteren Spur und Achse (sonst klebt „25 €“ am Heute-Punkt).
    static let axisGap: CGFloat = 14
    static let breakW: CGFloat = 12

    let tile: CGFloat
    let hit: CGFloat
    let captionH: CGFloat
    /// Höhe je Spur (unten → oben): Beträge bekommen nur dort eine Zeile, wo auch einer steht.
    var laneH: [CGFloat] = []
    var marks: [Mark] = []
    var ticks: [Tick] = []
    var columns: [Column] = []
    var bands: [Band] = []
    var todayX: CGFloat
    var zoneAEnd: CGFloat
    var breakW: CGFloat = 0
    var lanes = 1
    var axisY: CGFloat = 0
    var height: CGFloat = 0
    var summary = ""

    func slotTop(_ lane: Int) -> CGFloat { axisY - laneH[...lane].reduce(0, +) }

    init(items: [RadarItem], width: CGFloat, tile t: CGFloat, fonts: RadarFonts, now: Date) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let de = Locale(identifier: "de_DE")
        func days(_ d: Date) -> Int { max(0, cal.dateComponents([.day], from: today, to: cal.startOfDay(for: d)).day ?? 0) }

        tile = t
        hit = max(Layout.tap, t + 4)
        captionH = ceil(fonts.caption.lineHeight)
        todayX = t / 2 + 2

        if let yearEnd = cal.date(from: DateComponents(year: cal.component(.year, from: today), month: 12, day: 31)) {
            let toYearEnd = days(yearEnd)
            if toYearEnd > Self.horizon && toYearEnd <= 125 { horizon = toYearEnd }
        }
        let horizon = self.horizon
        let dated: [(item: RadarItem, d: Int)] = items.map { (item: $0, d: days($0.expires)) }
            .sorted { a, b in a.d != b.d ? a.d < b.d : a.item.name < b.item.name }
        let near = dated.filter { $0.d <= horizon }
        let far = dated.filter { $0.d > horizon }
        let W = max(width, 1)

        // Zone B: ein Kalenderjahr je Spalte, gleich breit. Passen nicht alle, fasst die letzte Spalte den Rest („2029+“).
        var farCols: [(x0: CGFloat, x1: CGFloat, from: Int, to: Int)] = []
        if let first = far.first, let last = far.last {
            let y0 = cal.component(.year, from: first.item.expires)
            let y1 = cal.component(.year, from: last.item.expires)
            // Spalten breit genug für Kachel und Betrag („2× 120 €“); passen nicht alle Jahre, fasst die letzte zusammen.
            // Spalten mindestens so breit wie „2027+“ bzw. eine Kachel; Beträge dürfen etwas über die Spalte hinausragen.
            let colMin = max(hit, 70, fonts.width("2027+", fonts.label) + 6)
            let room = W * 0.5 - Self.breakW
            let fit: Int = max(1, Int(room / colMin))
            let k: Int = Swift.min(y1 - y0 + 1, fit)
            let colW: CGFloat = Swift.max(colMin, Swift.min(84, room / CGFloat(k)))
            let start = W - CGFloat(k) * colW
            for i in 0..<k {
                let x0 = start + CGFloat(i) * colW
                farCols.append((x0: x0, x1: x0 + colW, from: y0 + i, to: i == k - 1 ? y1 : y0 + i))
            }
            breakW = Self.breakW
            zoneAEnd = start - breakW
        } else {
            zoneAEnd = W
        }
        // Zone A linear: Heute links, Tag 90 so weit rechts, dass keine Trefferfläche in die Jahreszone ragt.
        let xEnd = farCols.isEmpty ? W - todayX : zoneAEnd - hit / 2 + 6
        // Die ersten 30 Tage (dort liegt das Dringende) bekommen 55 % der Breite, der Rest bis zum Horizont 45 %:
        // rote und orange Zone sind so gut sichtbar, Kacheln der nächsten Wochen stehen nicht aufeinander.
        let span = max(0, xEnd - todayX)
        let x0 = todayX
        let near30 = span * 0.55
        func xA(_ d: Int) -> CGFloat {
            if d <= 30 { return x0 + CGFloat(d) / 30 * near30 }
            return x0 + near30 + CGFloat(d - 30) / CGFloat(max(1, horizon - 30)) * (span - near30)
        }

        bands = [Band(x0: x0, x1: xA(14), strong: true), Band(x0: xA(14), x1: xA(30), strong: false)]

        // Monatsstriche mit Beschriftung, die nicht mit „Heute“ oder der vorigen kollidiert.
        let pillW = fonts.width("Heute", fonts.pill) + 16
        var lastRight = pillW
        var m = cal.date(from: cal.dateComponents([.year, .month], from: today)) ?? today
        while let next = cal.date(byAdding: .month, value: 1, to: m), days(next) <= horizon {
            m = next
            let x = xA(days(m))
            var month = m.formatted(.dateTime.month(.abbreviated).locale(de)).replacingOccurrences(of: ".", with: "")
            if cal.component(.month, from: m) == 1 { month += " \(m.formatted(.dateTime.year(.twoDigits).locale(de)))" }
            let w = fonts.width(month, fonts.label)
            let fits = x + 3 >= lastRight + 6 && x + 3 + w <= zoneAEnd
            // Kein Monatsstrich direkt an der Heute-Marke (sah gequetscht aus).
            guard x - x0 >= 14 else { continue }
            ticks.append(Tick(x: x, label: fits ? month : nil))
            if fits { lastRight = x + 3 + w }
        }

        // Zone A in höchstens zwei Spuren, Mindestabstand in der Spur = Trefferfläche.
        // Der Stiel einer Kachel aus Spur 2 darf von keiner Kachel der Spur 1 (samt Warnring) verdeckt werden –
        // weder von der vorigen noch von der nächsten. Passt beides nicht, ans nächste Ziel bündeln.
        let clear = t / 2 + 5
        var last: [Int?] = [nil, nil]
        for (item, d) in near {
            let x = xA(d)
            let gap = last.map { i in i.map { x - marks[$0].x } ?? .infinity }
            let lane: Int? = gap[0] >= hit && gap[1] >= clear ? 0
                : gap[1] >= hit && gap[0] >= clear ? 1 : nil
            if let lane {
                marks.append(Mark(items: [item], x: x, lane: lane, zoneB: false))
                last[lane] = marks.count - 1
            } else if let idx = last.compactMap({ $0 }).max(by: { marks[$0].x < marks[$1].x }) {
                marks[idx].items.append(item)
                // Vorne der Gutschein mit dem meisten Guthaben, damit der Betrag darunter zu ihm passt.
                marks[idx].items.sort { ($0.value ?? -1) > ($1.value ?? -1) }
            }
        }
        // Zone B: je Spalte unten die früheste Kachel, darüber die zweite oder ein Bündel mit dem Rest.
        var fi = 0
        for c in farCols {
            var inCol: [RadarItem] = []
            while fi < far.count, cal.component(.year, from: far[fi].item.expires) <= c.to {
                inCol.append(far[fi].item); fi += 1
            }
            let full = fonts.width(c.from == c.to ? "2027" : "2027+", fonts.label) + 4 <= c.x1 - c.x0
            let yy = c.from % 100
            var label = full ? "\(c.from)\(c.from == c.to ? "" : "+")" : "’\(yy)\(c.from == c.to ? "" : "+")"
            // Rest des laufenden Jahres (nach der 90-Tage-Zone): nicht einfach „2026“ hinter „Jun“.
            if c.from == cal.component(.year, from: today), c.from == c.to {
                let rest = "Rest ’\(yy)"
                label = fonts.width(rest, fonts.label) + 4 <= c.x1 - c.x0 ? rest : "’\(yy)"
            }
            columns.append(Column(x0: c.x0, x1: c.x1, label: label))
            guard let first = inCol.first else { continue }
            // Eine Kachel je Jahr (früheste vorne, „+N“ für den Rest): gestapelte Kacheln mit Beträgen dazwischen
            // ließen nicht erkennen, welcher Betrag zu welcher Kachel gehört.
            // Vorne der Gutschein mit dem meisten Guthaben, damit die Summe darunter zu ihm passt.
            let face = inCol.max { ($0.value ?? -1) < ($1.value ?? -1) } ?? first
            marks.append(Mark(items: [face] + inCol.filter { $0.id != face.id }, x: (c.x0 + c.x1) / 2, lane: 0, zoneB: true))
        }

        // Beträge unter den Kacheln: nur wenn sie weder Nachbarn noch Stiele berühren.
        for i in marks.indices {
            let its = marks[i].items
            // Bündel: Summe der Euro-Guthaben auf ganze Euro („95 €“ statt „95,15 €“), damit sie in die Spalte passt;
            // Rabattcodes zählen nicht mit. Nur Rabattcodes im Bündel: kein Betrag.
            let sum = its.reduce(0) { $0 + ($1.value ?? 0) }
            // Jahresspalten sind schmal: Euro dort ohne Cent („12 €“ statt „12,40 €“), sonst fiele der Betrag weg.
            if its.count == 1, marks[i].zoneB, let v = its[0].value { marks[i].caption = RadarItem.short(v.rounded()) }
            else if its.count == 1 { marks[i].caption = its[0].amount }
            // Bündel: Anzahl und Summe ausgeschrieben („2× 95 €“) statt einer Plakette auf der Kachel.
            // Bündel in zwei Zeilen: Euro-Summe, darunter „3 Gutscheine“ (kein „3× 95 €“, das wie eine Multiplikation liest).
            // Rabattcodes stehen ausdrücklich dabei („95 € + 20 %“ bzw. „+ 2 Codes“), damit Summe und Anzahl zusammenpassen.
            else {
                let codes = its.filter { $0.value == nil }
                var first = sum > 0 ? RadarItem.short(sum.rounded()) : ""
                if codes.count == 1, let a = codes[0].amount { first += first.isEmpty ? a : " + \(a)" }
                else if !codes.isEmpty { first += first.isEmpty ? "\(codes.count) Codes" : " + \(codes.count) Codes" }
                marks[i].caption = "\(first)\n\(its.count) Gutscheine"
            }
            if let c = marks[i].caption {
                let lines = c.split(separator: "\n").map(String.init)
                marks[i].captionW = lines.map { fonts.width($0, fonts.caption) }.max() ?? 0
                marks[i].lines = lines.count
            }
        }
        let upperStems = marks.filter { $0.lane == 1 && !$0.zoneB }.map(\.x)   // schon aufsteigend
        for lane in 0..<2 {
            let idx = marks.indices.filter { marks[$0].lane == lane }.sorted { marks[$0].x < marks[$1].x }
            var prevRight = -CGFloat.infinity
            var stem = 0
            for (n, i) in idx.enumerated() {
                let mk = marks[i]
                let half = mk.captionW / 2
                var ok = mk.caption != nil && mk.x - half >= prevRight + 4 && mk.x - half >= -8 && mk.x + half <= W + 8
                if ok, n + 1 < idx.count { ok = marks[idx[n + 1]].x - t / 2 >= mk.x + half + 4 }
                // Jahresspalte: Betrag darf etwas überstehen (bis zum Nachbarn bzw. Rand), sonst fiele „120 €“ weg.
                if ok, mk.zoneB { ok = mk.captionW <= (farCols.first.map { $0.x1 - $0.x0 } ?? 0) + 18 }
                if ok, lane == 0, !mk.zoneB {
                    while stem < upperStems.count, upperStems[stem] < mk.x - half - 2 { stem += 1 }
                    if stem < upperStems.count, upperStems[stem] <= mk.x + half + 2 { ok = false }
                }
                marks[i].showCaption = ok
                prevRight = ok ? mk.x + half : mk.x + t / 2
            }
        }

        lanes = (marks.map(\.lane).max() ?? 0) + 1
        laneH = (0..<lanes).map { lane in
            let lines = marks.filter { $0.lane == lane && $0.showCaption }.map(\.lines).max() ?? 0
            // Luft zwischen den Spuren, damit Kachel und Betrag der unteren nie an die obere stoßen.
            return max(Layout.tap, t + 8 + (lines > 0 ? 3 + captionH * CGFloat(lines) : 0)) + (lane == 0 ? Self.axisGap : 0)
        }
        axisY = Self.topGap + laneH.reduce(0, +)
        // Achse, Abstand, „Heute“-Pille (Zeile + 2 × 2 pt Innenabstand).
        height = axisY + 1 + Self.labelGap + ceil(fonts.pill.lineHeight) + 4

        // Zusammenfassung für VoiceOver.
        let in14 = dated.filter { $0.d <= 14 }
        let in30 = dated.filter { $0.d <= 30 }
        let sum30 = in30.reduce(0.0) { $0 + ($1.item.value ?? 0) }
        var s = [items.count == 1 ? "1 Gutschein" : "\(items.count) Gutscheine"]
        s.append(in14.isEmpty ? "keiner läuft in den nächsten 14\u{00A0}Tagen ab" : "\(in14.count) in den nächsten 14\u{00A0}Tagen")
        if in30.count > in14.count { s.append("\(in30.count) in 30\u{00A0}Tagen") }
        if sum30 > 0 { s.append("\(sum30.euro) in 30\u{00A0}Tagen betroffen") }
        if let last = dated.last, last.d > horizon {
            s.append("Zeitachse: nächste \(horizon)\u{00A0}Tage, danach Jahre bis \(cal.component(.year, from: last.item.expires))")
        } else {
            s.append("Zeitachse: nächste \(horizon)\u{00A0}Tage")
        }
        summary = s.joined(separator: ", ")
    }
}

// MARK: - Abschnitt

/// Radar mit Abschnittskopf wie die anderen Abschnitte auf dem Start, in einer Ticket-Hülle:
/// Die Kerben sitzen auf Höhe der Achse, die Achse ist die Abrisslinie.
struct ExpiryRadarSection: View {
    let items: [RadarItem]
    var onSelect: ((RadarItem) -> Void)? = nil
    var onShowAll: (() -> Void)? = nil
    var animateIn = true
    /// Tipp auf ein Bündel. Ohne Angabe öffnet es wie `onShowAll` die Ablauftermine.
    var onBundle: (([RadarItem]) -> Void)? = nil
    /// Kachelgröße: 36 pt – das Radar steht unten auf der Startseite und darf Platz nehmen.
    var tileSize: CGFloat = 36

    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var axisY: CGFloat = 94
    private let top: CGFloat = 12

    /// „2 in 30 Tagen · 70 €“ – was bald verfällt und wie viel Geld daran hängt.
    private var soon: (text: String, spoken: String) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let in30 = items.filter { (cal.dateComponents([.day], from: today, to: cal.startOfDay(for: $0.expires)).day ?? 0) <= 30 }
        guard !in30.isEmpty else { return ("Nichts in 30\u{00A0}Tagen", "Nichts läuft in 30\u{00A0}Tagen ab") }
        let sum = in30.reduce(0.0) { $0 + ($1.value ?? 0) }
        let money = sum > 0 ? " · \(RadarItem.short(sum))" : ""
        let spokenMoney = sum > 0 ? ", zusammen \(sum.euro)" : ""
        return ("\(in30.count) in 30\u{00A0}Tagen\(money)", "\(in30.count) laufen in 30\u{00A0}Tagen ab\(spokenMoney)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.group) {
            // Bei sehr großer Schrift untereinander, damit die Zusammenfassung nicht zerbricht.
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
            layout {
                Text("Verfallsradar").font(.scaled(15, weight: .semibold)).foregroundStyle(Color.ink2)
                    .accessibilityAddTraits(.isHeader)
                if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                let s = soon
                if let onShowAll {
                    Button(action: onShowAll) {
                        HStack(spacing: 4) {
                            Text(s.text).multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
                            Image(systemName: "chevron.right").font(.scaled(12, weight: .semibold))
                        }
                        .font(.scaled(15)).foregroundStyle(Color.muted)
                        .frame(minHeight: Layout.tap).contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Alle Ablauftermine, \(s.spoken)")
                } else {
                    Text(s.text).font(.scaled(15)).foregroundStyle(Color.muted).multilineTextAlignment(.trailing)
                        .accessibilityLabel(s.spoken)
                }
            }
            ExpiryRadar(items: items, onSelect: onSelect,
                        onBundle: onBundle ?? onShowAll.map { all in { _ in all() } },
                        animateIn: animateIn, onAxis: { axisY = $0 }, baseTile: tileSize)
                .padding(.horizontal, Layout.inset).padding(.top, top).padding(.bottom, 14)
                .background(Color.surface, in: TicketShape(radius: Layout.cardRadius, notchRadius: 9, notchFromTop: top + axisY))
        }
    }
}
