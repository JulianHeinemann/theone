import SwiftUI
import UIKit
import LocalAuthentication
import UserNotifications
import UniformTypeIdentifiers
import RestwertKit

/// An der Kasse: großer Barcode bei voller Helligkeit, danach Ergebnis festhalten.
/// Online-Codes (Amazon, Spotify …) bekommen stattdessen „Code kopieren & einlösen“.
struct CheckoutView: View {
    let cardID: UUID
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var result: Bool?
    @State private var storeName = ""
    @State private var note = ""
    @State private var showPin = false
    @State private var confirmUnprotectedPin = false
    @State private var oldBrightness: CGFloat?
    @State private var showFull = false
    @State private var showPhotoFull = false
    @State private var torn = false
    /// Sperre während des Abrisses: kein zweiter Tipp, kein zweiter Ziffernblock.
    @State private var busy = false
    @State private var tearHaptic = 0
    @State private var copied = 0
    /// Foto einmal im Hintergrund dekodiert, nicht bei jedem Neuzeichnen.
    @State private var photoImage: UIImage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var numberShown = false
    @AppStorage("maskNumber") private var maskNumber = false
    @Environment(\.dynamicTypeSize) private var checkoutTypeSize
    /// „Codes erst nach Face ID zeigen“: verdeckt wie „Code verdecken“, Aufdecken nur nach Face ID oder Code.
    @AppStorage("codeLock") private var codeLockSetting = false
    /// Nur wirksam mit Gerätecode; sonst stünde der Code hinter einer Abfrage, die nie gelingen kann.
    private var codeLock: Bool { codeLockSetting && DeviceSecurity.status != .noPasscode }
    private var codeHidden: Bool { (maskNumber || codeLock) && !numberShown }

    private func revealCode(_ card: GiftCard) {
        guard codeLock else { numberShown = true; return }
        Task { if await DeviceSecurity.revealCode(of: card.name, spoken: card.number) { numberShown = true } }
    }
    @AppStorage("pinLock") private var pinLock = true

    /// Nur-online-Gutschein mit Code: kein Kassenablauf, sondern kopieren und im Shop einlösen.
    private func isOnline(_ card: GiftCard) -> Bool {
        card.merchant.category == .codeOnly && !card.number.isEmpty
    }

    private var online: Bool { store.card(cardID).map(isOnline) ?? false }

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
                            if !isOnline(card) {
                                LabeledField(label: "Filiale", placeholder: "optional, z.\u{00A0}B. Köln Hohe Straße", text: $storeName)
                            }
                            LabeledField(label: "Notiz", placeholder: result ? "optional" : "optional, z.\u{00A0}B. Kasse wollte Plastikkarte", text: $note)
                        }
                        .padding(Layout.inset)
                        .background(Color.surface, in: .rect(cornerRadius: Layout.cardRadius, style: .continuous))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, Layout.page).padding(.bottom, Layout.section)
            }
        }
        // Bei großer Schrift ist die Leiste unten hoch: extra Luft, damit „PIN anzeigen“ ganz darüber passt.
        .contentMargins(.bottom, Layout.section, for: .scrollContent)
        // Zeigt beim Öffnen kurz, dass unter der Leiste noch mehr kommt.
        .scrollIndicatorsFlash(onAppear: true)
        .scrollDismissesKeyboard(.interactively)
        // Entscheidung unten im Daumenbereich, auch wenn das Ticket hoch ist.
        .safeAreaInset(edge: .bottom, spacing: Layout.group) {
            if let card = store.card(cardID) { actions(card) }
        }
        .pageBackground()
        .toolbar(.hidden, for: .tabBar)
        .sensoryFeedback(.impact(weight: .medium), trigger: tearHaptic)
        .sensoryFeedback(.success, trigger: copied)
        .unprotectedPinConfirmation(isPresented: $confirmUnprotectedPin) { withAnimation(.snappy) { showPin = true } }
        .navigationTitle(online ? "Online einlösen" : "An der Kasse")
        .fullScreenCover(isPresented: $showFull) {
            if let card = store.card(cardID) { FullBarcode(card: card, masked: codeHidden) }
        }
        .fullScreenCover(isPresented: $showPhotoFull) {
            if let photoImage { PhotoViewer(image: photoImage) }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task(id: store.card(cardID)?.photo?.count) { await decodePhoto() }
        .onAppear {
            busy = false
            // Online-Codes werden nicht gescannt: Helligkeit bleibt, wie sie ist.
            guard !online else { return }
            UIApplication.shared.isIdleTimerDisabled = true
            if let screen = currentScreen {
                // Nur einmal merken: nach dem Vollbild läuft onAppear erneut, dann steht die Helligkeit schon auf 1.
                if oldBrightness == nil { oldBrightness = screen.brightness }
                screen.brightness = 1
            }
        }
        // fullScreenCover löst onDisappear der darunterliegenden View aus – dort muss es hell bleiben.
        .onDisappear {
            if !showFull && !showPhotoFull { restoreScreen() }
            // Erst jetzt, wo die Kasse nicht mehr zu sehen ist, das abgerissene Ticket wieder zusammensetzen.
            if torn {
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { torn = false }
            }
        }
        // Beim Wechsel in eine andere App Helligkeit und Displaysperre sofort zurückgeben.
        .onChange(of: scenePhase) { _, phase in
            // Mit Code-Schutz beim Verlassen wieder verdecken.
            if phase != .active && codeLock {
                numberShown = false
                showPin = false
                // Vollbild von Barcode und Foto schließen, sonst läge der Code nach der Rückkehr offen.
                showFull = false
                showPhotoFull = false
            }
            guard !online else { return }
            if phase == .active {
                UIApplication.shared.isIdleTimerDisabled = true
                currentScreen?.brightness = 1
            } else {
                restoreScreen()
            }
        }
    }

    @ViewBuilder
    private func pinButton(_ card: GiftCard) -> some View {
        Button { Task { await togglePin(card) } } label: {
            Label(showPin ? "PIN \(card.pin)" : "PIN anzeigen", systemImage: showPin ? "lock.open" : pinLock ? (DeviceSecurity.methodName == "Touch ID" ? "touchid" : "faceid") : "eye")
                .font(.scaled(15, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.large).tint(Color.ink)
        .frame(minHeight: Layout.tap)
    }

    private func actions(_ card: GiftCard) -> some View {
        VStack(spacing: 4) {
            if result == nil && !card.pin.isEmpty && checkoutTypeSize.isAccessibilitySize { pinButton(card) }
            if let result {
                Button(!result ? "Notieren" : "Als eingelöst markieren") { save(card, result) }
                    .buttonStyle(.primary)
                    .disabled(busy)
                Button("Zurück") { withAnimation(.snappy) { self.result = nil } }
                    .font(.scaled(15, weight: .medium)).foregroundStyle(Color.ink2)
                    .frame(maxWidth: .infinity, minHeight: Layout.tap)
                    .disabled(busy)
            } else {
                Button {
                    if card.kind.isValueBased {
                        pay(card)
                    } else if isOnline(card) {
                        save(card, true)
                    } else {
                        withAnimation(.snappy) { result = true }
                    }
                } label: {
                    Label(primaryTitle(card), systemImage: "checkmark")
                }
                .buttonStyle(.primary)
                .disabled(busy)
                // Nebeneinander, bei großer Schrift untereinander – nie abgeschnitten.
                ViewThatFits(in: .horizontal) {
                    HStack { notAccepted(card); Spacer(); later(card) }
                    VStack(spacing: 8) { notAccepted(card); later(card) }
                }
                .padding(.horizontal, 4)
                .disabled(busy)
            }
        }
        .padding(.horizontal, Layout.page).padding(.top, Layout.group).padding(.bottom, 4)
        .background(Color.page.ignoresSafeArea())
    }

    private func primaryTitle(_ card: GiftCard) -> String {
        if isOnline(card) { return card.kind.isValueBased ? "Eingelöst? Einkauf abziehen" : "Als eingelöst markieren" }
        return card.kind.isValueBased ? "Bezahlt – Einkauf abziehen" : "Eingelöst"
    }

    private func notAccepted(_ card: GiftCard) -> some View {
        Button(isOnline(card) ? "Hat nicht geklappt" : "Nicht angenommen") { withAnimation(.snappy) { result = false } }
            .font(.scaled(16, weight: .semibold)).foregroundStyle(Color.ink)
            .buttonStyle(.bordered).buttonBorderShape(.capsule).tint(Color.ink)
            .frame(minHeight: Layout.tap)
    }

    private func later(_ card: GiftCard) -> some View {
        Button("Später eintragen") {
            Task { await remindLater(card) }
            dismiss()
        }
        .font(.scaled(15, weight: .medium)).foregroundStyle(Color.ink2)
        .buttonStyle(.bordered).buttonBorderShape(.capsule).tint(Color.ink2)
        .frame(minHeight: Layout.tap)
    }

    /// „Bezahlt“: Abschnitt abreißen, dann den Ziffernblock auf die Kasse schieben.
    /// „Betrag offen“ bleibt stehen, bis dort ein Betrag gespeichert ist; „Zurück“ führt wieder zum Barcode.
    private func pay(_ card: GiftCard) {
        tearOff {
            if router.historyPath.last == .checkout(cardID) && router.homePath.last != .checkout(cardID) {
                router.historyPath.append(.pay(card.id))
            } else {
                router.homePath.append(.pay(card.id))
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

    private func decodePhoto() async {
        guard let data = store.card(cardID)?.photo else { photoImage = nil; return }
        // Dekodieren außerhalb des Hauptthreads; preparingForDisplay entpackt das Bild vollständig.
        let image = await Task.detached(priority: .userInitiated) {
            UIImage(data: data).map { $0.preparingForDisplay() ?? $0 }
        }.value
        photoImage = image
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
                if isOnline(card) {
                    onlineCode(card)
                } else if card.number.isEmpty, card.photo != nil {
                    paper(card)
                } else {
                    let textOnly = card.format == .text
                    let hidden = codeHidden
                    // Textcode verdeckt: erster Tipp deckt auf, erst der zweite öffnet das Vollbild.
                    // Mit Code-Schutz auch den Barcode erst nach Face ID groß zeigen.
                    Button { if hidden && (textOnly || codeLock) { revealCode(card) } else { showFull = true } } label: {
                        BarcodeView(number: card.number, format: card.format, height: 150, masked: hidden, concealed: hidden && codeLock)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(hidden && (textOnly || codeLock) ? "Geschützt. Tippen und entsperren" : "Barcode groß anzeigen")
                    if !textOnly && !(codeLock && hidden) {
                        Text(hidden ? card.number.masked : card.number.grouped)
                            // Dieselbe Mono-Schrift wie im Detail; bleibt einzeilig statt „1234“ allein umzubrechen.
                            .font(.scaled(20, weight: .bold, design: .monospaced))
                            .lineLimit(1).minimumScaleFactor(0.5)
                            .onTapGesture { revealCode(card) }
                    }
                    // Geschützt: nur ein Weg (auf den Code tippen), kein „Vollbild“-Versprechen vor dem Entsperren.
                    if !(codeLock && hidden) { Text("Tippen für Vollbild").font(.scaled(12)).foregroundStyle(Color.muted) }
                    if card.photo != nil {
                        Button("Original-Foto zeigen", systemImage: "photo") {
                            // Auf dem Foto steht der Code: bei Code-Schutz erst entsperren.
                            if codeLock && !numberShown {
                                Task { if await DeviceSecurity.revealCode(of: card.name, spoken: card.number) { numberShown = true; showPhotoFull = true } }
                            } else { showPhotoFull = true }
                        }
                            .font(.scaled(15, weight: .medium)).foregroundStyle(Color.ink2)
                            .frame(minHeight: Layout.tap)
                            .disabled(photoImage == nil)
                    }
                    // Vor dem Entsperren nichts versprechen, was noch nicht zu sehen ist.
                    if !(codeLock && hidden) {
                        Label("Helligkeit automatisch erhöht", systemImage: "checkmark.circle")
                            .font(.scaled(13)).foregroundStyle(Color.ink2)
                    }
                }
                // PIN direkt unter dem Code. Bei sehr großer Schrift steht sie stattdessen in der Leiste unten,
                // sonst läge sie unter der Leiste.
                if !card.pin.isEmpty && !checkoutTypeSize.isAccessibilitySize { pinButton(card) }
                if card.merchantID != Merchant.other.id {
                    Text(card.merchant.tip)
                        .font(.scaled(13)).foregroundStyle(Color.muted)
                        .multilineTextAlignment(.center)
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

    /// Papiergutschein: Restbetrag groß über dem Foto, damit man ihn an der Kasse nennen kann.
    @ViewBuilder
    private func paper(_ card: GiftCard) -> some View {
        if card.kind.isValueBased {
            VStack(spacing: 2) {
                Text("Noch drauf").font(.scaled(13, weight: .semibold)).foregroundStyle(Color.muted)
                AmountText(value: card.balance, size: 44).foregroundStyle(Color.ink)
            }
            .accessibilityElement(children: .combine)
        }
        let concealed = codeLock && !numberShown
        Button { if concealed { revealCode(card) } else { showPhotoFull = true } } label: {
            Group {
                if concealed {
                    // Auf dem Foto steht der Code: bei Code-Schutz verdeckt.
                    BarcodeView(number: card.number, format: .text, height: 150, concealed: true)
                } else if let photoImage {
                    Image(uiImage: photoImage).resizable().scaledToFit()
                } else {
                    Color.fill.aspectRatio(1.6, contentMode: .fit).overlay(ProgressView())
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 320)
            .clipShape(.rect(cornerRadius: Layout.buttonRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(photoImage == nil)
        .accessibilityLabel(concealed ? "Geschützt. Tippen und entsperren" : "Foto des Gutscheins groß anzeigen")
        if !concealed { Text("Tippen zum Vergrößern").font(.scaled(12)).foregroundStyle(Color.muted) }
        Label("Manche Läden wollen das Original sehen – nimm es sicherheitshalber mit.", systemImage: "doc.text")
            .font(.scaled(13)).foregroundStyle(Color.ink2)
            .multilineTextAlignment(.center)
    }

    /// Online-Code: groß zeigen, kopieren, im Shop einlösen.
    @ViewBuilder
    private func onlineCode(_ card: GiftCard) -> some View {
        let hidden = codeHidden
        Text("Code").font(.scaled(13, weight: .semibold)).foregroundStyle(Color.muted)
        Group {
            if hidden {
                Button { revealCode(card) } label: { Text(card.number.masked) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Geschützt. Tippen und entsperren")
            } else {
                Text(card.number).textSelection(.enabled)
            }
        }
        .font(.scaled(28, weight: .heavy, design: .monospaced))
        .foregroundStyle(Color.ink)
        .multilineTextAlignment(.center)
        .minimumScaleFactor(0.6)
        .frame(maxWidth: .infinity, minHeight: Layout.tap)
        .padding(.vertical, 8)
        .background(Color.fill, in: .rect(cornerRadius: Layout.controlRadius, style: .continuous))
        Button {
            // Verdeckter Code: erst entsperren, dann kopieren.
            if codeLock && !numberShown {
                Task { if await DeviceSecurity.revealCode(of: card.name, spoken: card.number) { numberShown = true; copy(card.number) } }
            } else {
                copy(card.number)
            }
        } label: {
            Label(copied > 0 ? "Kopiert" : "Code kopieren", systemImage: copied > 0 ? "checkmark" : "doc.on.doc")
                .font(.scaled(16, weight: .semibold))
                .foregroundStyle(Color.onInk)
                .frame(maxWidth: .infinity, minHeight: Layout.tap)
        }
        .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.large).tint(Color.ink)
        .accessibilityHint("Legt den Code für 10 Minuten nur auf diesem iPhone in die Zwischenablage. Nie am Telefon oder per Nachricht weitergeben.")
        Text("Bleibt 10 Minuten nur auf diesem iPhone in der Zwischenablage.")
            .font(.scaled(12)).foregroundStyle(Color.muted)
        if copied > 0 {
            Label("Kopiert. Nur im Shop einfügen, nie am Telefon oder per Nachricht weitergeben.", systemImage: "exclamationmark.shield")
                .font(.scaled(13)).foregroundStyle(Color.ink2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let link = Self.redeemLinks[card.merchantID], let url = URL(string: link.url) {
            Link(destination: url) {
                Label(link.label, systemImage: "arrow.up.right.square")
                    .font(.scaled(15, weight: .medium)).foregroundStyle(Color.ink2)
                    .frame(minHeight: Layout.tap)
            }
        }
        Text("Gib den Code auf der Website des Ladens oder in deinem Kundenkonto ein. Danach ziehst du hier den Einkauf ab.")
            .font(.scaled(13)).foregroundStyle(Color.ink2)
            .multilineTextAlignment(.center)
    }

    /// Wo man den Code eingibt – nicht `balanceURL`, die führt meist zu Guthaben-, Konto- oder FAQ-Seiten.
    /// Ohne eigene Einlöseseite (Code im Warenkorb) führt der Link zum Shop. Unbekannt: kein Link.
    private static let redeemLinks: [String: (label: String, url: String)] = [
        "amazon": ("Bei Amazon einlösen", "https://www.amazon.de/gc/redeem"),
        "apple": ("Im App Store einlösen", "https://apps.apple.com/redeem"),
        "googleplay": ("Bei Google Play einlösen", "https://play.google.com/redeem"),
        "spotify": ("Bei Spotify einlösen", "https://www.spotify.com/de/redeem/"),
        "netflix": ("Bei Netflix einlösen", "https://www.netflix.com/redeem"),
        "wunschgutschein": ("Bei Wunschgutschein einlösen", "https://app.wunschgutschein.de/"),
        "zalando": ("Zalando-Shop öffnen", "https://www.zalando.de/"),
        "otto": ("Otto-Shop öffnen", "https://www.otto.de/"),
        "db": ("bahn.de öffnen", "https://www.bahn.de/"),
        "lieferando": ("Lieferando öffnen", "https://www.lieferando.de/"),
        "eventim": ("Eventim öffnen", "https://www.eventim.de/"),
        "ticketmaster": ("Ticketmaster öffnen", "https://www.ticketmaster.de/"),
    ]

    private func copy(_ code: String) {
        // Nicht dauerhaft in der Zwischenablage liegen lassen.
        UIPasteboard.general.setItems([[UTType.plainText.identifier: code]],
                                      options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(600)])
        copied += 1
        AccessibilityNotification.Announcement("Code kopiert").post()
    }

    /// Erst abreißen lassen, dann weiter. Bei „Bewegung reduzieren“ sofort.
    /// Zurückgesetzt wird erst in onDisappear – so springt die Hälfte nie sichtbar zurück.
    private func tearOff(then commit: @escaping () -> Void) {
        guard !busy else { return }
        busy = true
        tearHaptic += 1
        guard !reduceMotion else { commit(); return }
        withAnimation(.easeIn(duration: 0.42)) { torn = true }
        Task {
            try? await Task.sleep(for: .milliseconds(460))
            commit()
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
        // Schon mit Code-Schutz entsperrt: ein Entsperren reicht für Code und PIN.
        if codeLock && numberShown { withAnimation(.snappy) { showPin = true }; return }
        guard DeviceSecurity.canAuthenticate else {
            confirmUnprotectedPin = true
            return
        }
        if await DeviceSecurity.guardSensitive("PIN von \(card.name) anzeigen") { withAnimation(.snappy) { showPin = true } }
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
        content.body = "Zieh den Einkauf ab, damit dein Guthaben stimmt."
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
                // addTest stempelt und beendet „Betrag offen“; der Eintrag merkt den Stand davor fürs „Rückgängig“.
                let message = "\(card.kind.label) eingelöst. Gut genutzt."
                if let entry = store.addTest(card: card, success: true, store: storeName, note: note, amount: nil) {
                    let id = card.id
                    router.showUndo(message) { store.undoRedemption(id, entry: entry) }
                } else {
                    router.toast = Toast(message: message, undo: nil)
                }
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
    /// Karte auf 0 gebracht: kleines Belohnungs-Sheet, danach erst zurück.
    @State private var usedUp: UsedUp?
    /// `sheet(item:)` setzt das Item vor onDismiss auf nil – daher hier gemerkt.
    @State private var lastUsedUp: UsedUp?
    /// Ziffern wachsen mit der Schrift, aber gedeckelt, damit das Feld auf den Bildschirm passt.
    @ScaledMetric(relativeTo: .title) private var keyFont: CGFloat = 28
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Sperre gegen Doppeltipp: ab dem ersten Bestätigen wird nichts mehr gebucht.
    @State private var saving = false
    @State private var panelHeight: CGFloat = 0
    @State private var screenHeight: CGFloat = .infinity

    private var value: Double { parseMoney(input.isEmpty ? "0" : input) ?? 0 }
    private var digitSize: CGFloat { min(keyFont, 40) }

    var body: some View {
        Group {
            if let card = store.card(cardID) { content(card) }
        }
        // Höhe ohne Tastatur messen: Beim Tippen der Filiale darf das Layout nicht umspringen (Fokus bliebe weg).
        .background {
            Color.clear.ignoresSafeArea(.keyboard)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { screenHeight = $0 }
        }
        .pageBackground()
        .toolbar(.hidden, for: .tabBar)
        .navigationTitle(store.card(cardID)?.name ?? "Einkauf")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $usedUp, onDismiss: finishUsedUp) { UsedUpSheet(info: $0) }
    }

    @ViewBuilder
    private func content(_ card: GiftCard) -> some View {
        // Sehr große Schrift oder kleiner Bildschirm: Das feste Tastenfeld ließe für den Betrag
        // keinen Platz – dann scrollt alles gemeinsam, der Betrag steht oben.
        if typeSize.isAccessibilitySize || (panelHeight > 0 && screenHeight - panelHeight < 170) {
            ScrollView {
                VStack(spacing: 0) {
                    top(card)
                    panel(card)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .sensoryFeedback(.error, trigger: rejected)
        } else {
            // Oberer Teil scrollt, Kurzwege, Tastenfeld und Bestätigung bleiben unten im Daumenbereich.
            ScrollView { top(card) }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom, spacing: 0) { panel(card) }
                .sensoryFeedback(.error, trigger: rejected)
        }
    }

    private func top(_ card: GiftCard) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(correct ? "Neuer Stand laut Bon" : "\(card.balance.euro) drauf")
                .font(.scaled(15, weight: .semibold)).foregroundStyle(Color.muted)
            amountDisplay
                .modifier(Shake(animatableData: CGFloat(rejected)))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(correct ? "Neuer Stand" : "Betrag")
                .accessibilityValue(value.euro)
                .accessibilityAddTraits(.updatesFrequently)
            if !input.isEmpty || correct {
                Text(hint(card)).font(.scaled(15, weight: !correct && value > card.balance ? .semibold : .regular))
                    .foregroundStyle(!correct && value > card.balance ? Color.warn : Color.ink2)
            }
            Group {
                if showStore {
                    LabeledField(label: "Filiale (für deinen Verlauf)", placeholder: "z.\u{00A0}B. Thalia Köln", text: $storeName)
                } else {
                    Button("+ Filiale notieren") { withAnimation(.snappy) { showStore = true } }
                        .font(.scaled(15, weight: .medium)).foregroundStyle(Color.ink2)
                        .frame(minHeight: Layout.tap)
                }
            }
            .padding(.top, Layout.group)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Layout.page).padding(.top, Layout.group).padding(.bottom, Layout.inset)
    }

    /// Kurzwege, Tasten und Bestätigung auf einer Fläche. Nach dem ersten Bestätigen gesperrt.
    private func panel(_ card: GiftCard) -> some View {
        VStack(spacing: Layout.group) {
            shortcuts(card)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", ",", "0", "⌫"], id: \.self) { key in
                    Button { press(key) } label: {
                        Group {
                            if key == "⌫" {
                                Image(systemName: "delete.left").font(.system(size: digitSize * 0.8, weight: .semibold))
                            } else {
                                Text(key).font(.system(size: digitSize, weight: .medium, design: .rounded))
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: min(digitSize + 28, 64))
                    }
                    .buttonStyle(KeyStyle())
                    .accessibilityLabel(key == "⌫" ? "Löschen" : key == "," ? "Komma" : key)
                }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: input)
            Button { confirm(card) } label: {
                Text(correct ? (input.isEmpty ? "Neuen Stand eintragen" : "\(value.euro) eintragen")
                     : value > card.balance ? "Alles abziehen (\(card.balance.euro))"
                     : value > 0 ? "\(value.euro) abziehen" : "Abziehen")
            }
            .buttonStyle(.primary)
            .disabled(saving || (correct ? input.isEmpty : value <= 0))
        }
        .disabled(saving)
        .padding(Layout.inset)
        .background(Color.surface, in: UnevenRoundedRectangle(topLeadingRadius: Layout.cardRadius, topTrailingRadius: Layout.cardRadius, style: .continuous))
        // Ein Schatten für die ganze Fläche, nicht einer je Taste.
        .ticketShadow(radius: Shadow.float, y: -4)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { panelHeight = $0 }
    }

    /// Betrag wie ein Preisschild: große Euro, kleine hochgestellte Cent. Noch nicht getippte Cent stehen blass da.
    private var amountDisplay: some View {
        let size: CGFloat = 64
        let parts = input.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let euros = parts.first.flatMap { $0.isEmpty ? nil : $0 } ?? "0"
        let cents = parts.count > 1 ? parts[1] : ""
        let open = String(repeating: "0", count: max(0, 2 - cents.count))
        let small = Font.display(size * 0.46)
        return Text("""
            \(Text("\(euros),").font(.display(size)).kerning(-size * 0.02).foregroundStyle(input.isEmpty ? Color.muted : Color.ink))\
            \(Text(cents).font(small).baselineOffset(size * 0.40).foregroundStyle(Color.ink))\
            \(Text(open).font(small).baselineOffset(size * 0.40).foregroundStyle(Color.muted))\
            \(Text(" €").font(small).baselineOffset(size * 0.40).foregroundStyle(Color.ink2))
            """)
            .lineLimit(1).minimumScaleFactor(0.5)
            .contentTransition(.numericText(value: value))
            .animation(.snappy(duration: 0.2), value: input)
    }

    /// Zwei gleichwertige Kurzwege direkt über den Tasten.
    @ViewBuilder
    private func shortcuts(_ card: GiftCard) -> some View {
        let all = Button("Alles (\(card.balance.euro))") {
            input = card.balance.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "de_DE"))).replacingOccurrences(of: ".", with: "")
            announce()
        }
        let mode = Button(correct ? "Einkauf abziehen" : "Neuen Stand eintragen") {
            withAnimation(.snappy) { correct.toggle(); input = "" }
        }
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                if !correct { all.buttonStyle(ShortcutStyle()) }
                mode.buttonStyle(ShortcutStyle())
            }
            VStack(spacing: 8) {
                if !correct { all.buttonStyle(ShortcutStyle()) }
                mode.buttonStyle(ShortcutStyle())
            }
        }
    }

    private func confirm(_ rendered: GiftCard) {
        // Zweiter Tipp während Speichern, Sheet oder Zurück-Animation: nichts buchen.
        guard !saving else { return }
        // Frischer Stand statt des zuletzt gezeichneten.
        let card = store.card(rendered.id) ?? rendered
        // Neuer Stand darf 0 sein (Bon zeigt leer), Abzug nicht.
        guard correct ? parseMoney(input) != nil : value > 0 else {
            withAnimation(.linear(duration: 0.4)) { rejected += 1 }
            AccessibilityNotification.Announcement(correct ? "Erst den neuen Stand eintragen." : "Erst einen Betrag eingeben.").post()
            return
        }
        saving = true
        // „Betrag offen“ endet erst hier: redeem, setBalance und addTest setzen pendingSince zurück
        // und merken den alten Zustand, damit „Rückgängig“ ihn wiederherstellt.
        let entry: UUID?
        let message: String
        if correct {
            entry = store.setBalance(card.id, to: value)
            message = "Neuer Stand bei \(card.name): \(value.euro)"
        } else {
            // Mehr als auf der Karte: Karte leeren, den Rest zahlt man an der Kasse anders.
            let taken = min(value, card.balance)
            entry = checkout
                ? store.addTest(card: card, success: true, store: storeName, note: "", amount: taken)
                : store.redeem(card.id, amount: taken, store: storeName)
            let rest = max(0, card.balance - taken)
            message = rest <= 0 ? "Aufgebraucht. Gut genutzt." : "\(taken.euro) abgezogen · noch \(rest.euro) drauf"
        }
        if card.balance > 0, let after = store.card(card.id), after.kind.isValueBased, after.balance <= 0 {
            // Belohnung zuerst, „Rückgängig“ danach – sonst läge der Hinweis unter dem Sheet.
            let info = UsedUp(name: card.name, amount: max(after.value, card.balance), entry: entry, message: message)
            lastUsedUp = info
            usedUp = info
            return
        }
        if let entry {
            router.showUndo(message) { store.undoRedemption(card.id, entry: entry) }
        }
        leave()
    }

    private func finishUsedUp() {
        guard let info = lastUsedUp else { leave(); return }
        lastUsedUp = nil
        if let entry = info.entry {
            let id = cardID
            router.showUndo(info.message) { store.undoRedemption(id, entry: entry) }
        }
        leave()
    }

    /// Nach dem Speichern: von der Kasse aus Ziffernblock und Kasse vom Stapel nehmen, sonst nur zurück.
    private func leave() {
        guard checkout else { dismiss(); return }
        func trimmed(_ path: [Route]) -> [Route] {
            var p = path
            if p.last == .pay(cardID) { p.removeLast() } else { return path }
            if p.last == .checkout(cardID) { p.removeLast() }
            return p
        }
        if router.homePath.last == .pay(cardID) {
            router.homePath = trimmed(router.homePath)
        } else if router.historyPath.last == .pay(cardID) {
            router.historyPath = trimmed(router.historyPath)
        } else {
            dismiss()
        }
    }

    private func hint(_ card: GiftCard) -> String {
        if correct { return "Bisher: \(card.balance.euro). Die Differenz steht im Verlauf." }
        if value > card.balance {
            return "Nur \(card.balance.euro) auf dem Gutschein. \((value - card.balance).euro) zahlst du an der Kasse anders."
        }
        if value > 0 { return "Danach noch \(max(0, card.balance - value).euro) drauf" }
        return "Wird vom Guthaben abgezogen"
    }

    private func press(_ key: String) {
        let before = input
        switch key {
        case "⌫":
            if !input.isEmpty { input.removeLast() }
        case ",":
            if !input.contains(",") { input = (input.isEmpty ? "0" : input) + "," }
        default:
            if let comma = input.firstIndex(of: ","), input.distance(from: comma, to: input.endIndex) > 2 { break }
            if input == "0" { input = "" }
            if input.count < 7 { input += key }
        }
        if input != before { announce() }
    }

    /// VoiceOver sagt nach jeder Taste den neuen Betrag.
    private func announce() {
        AccessibilityNotification.Announcement(input.isEmpty ? "Null Euro" : value.euro).post()
    }

    private struct KeyStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                // Ruhefläche sichtbar (auch im Dunkeln), beim Drücken eine Stufe kräftiger.
                .foregroundStyle(Color.ink)
                .background(configuration.isPressed ? Color.line : Color.fill, in: .rect(cornerRadius: Layout.controlRadius, style: .continuous))
                // Feiner Rand: im Hellen hebt sich die Taste sonst kaum von der weißen Fläche ab.
                .overlay(RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous).strokeBorder(Color.line))
                .contentShape(.rect)
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .animation(.spring(duration: 0.2, bounce: 0.5), value: configuration.isPressed)
        }
    }

    /// Kurzweg-Knopf: leise Fläche, gleich breit, mindestens 44 pt hoch.
    private struct ShortcutStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.scaled(15, weight: .semibold)).foregroundStyle(Color.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Layout.group).padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: Layout.tap)
                .background(configuration.isPressed ? Color.line : Color.fill, in: .capsule)
                .contentShape(.capsule)
        }
    }
}

// MARK: - Belohnung

struct UsedUp: Identifiable {
    let id = UUID()
    let name: String
    let amount: Double
    let entry: UUID?
    let message: String
}

/// Karte aufgebraucht: großer Stempel, eingelöste Summe und ein teilbares Bild ohne Code und PIN.
private struct UsedUpSheet: View {
    let info: UsedUp
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shareImage: Image?
    @State private var cheer = 0

    var body: some View {
        ScrollView {
            VStack(spacing: Layout.section) {
                // Kein scaleEffect: der ändert das Layout nicht, der Stempel ragte über den Rand.
                // Stattdessen gedeckelte Schriftgröße, damit er samt Drehung in die Breite passt.
                UsedUpStamp()
                    .fixedSize()
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .padding(.vertical, Layout.section)
                VStack(spacing: 6) {
                    Text("Gut genutzt: \(info.amount.euro) eingelöst")
                        .font(.scaled(22, weight: .bold))
                        .multilineTextAlignment(.center)
                    Text(info.name).font(.scaled(16, weight: .semibold)).foregroundStyle(Color.muted)
                }
                .accessibilityElement(children: .combine)
                VStack(spacing: Layout.group) {
                    if let shareImage {
                        ShareLink(item: shareImage, preview: SharePreview("Gut genutzt bei \(info.name)", image: shareImage)) {
                            Label("Teilen", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.quiet)
                    }
                    Button("Fertig") { dismiss() }
                        .buttonStyle(.primary)
                }
            }
            .padding(.horizontal, Layout.page).padding(.top, Layout.section)
            .frame(maxWidth: .infinity)
        }
        .background(Color.page.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .sensoryFeedback(.success, trigger: cheer)
        .onAppear {
            if !reduceMotion { cheer += 1 }
            AccessibilityNotification.Announcement("Aufgebraucht. Gut genutzt: \(info.amount.euro) eingelöst.").post()
            renderShareImage()
        }
    }

    private func renderShareImage() {
        let renderer = ImageRenderer(content: ShareCard(name: info.name, amount: info.amount))
        renderer.scale = 3
        if let ui = renderer.uiImage { shareImage = Image(uiImage: ui) }
    }
}

/// Das geteilte Bild: Wortmarke, Laden, Betrag, Stempel – bewusst ohne Code und PIN. Immer hell gerendert.
private struct ShareCard: View {
    let name: String
    let amount: Double

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.group) {
            Wordmark(size: 26)
            DashedRule()
            Text(name).font(.system(size: 22, weight: .bold))
            Text("Gut genutzt – eingelöst:").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.muted)
            // Betrag und Stempel untereinander: nebeneinander wäre es breiter als die Karte.
            AmountText(value: amount, size: 56)
                .lineLimit(1).minimumScaleFactor(0.6)
            // Stempel ohne Einblend-Animation: ImageRenderer ruft kein onAppear auf.
            Text("AUFGEBRAUCHT")
                .font(.system(size: 17, weight: .heavy, design: .rounded)).kerning(2.5)
                .fixedSize()
                .foregroundStyle(Color.onBrand)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .overlay(RoundedRectangle(cornerRadius: Layout.controlRadius).strokeBorder(Color.onBrand, lineWidth: 3))
                .background(Color.brandYellow, in: .rect(cornerRadius: Layout.controlRadius))
                .rotationEffect(.degrees(-8))
                // Platz für die Drehung, damit nichts über den Kartenrand ragt.
                .padding(.vertical, 14).padding(.trailing, 8)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .foregroundStyle(Color.ink)
        .padding(28)
        .frame(width: 380, alignment: .leading)
        .background(Color.surface, in: TicketShape())
        .padding(20)
        .background(Color.page)
        .environment(\.colorScheme, .light)
        .dynamicTypeSize(.large)
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
