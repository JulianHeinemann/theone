import SwiftUI
import UIKit
import UserNotifications
import RestwertKit

/// An der Kasse: großer Barcode bei voller Helligkeit, danach Ergebnis festhalten.
struct CheckoutView: View {
    let cardID: UUID
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var result: Bool?
    @State private var amount = ""
    @State private var storeName = ""
    @State private var note = ""
    @State private var showPin = false
    @State private var oldBrightness: CGFloat?
    @State private var showFull = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var numberShown = false
    @AppStorage("maskNumber") private var maskNumber = false

    var body: some View {
        ScrollView {
            if let card = store.card(cardID) {
                VStack(spacing: 16) {
                    ticket(card)
                    if let result {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(result ? "Wie viel hast du bezahlt?" : "Nicht angenommen – dein Guthaben bleibt gleich.")
                                .font(.scaled(17, weight: .semibold))
                            if result {
                                LabeledField(label: "Betrag, wird vom Guthaben abgezogen", placeholder: "z. B. 18,50",
                                             text: $amount, keyboard: .decimalPad)
                            }
                            LabeledField(label: "Filiale", placeholder: "optional, z. B. Köln Hohe Straße", text: $storeName)
                            LabeledField(label: "Notiz", placeholder: result ? "optional" : "optional, z. B. Kasse wollte Plastikkarte", text: $note)
                            Button(result ? "Eintragen" : "Notieren") { save(card, result) }
                                .buttonStyle(.primary)
                                .padding(.top, 6)
                            Button("Zurück") { withAnimation(.snappy) { self.result = nil } }
                                .font(.scaled(15, weight: .medium)).foregroundStyle(Color.ink2)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .padding(16)
                        .background(Color.surface, in: .rect(cornerRadius: 18, style: .continuous))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        VStack(spacing: 14) {
                            Button { withAnimation(.snappy) { result = true } } label: {
                                Label("Bezahlt – Betrag eintragen", systemImage: "checkmark")
                            }
                            .buttonStyle(.accent)
                            Button { withAnimation(.snappy) { result = false } } label: {
                                Label("Nicht angenommen", systemImage: "xmark")
                            }
                            .buttonStyle(.quiet)
                            Button("Später eintragen") {
                                Task { await remindLater(card) }
                                dismiss()
                            }
                                .font(.scaled(15, weight: .medium)).foregroundStyle(Color.ink2)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .padding(.top, 12)
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 30)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .pageBackground()
        .toolbar(.hidden, for: .tabBar)
        .navigationTitle("An der Kasse")
        .fullScreenCover(isPresented: $showFull) {
            if let card = store.card(cardID) { FullBarcode(card: card) }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            if let screen = currentScreen {
                oldBrightness = screen.brightness
                screen.brightness = 1
            }
        }
        .onDisappear { restoreScreen() }
        // Beim Wechsel in eine andere App Helligkeit und Displaysperre sofort zurückgeben.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                UIApplication.shared.isIdleTimerDisabled = true
                currentScreen?.brightness = 1
            } else {
                restoreScreen()
            }
        }
    }

    private func restoreScreen() {
        UIApplication.shared.isIdleTimerDisabled = false
        if let screen = currentScreen, let old = oldBrightness { screen.brightness = old }
    }

    private var currentScreen: UIScreen? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.screen
    }

    private func ticket(_ card: GiftCard) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                MerchantMark(card: card)
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.name).font(.scaled(19, weight: .bold))
                    Text(card.kind.isValueBased ? "Guthaben \(card.balance.euro)" : card.headline)
                        .font(.scaled(16, weight: .semibold)).foregroundStyle(Color.ink)
                }
                Spacer()
            }
            .padding(18)
            Perforation()
            VStack(spacing: 10) {
                Button { showFull = true } label: {
                    BarcodeView(number: card.number, format: card.format, height: 150)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Barcode groß anzeigen")
                if card.format != .text {
                    Text(maskNumber && !numberShown ? card.number.masked : card.number.grouped)
                        .font(.scaled(19, weight: .bold)).kerning(2.4)
                        .onTapGesture { numberShown = true }
                }
                Text("Tippen für Vollbild").font(.scaled(12)).foregroundStyle(Color.muted)
                Label("Helligkeit automatisch erhöht", systemImage: "checkmark.circle")
                    .font(.scaled(13)).foregroundStyle(Color.ink2)
                if card.merchantID != Merchant.other.id {
                    Text(card.merchant.tip)
                        .font(.scaled(13)).foregroundStyle(Color.muted)
                        .multilineTextAlignment(.center)
                }
                if !card.pin.isEmpty {
                    Button { withAnimation(.snappy) { showPin = true } } label: {
                        Label(showPin ? "PIN \(card.pin)" : "PIN anzeigen", systemImage: showPin ? "lock.open" : "faceid")
                            .font(.scaled(15, weight: .semibold))
                    }
                    .buttonStyle(.glass)
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 20)
        }
        .cardSurface(radius: 28)
    }

    /// Nach 10 Minuten nachfragen, ob bezahlt wurde.
    private func remindLater(_ card: GiftCard) async {
        let content = UNMutableNotificationContent()
        content.title = "Hast du bei \(card.name) bezahlt?"
        content.body = "Trag den Betrag ein, damit dein Guthaben stimmt."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "\(card.id.uuidString)-later", content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 600, repeats: false))
        try? await UNUserNotificationCenter.current().add(request)
        router.toast = Toast(message: "Wir erinnern dich in 10 Minuten.", undo: nil)
    }

    private func save(_ card: GiftCard, _ ok: Bool) {
        let value = parseMoney(amount)
        let entry = store.addTest(card: card, success: ok, store: storeName, note: note, amount: value)
        if let entry, let value {
            router.showUndo("\(min(value, card.balance).euro) bei \(card.name) abgezogen") {
                store.undoRedemption(card.id, entry: entry)
            }
        } else if !ok {
            router.toast = Toast(message: "Notiert. Guthaben unverändert.", undo: nil)
        }
        dismiss()
    }

    private func choice(_ value: Bool, _ title: String, _ subtitle: String, _ icon: String, _ fg: Color, _ bg: Color) -> some View {
        Button { withAnimation(.snappy) { result = value } } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.scaled(17, weight: .bold)).foregroundStyle(fg)
                    .frame(width: 40, height: 40).background(bg, in: .rect(cornerRadius: 12, style: .continuous))
                    .symbolEffect(.bounce, value: result == value)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.scaled(16, weight: .bold)).foregroundStyle(Color.ink)
                    Text(subtitle).font(.scaled(13)).foregroundStyle(Color.ink2)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxHeight: .infinity)
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
    @Environment(Router.self) private var router
    @State private var showStore = false
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
        .toolbar(.hidden, for: .tabBar)
        .navigationTitle("Einkauf abziehen")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ card: GiftCard) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                MerchantMark(card: card)
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.name).font(.scaled(16, weight: .bold))
                    Text("\(card.balance.euro) verfügbar").font(.scaled(13)).foregroundStyle(Color.muted)
                }
                Spacer()
            }
            .padding(12).cardSurface(radius: 20).padding(.horizontal, 16).padding(.top, 8)

            VStack(alignment: .leading, spacing: 6) {
                Text("Betrag eingeben").font(.scaled(15, weight: .semibold)).foregroundStyle(Color.muted)
                HStack(spacing: 4) {
                    Text(input.isEmpty ? "0" : input).font(.scaled(56, weight: .heavy)).monospacedDigit()
                        .contentTransition(.numericText())
                    Rectangle().fill(Color.ink).frame(width: 2, height: 50)
                        .phaseAnimator([1.0, 0.2]) { content, opacity in content.opacity(opacity) }
                    Text(" €").font(.scaled(56, weight: .heavy)).foregroundStyle(Color.muted)
                }
                .lineLimit(1).minimumScaleFactor(0.5)
                .modifier(Shake(animatableData: CGFloat(rejected)))
                Divider()
                Text(hint(card)).font(.scaled(15, weight: value > card.balance ? .semibold : .regular))
                    .foregroundStyle(value > card.balance ? Color.warn : Color.ink2)
            }
            .padding(.horizontal, 18).padding(.top, 22)

            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach([5.0, 10, 20].filter { $0 < card.balance }, id: \.self) { q in chip("\(Int(q)) €") { input = "\(Int(q))" } }
                    chip("Alles") { input = card.balance.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "de_DE"))).replacingOccurrences(of: ".", with: "") }
                }
                .padding(.horizontal, 16).padding(.vertical, 4)
            }
            .padding(.top, 14)

            Group {
                if showStore {
                    LabeledField(label: "Filiale (für deinen Verlauf)", placeholder: "z. B. Thalia Köln", text: $storeName)
                } else {
                    Button("+ Filiale notieren") { withAnimation(.snappy) { showStore = true } }
                        .font(.scaled(15, weight: .medium)).foregroundStyle(Color.ink2)
                }
            }
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
                Button {
                    guard value > 0 else {
                        withAnimation(.linear(duration: 0.4)) { rejected += 1 }
                        return
                    }
                    // Mehr als auf der Karte: Karte leeren, den Rest zahlt man an der Kasse anders.
                    let taken = min(value, card.balance)
                    if let entry = store.redeem(card.id, amount: taken, store: storeName) {
                        router.showUndo("\(taken.euro) bei \(card.name) abgezogen") {
                            store.undoRedemption(card.id, entry: entry)
                        }
                    }
                    dismiss()
                } label: {
                    Text(value > card.balance ? "Alles abziehen (\(card.balance.euro))"
                         : value > 0 ? "\(value.euro) abziehen" : "Erst Betrag wählen")
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
        if value > card.balance {
            return "Nur \(card.balance.euro) auf der Karte. \((value - card.balance).euro) zahlst du an der Kasse anders."
        }
        if value > 0 { return "Danach übrig: \(max(0, card.balance - value).euro)" }
        return "Wird vom Guthaben abgezogen"
    }

    private func chip(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.scaled(16, weight: .bold)).foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity, minHeight: 46)
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
                .background(configuration.isPressed ? Color.brandYellow : Color(hex: 0xE6E7EB), in: .circle)
                .scaleEffect(configuration.isPressed ? 0.92 : 1)
                .animation(.spring(duration: 0.2, bounce: 0.5), value: configuration.isPressed)
        }
    }
}

/// Barcode bildschirmfüllend, quer, mit Ruhezone – für schwierige Scanner.
private struct FullBarcode: View {
    let card: GiftCard
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 18) {
                BarcodeView(number: card.number, format: card.format, height: min(geo.size.width * 0.5, 220))
                    .padding(.horizontal, 24)
                Text(card.number.grouped).font(.system(size: 26, weight: .bold, design: .monospaced)).kerning(2)
                    .foregroundStyle(.black)
            }
            .frame(width: geo.size.height, height: geo.size.width)
            .rotationEffect(.degrees(90))
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(Color.white.ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            Button("Schließen", systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly).font(.system(size: 17, weight: .bold))
                .buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.large)
                .padding(16)
        }
        .onTapGesture { dismiss() }
    }
}
