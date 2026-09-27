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
    @State private var storeName = ""
    @State private var note = ""
    @State private var showPin = false
    @State private var oldBrightness: CGFloat?
    @State private var showFull = false
    @State private var showPhotoFull = false
    @State private var torn = false
    @State private var tearHaptic = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var numberShown = false
    @AppStorage("maskNumber") private var maskNumber = false
    @AppStorage("pinLock") private var pinLock = true

    var body: some View {
        ScrollView {
            if let card = store.card(cardID) {
                VStack(spacing: Layout.inset) {
                    ticket(card)
                    if let result {
                        // Nur noch für „Nicht angenommen“ und Rabattcodes; Beträge laufen über den Ziffernblock.
                        VStack(alignment: .leading, spacing: Layout.group) {
                            Text(!result ? "Nicht angenommen – dein Guthaben bleibt gleich." : "\(card.kind.label) wird als eingelöst markiert.")
                                .font(.scaled(17, weight: .semibold))
                            LabeledField(label: "Filiale", placeholder: "optional, z. B. Köln Hohe Straße", text: $storeName)
                            LabeledField(label: "Notiz", placeholder: result ? "optional" : "optional, z. B. Kasse wollte Plastikkarte", text: $note)
                        }
                        .padding(Layout.inset)
                        .background(Color.surface, in: .rect(cornerRadius: Layout.cardRadius, style: .continuous))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, Layout.page).padding(.bottom, Layout.section)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        // Entscheidung unten im Daumenbereich, auch wenn das Ticket hoch ist.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let card = store.card(cardID) { actions(card) }
        }
        .pageBackground()
        .toolbar(.hidden, for: .tabBar)
        .sensoryFeedback(.impact(weight: .medium), trigger: tearHaptic)
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

    @ViewBuilder
    private func actions(_ card: GiftCard) -> some View {
        VStack(spacing: 4) {
            if let result {
                Button(!result ? "Notieren" : "Als eingelöst markieren") { save(card, result) }
                    .buttonStyle(.primary)
                Button("Zurück") { withAnimation(.snappy) { self.result = nil } }
                    .font(.scaled(15, weight: .medium)).foregroundStyle(Color.ink2)
                    .frame(maxWidth: .infinity, minHeight: Layout.tap)
            } else {
                Button {
                    if card.kind.isValueBased { pay(card) } else { withAnimation(.snappy) { result = true } }
                } label: {
                    Label(card.kind.isValueBased ? "Bezahlt – Betrag eintragen" : "Eingelöst", systemImage: "checkmark")
                }
                .buttonStyle(.primary)
                // Nebeneinander, bei großer Schrift untereinander – nie abgeschnitten.
                ViewThatFits(in: .horizontal) {
                    HStack { notAccepted; Spacer(); later(card) }
                    VStack(spacing: 0) { notAccepted; later(card) }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, Layout.page).padding(.top, Layout.group).padding(.bottom, 4)
        .background(Color.page.ignoresSafeArea())
    }

    private var notAccepted: some View {
        Button("Nicht angenommen") { withAnimation(.snappy) { result = false } }
            .font(.scaled(16, weight: .semibold)).foregroundStyle(Color.ink)
            .frame(minHeight: Layout.tap)
    }

    private func later(_ card: GiftCard) -> some View {
        Button("Später eintragen") {
            Task { await remindLater(card) }
            dismiss()
        }
        .font(.scaled(15, weight: .medium)).foregroundStyle(Color.ink2)
        .frame(minHeight: Layout.tap)
    }

    /// „Bezahlt“: Abschnitt abreißen, dann direkt zum Ziffernblock – dort wird der Betrag abgezogen.
    private func pay(_ card: GiftCard) {
        tearOff {
            store.setPending(card.id, false)
            var path = router.homePath
            if case .checkout = path.last { path.removeLast() }
            path.append(.pay(card.id))
            router.homePath = path
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
                    Text(card.name).font(.scaled(20, weight: .bold))
                    Text(card.kind.isValueBased ? "Guthaben \(card.balance.euro)" : card.headline)
                        .font(.scaled(16, weight: .semibold)).foregroundStyle(Color.ink)
                }
                Spacer()
            }
            .padding(Layout.inset)
            .frame(maxWidth: .infinity)
            .background(Color.surface, in: TicketHalf(top: true))
            .overlay(alignment: .bottom) { TearLine().padding(.horizontal, Layout.inset) }
            VStack(spacing: 10) {
                if card.number.isEmpty, let data = card.photo, let image = UIImage(data: data) {
                    // Papiergutschein: das Foto vorzeigen.
                    Button { showPhotoFull = true } label: {
                        Image(uiImage: image).resizable().scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 320)
                            .clipShape(.rect(cornerRadius: Layout.buttonRadius, style: .continuous))
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
                        // Dieselbe Mono-Schrift wie im Detail; bleibt einzeilig statt „1234“ allein umzubrechen.
                        .font(.scaled(20, weight: .bold, design: .monospaced))
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .onTapGesture { numberShown = true }
                }
                Text(card.number.isEmpty ? "Tippen zum Vergrößern" : "Tippen für Vollbild").font(.scaled(12)).foregroundStyle(Color.muted)
                if !card.number.isEmpty && card.photo != nil {
                    Button("Original-Foto zeigen", systemImage: "photo") { showPhotoFull = true }
                        .font(.scaled(15, weight: .medium)).foregroundStyle(Color.ink2)
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
                    .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.large).tint(Color.ink)
                }
            }
            .padding(.horizontal, Layout.inset).padding(.top, Layout.inset).padding(.bottom, Layout.ticketInset)
            .frame(maxWidth: .infinity)
            .background(Color.surface, in: TicketHalf(top: false))
            // Abriss-Moment: Der untere Abschnitt samt Papier reißt an der Linie ab und kippt nach unten weg.
            .rotationEffect(.degrees(torn ? 9 : 0), anchor: .topLeading)
            .offset(y: torn ? 160 : 0)
            .opacity(torn ? 0 : 1)
        }
        .compositingGroup()
        .shadow(color: Color.shade, radius: 14, y: 6)
    }

    /// Erst abreißen lassen, dann speichern und zurück. Bei „Bewegung reduzieren“ sofort.
    private func tearOff(then commit: @escaping () -> Void) {
        tearHaptic += 1
        guard !reduceMotion else { commit(); return }
        withAnimation(.easeIn(duration: 0.42)) { torn = true }
        Task {
            try? await Task.sleep(for: .milliseconds(460))
            commit()
            torn = false
        }
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
            tearOff {
                _ = store.addTest(card: card, success: true, store: storeName, note: note, amount: nil)
                store.setPending(card.id, false)
                store.markRedeemed(card.id, store: storeName)
                router.toast = Toast(message: "\(card.kind.label) eingelöst. Gut genutzt.", undo: nil)
                dismiss()
            }
            return
        }
        _ = store.addTest(card: card, success: false, store: storeName, note: note, amount: nil)
        router.toast = Toast(message: "Notiert. Guthaben bleibt gleich.", undo: nil)
        dismiss()
    }
}

// MARK: - Nummernblock

struct KeypadView: View {
    let cardID: UUID
    /// Direkt von der Kasse: Abzug wird als erfolgreicher Kassentest festgehalten.
    var checkout = false
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
        .navigationTitle(store.card(cardID)?.name ?? "Einkauf")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ card: GiftCard) -> some View {
        // Oberer Teil scrollt, Tastenfeld samt Bestätigung bleibt unten – auch bei großer Schrift.
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Ein Eingabeweg: Betrag groß, darunter zwei leise Kurzwege. Kein Modus-Segment, keine Kopfkarte.
                VStack(alignment: .leading, spacing: 6) {
                    Text(correct ? "Neuer Stand laut Bon" : "\(card.balance.euro) drauf")
                        .font(.scaled(15, weight: .semibold)).foregroundStyle(Color.muted)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(input.isEmpty ? "0" : input).font(.display(64))
                            .foregroundStyle(input.isEmpty ? Color.muted : Color.ink)
                            .contentTransition(.numericText())
                        Text("€").font(.display(30)).foregroundStyle(Color.ink2)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(correct ? "Neuer Stand" : "Betrag")
                    .accessibilityValue(value.euro)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .modifier(Shake(animatableData: CGFloat(rejected)))
                    if !input.isEmpty || correct {
                        Text(hint(card)).font(.scaled(15, weight: !correct && value > card.balance ? .semibold : .regular))
                            .foregroundStyle(!correct && value > card.balance ? Color.warn : Color.ink2)
                    }
                }
                .padding(.horizontal, Layout.page).padding(.top, Layout.group)

                HStack(spacing: Layout.inset) {
                    if !correct {
                        Button("Alles (\(card.balance.euro))") {
                            input = card.balance.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "de_DE"))).replacingOccurrences(of: ".", with: "")
                        }
                        .font(.scaled(15, weight: .semibold)).foregroundStyle(Color.ink)
                        .padding(.horizontal, Layout.inset).frame(minHeight: Layout.tap)
                        .background(Color.surface, in: .capsule)
                    }
                    Button(correct ? "Doch Einkauf abziehen" : "Neuen Stand eintragen") {
                        withAnimation(.snappy) { correct.toggle(); input = "" }
                    }
                    .font(.scaled(15, weight: .medium)).foregroundStyle(Color.ink2)
                    .frame(minHeight: Layout.tap)
                }
                .padding(.horizontal, Layout.page).padding(.top, Layout.group)

                Group {
                    if showStore {
                        LabeledField(label: "Filiale (für deinen Verlauf)", placeholder: "z. B. Thalia Köln", text: $storeName)
                    } else {
                        Button("+ Filiale notieren") { withAnimation(.snappy) { showStore = true } }
                            .font(.scaled(15, weight: .medium)).foregroundStyle(Color.ink2)
                    }
                }
                .padding(.horizontal, Layout.page).padding(.top, Layout.group).padding(.bottom, Layout.inset)
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
                                    Text(key).font(.system(size: 28, weight: .medium, design: .rounded))
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 56)
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
                        AccessibilityNotification.Announcement(correct ? "Erst den neuen Stand eingeben." : "Erst einen Betrag eingeben.").post()
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
                    let entry = checkout
                        ? store.addTest(card: card, success: true, store: storeName, note: "", amount: taken)
                        : store.redeem(card.id, amount: taken, store: storeName)
                    if let entry {
                        let rest = max(0, card.balance - taken)
                        router.showUndo(rest <= 0 ? "Aufgebraucht. Gut genutzt." : "\(taken.euro) abgezogen · noch \(rest.euro) drauf") {
                            store.undoRedemption(card.id, entry: entry)
                        }
                    }
                    dismiss()
                } label: {
                    Text(correct ? (input.isEmpty ? "Neuen Stand eingeben" : "Stand auf \(value.euro) setzen")
                         : value > card.balance ? "Alles abziehen (\(card.balance.euro))"
                         : value > 0 ? "\(value.euro) abziehen" : "Abziehen")
                }
                .buttonStyle(.primary)
                .disabled(correct ? input.isEmpty : value <= 0)
            }
            .padding(Layout.inset)
            .background(Color.surface, in: UnevenRoundedRectangle(topLeadingRadius: Layout.cardRadius, topTrailingRadius: Layout.cardRadius, style: .continuous))
            .shadow(color: Color.shade, radius: 16, y: -4)
        }
        .sensoryFeedback(.error, trigger: rejected)
    }

    private func hint(_ card: GiftCard) -> String {
        if correct { return "Bisher: \(card.balance.euro). Die Differenz steht im Verlauf." }
        if value > card.balance {
            return "Nur \(card.balance.euro) auf der Karte. \((value - card.balance).euro) zahlst du an der Kasse anders."
        }
        if value > 0 { return "Danach noch \(max(0, card.balance - value).euro) drauf" }
        return "Wird vom Guthaben abgezogen"
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
                // Flache Tasten wie ein Zahlenfeld, nicht wie die Telefon-App: nur beim Drücken eine Fläche.
                .foregroundStyle(Color.ink)
                .background(configuration.isPressed ? Color.fill : Color.clear, in: .rect(cornerRadius: Layout.controlRadius, style: .continuous))
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
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
