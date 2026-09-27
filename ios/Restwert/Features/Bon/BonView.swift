import SwiftUI
import RestwertKit

/// Der große Bon: jede Einlösung über alle Gutscheine, wie ein Kassenzettel.
struct BonView: View {
    @Environment(Store.self) private var store
    @State private var period: Period = .all

    enum Period: String, CaseIterable, Identifiable {
        case month = "30 Tage", year = "Dieses Jahr", all = "Alles"
        var id: String { rawValue }
    }

    private var lines: [BonLine] {
        let cal = Calendar.current
        let monthAgo = cal.date(byAdding: .day, value: -30, to: .now) ?? .now
        return store.bonLines.filter { line in
            switch period {
            case .all: true
            case .month: line.redemption.date >= monthAgo
            case .year: cal.isDate(line.redemption.date, equalTo: .now, toGranularity: .year)
            }
        }
    }

    private var days: [(day: Date, lines: [BonLine])] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: lines) { cal.startOfDay(for: $0.redemption.date) }
        return groups.keys.sorted(by: >).map { day in (day, groups[day] ?? []) }
    }

    /// Nur echte Abzüge. Aufladungen und Korrekturen nach oben sind als negative Beträge gespeichert und stehen extra.
    private var sum: Double { lines.reduce(0) { $0 + max(0, $1.redemption.amount) } }
    private var topUps: Double { lines.reduce(0) { $0 + max(0, -$1.redemption.amount) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Layout.inset) {
                Text("Was du wann und wo eingelöst hast.").foregroundStyle(Color.muted)
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Period.allCases) { p in
                            FilterChip(title: p.rawValue, on: period == p) { withAnimation(.smooth) { period = p } }
                        }
                    }
                }
                .scrollIndicators(.hidden).scrollClipDisabled()

                receipt

                NavigationLink(value: Route.tests) {
                    HStack {
                        Image(systemName: "checkmark.seal").font(.scaled(17, weight: .semibold))
                            .frame(width: 44, height: 44).background(Color.fill, in: .rect(cornerRadius: Layout.controlRadius, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Kassentests").font(.scaled(16, weight: .semibold))
                            Text(store.tests.isEmpty ? "Noch kein Kassentest – teste, ob die Kasse das Handy nimmt"
                                 : "\(store.tests.filter(\.success).count) von \(store.tests.count) Kassen haben das Handy akzeptiert")
                                .font(.scaled(13)).foregroundStyle(Color.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Color.muted)
                    }
                    .foregroundStyle(Color.ink).padding(Layout.inset).background(Color.surface, in: .rect(cornerRadius: Layout.cardRadius, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Layout.page).padding(.bottom, Layout.section)
        }
        .scrollIndicators(.hidden)
        .pageBackground()
        .navigationTitle("Verlauf")
    }

    private var receipt: some View {
        ReceiptPaper {
            VStack(alignment: .leading, spacing: 10) {
                VStack(spacing: 4) {
                    // Kopf mit der Wortmarke: der Bon ist die Sammlung deiner abgerissenen Ticket-Abschnitte.
                    Wordmark(size: 22)
                    Text("EINLÖSUNGEN · \(period.rawValue.uppercased())").font(.scaled(12, design: .monospaced))
                        .foregroundStyle(Color.muted)
                        .contentTransition(.interpolate)
                    Text(Date.now.formatted(date: .numeric, time: .shortened)).font(.scaled(12, design: .monospaced))
                        .foregroundStyle(Color.muted)
                    Text("NOCH OFFEN \(store.total.euro)").font(.scaled(13, weight: .semibold, design: .monospaced))
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity)
                DashedRule()
                if days.isEmpty {
                    Text("NOCH KEINE POSTEN\nZieh einen Einkauf ab oder mach einen Kassentest.")
                        .font(.scaled(13, design: .monospaced)).foregroundStyle(Color.muted)
                        .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 12)
                }
                ForEach(days, id: \.day) { day in
                    Text(day.day.formatted(.dateTime.weekday(.abbreviated).day().month(.twoDigits).year()
                        .locale(Locale(identifier: "de_DE"))).uppercased())
                        .font(.scaled(12, weight: .bold, design: .monospaced)).foregroundStyle(Color.muted)
                    ForEach(day.lines) { line in
                        NavigationLink(value: Route.card(line.cardID)) { lineRow(line) }
                            .buttonStyle(.plain)
                            .disabled(store.card(line.cardID) == nil)
                    }
                }
                DashedRule()
                HStack {
                    Text("SUMME EINGELÖST").font(.scaled(16, weight: .heavy, design: .monospaced))
                    Spacer()
                    Text(sum > 0 ? "−" + sum.euro : sum.euro).font(.scaled(16, weight: .heavy, design: .monospaced))
                        .contentTransition(.numericText(value: sum))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Summe eingelöst \(sum.euro)")
                if topUps > 0 {
                    HStack {
                        Text("AUFGELADEN/KORRIGIERT")
                        Spacer()
                        Text("+" + topUps.euro).contentTransition(.numericText(value: topUps))
                    }
                    .font(.scaled(12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.ink2)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Aufgeladen oder korrigiert \(topUps.euro)")
                }
                HStack {
                    Text("POSTEN")
                    Spacer()
                    Text("\(lines.count)").contentTransition(.numericText())
                }
                .font(.scaled(12, design: .monospaced))
                .foregroundStyle(Color.muted)
            }
        }
        .animation(.smooth, value: period)
    }

    private func lineRow(_ line: BonLine) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(line.cardName.uppercased()).font(.scaled(15, weight: .bold, design: .monospaced))
                // Händlername steht schon darüber, also nur die Filiale („thalia Köln“ → „Köln“, „Thalia“ → nichts).
                let place = Self.place(line.redemption.store, merchant: line.cardName)
                // Rabattcodes haben keinen Rest; gelöschte Karten zeigen ihn weiter.
                let showRest = store.card(line.cardID)?.kind.isValueBased ?? true
                Text([place, line.redemption.note, showRest ? "Rest \(line.redemption.balanceAfter.euro)" : ""]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.scaled(13, design: .monospaced)).foregroundStyle(Color.ink2)
            }
            Spacer()
            Text(line.redemption.amount > 0 ? "−" + line.redemption.amount.euro : line.redemption.amount < 0 ? "+" + (-line.redemption.amount).euro : "✓")
                .font(.scaled(15, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(Color.ink)
        .contentShape(.rect)
        .transition(.opacity.combined(with: .move(edge: .leading)))
    }

    /// Filiale ohne vorangestellten Händlernamen, unabhängig von Groß-/Kleinschreibung und Akzenten.
    static func place(_ store: String, merchant: String) -> String {
        let raw = store.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              let r = raw.range(of: name, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) else { return raw }
        let rest = raw[r.upperBound...]
        // Nur abschneiden, wenn der Name allein steht oder ein Trenner folgt („Thalia Köln“, nicht „Thaliahaus“).
        guard rest.isEmpty || rest.first?.isWhitespace == true || rest.first?.isPunctuation == true else { return raw }
        return rest.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }
}

// MARK: - Kassentest

struct TestsView: View {
    @Environment(Store.self) private var store
    @State private var filter = 0

    var body: some View {
        let all = store.tests.sorted { $0.date > $1.date }
        let ok = all.filter(\.success).count
        let shown = all.filter { filter == 0 || (filter == 1 ? $0.success : !$0.success) }
        ScrollView {
            VStack(alignment: .leading, spacing: Layout.inset) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("An der Kasse angenommen").font(.scaled(15, weight: .semibold)).foregroundStyle(Color.ink2)
                    // Unter 5 Tests ist eine Prozentzahl irreführend, dann in Worten.
                    Text(all.isEmpty ? "Noch nicht getestet" : all.count < 5 ? "\(ok) von \(all.count) Mal" : "\(ok * 100 / all.count) %")
                        .font(.display(40))
                        .contentTransition(.numericText())
                    Text("Wie oft Kassen den Barcode vom Handy genommen haben").font(.scaled(13)).foregroundStyle(Color.ink2)
                }
                .padding(Layout.ticketInset).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.surface, in: .rect(cornerRadius: Layout.cardRadius, style: .continuous))
                HStack(spacing: 8) {
                    ForEach([(0, "Alle"), (1, "Geklappt"), (2, "Abgelehnt")], id: \.0) { tag, title in
                        FilterChip(title: title, on: filter == tag) { withAnimation(.smooth) { filter = tag } }
                    }
                }
                if all.isEmpty {
                    Text("Noch keine Tests. Öffne einen Gutschein und tipp auf „An der Kasse zeigen“.").foregroundStyle(Color.muted)
                } else if shown.isEmpty {
                    Text(filter == 1 ? "Keine geklappten Tests." : "Keine abgelehnten Tests.").foregroundStyle(Color.muted)
                }
                ForEach(shown) { test in
                    HStack(spacing: 14) {
                        Image(systemName: test.success ? "checkmark" : "xmark").font(.scaled(17, weight: .bold))
                            .foregroundStyle(test.success ? Color.good : Color.bad)
                            .frame(width: 44, height: 44)
                            .background(test.success ? Color.goodSoft : Color.badSoft, in: .rect(cornerRadius: Layout.controlRadius, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(test.merchantName).font(.scaled(16, weight: .bold))
                                if test.isExample { Chip(text: "Beispiel") }
                            }
                            Text([test.date.dayMonthYear, test.format.label, test.store, test.note].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.scaled(13)).foregroundStyle(Color.muted)
                        }
                        Spacer()
                    }
                    .padding(Layout.inset).background(Color.surface, in: .rect(cornerRadius: Layout.cardRadius, style: .continuous))
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
                }
            }
            .padding(.horizontal, Layout.page).padding(.bottom, Layout.section)
        }
        .pageBackground()
        .navigationTitle("Kassentest")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // Exportiert, was angezeigt wird, ohne Beispiele (wie Backup und CSV).
                ShareLink(item: exportText(shown.filter { !$0.isExample })) { Image(systemName: "square.and.arrow.up") }
                    .disabled(!shown.contains { !$0.isExample })
            }
        }
    }

    private func exportText(_ tests: [TestResult]) -> String {
        "Restwert Kassentest\n" + tests.map {
            [$0.date.dayMonthYear, $0.merchantName, $0.success ? "geklappt" : "abgelehnt", $0.format.label, $0.store, $0.note]
                .filter { !$0.isEmpty }.joined(separator: " | ")
        }.joined(separator: "\n")
    }
}
