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

    private var sum: Double { lines.reduce(0) { $0 + $1.redemption.amount } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Was du wann und wo eingelöst hast.").foregroundStyle(Color.muted)
                Picker("Zeitraum", selection: $period.animation(.smooth)) {
                    ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                receipt

                NavigationLink(value: Route.tests) {
                    HStack {
                        Image(systemName: "checkmark.seal").font(.scaled(18, weight: .semibold))
                            .frame(width: 42, height: 42).background(Color.fill, in: .rect(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Kassentests").font(.scaled(16, weight: .semibold))
                            Text("\(store.tests.filter(\.success).count) von \(store.tests.count) Kassen haben das Handy akzeptiert")
                                .font(.scaled(13)).foregroundStyle(Color.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Color.muted)
                    }
                    .foregroundStyle(Color.ink).padding(14).background(Color.surface, in: .rect(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .pageBackground()
        .navigationTitle("Verlauf")
    }

    private var receipt: some View {
        ReceiptPaper {
            VStack(alignment: .leading, spacing: 10) {
                VStack(spacing: 4) {
                    Text("RESTWERT").font(.scaled(22, weight: .heavy, design: .monospaced)).kerning(3)
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
                        .font(.scaled(12.5, design: .monospaced)).foregroundStyle(Color.muted)
                        .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 12)
                }
                ForEach(days, id: \.day) { day in
                    Text(day.day.formatted(.dateTime.weekday(.abbreviated).day().month(.twoDigits).year()
                        .locale(Locale(identifier: "de_DE"))).uppercased())
                        .font(.scaled(11, weight: .bold, design: .monospaced)).foregroundStyle(Color.muted)
                    ForEach(day.lines) { line in
                        NavigationLink(value: Route.card(line.cardID)) { lineRow(line) }
                            .buttonStyle(.plain)
                            .disabled(store.card(line.cardID) == nil)
                    }
                }
                DashedRule()
                HStack {
                    Text("SUMME").font(.scaled(16, weight: .heavy, design: .monospaced))
                    Spacer()
                    Text(sum.euro).font(.scaled(16, weight: .heavy, design: .monospaced))
                        .contentTransition(.numericText(value: sum))
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
                Text(line.cardName.uppercased()).font(.scaled(14, weight: .bold, design: .monospaced))
                // Händlername steht schon darüber, also nur die Filiale („Thalia Köln“ → „Köln“).
                let place = line.redemption.store.hasPrefix(line.cardName + " ")
                    ? String(line.redemption.store.dropFirst(line.cardName.count + 1)) : line.redemption.store
                Text([place, line.redemption.note, "Rest \(line.redemption.balanceAfter.euro)"]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.scaled(13, design: .monospaced)).foregroundStyle(Color.ink2)
            }
            Spacer()
            Text(line.redemption.amount > 0 ? "−" + line.redemption.amount.euro : line.redemption.amount < 0 ? "+" + (-line.redemption.amount).euro : "✓")
                .font(.scaled(14, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(Color.ink)
        .contentShape(.rect)
        .transition(.opacity.combined(with: .move(edge: .leading)))
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
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("An der Kasse angenommen").font(.scaled(14, weight: .semibold)).foregroundStyle(Color.ink2)
                    // Unter 5 Tests ist eine Prozentzahl irreführend, dann in Worten.
                    Text(all.count < 5 ? "\(ok) von \(all.count) Mal" : "\(ok * 100 / all.count) %")
                        .font(.scaled(40, weight: .bold))
                        .contentTransition(.numericText())
                    Text("Wie oft Kassen den Barcode vom Handy genommen haben").font(.scaled(13)).foregroundStyle(Color.ink2)
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.surface, in: .rect(cornerRadius: 22, style: .continuous))
                Picker("Filter", selection: $filter.animation(.smooth)) {
                    Text("Alle").tag(0)
                    Text("Geklappt").tag(1)
                    Text("Abgelehnt").tag(2)
                }
                .pickerStyle(.segmented)
                if shown.isEmpty {
                    Text("Noch keine Tests. Öffne einen Gutschein und tipp auf „An der Kasse zeigen“.").foregroundStyle(Color.muted)
                }
                ForEach(shown) { test in
                    HStack(spacing: 14) {
                        Image(systemName: test.success ? "checkmark" : "xmark").font(.scaled(17, weight: .bold))
                            .foregroundStyle(test.success ? Color.good : Color.bad)
                            .frame(width: 46, height: 46)
                            .background(test.success ? Color.goodSoft : Color.badSoft, in: .rect(cornerRadius: 14, style: .continuous))
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
                    .padding(12).cardSurface(radius: 20)
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 30)
        }
        .pageBackground()
        .navigationTitle("Kassentest")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: exportText(all)) { Image(systemName: "square.and.arrow.up") }
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
