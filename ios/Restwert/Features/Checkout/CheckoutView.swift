import SwiftUI
import UIKit
import RestwertKit

/// An der Kasse: großer Barcode bei voller Helligkeit, danach Ergebnis festhalten.
struct CheckoutView: View {
    let cardID: UUID
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var result: Bool?
    @State private var amount = ""
    @State private var storeName = ""
    @State private var note = ""
    @State private var showPin = false
    @State private var oldBrightness: CGFloat?

    var body: some View {
        ScrollView {
            if let card = store.card(cardID) {
                VStack(spacing: 16) {
                    ticket(card)
                    Text("Hat es geklappt?").font(.system(size: 24, weight: .heavy)).padding(.top, 8)
                    HStack(spacing: 10) {
                        choice(true, "Geklappt", "checkmark", .good, .goodSoft)
                        choice(false, "Abgelehnt", "xmark", .bad, .badSoft)
                    }
                    if let result {
                        VStack(spacing: 8) {
                            if result {
                                LabeledField(label: "Bezahlter Betrag, wird abgezogen", placeholder: "z. B. 18,50",
                                             text: $amount, keyboard: .decimalPad)
                            }
                            LabeledField(label: "Filiale", placeholder: "optional, z. B. Köln Hohe Straße", text: $storeName)
                            LabeledField(label: "Notiz", placeholder: "optional, z. B. Kasse wollte PIN", text: $note)
                            Button("Ergebnis speichern") {
                                store.addTest(card: card, success: result, store: storeName, note: note, amount: parseMoney(amount))
                                dismiss()
                            }
                            .buttonStyle(.primary)
                            .padding(.top, 6)
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 30)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .pageBackground()
        .navigationTitle("An der Kasse")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            if let screen = currentScreen {
                oldBrightness = screen.brightness
                screen.brightness = 1
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            if let screen = currentScreen, let old = oldBrightness { screen.brightness = old }
        }
    }

    private var currentScreen: UIScreen? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.screen
    }

    private func ticket(_ card: GiftCard) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                LetterTile(text: card.name, color: Pastel.color(for: card))
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.name).font(.system(size: 19, weight: .bold))
                    Text(card.kind.isValueBased ? "Restguthaben \(card.balance.euro)" : card.headline)
                        .font(.system(size: 14)).foregroundStyle(Color.muted)
                }
                Spacer()
            }
            .padding(18)
            Perforation()
            VStack(spacing: 10) {
                BarcodeView(number: card.number, format: card.format, height: 150)
                if card.format != .text {
                    Text(card.number.grouped).font(.system(size: 19, weight: .bold)).kerning(2.4)
                }
                Label("\(card.format.label) · Helligkeit auf Maximum", systemImage: "sun.max.fill")
                    .font(.system(size: 12)).foregroundStyle(Color.muted)
                    .symbolEffect(.pulse)
                if !card.pin.isEmpty {
                    Button(showPin ? "PIN \(card.pin)" : "PIN anzeigen") { withAnimation(.snappy) { showPin = true } }
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .buttonStyle(.glass)
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 20)
        }
        .cardSurface(radius: 28)
    }

    private func choice(_ value: Bool, _ title: String, _ icon: String, _ fg: Color, _ bg: Color) -> some View {
        Button { withAnimation(.snappy) { result = value } } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 17, weight: .bold)).foregroundStyle(fg)
                    .frame(width: 40, height: 40).background(bg, in: .rect(cornerRadius: 12, style: .continuous))
                    .symbolEffect(.bounce, value: result == value)
                Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(Color.ink)
                Spacer(minLength: 0)
            }
            .padding(12)
            .cardSurface(radius: 20)
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(result == value ? fg : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: result)
    }
}

// MARK: - Nummernblock

struct KeypadView: View {
    let cardID: UUID
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var storeName = ""
    @State private var rejected = 0

    private var value: Double { parseMoney(input.isEmpty ? "0" : input) ?? 0 }

    var body: some View {
        Group {
            if let card = store.card(cardID) { content(card) }
        }
        .pageBackground()
        .navigationTitle("Einkauf abziehen")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ card: GiftCard) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                LetterTile(text: card.name, color: Pastel.color(for: card))
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.name).font(.system(size: 16, weight: .bold))
                    Text("\(card.balance.euro) verfügbar").font(.system(size: 13)).foregroundStyle(Color.muted)
                }
                Spacer()
            }
            .padding(12).cardSurface(radius: 20).padding(.horizontal, 16).padding(.top, 8)

            VStack(alignment: .leading, spacing: 6) {
                Text("Betrag eingeben").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.muted)
                HStack(spacing: 4) {
                    Text(input.isEmpty ? "0" : input).font(.system(size: 56, weight: .heavy)).monospacedDigit()
                        .contentTransition(.numericText())
                    Rectangle().fill(Color.brandYellow).frame(width: 3, height: 50)
                        .phaseAnimator([1.0, 0.2]) { content, opacity in content.opacity(opacity) }
                    Text(" €").font(.system(size: 56, weight: .heavy)).foregroundStyle(Color.muted)
                }
                .lineLimit(1).minimumScaleFactor(0.5)
                .modifier(Shake(animatableData: CGFloat(rejected)))
                Divider()
                Text(hint(card)).font(.system(size: 13)).foregroundStyle(value > card.balance ? Color.bad : Color.muted)
            }
            .padding(.horizontal, 18).padding(.top, 22)

            ScrollView(.horizontal) {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(["5", "10", "20", "50"], id: \.self) { q in chip("\(q) €") { input = q } }
                        chip("Alles") { input = card.balance.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "de_DE"))).replacingOccurrences(of: ".", with: "") }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 4)
                }
            }
            .scrollIndicators(.hidden)
            .padding(.top, 14)

            LabeledField(label: "Filiale (optional, erscheint auf dem Bon)", placeholder: "z. B. Thalia Köln", text: $storeName)
                .padding(.horizontal, 16).padding(.top, 12)

            Spacer(minLength: 16)

            VStack(spacing: 14) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 6) {
                    ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", ",", "0", "⌫"], id: \.self) { key in
                        Button { press(key) } label: {
                            Group {
                                if key == "⌫" {
                                    Image(systemName: "delete.left").font(.system(size: 22, weight: .semibold))
                                } else {
                                    Text(key).font(.system(size: 28, weight: .semibold))
                                }
                            }
                            .foregroundStyle(Color.ink)
                            .frame(width: 64, height: 58)
                        }
                        .buttonStyle(KeyStyle())
                        .accessibilityLabel(key == "⌫" ? "Löschen" : key)
                    }
                }
                .sensoryFeedback(.impact(weight: .light), trigger: input)
                Button("Abziehen") {
                    guard value > 0, value <= card.balance else {
                        withAnimation(.linear(duration: 0.4)) { rejected += 1 }
                        return
                    }
                    store.redeem(card.id, amount: value, store: storeName)
                    dismiss()
                }
                .buttonStyle(.accent)
                .disabled(value <= 0)
            }
            .padding(16)
            .background(Color.surface, in: UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous))
            .shadow(color: Color.ink.opacity(0.06), radius: 16, y: -4)
        }
        .sensoryFeedback(.error, trigger: rejected)
    }

    private func hint(_ card: GiftCard) -> String {
        if value > card.balance { return "Mehr als das Restguthaben von \(card.balance.euro)" }
        if value > 0 { return "Danach übrig: \(max(0, card.balance - value).euro)" }
        return "Wird vom Restguthaben abgezogen"
    }

    private func chip(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(Color.ink)
                .padding(.horizontal, 18).padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14, style: .continuous))
    }

    private func press(_ key: String) {
        switch key {
        case "⌫":
            if !input.isEmpty { input.removeLast() }
        case ",":
            if !input.contains(",") { input = (input.isEmpty ? "0" : input) + "," }
        default:
            if let comma = input.firstIndex(of: ","), input.distance(from: comma, to: input.endIndex) > 2 { return }
            if input == "0" { input = "" }
            if input.count < 7 { input += key }
        }
    }

    private struct KeyStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .background(configuration.isPressed ? Color.brandYellow : Color.fill, in: .circle)
                .scaleEffect(configuration.isPressed ? 0.92 : 1)
                .animation(.spring(duration: 0.2, bounce: 0.5), value: configuration.isPressed)
        }
    }
}
