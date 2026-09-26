import SwiftUI
import UIKit
import LocalAuthentication
import RestwertKit

struct CardDetailView: View {
    let cardID: UUID
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @AppStorage("pinLock") private var pinLock = true
    @AppStorage("warnDays") private var warnDays = 30

    @State private var pinVisible = false
    @State private var confirmDelete = false
    @State private var showLocation = false
    @State private var amount: Double = 0
    @State private var tornAmount: Double = 0
    @State private var tearTrigger = 0
    @State private var stampVisible = false
    @State private var copied = false
    @State private var success = 0

    var body: some View {
        Group {
            if let card = store.card(cardID) {
                content(card)
            } else {
                ContentUnavailableView("Gutschein entfernt", systemImage: "trash")
            }
        }
        .pageBackground()
        .sensoryFeedback(.success, trigger: success)
    }

    private func content(_ card: GiftCard) -> some View {
        let status = card.status(warnDays: warnDays)
        return ScrollView {
            VStack(spacing: 16) {
                summary(card, status)
                locationRow(card)
                codeTicket(card)
                if card.isActive {
                    if card.kind.isValueBased { partialRedeem(card) } else { markRedeemedBlock(card) }
                }
                NavigationLink(value: Route.checkout(card.id)) {
                    Label("An der Kasse zeigen & testen", systemImage: "barcode.viewfinder")
                }
                .buttonStyle(.quiet)
                CardBon(card: card).padding(.top, 6)
                Button("Gutschein entfernen", role: .destructive) { confirmDelete = true }
                    .font(.system(size: 15, weight: .bold)).padding(.top, 6)
            }
            .padding(.horizontal, 16).padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .navigationTitle(card.kind.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Bearbeiten", systemImage: "pencil") { router.editing = card }
            }
        }
        .confirmationDialog("Gutschein endgültig entfernen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Entfernen", role: .destructive) {
                dismiss()
                store.delete(card.id)
            }
        }
        .sheet(isPresented: $showLocation) {
            LocationSheet(location: card.location, note: card.locationNote) { location, note in
                store.setLocation(card.id, location, note: note)
            }
            .presentationDetents([.medium, .large])
        }
        .onAppear { if amount == 0 { amount = min(10, card.balance) } }
    }

    // MARK: Übersicht

    private func summary(_ card: GiftCard, _ status: VoucherStatus) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                LetterTile(text: card.name, color: Pastel.color(for: card))
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.name).font(.system(size: 19, weight: .bold))
                    Text(card.merchant.category.label).font(.system(size: 13)).foregroundStyle(Color.muted)
                }
                Spacer()
                Chip(text: status.label, fg: status.tint, bg: status.soft)
                    .contentTransition(.interpolate)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(card.kind.isValueBased ? "Restwert" : "Rabatt")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.muted)
                Text(card.headline)
                    .font(.system(size: 52, weight: .heavy)).kerning(-1.5).monospacedDigit()
                    .contentTransition(.numericText(value: card.balance))
                    .strikethrough(status == .redeemed || status == .expired, color: Color.muted)
                    .minimumScaleFactor(0.5).lineLimit(1)
            }
            ProgressBar(value: card.remainingShare, tint: status.tint)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                cell("Gültig bis", card.expires.dayMonthYear)
                cell("Verbleibend", card.daysLeft < 0 ? "abgelaufen" : "\(card.daysLeft) Tage",
                     tint: card.daysLeft <= warnDays ? status.tint : .ink)
                cell("Ursprünglich", card.kind.isValueBased ? card.value.euro : (card.percent.map { "\(Int($0)) %" } ?? "–"))
                cell("Einlösungen", "\(card.history.count)")
            }
            if card.kind == .giftCard && !card.pin.isEmpty {
                Button { Task { await togglePin(card) } } label: {
                    HStack {
                        Image(systemName: pinVisible ? "lock.open" : "faceid")
                            .contentTransition(.symbolEffect(.replace))
                        Text(pinVisible ? "PIN \(card.pin)" : "PIN anzeigen")
                            .font(.system(size: 15, weight: .bold, design: pinVisible ? Font.Design.monospaced : Font.Design.default))
                        Spacer()
                    }
                    .foregroundStyle(Color.ink).padding(14)
                    .background(Color.fill, in: .rect(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .cardSurface(radius: 28)
        .overlay {
            if card.redeemedAt != nil || stampVisible {
                Stamp(date: card.redeemedAt ?? .now).allowsHitTesting(false)
            }
        }
    }

    private func cell(_ label: String, _ value: String, tint: Color = .ink) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 12)).foregroundStyle(Color.muted)
            Text(value).font(.system(size: 16, weight: .bold)).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.7)
                .contentTransition(.numericText())
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.fill, in: .rect(cornerRadius: 16, style: .continuous))
    }

    private func locationRow(_ card: GiftCard) -> some View {
        Button { showLocation = true } label: {
            HStack(spacing: 14) {
                Image(systemName: card.location.symbol).font(.system(size: 18, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44)
                    .background(Pastel.all[3], in: .rect(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Aufbewahrt: \(card.location.label)").font(.system(size: 16, weight: .bold))
                    Text(card.locationNote.isEmpty ? "Notiz hinzufügen" : card.locationNote)
                        .font(.system(size: 13)).foregroundStyle(Color.muted).lineLimit(2)
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
                    success += 1
                    Task {
                        try? await Task.sleep(for: .seconds(1.6))
                        copied = false
                    }
                } label: {
                    Label(copied ? "Kopiert" : "Code kopieren", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 14, weight: .bold))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.glassProminent)
                .tint(Color.brandYellow)
                .foregroundStyle(Color.ink)
            }
            .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 4)
            Perforation()
            VStack(spacing: 8) {
                BarcodeView(number: card.number, format: card.format, height: 84)
                if card.format != .text {
                    Text(card.number.grouped).font(.system(size: 17, weight: .bold)).kerning(2).textSelection(.enabled)
                }
                if let url = card.merchant.balanceURL {
                    Link(destination: url) {
                        Label("Guthaben beim Händler prüfen", systemImage: "arrow.up.right").font(.system(size: 14, weight: .bold))
                    }
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
                Text(amount.euro).font(.system(size: 28, weight: .heavy)).monospacedDigit()
                    .contentTransition(.numericText(value: amount))
                    .animation(.snappy, value: amount)
            }
            Slider(value: $amount, in: 0...max(card.balance, 0.5), step: 0.5)
                .tint(Color.ink)
                .sensoryFeedback(.selection, trigger: amount)
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach([5.0, 10, 20], id: \.self) { value in
                        quickPick("\(Int(value)) €") { amount = min(value, card.balance) }
                    }
                    quickPick("Alles") { amount = card.balance }
                }
            }
            Text(amount > 0 ? "Danach übrig: \(max(0, card.balance - amount).euro)" : "Betrag wählen")
                .font(.system(size: 13)).foregroundStyle(Color.muted)
                .contentTransition(.numericText())
            Button {
                guard amount > 0 else { return }
                let value = min(amount, card.balance)
                tornAmount = value
                tearTrigger += 1
                success += 1
                withAnimation(.snappy) { store.redeem(card.id, amount: value) }
                amount = min(amount, max(0, card.balance - value))
            } label: {
                Label("Einlösen", systemImage: "scissors")
            }
            .buttonStyle(.accent)
            .disabled(amount <= 0)
            NavigationLink(value: Route.keypad(card.id)) {
                Text("Betrag genau eintippen").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.muted)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(18)
        .cardSurface(radius: 28)
        .overlay(alignment: .bottom) {
            TearStub(amount: tornAmount, merchant: card.name)
                .keyframeAnimator(initialValue: TearFrame(), trigger: tearTrigger) { content, frame in
                    content
                        .offset(y: frame.y)
                        .rotationEffect(.degrees(frame.angle), anchor: .topLeading)
                        .opacity(frame.opacity)
                } keyframes: { _ in
                    KeyframeTrack(\.opacity) {
                        LinearKeyframe(1, duration: 0.08)
                        LinearKeyframe(1, duration: 0.55)
                        LinearKeyframe(0, duration: 0.3)
                    }
                    KeyframeTrack(\.y) {
                        LinearKeyframe(40, duration: 0.08)
                        SpringKeyframe(52, duration: 0.25, spring: .bouncy)
                        CubicKeyframe(460, duration: 0.6)
                    }
                    KeyframeTrack(\.angle) {
                        LinearKeyframe(0, duration: 0.2)
                        SpringKeyframe(-4, duration: 0.15)
                        CubicKeyframe(16, duration: 0.6)
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func quickPick(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 15, weight: .bold)).foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14, style: .continuous))
    }

    private func markRedeemedBlock(_ card: GiftCard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(card.kind.label) benutzt?").font(.system(size: 20, weight: .bold))
            Text("Rabattcodes und Coupons gelten meist nur einmal. Markier ihn nach dem Einkauf, dann erscheint er im Verlauf.")
                .font(.system(size: 14)).foregroundStyle(Color.muted)
            Button {
                stampVisible = true
                success += 1
                Task {
                    try? await Task.sleep(for: .milliseconds(650))
                    withAnimation(.smooth) { store.markRedeemed(card.id) }
                }
            } label: {
                Label("Als eingelöst markieren", systemImage: "seal")
            }
            .buttonStyle(.accent)
        }
        .padding(18)
        .cardSurface(radius: 28)
    }

    private func togglePin(_ card: GiftCard) async {
        if pinVisible {
            withAnimation(.snappy) { pinVisible = false }
            return
        }
        guard pinLock else {
            withAnimation(.snappy) { pinVisible = true }
            return
        }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            withAnimation(.snappy) { pinVisible = true }
            return
        }
        let ok = (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "PIN von \(card.name) anzeigen")) ?? false
        if ok { withAnimation(.snappy) { pinVisible = true } }
    }
}

// MARK: - Bausteine

private struct ProgressBar: View {
    let value: Double
    let tint: Color

    var body: some View {
        Capsule().fill(Color.fill)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule().fill(tint.gradient).frame(width: geo.size.width * value)
                }
            }
            .frame(height: 6)
            .animation(.spring(duration: 0.6, bounce: 0.3), value: value)
    }
}

private struct TearFrame {
    var y: CGFloat = 40
    var angle: Double = 0
    var opacity: Double = 0
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
                    Text(Date.now.formatted(date: .numeric, time: .shortened))
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.muted)
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

/// Roter Stempel „Eingelöst“, fällt mit Wucht aufs Papier.
struct Stamp: View {
    let date: Date
    @State private var landed = false

    var body: some View {
        VStack(spacing: 2) {
            Text("EINGELÖST").font(.system(size: 28, weight: .black, design: .rounded)).kerning(3)
            Text(date.dayMonthYear).font(.system(size: 13, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(Color.bad.opacity(0.85))
        .padding(.horizontal, 18).padding(.vertical, 10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.bad.opacity(0.85), lineWidth: 4))
        .rotationEffect(.degrees(landed ? -14 : -30))
        .scaleEffect(landed ? 1 : 2.4)
        .opacity(landed ? 1 : 0)
        .onAppear { withAnimation(.spring(duration: 0.45, bounce: 0.5)) { landed = true } }
        .sensoryFeedback(.impact(weight: .heavy), trigger: landed)
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
                    Button { withAnimation(.snappy) { location = loc } } label: {
                        VStack(spacing: 8) {
                            Image(systemName: loc.symbol).font(.system(size: 22, weight: .semibold))
                                .symbolEffect(.bounce, value: location == loc)
                            Text(loc.label).font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity, minHeight: 84)
                        .background(location == loc ? Color.brandYellow : Color.fill, in: .rect(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .sensoryFeedback(.selection, trigger: location)
            LabeledField(label: "Notiz", placeholder: "z. B. oberste Schublade im Flur", text: $note)
            Spacer()
            Button("Speichern") {
                onSave(location, note.trimmingCharacters(in: .whitespaces))
                dismiss()
            }
            .buttonStyle(.primary)
        }
        .padding(.horizontal, 20).padding(.bottom, 16)
    }
}

/// Mini-Bon eines Gutscheins: alle Einlösungen mit Restwert danach.
struct CardBon: View {
    let card: GiftCard

    var body: some View {
        ReceiptPaper {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Einlöse-Verlauf").font(.system(size: 20, weight: .heavy))
                    Spacer()
                    Text(card.name.uppercased()).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(Color.muted)
                }
                DashedRule()
                row(card.kind.isValueBased ? "Erhalten" : "Hinzugefügt", card.received.dayMonthYear,
                    card.kind.isValueBased ? "+" + card.value.euro : card.headline)
                ForEach(card.history.sorted { $0.date < $1.date }) { r in
                    row(r.store.isEmpty ? (r.amount > 0 ? "Eingelöst" : r.note) : r.store, subline(r),
                        r.amount > 0 ? "−" + r.amount.euro : "✓")
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if card.history.isEmpty {
                    Text("Noch nichts eingelöst.").font(.system(size: 13, design: .monospaced)).foregroundStyle(Color.muted)
                }
                DashedRule()
                row(card.kind.isValueBased ? "RESTWERT" : "STATUS", "",
                    card.kind.isValueBased ? card.balance.euro : (card.redeemedAt == nil ? "OFFEN" : "EINGELÖST"), bold: true)
            }
            .animation(.smooth, value: card.history.count)
        }
    }

    private func subline(_ r: Redemption) -> String {
        var s = r.date.dayMonthYear
        if !r.note.isEmpty && r.amount > 0 { s += " · \(r.note)" }
        if card.kind.isValueBased { s += " · Rest \(r.balanceAfter.euro)" }
        return s
    }

    private func row(_ title: String, _ sub: String, _ amount: String, bold: Bool = false) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: bold ? .heavy : .semibold, design: .monospaced))
                if !sub.isEmpty {
                    Text(sub).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Color.muted)
                }
            }
            Spacer()
            Text(amount).font(.system(size: 14, weight: bold ? .heavy : .semibold, design: .monospaced))
        }
    }
}
