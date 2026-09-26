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
                HStack(spacing: 10) {
                    statTile("Eingelöst", sum, "arrow.down.right", .good)
                    statTile("Noch offen", store.total, "clock", .warn)
                }
                Picker("Zeitraum", selection: $period.animation(.smooth)) {
                    ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                receipt

                NavigationLink(value: Route.tests) {
                    HStack {
                        Image(systemName: "checkmark.seal").font(.system(size: 18, weight: .semibold))
                            .frame(width: 42, height: 42).background(Color.goodSoft, in: .rect(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Kassentest").font(.system(size: 16, weight: .bold))
                            Text("\(store.tests.filter(\.success).count) von \(store.tests.count) Kassen haben das Handy genommen")
                                .font(.system(size: 13)).foregroundStyle(Color.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Color.muted)
                    }
                    .foregroundStyle(Color.ink).padding(14).cardSurface(radius: 20)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .pageBackground()
        .navigationTitle("Verlauf")
    }

    private func statTile(_ label: String, _ value: Double, _ icon: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value.euro).font(.system(size: 24, weight: .heavy)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                .contentTransition(.numericText(value: value))
            HStack(spacing: 6) {
                Text(label)
                Image(systemName: icon).foregroundStyle(tint)
            }
            .font(.system(size: 13.5)).foregroundStyle(Color.muted)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).cardSurface(radius: 24)
    }

    private var receipt: some View {
        ReceiptPaper {
            VStack(alignment: .leading, spacing: 10) {
                VStack(spacing: 4) {
                    Text("RESTWERT").font(.system(size: 22, weight: .heavy, design: .monospaced)).kerning(3)
                    Text("EINLÖSUNGEN · \(period.rawValue.uppercased())").font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.muted)
                        .contentTransition(.interpolate)
                    Text(Date.now.formatted(date: .numeric, time: .shortened)).font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.muted)
                }
                .frame(maxWidth: .infinity)
                DashedRule()
                if days.isEmpty {
                    Text("NOCH KEINE POSTEN\nZieh einen Einkauf ab oder mach einen Kassentest.")
                        .font(.system(size: 12.5, design: .monospaced)).foregroundStyle(Color.muted)
                        .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 12)
                }
                ForEach(days, id: \.day) { day in
                    Text(day.day.formatted(.dateTime.weekday(.abbreviated).day().month(.twoDigits).year()
                        .locale(Locale(identifier: "de_DE"))).uppercased())
                        .font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(Color.muted)
                    ForEach(day.lines) { line in
                        NavigationLink(value: Route.card(line.cardID)) { lineRow(line) }
                            .buttonStyle(.plain)
                            .disabled(store.card(line.cardID) == nil)
                    }
                }
                DashedRule()
                HStack {
                    Text("SUMME").font(.system(size: 16, weight: .heavy, design: .monospaced))
                    Spacer()
                    Text(sum.euro).font(.system(size: 16, weight: .heavy, design: .monospaced))
                        .contentTransition(.numericText(value: sum))
                }
                HStack {
                    Text("POSTEN")
                    Spacer()
                    Text("\(lines.count)").contentTransition(.numericText())
                }
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.muted)
                DashedRule()
                Text("DANKE, DASS DU NICHTS VERFALLEN LÄSST").font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.muted).frame(maxWidth: .infinity)
                BarcodeView(number: "RESTWERT", format: .code128, height: 34).padding(.horizontal, 40).opacity(0.85)
            }
        }
        .animation(.smooth, value: period)
    }

    private func lineRow(_ line: BonLine) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(line.cardName.uppercased()).font(.system(size: 14, weight: .bold, design: .monospaced))
                Text([line.redemption.store, line.redemption.note, "Rest \(line.redemption.balanceAfter.euro)"]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Color.muted)
            }
            Spacer()
            Text(line.redemption.amount > 0 ? "−" + line.redemption.amount.euro : "✓")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
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
                    Text("Quote").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.ink2)
                    Text("\(all.isEmpty ? 0 : ok * 100 / all.count) %").font(.system(size: 48, weight: .heavy))
                        .contentTransition(.numericText())
                    Text("Kassen, die den Barcode vom Handy angenommen haben").font(.system(size: 13)).foregroundStyle(Color.ink2)
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.brandYellow.gradient, in: .rect(cornerRadius: 28, style: .continuous))
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
                        Image(systemName: test.success ? "checkmark" : "xmark").font(.system(size: 17, weight: .bold))
                            .foregroundStyle(test.success ? Color.good : Color.bad)
                            .frame(width: 46, height: 46)
                            .background(test.success ? Color.goodSoft : Color.badSoft, in: .rect(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(test.merchantName).font(.system(size: 16, weight: .bold))
                                if test.isExample { Chip(text: "Beispiel") }
                            }
                            Text([test.date.dayMonthYear, test.format.label, test.store, test.note].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.system(size: 13)).foregroundStyle(Color.muted)
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
