import SwiftUI

/// Der große Bon: jede Einlösung über alle Karten, wie ein Kassenzettel.
struct BonView: View {
    @Environment(Store.self) private var store
    @Binding var path: NavigationPath
    @State private var range: Period = .all

    enum Period: String, CaseIterable, Identifiable {
        case month = "30 Tage", year = "Dieses Jahr", all = "Alles"
        var id: String { rawValue }
    }

    private var lines: [BonLine] {
        let cal = Calendar.current
        return store.bonLines.filter { line in
            switch range {
            case .all: true
            case .month: line.redemption.date >= cal.date(byAdding: .day, value: -30, to: .now)!
            case .year: cal.isDate(line.redemption.date, equalTo: .now, toGranularity: .year)
            }
        }
    }

    private var days: [(day: Date, lines: [BonLine])] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: lines) { cal.startOfDay(for: $0.redemption.date) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0]!) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bon").font(.system(size: 34, weight: .heavy))
                    Text("Was du wann und wo eingelöst hast.").foregroundStyle(Color.muted)
                }
                .padding(.top, 8)

                HStack(spacing: 10) {
                    statTile("Eingelöst", lines.reduce(0) { $0 + $1.redemption.amount }.euro, "arrow.down.right", .good)
                    statTile("Noch offen", store.total.euro, "clock", .warn)
                }

                Picker("Zeitraum", selection: $range) {
                    ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                receipt

                Button { path.append(Route.tests) } label: {
                    HStack {
                        Image(systemName: "checkmark.seal").font(.system(size: 18, weight: .semibold))
                            .frame(width: 42, height: 42).background(Color.goodSoft, in: RoundedRectangle(cornerRadius: 12))
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
        .background(Color.page.ignoresSafeArea())
    }

    private func statTile(_ label: String, _ value: String, _ icon: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 24, weight: .heavy)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            HStack(spacing: 6) { Text(label); Image(systemName: icon).foregroundStyle(tint) }
                .font(.system(size: 13.5)).foregroundStyle(Color.muted)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).cardSurface(radius: 24)
    }

    private var receipt: some View {
        VStack(spacing: 0) {
            ZigZag(top: true).fill(Color.paper).frame(height: 10)
            VStack(alignment: .leading, spacing: 10) {
                VStack(spacing: 4) {
                    Text("RESTWERT").font(.system(size: 22, weight: .heavy, design: .monospaced)).kerning(3)
                    Text("EINLÖSUNGEN · \(range.rawValue.uppercased())").font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.muted)
                    Text(Date.now.formatted(date: .numeric, time: .shortened)).font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.muted)
                }
                .frame(maxWidth: .infinity)
                DashedRule()
                if days.isEmpty {
                    Text("NOCH KEINE POSTEN\nZieh einen Einkauf ab oder mach einen Kassentest.")
                        .font(.system(size: 12.5, design: .monospaced)).foregroundStyle(Color.muted)
                        .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 12)
                }
                ForEach(days, id: \.day) { day in
                    Text(day.day.formatted(.dateTime.weekday(.abbreviated).day().month(.twoDigits).year()).uppercased())
                        .font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(Color.muted)
                    ForEach(day.lines) { line in
                        Button { path.append(Route.card(line.cardID)) } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(line.cardName.uppercased()).font(.system(size: 14, weight: .bold, design: .monospaced))
                                    Text([line.redemption.store, line.redemption.note, "Rest \(line.redemption.balanceAfter.euro)"]
                                        .filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Color.muted)
                                }
                                Spacer()
                                Text(line.redemption.amount > 0 ? "−" + line.redemption.amount.euro : "✓").font(.system(size: 14, weight: .bold, design: .monospaced))
                            }
                            .foregroundStyle(Color.ink)
                        }
                        .buttonStyle(.plain)
                    }
                }
                DashedRule()
                HStack {
                    Text("SUMME").font(.system(size: 16, weight: .heavy, design: .monospaced))
                    Spacer()
                    Text(lines.reduce(0) { $0 + $1.redemption.amount }.euro).font(.system(size: 16, weight: .heavy, design: .monospaced))
                }
                HStack {
                    Text("POSTEN").font(.system(size: 12, design: .monospaced))
                    Spacer()
                    Text("\(lines.count)").font(.system(size: 12, design: .monospaced))
                }
                .foregroundStyle(Color.muted)
                DashedRule()
                Text("DANKE, DASS DU NICHTS VERFALLEN LÄSST").font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.muted)
                    .frame(maxWidth: .infinity)
                BarcodeView(number: "RESTWERT", format: .code128, height: 34).padding(.horizontal, 40).opacity(0.85)
            }
            .padding(.horizontal, 18).padding(.vertical, 10)
            .background(Color.paper)
            ZigZag(top: false).fill(Color.paper).frame(height: 10)
        }
        .foregroundStyle(Color.ink)
        .shadow(color: Color.ink.opacity(0.1), radius: 18, y: 10)
    }
}

// MARK: - Kassentest

struct TestsView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var mode = 0

    var body: some View {
        let all = store.tests.sorted { $0.date > $1.date }
        let ok = all.filter(\.success).count
        let shown = all.filter { mode == 0 || (mode == 1 ? $0.success : !$0.success) }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    CircleButton(systemImage: "arrow.left", label: "Zurück") { dismiss() }
                    Spacer()
                    Text("Kassentest").font(.system(size: 21, weight: .bold))
                    Spacer()
                    ShareLink(item: exportText(all)) {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.ink)
                            .frame(width: 48, height: 48).background(Color.surface, in: Circle()).overlay(Circle().stroke(Color.line))
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Quote").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.muted)
                    Text("\(all.isEmpty ? 0 : ok * 100 / all.count) %").font(.system(size: 48, weight: .heavy))
                    Text("Kassen, die den Barcode vom Handy angenommen haben").font(.system(size: 13)).foregroundStyle(Color.muted)
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.brandYellow, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                Picker("Filter", selection: $mode) {
                    Text("Alle").tag(0); Text("Geklappt").tag(1); Text("Abgelehnt").tag(2)
                }
                .pickerStyle(.segmented)
                if shown.isEmpty {
                    Text("Noch keine Tests. Öffne eine Karte und tipp auf „An der Kasse zeigen“.").foregroundStyle(Color.muted)
                }
                ForEach(shown) { t in
                    HStack(spacing: 14) {
                        Image(systemName: t.success ? "checkmark" : "xmark").font(.system(size: 17, weight: .bold))
                            .foregroundStyle(t.success ? Color.good : Color.bad)
                            .frame(width: 46, height: 46)
                            .background(t.success ? Color.goodSoft : Color.badSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(t.merchantName).font(.system(size: 16, weight: .bold))
                                if t.isExample { Chip(text: "Beispiel") }
                            }
                            Text([t.date.dayMonthYear, t.format.label, t.store, t.note].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.system(size: 13)).foregroundStyle(Color.muted)
                        }
                        Spacer()
                    }
                    .padding(12).cardSurface(radius: 20)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 30)
        }
        .background(Color.page.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private func exportText(_ tests: [TestResult]) -> String {
        "Restwert Kassentest\n" + tests.map {
            [$0.date.dayMonthYear, $0.merchantName, $0.success ? "geklappt" : "abgelehnt", $0.format.label, $0.store, $0.note]
                .filter { !$0.isEmpty }.joined(separator: " | ")
        }.joined(separator: "\n")
    }
}
