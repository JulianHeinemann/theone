import SwiftUI
import UIKit

/// An der Kasse: großer Barcode bei voller Helligkeit, danach Ergebnis festhalten.
struct CheckoutView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let cardID: UUID

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
                    HStack {
                        CircleButton(systemImage: "arrow.left", label: "Zurück") { dismiss() }
                        Spacer()
                        Text("An der Kasse").font(.system(size: 21, weight: .bold))
                        Spacer()
                        Color.clear.frame(width: 48, height: 48)
                    }
                    VStack(spacing: 0) {
                        HStack(spacing: 14) {
                            LetterTile(text: card.name, color: Pastel.color(for: card))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(card.name).font(.system(size: 19, weight: .bold))
                                Text("Restguthaben \(card.balance.euro)").font(.system(size: 14)).foregroundStyle(Color.muted)
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
                            Text("\(card.format.label) · Helligkeit ist auf Maximum").font(.system(size: 12)).foregroundStyle(Color.muted)
                            if !card.pin.isEmpty {
                                Button(showPin ? "PIN \(card.pin)" : "PIN anzeigen") { showPin = true }
                                    .font(.system(size: 15, weight: .bold, design: .monospaced)).foregroundStyle(Color.ink2)
                            }
                        }
                        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 20)
                    }
                    .cardSurface(radius: 28)

                    Text("Hat es geklappt?").font(.system(size: 24, weight: .heavy)).padding(.top, 8)
                    HStack(spacing: 10) {
                        choice(true, "Geklappt", "checkmark", .good, .goodSoft)
                        choice(false, "Abgelehnt", "xmark", .bad, .badSoft)
                    }
                    if let result {
                        VStack(spacing: 8) {
                            if result { field("Bezahlter Betrag, wird abgezogen", "z. B. 18,50", $amount, keyboard: .decimalPad) }
                            field("Filiale", "optional, z. B. Köln Hohe Straße", $storeName)
                            field("Notiz", "optional, z. B. Kasse wollte PIN", $note)
                            Button("Ergebnis speichern") {
                                store.addTest(card: card, success: result, store: storeName, note: note, amount: parseMoney(amount))
                                dismiss()
                            }
                            .buttonStyle(FilledButtonStyle())
                            .padding(.top, 6)
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 30)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.page.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            if let screen = currentScreen { oldBrightness = screen.brightness; screen.brightness = 1 }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            if let screen = currentScreen, let b = oldBrightness { screen.brightness = b }
        }
    }

    private var currentScreen: UIScreen? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.screen
    }

    private func choice(_ value: Bool, _ title: String, _ icon: String, _ fg: Color, _ bg: Color) -> some View {
        Button { withAnimation(.snappy) { result = value } } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 17, weight: .bold)).foregroundStyle(fg)
                    .frame(width: 40, height: 40).background(bg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(Color.ink)
                Spacer(minLength: 0)
            }
            .padding(12)
            .cardSurface(radius: 20)
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(result == value ? fg : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

/// Eingabefeld im Stil der grauen Kästen mit kleiner Beschriftung.
@MainActor
func field(_ label: String, _ placeholder: String, _ text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.muted)
        TextField(placeholder, text: text)
            .font(.system(size: 16, weight: .semibold))
            .keyboardType(keyboard)
    }
    .padding(.horizontal, 14).padding(.vertical, 10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
}

// MARK: - Nummernblock

struct KeypadView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let cardID: UUID
    @State private var input = ""
    @State private var storeName = ""

    private var value: Double { parseMoney(input.isEmpty ? "0" : input) ?? 0 }

    var body: some View {
        if let card = store.card(cardID) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    CircleButton(systemImage: "arrow.left", label: "Zurück") { dismiss() }
                    Spacer()
                    Text("Einkauf abziehen").font(.system(size: 21, weight: .bold))
                    Spacer()
                    Color.clear.frame(width: 48, height: 48)
                }
                .padding(.horizontal, 16)
                HStack(spacing: 14) {
                    LetterTile(text: card.name, color: Pastel.color(for: card))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(card.name).font(.system(size: 16, weight: .bold))
                        Text("\(card.balance.euro) verfügbar").font(.system(size: 13)).foregroundStyle(Color.muted)
                    }
                    Spacer()
                }
                .padding(12).cardSurface(radius: 20).padding(.horizontal, 16).padding(.top, 14)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Betrag eingeben").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.muted)
                    HStack(spacing: 4) {
                        Text(input.isEmpty ? "0" : input).font(.system(size: 56, weight: .heavy)).monospacedDigit()
                        Rectangle().fill(Color.brandYellow).frame(width: 3, height: 50)
                        Text(" €").font(.system(size: 56, weight: .heavy)).foregroundStyle(Color.muted)
                    }
                    .lineLimit(1).minimumScaleFactor(0.5)
                    Divider()
                    Text(value > card.balance ? "Mehr als das Restguthaben von \(card.balance.euro)" : (value > 0 ? "Danach übrig: \(max(0, card.balance - value).euro)" : "Wird vom Restguthaben abgezogen"))
                        .font(.system(size: 13)).foregroundStyle(value > card.balance ? Color.bad : Color.muted)
                }
                .padding(.horizontal, 18).padding(.top, 26)

                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(["5", "10", "20", "50"], id: \.self) { q in chip("\(q) €") { input = q } }
                        chip("Alles") { input = String(format: "%.2f", card.balance).replacingOccurrences(of: ".", with: ",") }
                    }
                    .padding(.horizontal, 16)
                }
                .scrollIndicators(.hidden)
                .padding(.top, 16)

                field("Filiale (optional, erscheint auf dem Bon)", "z. B. Thalia Köln", $storeName)
                    .padding(.horizontal, 16).padding(.top, 12)

                Spacer(minLength: 16)

                VStack(spacing: 14) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 6) {
                        ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", ",", "0", "⌫"], id: \.self) { k in
                            Button { press(k) } label: {
                                Group {
                                    if k == "⌫" { Image(systemName: "delete.left").font(.system(size: 22, weight: .semibold)) }
                                    else { Text(k).font(.system(size: 28, weight: .semibold)) }
                                }
                                .foregroundStyle(Color.ink)
                                .frame(width: 64, height: 58)
                                .background(Color.fill, in: Circle())
                            }
                            .buttonStyle(KeyStyle())
                            .accessibilityLabel(k == "⌫" ? "Löschen" : k)
                        }
                    }
                    Button("Abziehen") {
                        guard value > 0 else { return }
                        store.redeem(card.id, amount: min(value, card.balance), store: storeName)
                        dismiss()
                    }
                    .buttonStyle(FilledButtonStyle(background: .brandYellow, foreground: .ink))
                    .disabled(value <= 0)
                }
                .padding(16)
                .background(Color.surface, in: UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous))
                .shadow(color: Color.ink.opacity(0.06), radius: 16, y: -4)
            }
            .background(Color.page.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func chip(_ t: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).font(.system(size: 16, weight: .bold)).foregroundStyle(Color.ink)
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func press(_ k: String) {
        switch k {
        case "⌫": if !input.isEmpty { input.removeLast() }
        case ",": if !input.contains(",") { input = (input.isEmpty ? "0" : input) + "," }
        default:
            if let comma = input.firstIndex(of: ","), input.distance(from: comma, to: input.endIndex) > 2 { return }
            if input == "0" { input = "" }
            if input.count < 7 { input += k }
        }
    }

    private struct KeyStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .colorMultiply(configuration.isPressed ? Color.keyBlue : .white)
                .scaleEffect(configuration.isPressed ? 0.94 : 1)
        }
    }
}
