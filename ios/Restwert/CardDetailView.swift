import SwiftUI
import LocalAuthentication
import UIKit

struct CardDetailView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let cardID: UUID
    @Binding var path: NavigationPath
    var onEdit: (GiftCard) -> Void

    @AppStorage("pinLock") private var pinLock = true
    @AppStorage("warnDays") private var warnDays = 30
    @State private var pinVisible = false
    @State private var confirmDelete = false
    @State private var showLocation = false
    @State private var amount: Double = 0
    @State private var tearAmount: Double?
    @State private var tearing = false
    @State private var stampVisible = false
    @State private var copied = false
    @State private var feedback = 0

    var body: some View {
        Group {
            if let card = store.card(cardID) {
                content(card)
            } else {
                Color.page.onAppear { dismiss() }
            }
        }
        .background(Color.page.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sensoryFeedback(.success, trigger: feedback)
    }

    // MARK: Layout

    private func content(_ card: GiftCard) -> some View {
        let status = card.status(warnDays: warnDays)
        return ScrollView {
            VStack(spacing: 16) {
                HStack {
                    CircleButton(systemImage: "arrow.left", label: "Zurück") { dismiss() }
                    Spacer()
                    Text(card.kind.label).font(.system(size: 21, weight: .bold))
                    Spacer()
                    CircleButton(systemImage: "pencil", label: "Bearbeiten") { onEdit(card) }
                }
                summary(card, status)
                locationRow(card)
                codeTicket(card)
                if card.isOpen && card.daysLeft >= 0 {
                    if card.kind.isValueBased { partialRedeem(card) } else { markRedeemedBlock(card) }
                }
                Button { path.append(Route.checkout(card.id)) } label: {
                    Label("An der Kasse zeigen & testen", systemImage: "barcode.viewfinder")
                }
                .buttonStyle(FilledButtonStyle(background: .surface, foreground: .ink))
                CardBon(card: card).padding(.top, 6)
                Button("Gutschein entfernen", role: .destructive) { confirmDelete = true }
                    .font(.system(size: 15, weight: .bold)).padding(.top, 6)
            }
            .padding(.horizontal, 16).padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .confirmationDialog("Gutschein endgültig entfernen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Entfernen", role: .destructive) { store.delete(card.id); dismiss() }
        }
        .sheet(isPresented: $showLocation) {
            LocationSheet(location: card.location, note: card.locationNote) { loc, note in
                store.setLocation(card.id, loc, note: note)
            }
            .presentationDetents([.medium, .large])
        }
        .onAppear { if amount == 0 { amount = min(10, card.balance) } }
    }

    private func statusColors(_ s: VoucherStatus) -> (Color, Color) {
        switch s {
        case .valid: (.good, .goodSoft)
        case .expiringSoon: (.warn, .warnSoft)
        case .redeemed: (.ink2, .line)
        case .expired: (.bad, .badSoft)
        }
    }

    private func summary(_ card: GiftCard, _ status: VoucherStatus) -> some View {
        let (fg, bg) = statusColors(status)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                LetterTile(text: card.name, color: Pastel.color(for: card))
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.name).font(.system(size: 19, weight: .bold))
                    Text(card.merchant.category.label).font(.system(size: 13)).foregroundStyle(Color.muted)
                }
                Spacer()
                Chip(text: status.label, fg: fg, bg: bg)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(card.kind.isValueBased ? "Restwert" : "Rabatt").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.muted)
                Text(card.headline).font(.system(size: 52, weight: .heavy)).kerning(-1.5).monospacedDigit()
                    .contentTransition(.numericText())
                    .strikethrough(status == .redeemed || status == .expired, color: Color.muted)
                    .minimumScaleFactor(0.5).lineLimit(1)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.fill)
                    Capsule().fill(fg).frame(width: g.size.width * card.remainingShare)
                }
            }
            .frame(height: 6)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                cell("Gültig bis", card.expires.dayMonthYear)
                cell("Verbleibend", card.daysLeft < 0 ? "abgelaufen" : "\(card.daysLeft) Tage", tint: card.daysLeft <= warnDays ? fg : .ink)
                cell("Ursprünglich", card.kind.isValueBased ? card.value.euro : (card.percent.map { "\(Int($0)) %" } ?? "–"))
                cell("Einlösungen", "\(card.history.count)")
            }
            if card.kind == .giftCard && !card.pin.isEmpty {
                Button { Task { await togglePin(card) } } label: {
                    HStack {
                        Image(systemName: pinVisible ? "lock.open" : "faceid")
                        Text(pinVisible ? "PIN \(card.pin)" : "PIN anzeigen").font(.system(size: 15, weight: .bold, design: pinVisible ? Font.Design.monospaced : Font.Design.default))
                        Spacer()
                    }
                    .foregroundStyle(Color.ink).padding(14)
                    .background(Color.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .cardSurface(radius: 28)
        .overlay { if card.redeemedAt != nil || stampVisible { Stamp(date: card.redeemedAt ?? .now).allowsHitTesting(false) } }
    }

    private func cell(_ label: String, _ value: String, tint: Color = .ink) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 12)).foregroundStyle(Color.muted)
            Text(value).font(.system(size: 16, weight: .bold)).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func locationRow(_ card: GiftCard) -> some View {
        Button { showLocation = true } label: {
            HStack(spacing: 14) {
                Image(systemName: card.location.symbol).font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44).background(Pastel.all[3], in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Aufbewahrt: \(card.location.label)").font(.system(size: 16, weight: .bold))
                    Text(card.locationNote.isEmpty ? "Notiz hinzufügen" : card.locationNote).font(.system(size: 13)).foregroundStyle(Color.muted).lineLimit(2)
                }
                Spacer()
                Text("Ändern").font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(Color.ink).padding(12).cardSurface(radius: 20)
        }
        .buttonStyle(.plain)
    }

    private func codeTicket(_ card: GiftCard) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("Code").font(.system(size: 16, weight: .bold))
                Spacer()
                Button {
                    UIPasteboard.general.string = card.number
                    copied = true
                    feedback += 1
                    Task { try? await Task.sleep(for: .seconds(1.6)); copied = false }
                } label: {
                    Label(copied ? "Kopiert" : "Code kopieren", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(Color.ink)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color.brandYellow, in: Capsule())
                }
            }
            .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 4)
            Perforation()
            VStack(spacing: 8) {
                BarcodeView(number: card.number, format: card.format, height: 84)
                if card.format != .text {
                    Text(card.number.grouped).font(.system(size: 17, weight: .bold)).kerning(2).textSelection(.enabled)
                }
                if let url = card.merchant.balanceURL {
                    Link(destination: url) { Label("Guthaben beim Händler prüfen", systemImage: "arrow.up.right").font(.system(size: 14, weight: .bold)) }
                        .foregroundStyle(Color.ink).padding(.top, 4)
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 18)
        }
        .cardSurface(radius: 28)
    }

    // MARK: Teileinlösung mit Abriss

    private func partialRedeem(_ card: GiftCard) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Einlösen").font(.system(size: 20, weight: .bold))
                Spacer()
                Text(amount.euro).font(.system(size: 28, weight: .heavy)).monospacedDigit().contentTransition(.numericText())
            }
            Slider(value: $amount, in: 0...max(card.balance, 0.5), step: 0.5)
                .tint(Color.ink)
            HStack(spacing: 8) {
                ForEach([5.0, 10, 20], id: \.self) { v in quick(v.euro.replacingOccurrences(of: ",00", with: "")) { amount = min(v, card.balance) } }
                quick("Alles") { amount = card.balance }
            }
            Text(amount > 0 ? "Danach übrig: \((card.balance - amount).euro)" : "Betrag wählen")
                .font(.system(size: 13)).foregroundStyle(Color.muted)
            Button {
                guard amount > 0 else { return }
                tearAmount = amount
                withAnimation(.easeIn(duration: 0.7)) { tearing = true }
                Task {
                    try? await Task.sleep(for: .milliseconds(650))
                    withAnimation(.snappy) { _ = store.redeem(card.id, amount: amount) }
                    feedback += 1
                    try? await Task.sleep(for: .milliseconds(200))
                    tearing = false
                    tearAmount = nil
                    amount = min(amount, store.card(card.id)?.balance ?? 0)
                }
            } label: { Label("Einlösen", systemImage: "scissors") }
            .buttonStyle(FilledButtonStyle(background: .brandYellow, foreground: .ink))
            .disabled(amount <= 0)
            Button("Betrag genau eintippen") { path.append(Route.keypad(card.id)) }
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.muted).frame(maxWidth: .infinity)
        }
        .padding(18)
        .cardSurface(radius: 28)
        .overlay(alignment: .bottom) {
            if let tearAmount {
                TearStub(amount: tearAmount, merchant: card.name)
                    .offset(y: tearing ? 420 : 40)
                    .rotationEffect(.degrees(tearing ? 14 : 0), anchor: .topLeading)
                    .opacity(tearing ? 0 : 1)
                    .allowsHitTesting(false)
            }
        }
    }

    private func quick(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 15, weight: .bold)).foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func markRedeemedBlock(_ card: GiftCard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(card.kind.label) benutzt?").font(.system(size: 20, weight: .bold))
            Text("Rabattcodes und Coupons gelten meist nur einmal. Markier ihn nach dem Einkauf, dann erscheint er im Verlauf.")
                .font(.system(size: 14)).foregroundStyle(Color.muted)
            Button {
                withAnimation(.spring(duration: 0.45, bounce: 0.5)) { stampVisible = true }
                feedback += 1
                Task {
                    try? await Task.sleep(for: .milliseconds(450))
                    store.markRedeemed(card.id)
                }
            } label: { Label("Als eingelöst markieren", systemImage: "seal") }
            .buttonStyle(FilledButtonStyle(background: .brandYellow, foreground: .ink))
        }
        .padding(18)
        .cardSurface(radius: 28)
    }

    private func togglePin(_ card: GiftCard) async {
        if pinVisible { pinVisible = false; return }
        guard pinLock else { pinVisible = true; return }
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { pinVisible = true; return }
        if (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "PIN von \(card.name) anzeigen")) == true {
            pinVisible = true
        }
    }
}

/// Abriss-Streifen, der beim Einlösen vom Gutschein abreißt und herunterfällt.
private struct TearStub: View {
    let amount: Double
    let merchant: String

    var body: some View {
        VStack(spacing: 0) {
            ZigZag(tooth: 12, top: true).fill(Color.paper).frame(height: 10)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(merchant.uppercased()).font(.system(size: 12, weight: .bold, design: .monospaced))
                    Text(Date.now.formatted(date: .numeric, time: .shortened)).font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.muted)
                }
                Spacer()
                Text("−" + amount.euro).font(.system(size: 20, weight: .heavy, design: .monospaced))
            }
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 18).padding(.vertical, 12)
            .background(Color.paper)
            ZigZag(tooth: 12, top: false).fill(Color.paper).frame(height: 10)
        }
        .padding(.horizontal, 24)
        .shadow(color: Color.ink.opacity(0.15), radius: 10, y: 6)
    }
}

/// Roter Stempel „Eingelöst“.
struct Stamp: View {
    let date: Date
    @State private var appear = false

    var body: some View {
        VStack(spacing: 2) {
            Text("EINGELÖST").font(.system(size: 28, weight: .black, design: .rounded)).kerning(3)
            Text(date.dayMonthYear).font(.system(size: 13, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(Color.bad.opacity(0.85))
        .padding(.horizontal, 18).padding(.vertical, 10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.bad.opacity(0.85), lineWidth: 4))
        .rotationEffect(.degrees(-14))
        .scaleEffect(appear ? 1 : 2.2)
        .opacity(appear ? 1 : 0)
        .onAppear { withAnimation(.spring(duration: 0.4, bounce: 0.45)) { appear = true } }
    }
}

/// Auswahl-Sheet für den Aufbewahrungsort.
struct LocationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var location: StorageLocation
    @State var note: String
    var onSave: (StorageLocation, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Wo liegt der Gutschein?").font(.system(size: 24, weight: .heavy)).padding(.top, 24)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(StorageLocation.allCases) { loc in
                    Button { location = loc } label: {
                        VStack(spacing: 8) {
                            Image(systemName: loc.symbol).font(.system(size: 22, weight: .semibold))
                            Text(loc.label).font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity, minHeight: 84)
                        .background(location == loc ? Color.brandYellow : Color.fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            field("Notiz", "z. B. oberste Schublade im Flur", $note)
            Spacer()
            Button("Speichern") { onSave(location, note.trimmingCharacters(in: .whitespaces)); dismiss() }
                .buttonStyle(FilledButtonStyle())
        }
        .padding(.horizontal, 20).padding(.bottom, 16)
        .background(Color.surface.ignoresSafeArea())
    }
}

/// Mini-Bon einer Karte: alle Einlösungen mit Restwert danach.
struct CardBon: View {
    let card: GiftCard

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZigZag(top: true).fill(Color.paper).frame(height: 10)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Einlöse-Verlauf").font(.system(size: 20, weight: .heavy))
                    Spacer()
                    Text(card.name.uppercased()).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(Color.muted)
                }
                DashedRule()
                bonRow(card.kind.isValueBased ? "Erhalten" : "Hinzugefügt", card.received.dayMonthYear,
                       card.kind.isValueBased ? "+" + card.value.euro : card.headline, bold: false)
                ForEach(card.history.sorted { $0.date < $1.date }) { r in
                    bonRow(r.store.isEmpty ? (r.amount > 0 ? "Eingelöst" : r.note) : r.store,
                           subline(r),
                           r.amount > 0 ? "−" + r.amount.euro : "✓", bold: false)
                }
                if card.history.isEmpty {
                    Text("Noch nichts eingelöst.").font(.system(size: 13, design: .monospaced)).foregroundStyle(Color.muted)
                }
                DashedRule()
                bonRow(card.kind.isValueBased ? "RESTWERT" : "STATUS", "", card.kind.isValueBased ? card.balance.euro : (card.redeemedAt == nil ? "OFFEN" : "EINGELÖST"), bold: true)
            }
            .padding(.horizontal, 18).padding(.vertical, 8)
            .background(Color.paper)
            ZigZag(top: false).fill(Color.paper).frame(height: 10)
        }
        .shadow(color: Color.ink.opacity(0.08), radius: 12, y: 6)
    }

    private func subline(_ r: Redemption) -> String {
        var s: String = r.date.dayMonthYear
        if !(r.note.isEmpty || r.amount == 0) { s += " · \(r.note)" }
        if card.kind.isValueBased { s += " · Rest \(r.balanceAfter.euro)" }
        return s
    }

    private func bonRow(_ title: String, _ sub: String, _ amount: String, bold: Bool) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: bold ? .heavy : .semibold, design: .monospaced))
                if !sub.isEmpty { Text(sub).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Color.muted) }
            }
            Spacer()
            Text(amount).font(.system(size: 14, weight: bold ? .heavy : .semibold, design: .monospaced))
        }
        .foregroundStyle(Color.ink)
    }
}

struct DashedRule: View {
    var body: some View {
        Perforation.Line().stroke(style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])).foregroundStyle(Color.muted.opacity(0.6)).frame(height: 1)
    }
}
