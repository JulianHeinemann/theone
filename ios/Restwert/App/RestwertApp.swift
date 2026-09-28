import SwiftUI
import AppIntents
import LocalAuthentication
import UserNotifications
import RestwertKit

@main
struct RestwertApp: App {
    @UIApplicationDelegateAdaptor(NotificationHandler.self) private var notifications
    @State private var store = Store()
    @State private var cloud = CloudSync()
    @State private var router: Router
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Router früh anlegen und für App Intents („Gutschein öffnen“) bereitstellen, auch beim Kaltstart.
        let router = Router()
        _router = State(initialValue: router)
        AppDependencyManager.shared.add(dependency: router)
        #if DEBUG
        // Nur für Tests: `-resetOnboarding YES` zeigt den Einstieg wieder, dauerhaft bis „Fertig“.
        if UserDefaults.standard.bool(forKey: "resetOnboarding") {
            UserDefaults.standard.set(false, forKey: "onboarded")
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(cloud)
                .environment(router)
                .tint(Color.ink)
                .onOpenURL { url in router.openImport(url) }
                .task {
                    NotificationHandler.cardLookup = { [store] id in store.cards.first { $0.id == id } }
                    NotificationHandler.openCard = { [router] id in router.showCard(id) }
                    cloud.attach(store)
                    await cloud.syncNow()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            // Beim Verlassen der App alles sicher auf die Platte bringen.
            if phase == .background { store.flush() }
            guard phase == .active else { return }
            // Nach dem Entsperren ggf. die Datei nachladen, die vorher gesperrt war.
            store.reloadIfNeeded()
            // Widget-Zeitleiste auffrischen (Tage und Summe hängen am Datum).
            WidgetBridge.update(cards: store.cards, total: store.total)
            // Gutscheinnamen für Siri-Phrasen („Öffne Zalando in Restwert“) aktuell halten.
            RestwertShortcuts.updateAppShortcutParameters()
            Task { await cloud.syncNow() }
        }
    }
}

// MARK: - Navigation

enum AppTab: Hashable { case home, history, merchants, settings, scan }

enum ScanIntent { case camera, manual, issue }

enum Route: Hashable {
    case card(UUID)
    case checkout(UUID)
    case keypad(UUID)
    /// Ziffernblock direkt nach „Bezahlt“ an der Kasse: zählt als Kassentest.
    case pay(UUID)
    case radar
    case tests
}

/// Zentraler Navigationszustand: Tabs, Stapel pro Tab, Bearbeiten-Sheet und eingehende Dateien.
@Observable
final class Router {
    var tab: AppTab = .home
    var homePath: [Route] = []
    var historyPath: [Route] = []
    var editing: GiftCard?
    /// Datei, die über „Teilen → Restwert“ oder „Öffnen in“ angekommen ist.
    var pendingImport: URL?
    /// Kurze Bestätigung unten, optional mit „Rückgängig“.
    var toast: Toast?
    /// Aus dem Einstieg: direkt Kamera oder Formular im Hinzufügen-Tab öffnen.
    var scanIntent: ScanIntent?

    func showUndo(_ message: String, undo: @escaping () -> Void) {
        toast = Toast(message: message, undo: undo)
    }

    /// Fehlerhinweis (z. B. Speichern fehlgeschlagen): Warndreieck statt Haken, bleibt länger stehen.
    func showError(_ message: String) {
        toast = Toast(message: message, undo: nil, isError: true)
    }

    func openImport(_ url: URL) {
        // restwert://card/<id> aus dem Widget öffnet den Gutschein.
        if url.scheme == "restwert" {
            if url.host() == "card", let id = UUID(uuidString: url.lastPathComponent) { showCard(id) } else { tab = .home }
            return
        }
        pendingImport = url
        tab = .scan
    }

    /// Nach dem Speichern direkt die Detailansicht zeigen.
    func showCard(_ id: UUID) {
        tab = .home
        homePath = [.card(id)]
    }
}

extension View {
    /// Alle Ziele, die aus Start und Verlauf erreichbar sind. Gutscheine öffnen mit Zoom-Übergang.
    func appDestinations(zoom: Namespace.ID) -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .card(let id):
                CardDetailView(cardID: id)
                    .navigationTransition(.zoom(sourceID: id, in: zoom))
            case .checkout(let id): CheckoutView(cardID: id)
            case .keypad(let id): KeypadView(cardID: id)
            case .pay(let id): KeypadView(cardID: id, checkout: true)
            case .radar: RadarView(zoom: zoom)
            case .tests: TestsView()
            }
        }
    }
}

// MARK: - Wurzel

struct RootView: View {
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appLock") private var appLock = false
    @AppStorage("onboarded") private var onboarded = false

    var body: some View {
        ZStack {
            if !onboarded {
                OnboardingView { exit in
                    // Auch nach „Einführung ansehen“ nicht wieder in den Einstellungen landen.
                    router.homePath = []
                    router.tab = .home
                    withAnimation(.smooth(duration: 0.5)) { onboarded = true }
                    guard exit != .browse else { return }
                    // Tab erst wechseln, wenn die Tab-Leiste steht – sonst übernimmt sie die Auswahl nicht.
                    Task {
                        try? await Task.sleep(for: .milliseconds(550))
                        router.scanIntent = exit == .scan ? .camera : exit == .manual ? .manual : nil
                        router.tab = .scan
                    }
                }
                .transition(.blurReplace)
            } else {
                MainTabView()
                    .transition(.blurReplace)
            }
        }
        // Sperre in eigenem Fenster, damit sie auch über Sheets und Vollbildansichten liegt.
        .onAppear { AppLock.shared.update(enabled: appLock, phase: scenePhase) }
        .onChange(of: scenePhase) { _, phase in AppLock.shared.update(enabled: appLock, phase: phase) }
        .onChange(of: appLock) { _, on in AppLock.shared.update(enabled: on, phase: scenePhase) }
    }
}

struct MainTabView: View {
    @Environment(Router.self) private var router
    @Environment(Store.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var zoom

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("Start", systemImage: "house", value: AppTab.home) {
                NavigationStack(path: $router.homePath) {
                    HomeView(zoom: zoom).appDestinations(zoom: zoom)
                }
            }

            Tab("Verlauf", systemImage: "scroll", value: AppTab.history) {
                NavigationStack(path: $router.historyPath) {
                    BonView().appDestinations(zoom: zoom)
                }
            }

            Tab("Läden", systemImage: "storefront", value: AppTab.merchants) {
                NavigationStack { MerchantsView() }
            }

            Tab("Einstellungen", systemImage: "gearshape", value: AppTab.settings) {
                NavigationStack { SettingsView() }
            }

            // Bewusst mit Suchrolle: nur sie setzt den Tab als eigenen, schwebenden Knopf neben die Leiste.
            // Ein normaler Tab verlöre diese Form, Toolbar oder Bottom-Accessory wären eine andere Optik.
            // Die Suche selbst sitzt fest oben auf Start; Name und VoiceOver sagen „Hinzufügen“.
            Tab("Hinzufügen", systemImage: "plus", value: AppTab.scan, role: .search) {
                NavigationStack { ScanView() }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        // Aktiver Tab in Tinte, keine dritte Akzentfarbe.
        .tint(Color.ink)
        .overlay(alignment: .bottom) {
            if let toast = router.toast {
                // Nur den eigenen Toast schließen, nie einen inzwischen neueren.
                ToastView(toast: toast) { if router.toast?.id == toast.id { router.toast = nil } }
                    .id(toast.id)
                    .padding(.horizontal, 16).padding(.bottom, 96)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: router.toast?.id)
        // Speichern gescheitert (Speicher voll, Kodierfehler, Sicherungskopie): sichtbar machen.
        // Der Store meldet nur Wechsel, derselbe Fehler erscheint also nicht bei jedem Speichern erneut.
        .onChange(of: store.saveError, initial: true) { _, error in
            if let error {
                router.showError(error)
            } else if router.toast?.isError == true {
                // Wieder gespeichert: veralteten Fehler wegnehmen.
                router.toast = nil
            }
        }
        // Bleibt derselbe Fehler bestehen (gleicher Text, kein Wertwechsel), nach dem Schließen erneut erinnern.
        // saveError hier bewusst nicht auf nil setzen: Der Store plant seinen Wiederholversuch nur, solange er gesetzt ist.
        .task(id: store.saveError) {
            guard store.saveError != nil else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, let error = store.saveError else { return }
                // Einen gerade sichtbaren „Rückgängig“-Hinweis nicht verdrängen; dann eben beim nächsten Durchlauf.
                if router.toast == nil { router.showError(error) }
            }
        }
        #if DEBUG
        .task { router.applyDemoScreen(store: store) }
        #endif
        .sheet(item: $router.editing) { card in
            NavigationStack {
                CardFormView(editing: card) { _ in router.editing = nil }
            }
        }
    }
}

#if DEBUG
extension Router {
    /// Nur für Simulator-Screenshots: Start mit `-demoScreen radar` öffnet direkt diesen Bildschirm.
    func applyDemoScreen(store: Store) {
        // `-demoSavedToast YES`: Hinweis nach dem Speichern mit „Nächsten scannen“ (Screenshot des Stapel-Scans).
        if UserDefaults.standard.bool(forKey: "demoSavedToast"), let sample = store.cards.first {
            showCard(sample.id)
            toast = Toast(message: "„\(sample.name)“ gespeichert", undo: { [weak self] in
                self?.scanIntent = .camera
                self?.tab = .scan
            }, actionTitle: "Nächsten scannen")
            return
        }
        // `-demoImport /pfad/gutschein.jpg` liest die Datei wie „Aus einer Datei“ ein (Scan-Tests im Simulator).
        if let path = UserDefaults.standard.string(forKey: "demoImport") {
            openImport(URL(fileURLWithPath: path))
            return
        }
        // `-demoBarcode ean13:4006381333931` legt eine Testkarte in diesem Format an und öffnet die Kasse
        // (Barcode-Test: Screenshot mit einem echten Barcode-Leser zurücklesen).
        if let spec = UserDefaults.standard.string(forKey: "demoBarcode"),
           let colon = spec.firstIndex(of: ":"), let format = CodeFormat(rawValue: String(spec[..<colon])) {
            // Optional „@laden“ am Ende: z. B. text:AQ7K-2ZPM@amazon für einen Online-Code.
            var rest = String(spec[spec.index(after: colon)...])
            var merchantID = Merchant.other.id
            if let at = rest.lastIndex(of: "@"), Merchant.byID[String(rest[rest.index(after: at)...])] != nil {
                merchantID = String(rest[rest.index(after: at)...])
                rest = String(rest[..<at])
            }
            let number = rest
            var card = GiftCard(kind: merchantID == Merchant.other.id ? .giftCard : .valueVoucher, merchantID: merchantID,
                                customName: merchantID == Merchant.other.id ? "Barcode-Test \(format.label)" : "",
                                number: number, format: format, value: 25, balance: 25, received: .now,
                                expires: GiftCard.legalExpiry(from: .now))
            card.isExample = true
            // `-demoMinOrder 50`: Mindestbestellwert zeigen (Online-Kasse).
            let minOrder = UserDefaults.standard.double(forKey: "demoMinOrder")
            if minOrder > 0 { card.minOrder = minOrder }
            store.upsert(card)
            homePath = [.checkout(card.id)]
            return
        }
        guard let screen = UserDefaults.standard.string(forKey: "demoScreen") else { return }
        let sample = store.cards.first { !$0.history.isEmpty } ?? store.cards.first
        switch screen {
        case "radar": homePath = [.radar]
        case "detail": if let sample { homePath = [.card(sample.id)] }
        case "checkout": if let sample { homePath = [.checkout(sample.id)] }
        case "keypad": if let sample { homePath = [.keypad(sample.id)] }
        case "form": editing = sample
        case "history": tab = .history
        case "tests":
            tab = .history
            historyPath = [.tests]
        case "merchants": tab = .merchants
        case "settings": tab = .settings
        case "scan": tab = .scan
        case "issue":
            tab = .scan
            scanIntent = .issue
        case "pending":
            if let sample {
                store.setPending(sample.id, true)
                homePath = [.card(sample.id)]
            }
        case "paper", "paperCheckout", "newForm":
            if screen == "newForm" { tab = .scan; return }
            let card = Self.paperExample()
            store.upsert(card)
            homePath = [screen == "paper" ? .card(card.id) : .checkout(card.id)]
        default: break
        }
    }

    /// Papiergutschein ohne Code mit gezeichnetem Foto, nur für Screenshots.
    static func paperExample() -> GiftCard {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 560)).image { ctx in
            UIColor(red: 0.98, green: 0.95, blue: 0.88, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 900, height: 560))
            let title: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 64, weight: .heavy), .foregroundColor: UIColor.brown]
            let body: [NSAttributedString.Key: Any] = [.font: UIFont.italicSystemFont(ofSize: 40), .foregroundColor: UIColor.darkGray]
            ("GUTSCHEIN" as NSString).draw(at: CGPoint(x: 60, y: 60), withAttributes: title)
            ("Café am Markt" as NSString).draw(at: CGPoint(x: 60, y: 170), withAttributes: body)
            ("über 20,– Euro" as NSString).draw(at: CGPoint(x: 60, y: 240), withAttributes: body)
            ("gültig bis 31.12.2027   – Stempel –" as NSString).draw(at: CGPoint(x: 60, y: 420), withAttributes: body)
        }
        var card = GiftCard(kind: .valueVoucher, merchantID: "other", customName: "Café am Markt", number: "", format: .text,
                            value: 20, balance: 20, received: .now,
                            expires: Calendar.current.date(from: DateComponents(year: 2027, month: 12, day: 31)) ?? .now)
        card.photo = image.jpegData(compressionQuality: 0.8)
        card.isExample = true
        return card
    }
}
#endif

// MARK: - Toast

struct Toast: Identifiable {
    let id = UUID()
    let message: String
    let undo: (() -> Void)?
    var isError = false
    /// Beschriftung der Aktion (Standard „Rückgängig“), z. B. „Nächsten scannen“.
    var actionTitle = "Rückgängig"
}

/// Bestätigung mit „Rückgängig“, verschwindet nach 8 Sekunden. Fehler bleiben 15 Sekunden und lassen sich schließen.
struct ToastView: View {
    let toast: Toast
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: toast.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(toast.isError ? Color.warnOnInk : Color.goodOnInk)
                .accessibilityHidden(true)
            // Fehlertexte sind länger: nicht abschneiden.
            Text(toast.message).font(.scaled(15, weight: .medium)).lineLimit(toast.isError ? nil : 2)
                .fixedSize(horizontal: false, vertical: toast.isError)
            Spacer(minLength: 8)
            if toast.isError || UIAccessibility.isVoiceOverRunning {
                Button("Schließen", systemImage: "xmark") { onClose() }
                    .labelStyle(.iconOnly)
                    .frame(minWidth: Layout.tap, minHeight: Layout.tap)
                    .contentShape(.rect)
            }
            if let undo = toast.undo {
                Button(toast.actionTitle) {
                    undo()
                    onClose()
                }
                .font(.scaled(15, weight: .bold))
            }
        }
        .foregroundStyle(Color.onInk)
        .tint(Color.onInk)
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Color.ink, in: .rect(cornerRadius: Layout.buttonRadius, style: .continuous))
        .ticketShadow(radius: Shadow.float)
        .task {
            // Vorlesen, und mit VoiceOver ohne Zeitlimit stehen lassen, damit „Rückgängig“ erreichbar bleibt.
            let spoken = toast.isError ? "Fehler: \(toast.message)" : toast.undo == nil ? toast.message : "\(toast.message). \(toast.actionTitle) möglich."
            var announcement = AttributedString(spoken)
            if toast.isError { announcement.accessibilitySpeechAnnouncementPriority = .high }
            AccessibilityNotification.Announcement(announcement).post()
            guard !UIAccessibility.isVoiceOverRunning else { return }
            // Fehler und „Nächsten scannen“ länger stehen lassen (Zeit zum Greifen des nächsten Gutscheins).
            try? await Task.sleep(for: .seconds(toast.isError || toast.actionTitle != "Rückgängig" ? 15 : 8))
            guard !Task.isCancelled else { return }
            onClose()
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - App-Sperre

/// Zustand der App-Sperre. Zeigt Sperre und Sichtschutz in einem eigenen Fenster über allem,
/// auch über Sheets und Vollbildansichten.
@MainActor @Observable
final class AppLock {
    static let shared = AppLock()

    /// Gesperrt bis Face ID oder Code; beim Start mit aktiver Sperre von Anfang an.
    var locked = UserDefaults.standard.bool(forKey: "appLock")
    /// Sichtschutz, solange die Szene nicht aktiv ist (App-Übersicht, Kontrollzentrum).
    private(set) var shielded = false
    private(set) var active = false
    /// Face ID einmal von selbst starten (nach dem Start oder Zurückkehren), nicht nach jedem Abbruch erneut.
    var autoPrompt = true

    @ObservationIgnored private var window: UIWindow?
    /// Wann die App zuletzt in den Hintergrund ging (für die Schonfrist). ContinuousClock zählt auch den
    /// Ruhezustand des Geräts mit und hängt nicht an der verstellbaren Uhrzeit.
    @ObservationIgnored private var backgroundAt: ContinuousClock.Instant?

    func update(enabled: Bool, phase: ScenePhase) {
        if !enabled { locked = false }
        if enabled && phase == .background {
            if backgroundAt == nil { backgroundAt = .now }
            // Ohne Schonfrist sofort sperren; auch wenn sie schon gesperrt war: nach der Rückkehr einmal von selbst fragen.
            if Self.delay == 0 { locked = true }
            autoPrompt = true
        }
        if enabled && phase == .active, let since = backgroundAt {
            backgroundAt = nil
            if since.duration(to: .now) >= .seconds(Self.delay) { locked = true }
        }
        shielded = enabled && phase != .active
        active = phase == .active
        show(enabled && (locked || shielded))
    }

    func unlock() {
        locked = false
        show(shielded)
    }

    /// Schonfrist in Sekunden („lockDelay“: 0 = sofort, 60, 300).
    static var delay: TimeInterval { TimeInterval(UserDefaults.standard.integer(forKey: "lockDelay")) }

    private func show(_ visible: Bool) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        if visible {
            if window == nil {
                let w = UIWindow(windowScene: scene)
                w.windowLevel = .alert + 1
                let host = UIHostingController(rootView: LockOverlay().tint(Color.ink))
                host.view.backgroundColor = .clear
                w.rootViewController = host
                window = w
            }
            guard let window, window.isHidden || !window.isKeyWindow else { return }
            // Tastatur schließen, damit sie nicht über der Sperre stehen bleibt.
            if locked { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
            window.makeKeyAndVisible()
        } else if let window, !window.isHidden {
            window.isHidden = true
            scene.windows.first { $0 !== window && !$0.isHidden }?.makeKey()
        }
    }
}

/// Inhalt des Sperrfensters: Sperrbildschirm oder reiner Sichtschutz.
private struct LockOverlay: View {
    var body: some View {
        if AppLock.shared.locked {
            LockScreen()
        } else {
            Color.page.ignoresSafeArea()
                .overlay { Image(systemName: "lock.fill").font(.scaled(34)).foregroundStyle(Color.ink) }
        }
    }
}

/// Ob das Gerät überhaupt prüfen kann (Face ID oder iPhone-Code). Ohne Gerätecode kann iOS nichts sperren.
enum DeviceSecurity {
    enum Status: Equatable { case ready, noPasscode, unavailable }

    /// Nur „kein Code eingerichtet“ heißt: iOS kann nichts sperren. Andere Fehler sind vorübergehend.
    static var status: Status {
        #if DEBUG
        // Nur für Tests: `-simulateNoPasscode YES` spielt ein iPhone ohne Code durch.
        if UserDefaults.standard.bool(forKey: "simulateNoPasscode") { return .noPasscode }
        #endif
        var error: NSError?
        if LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) { return .ready }
        return (error as? LAError)?.code == .passcodeNotSet ? .noPasscode : .unavailable
    }

    static var canAuthenticate: Bool { status == .ready }

    /// „Codes erst nach Face ID zeigen“ wirkt nur mit Gerätecode (ohne Code zeigen die Einstellungen den Schalter aus und warnen).
    static var codeLockActive: Bool { UserDefaults.standard.bool(forKey: "codeLock") && status != .noPasscode }

    /// Face ID/Touch ID oder iPhone-Code abfragen. Ohne Prüfmöglichkeit: false (nie still freigeben).
    @MainActor
    static func authenticate(reason: String, biometricsFirst: Bool = false) async -> Bool {
        guard status == .ready else { return false }
        if biometricsFirst {
            // Geteilte Geräte: der iPhone-Code ist in der Familie oft bekannt. Daher zuerst nur Face ID/Touch ID;
            // der Code gilt erst, wenn Biometrie fehlt oder nach Fehlversuchen gesperrt ist.
            let bio = LAContext()
            bio.localizedFallbackTitle = ""
            var error: NSError?
            if bio.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
                do { return try await bio.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) }
                catch let e as LAError where e.code == .biometryLockout { /* weiter mit Code */ }
                catch { return false }
            }
        }
        return (try? await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }

    /// Code-Schutz entsperren: Biometrie zuerst, danach Ansage für VoiceOver (mit dem Code selbst, falls übergeben).
    /// Bei Fehlschlag Rückmeldung per Haptik und Ansage statt still nichts zu tun.
    @MainActor
    static func revealCode(of name: String, spoken code: String? = nil) async -> Bool {
        let ok = await authenticate(reason: "Code von \(name) anzeigen", biometricsFirst: true)
        if ok {
            // Nicht den ganzen Code laut vorlesen (Umstehende hören mit): nur die letzten Ziffern.
            AccessibilityNotification.Announcement(code.map { "Code sichtbar, endet auf \(String($0.filter { !$0.isWhitespace }.suffix(4)))" } ?? "Code sichtbar").post()
        } else {
            announceFailure()
        }
        return ok
    }

    /// Jede Prüfung, die einen Schutz aufhebt oder Codes/PINs herausgibt. Mit aktivem Code-Schutz Biometrie zuerst,
    /// damit ein in der Familie bekannter iPhone-Code nicht reicht.
    @MainActor
    static func guardSensitive(_ reason: String) async -> Bool {
        let ok = await authenticate(reason: reason, biometricsFirst: codeLockActive)
        if !ok { announceFailure() }
        return ok
    }

    @MainActor
    private static func announceFailure() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        var text = AttributedString("\(methodName) hat nicht geklappt. Nochmal versuchen.")
        text.accessibilitySpeechAnnouncementPriority = .high
        AccessibilityNotification.Announcement(text).post()
    }

    /// „Face ID“, „Touch ID“ oder „Code“ – je nach Gerät, für Beschriftungen.
    static var methodName: String {
        let context = LAContext()
        var error: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Code"
        }
    }
}

extension View {
    /// Rückfrage, bevor eine PIN ohne Schutz gezeigt wird (Gerät ohne iPhone-Code).
    func unprotectedPinConfirmation(isPresented: Binding<Bool>, onShow: @escaping () -> Void) -> some View {
        confirmationDialog("PIN ohne Schutz zeigen?", isPresented: isPresented, titleVisibility: .visible) {
            Button("PIN zeigen", action: onShow)
        } message: {
            Text("Auf diesem \(Device.name) ist kein Code eingerichtet, deshalb kann Restwert die PIN nicht schützen. Jeder, der dein \(Device.name) hat, kann sie sehen.")
        }
    }
}

/// Sperrbildschirm, wenn die App-Sperre an ist.
struct LockScreen: View {
    @Environment(\.openURL) private var openURL
    @State private var authenticating = false
    /// Gerät ohne Code: nicht still öffnen, sondern erklären und die Wahl lassen.
    @State private var noPasscode = false
    @State private var confirmDisable = false
    @State private var unavailableHint = false
    @AppStorage("appLock") private var appLock = false
    private var lock: AppLock { .shared }

    var body: some View {
        // Bei sehr großer Schrift scrollen statt Knöpfe abzuschneiden.
        ScrollView {
            VStack(spacing: 16) {
                Image("AppLogo")
                    .resizable().interpolation(.high)
                    .frame(width: 64, height: 64)
                    .clipShape(.rect(cornerRadius: 15, style: .continuous))
                    .accessibilityHidden(true)
                Text("Restwert ist gesperrt").font(.scaled(22, weight: .bold)).foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                if noPasscode {
                    Text("Auf diesem \(Device.name) ist kein Code eingerichtet. Ohne Code kann Restwert nicht sicher sperren. Leg in den Einstellungen unter „\(DeviceSecurity.methodName == "Touch ID" ? "Touch ID" : "Face ID") & Code“ einen Code fest.")
                        .font(.scaled(15)).foregroundStyle(Color.ink2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("„Einstellungen öffnen“ springt in die Einstellungen-App. Tipp dort oben links auf „Einstellungen“ und dann auf „\(DeviceSecurity.methodName == "Touch ID" ? "Touch ID" : "Face ID") & Code“.")
                        .font(.scaled(13)).foregroundStyle(Color.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Einstellungen öffnen", systemImage: "gear") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .buttonStyle(.primary)
                    // Bewusst unscheinbar: der sichere Weg ist, einen Code einzurichten.
                    Button("Sperre ausschalten und öffnen") { confirmDisable = true }
                        .font(.scaled(14)).foregroundStyle(Color.ink2).underline()
                        .frame(minHeight: Layout.tap)
                } else {
                    // Knopf direkt unter dem Titel: das Face-ID-Fenster des Systems liegt in der Mitte darüber.
                    Button("Entsperren", systemImage: DeviceSecurity.methodName == "Touch ID" ? "touchid" : "faceid") { Task { await unlock() } }
                        .buttonStyle(.primary)
                    Text("Entsperre mit \(DeviceSecurity.methodName == "Code" ? "deinem \(Device.name)\u{2011}Code" : "\(DeviceSecurity.methodName) oder deinem \(Device.name)\u{2011}Code").")
                        .font(.scaled(15)).foregroundStyle(Color.ink2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    if unavailableHint {
                        Text("\(DeviceSecurity.methodName) ist gerade nicht verfügbar. Warte kurz oder entsperre dein \(Device.name) einmal mit dem Code, dann nochmal versuchen.")
                            .font(.scaled(14)).foregroundStyle(Color.warn)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 40).padding(.vertical, 24)
            .frame(maxWidth: .infinity)
            // Oben statt mittig: das Face-ID-Fenster des Systems erscheint in der Bildschirmmitte.
            .padding(.top, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color.page.ignoresSafeArea())
        .confirmationDialog("App-Sperre ausschalten?", isPresented: $confirmDisable, titleVisibility: .visible) {
            Button("Ausschalten und öffnen", role: .destructive) {
                appLock = false
                lock.unlock()
            }
        } message: {
            Text("Restwert öffnet sich dann ohne Prüfung. Jeder mit deinem \(Device.name) sieht Guthaben, Codes und PINs, bis du die Sperre in den Einstellungen wieder einschaltest.")
        }
        // Face ID erst starten, wenn die App wirklich im Vordergrund ist; im Hintergrund schlägt die Abfrage fehl.
        // Nach der Rückkehr (z. B. aus den iPhone-Einstellungen) neu prüfen.
        .task(id: lock.active) {
            guard lock.active else { return }
            if noPasscode { noPasscode = DeviceSecurity.status == .noPasscode }
            guard lock.autoPrompt else { return }
            lock.autoPrompt = false
            await unlock()
        }
    }

    private func unlock() async {
        guard !authenticating else { return }
        authenticating = true
        defer { authenticating = false }
        // Früher öffnete die App hier ohne Prüfung. Jetzt bleibt sie zu, bis ein Code eingerichtet ist
        // oder die Sperre bewusst ausgeschaltet wird. Andere Fehler (z. B. gerade gesperrt) lassen nur „Entsperren“ stehen.
        switch DeviceSecurity.status {
        case .noPasscode:
            withAnimation(.snappy) { noPasscode = true }
            return
        case .unavailable:
            // Z. B. Face ID nach Fehlversuchen gesperrt: sagen statt still nichts tun.
            withAnimation(.snappy) { unavailableHint = true }
            return
        case .ready:
            noPasscode = false
        }
        if (try? await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Restwert entsperren")) == true {
            lock.unlock()
        }
    }
}

// MARK: - Mitteilungen

/// Tippen auf eine Erinnerung öffnet den Gutschein; „Morgen erinnern“ plant sie einen Tag später neu.
final class NotificationHandler: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Beim Kaltstart angetippter Gutschein, bis der Router bereitsteht.
    @MainActor static var pendingCard: UUID?
    @MainActor static var openCard: ((UUID) -> Void)? {
        didSet {
            if let id = pendingCard, let openCard {
                pendingCard = nil
                openCard(id)
            }
        }
    }
    /// Aktueller Stand eines Gutscheins aus dem Store (für „Morgen erinnern“).
    @MainActor static var cardLookup: ((UUID) -> GiftCard?)?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let content = response.notification.request.content
        guard let raw = content.userInfo["card"] as? String, let id = UUID(uuidString: raw) else { return }
        if response.actionIdentifier == "snooze" {
            let fire = Date.now.addingTimeInterval(24 * 3600)
            let expires = (content.userInfo["expires"] as? Double).map { Date(timeIntervalSince1970: $0) }
            guard let text = Self.snoozeText(id: id, fire: fire, title: content.title, body: content.body,
                                                   name: content.userInfo["name"] as? String, expires: expires) else { return }
            let copy = content.mutableCopy() as? UNMutableNotificationContent ?? UNMutableNotificationContent()
            copy.title = text.title
            copy.body = text.body
            let request = UNNotificationRequest(identifier: "\(raw)-snooze", content: copy,
                                                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 24 * 3600, repeats: false))
            try? await center.add(request)
        } else {
            await MainActor.run {
                // Beim Kaltstart ist der Router evtl. noch nicht bereit: ID vormerken, didSet öffnet sie.
                if let open = Self.openCard { open(id) } else { Self.pendingCard = id }
            }
        }
    }

    /// Titel und Text für „Morgen erinnern“ zum neuen Zeitpunkt; nil, wenn der Gutschein dann abgelaufen oder erledigt ist.
    @MainActor
    private static func snoozeText(id: UUID, fire: Date, title: String, body: String,
                                   name: String?, expires: Date?) -> (title: String, body: String)? {
        let card = cardLookup?(id) ?? storedCard(id)
        if let card, !card.isActive { return nil }
        let prefix = title.components(separatedBy: ": ").dropLast().joined(separator: ": ")
        let name = name ?? card?.name ?? (prefix.isEmpty ? title : prefix)
        let body = card.map { "\($0.headline) gültig bis \($0.expires.dayMonthYear). Jetzt einlösen." } ?? body
        guard let expires = expires ?? card?.expires ?? expiry(in: body) else { return ("\(name): deine Erinnerung", body) }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: fire), to: cal.startOfDay(for: expires)).day ?? 0
        guard days >= 0 else { return nil }
        let text = days == 0 ? "läuft heute ab" : days == 1 ? "läuft morgen ab" : "noch \(days) Tage"
        return ("\(name): \(text)", body)
    }

    /// Gutschein direkt aus der Datei, wenn die App nur im Hintergrund für die Aktion gestartet wurde.
    private static func storedCard(_ id: UUID) -> GiftCard? {
        struct Stored: Decodable { var cards: [GiftCard] }
        guard let data = try? Data(contentsOf: URL.applicationSupportDirectory.appending(path: "restwert.json")),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return nil }
        return stored.cards.first { $0.id == id }
    }

    /// Letzte Rückfallebene: Datum aus „… gültig bis TT.MM.JJJJ“ im Mitteilungstext.
    private static func expiry(in body: String) -> Date? {
        guard let match = body.firstMatch(of: /bis (\d{2}\.\d{2}\.\d{4})/) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "dd.MM.yyyy"
        return f.date(from: String(match.1))
    }
}
