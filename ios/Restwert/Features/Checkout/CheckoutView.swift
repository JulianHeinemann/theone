import SwiftUI
import UIKit
import LocalAuthentication
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
    @State private var showPhotoFull = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var numberShown = false
    @AppStorage("maskNumber") private var maskNumber = false
    @AppStorage("pinLock") private var pinLock = true

    var body: some View {
        ScrollView {
            if let card = store.card(cardID) {
                VStack(spacing: 16) {
                    ticket(card)
                    if let result {
                        let needsAmount = result && card.kind.isValueBased
                        VStack(alignment: .leading, spacing: 8) {
                            Text(!result ? "Nicht angenommen – dein Guthaben bleibt gleich."
                                 : needsAmount ? "Wie viel hast du bezahlt?" : "\(card.kind.label) wird als eingelöst markiert.")
                                .font(.scaled(17, weight: .semibold))
                            if needsAmount {
                                LabeledField(label: "Betrag, wird vom Guthaben abgezogen", placeholder: "z. B. 18,50",
                                             text: $amount, keyboard: .decimalPad)
                                if !amountValid {
                                    Label(amount.isEmpty ? "Gib den bezahlten Betrag ein." : "Kein gültiger Betrag, z. B. 18,50.",
                                          systemImage: "exclamationmark.circle")
                                        .font(.scaled(13)).foregroundStyle(amount.isEmpty ? Color.ink2 : Color.warn)
                                }
                            }
                            LabeledField(label: "Filiale", placeholder: "optional, z. B. Köln Hohe Straße", text: $storeName)
                            LabeledField(label: "Notiz", placeholder: result ? "optional" : "optional, z. B. Kasse wollte Plastikkarte", text: $note)
                            Button(!result ? "Notieren" : needsAmount ? "Eintragen" : "Als eingelöst markieren") { save(card, result) }
                                .buttonStyle(.primary)
                                .disabled(needsAmount && !amountValid)
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
                            actionButton("Bezahlt – Betrag eintragen", "Wird von deinem Guthaben abgezogen", "checkmark", .accent) {
                                withAnimation(.snappy) { result = true }
                            }
                            actionButton("Nicht angenommen", "Guthaben bleibt gleich, wird nur notiert", "xmark", .quiet) {
                                withAnimation(.snappy) { result = false }
                            }
                            Button {
                                Task { await remindLater(card) }
                                dismiss()
                            } label: {
                                VStack(spacing: 2) {
                                    Text("Später eintragen").font(.scaled(15, weight: .semibold))
                                    Text("Wird als „Betrag offen“ markiert").font(.scaled(12))
                                }
                                .foregroundStyle(Color.ink2)
                                .frame(maxWidth: .infinity, minHeight: 44)
                            }
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
            if let card = store.card(cardID) { FullBarcode(card: card, masked: maskNumber && !numberShown) }
        }
        .fullScreenCover(isPresented: $showPhotoFull) {
            if let data = store.card(cardID)?.photo, let image = UIImage(data: data) { PhotoViewer(image: image) }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            if let screen = currentScreen {
                // Nur einmal merken: nach dem Vollbild läuft onAppear erneut, dann steht die Helligkeit schon auf 1.
                if oldBrightness == nil { oldBrightness = screen.brightness }
                screen.brightness = 1
            }
        }
        // fullScreenCover löst onDisappear der darunterliegenden View aus – dort muss es hell bleiben.
        .onDisappear { if !showFull && !showPhotoFull { restoreScreen() } }
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
                if card.number.isEmpty, let data = card.photo, let image = UIImage(data: data) {
                    // Papiergutschein: das Foto vorzeigen.
                    Button { showPhotoFull = true } label: {
                        Image(uiImage: image).resizable().scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 320)
                            .clipShape(.rect(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Foto des Gutscheins groß anzeigen")
                } else {
                    let textOnly = card.format == .text || card.format == .dataMatrix
                    let hidden = maskNumber && !numberShown
                    // Textcode verdeckt: erster Tipp deckt auf, erst der zweite öffnet das Vollbild.
                    Button { if textOnly && hidden { numberShown = true } else { showFull = true } } label: {
                        BarcodeView(number: card.number, format: card.format, height: 150, masked: hidden)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(textOnly && hidden ? "Code aufdecken" : "Barcode groß anzeigen")
                }
                if card.format != .text && card.format != .dataMatrix {
                    Text(maskNumber && !numberShown ? card.number.masked : card.number.grouped)
                        .font(.scaled(19, weight: .bold)).kerning(2.4)
                        .onTapGesture { numberShown = true }
                }
                Text(card.number.isEmpty ? "Tippen zum Vergrößern" : "Tippen für Vollbild").font(.scaled(12)).foregroundStyle(Color.muted)
                if !card.number.isEmpty && card.photo != nil {
                    Button("Original-Foto zeigen", systemImage: "photo") { showPhotoFull = true }
                        .font(.scaled(14, weight: .medium)).foregroundStyle(Color.ink2)
                }
                Label("Helligkeit automatisch erhöht", systemImage: "checkmark.circle")
                    .font(.scaled(13)).foregroundStyle(Color.ink2)
                if card.merchantID != Merchant.other.id {
                    Text(card.merchant.tip)
                        .font(.scaled(13)).foregroundStyle(Color.muted)
                        .multilineTextAlignment(.center)
                }
                if !card.pin.isEmpty {
                    Button { Task { await togglePin(card) } } label: {
                        Label(showPin ? "PIN \(card.pin)" : "PIN anzeigen", systemImage: showPin ? "lock.open" : pinLock ? "faceid" : "eye")
                            .font(.scaled(15, weight: .semibold))
                    }
                    .buttonStyle(.glass)
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 20)
        }
        .cardSurface(radius: 28)
    }

    /// Wie CardDetailView.togglePin: bei PIN-Schutz erst Face ID oder Gerätecode.
    private func togglePin(_ card: GiftCard) async {
        if showPin {
            withAnimation(.snappy) { showPin = false }
            return
        }
        guard pinLock else {
            withAnimation(.snappy) { showPin = true }
            return
        }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            withAnimation(.snappy) { showPin = true }
            return
        }
        let ok = (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "PIN von \(card.name) anzeigen")) ?? false
        if ok { withAnimation(.snappy) { showPin = true } }
    }

    private var amountValid: Bool { (parseMoney(amount) ?? 0) > 0 }

    /// „Später eintragen“: Gutschein als „Betrag offen“ markieren und nach 2 Stunden nachfragen, nie nachts.
    private func remindLater(_ card: GiftCard) async {
        store.setPending(card.id, true)
        var fire = Date.now.addingTimeInterval(2 * 3600)
        let cal = Calendar.current
        let hour = cal.component(.hour, from: fire)
        if hour >= 21 || hour < 8 {
            let base = hour >= 21 ? cal.date(byAdding: .day, value: 1, to: fire) ?? fire : fire
            fire = cal.date(bySettingHour: 9, minute: 0, second: 0, of: base) ?? fire
        }
        let content = UNMutableNotificationContent()
        content.title = "Hast du bei \(card.name) bezahlt?"
        content.body = "Trag den Betrag ein, damit dein Guthaben stimmt."
        content.sound = .default
        content.userInfo = ["card": card.id.uuidString]
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let request = UNNotificationRequest(identifier: "\(card.id.uuidString)-later", content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
        // Erinnerung nur versprechen, wenn Mitteilungen erlaubt sind.
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            status = await center.notificationSettings().authorizationStatus
        }
        var scheduled = false
        if status == .authorized || status == .provisional || status == .ephemeral {
            scheduled = (try? await center.add(request)) != nil
        }
        router.toast = Toast(message: scheduled
            ? "Als „Betrag offen“ markiert. Wir fragen später nach."
            : "Als „Betrag offen“ markiert. Mitteilungen sind aus – schau selbst in der Liste nach.", undo: nil)
    }

    private func save(_ card: GiftCard, _ ok: Bool) {
        // Rabattcodes und Coupons: kein Betrag, sondern als Ganzes einlösen.
        if ok && !card.kind.isValueBased {
            _ = store.addTest(card: card, success: true, store: storeName, note: note, amount: nil)
            store.setPending(card.id, false)
            store.markRedeemed(card.id, store: storeName)
            router.toast = Toast(message: "\(card.kind.label) als eingelöst markiert.", undo: nil)
            dismiss()
            return
        }
        let value = parseMoney(amount)
        if ok, (value ?? 0) <= 0 { return }
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

    private func actionButton(_ title: String, _ consequence: String, _ icon: String, _ style: FilledButtonStyle,
                              action: @escaping () -> Void) -> some View {
        VStack(spacing: 4) {
            Button(action: action) { Label(title, systemImage: icon) }.buttonStyle(style)
            Text(consequence).font(.scaled(13)).foregroundStyle(Color.ink2)
        }
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
    @State private var correct = false
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
        // Oberer Teil scrollt, Tastenfeld samt Bestätigung bleibt unten – auch bei großer Schrift.
        ScrollView {
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

                Picker("Modus", selection: $correct) {
                    Text("Einkauf abziehen").tag(false)
                    Text("Neuen Stand eintragen").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.top, 14)
                VStack(alignment: .leading, spacing: 6) {
                    Text(correct ? "Guthaben laut Bon oder nach Aufladung" : "Betrag eingeben").font(.scaled(15, weight: .semibold)).foregroundStyle(Color.muted)
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
                    Text(hint(card)).font(.scaled(15, weight: !correct && value > card.balance ? .semibold : .regular))
                        .foregroundStyle(!correct && value > card.balance ? Color.warn : Color.ink2)
                }
                .padding(.horizontal, 18).padding(.top, 22)

                if !correct { GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach([5.0, 10, 20].filter { $0 < card.balance }, id: \.self) { q in chip("\(Int(q)) €") { input = "\(Int(q))" } }
                        chip("Alles") { input = card.balance.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "de_DE"))).replacingOccurrences(of: ".", with: "") }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 4)
                }
                .padding(.top, 14) }

                Group {
                    if showStore {
                        LabeledField(label: "Filiale (für deinen Verlauf)", placeholder: "z. B. Thalia Köln", text: $storeName)
                    } else {
                        Button("+ Filiale notieren") { withAnimation(.snappy) { showStore = true } }
                            .font(.scaled(15, weight: .medium)).foregroundStyle(Color.ink2)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 16)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
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
                            .frame(width: 64, height: 58)
                        }
                        .buttonStyle(KeyStyle())
                        .accessibilityLabel(key == "⌫" ? "Löschen" : key)
                    }
                }
                .sensoryFeedback(.impact(weight: .light), trigger: input)
                Button {
                    // Neuer Stand darf 0 sein (Bon zeigt leer), Abzug nicht.
                    guard correct ? parseMoney(input) != nil : value > 0 else {
                        withAnimation(.linear(duration: 0.4)) { rejected += 1 }
                        return
                    }
                    if correct {
                        if let entry = store.setBalance(card.id, to: value) {
                            router.showUndo("Neuer Stand bei \(card.name): \(value.euro)") {
                                store.undoRedemption(card.id, entry: entry)
                            }
                        }
                        dismiss()
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
                    Text(correct ? (input.isEmpty ? "Neuen Stand eingeben" : "Stand auf \(value.euro) setzen")
                         : value > card.balance ? "Alles abziehen (\(card.balance.euro))"
                         : value > 0 ? "\(value.euro) abziehen" : "Erst Betrag wählen")
                }
                .buttonStyle(.accent)
                .disabled(correct ? input.isEmpty : value <= 0)
            }
            .padding(16)
            .background(Color.surface, in: UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous))
            .shadow(color: Color.ink.opacity(0.06), radius: 16, y: -4)
        }
        .sensoryFeedback(.error, trigger: rejected)
    }

    private func hint(_ card: GiftCard) -> String {
        if correct { return "Bisher: \(card.balance.euro). Die Differenz steht im Verlauf." }
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
                .foregroundStyle(configuration.isPressed ? Color.onBrand : Color.ink)
                .background(configuration.isPressed ? Color.brandYellow : Color.disabledFill, in: .circle)
                .scaleEffect(configuration.isPressed ? 0.92 : 1)
                .animation(.spring(duration: 0.2, bounce: 0.5), value: configuration.isPressed)
        }
    }
}

/// Barcode bildschirmfüllend, quer, mit Ruhezone – für schwierige Scanner.
private struct FullBarcode: View {
    let card: GiftCard
    let masked: Bool
    @State private var revealed = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let hidden = masked && !revealed
        GeometryReader { geo in
            VStack(spacing: 18) {
                BarcodeView(number: card.number, format: card.format, height: min(geo.size.width * 0.5, 220), masked: hidden)
                    .padding(.horizontal, 24)
                    .onTapGesture { if hidden { revealed = true } else { dismiss() } }
                Text(hidden ? card.number.masked : card.number.grouped)
                    .font(.system(size: 26, weight: .bold, design: .monospaced)).kerning(2)
                    .foregroundStyle(.black)
                    .onTapGesture { if hidden { revealed = true } else { dismiss() } }
            }
            // Weißer Hintergrund: Textcodes auch im Dunkelmodus dunkel zeichnen.
            .environment(\.colorScheme, .light)
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
        .onAppear {
            // Hell und wach bleiben, auch falls die Kasse darunter schon zurückgesetzt hat.
            UIApplication.shared.isIdleTimerDisabled = true
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.screen.brightness = 1
        }
    }
}
