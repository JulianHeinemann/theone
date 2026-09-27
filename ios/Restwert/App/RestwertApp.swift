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

enum ScanIntent { case camera, manual }

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
                Button("Rückgängig") {
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
            let spoken = toast.isError ? "Fehler: \(toast.message)" : toast.undo == nil ? toast.message : "\(toast.message). Rückgängig möglich."
            var announcement = AttributedString(spoken)
            if toast.isError { announcement.accessibilitySpeechAnnouncementPriority = .high }
            AccessibilityNotification.Announcement(announcement).post()
            guard !UIAccessibility.isVoiceOverRunning else { return }
            try? await Task.sleep(for: .seconds(toast.isError ? 15 : 8))
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

    func update(enabled: Bool, phase: ScenePhase) {
        if !enabled { locked = false }
        if enabled && phase == .background && !locked {
            locked = true
            autoPrompt = true
        }
        shielded = enabled && phase != .active
        active = phase == .active
        show(enabled && (locked || shielded))
    }

    func unlock() {
        locked = false
        show(shielded)
    }

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

/// Sperrbildschirm, wenn „App mit Face ID sperren“ an ist.
struct LockScreen: View {
    @State private var authenticating = false
    private var lock: AppLock { .shared }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill").font(.scaled(34)).foregroundStyle(Color.ink)
            Text("Restwert ist gesperrt").font(.scaled(20, weight: .semibold)).foregroundStyle(Color.ink)
            Button("Entsperren", systemImage: "faceid") { Task { await unlock() } }
                .buttonStyle(.primary).padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.page.ignoresSafeArea())
        // Face ID erst starten, wenn die App wirklich im Vordergrund ist; im Hintergrund schlägt die Abfrage fehl.
        .task(id: lock.active) {
            guard lock.active, lock.autoPrompt else { return }
            lock.autoPrompt = false
            await unlock()
        }
    }

    private func unlock() async {
        guard !authenticating else { return }
        authenticating = true
        defer { authenticating = false }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { lock.unlock(); return }
        if (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Restwert entsperren")) == true {
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
