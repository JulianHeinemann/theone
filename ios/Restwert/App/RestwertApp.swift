import SwiftUI
import LocalAuthentication
import UserNotifications
import RestwertKit

@main
struct RestwertApp: App {
    @UIApplicationDelegateAdaptor(NotificationHandler.self) private var notifications
    @State private var store = Store()
    @State private var cloud = CloudSync()
    @State private var router = Router()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(cloud)
                .environment(router)
                .tint(Color.ink)
                .onOpenURL { url in router.openImport(url) }
                .task {
                    NotificationHandler.openCard = { [router] id in router.showCard(id) }
                    cloud.attach(store)
                    await cloud.syncNow()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await cloud.syncNow() } }
        }
    }
}

// MARK: - Navigation

enum AppTab: Hashable { case home, history, merchants, settings, scan }

enum Route: Hashable {
    case card(UUID)
    case checkout(UUID)
    case keypad(UUID)
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

    func showUndo(_ message: String, undo: @escaping () -> Void) {
        toast = Toast(message: message, undo: undo)
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
            case .radar: RadarView()
            case .tests: TestsView()
            }
        }
    }
}

// MARK: - Wurzel

struct RootView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appLock") private var appLock = false
    @State private var locked = UserDefaults.standard.bool(forKey: "appLock")
    @AppStorage("onboarded") private var onboarded = false

    var body: some View {
        ZStack {
            if !onboarded {
                OnboardingView { withAnimation(.smooth(duration: 0.5)) { onboarded = true } }
                    .transition(.blurReplace)
            } else {
                MainTabView()
                    // Schriftgrößen werden beim Aufbau berechnet; bei geänderter Textgröße neu aufbauen.
                    .id(typeSize)
                    .transition(.blurReplace)
            }
        }
        .overlay {
            if appLock && locked {
                LockScreen { locked = false }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background && appLock { locked = true }
        }
    }
}

struct MainTabView: View {
    @Environment(Router.self) private var router
    @Environment(Store.self) private var store
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

            Tab("Händler", systemImage: "storefront", value: AppTab.merchants) {
                NavigationStack { MerchantsView() }
            }

            Tab("Einstellungen", systemImage: "gearshape", value: AppTab.settings) {
                NavigationStack { SettingsView() }
            }

            Tab("Hinzufügen", systemImage: "plus", value: AppTab.scan, role: .search) {
                NavigationStack { ScanView() }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .overlay(alignment: .bottom) {
            if let toast = router.toast {
                ToastView(toast: toast) { router.toast = nil }
                    .id(toast.id)
                    .padding(.horizontal, 16).padding(.bottom, 96)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: router.toast?.id)
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
}

/// Bestätigung mit „Rückgängig“, verschwindet nach 8 Sekunden.
struct ToastView: View {
    let toast: Toast
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.good)
            Text(toast.message).font(.scaled(15, weight: .medium)).lineLimit(2)
            Spacer(minLength: 8)
            if UIAccessibility.isVoiceOverRunning {
                Button("Schließen", systemImage: "xmark") { onClose() }.labelStyle(.iconOnly)
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
        .background(Color.ink, in: .rect(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.ink.opacity(0.2), radius: 16, y: 6)
        .task {
            // Vorlesen, und mit VoiceOver ohne Zeitlimit stehen lassen, damit „Rückgängig“ erreichbar bleibt.
            AccessibilityNotification.Announcement(toast.undo == nil ? toast.message : "\(toast.message). Rückgängig möglich.").post()
            guard !UIAccessibility.isVoiceOverRunning else { return }
            try? await Task.sleep(for: .seconds(8))
            onClose()
        }
        .accessibilityElement(children: .contain)
    }
}

/// Sperrbildschirm, wenn „App mit Face ID sperren“ an ist.
struct LockScreen: View {
    var onUnlock: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill").font(.scaled(34)).foregroundStyle(Color.ink)
            Text("Restwert ist gesperrt").font(.scaled(20, weight: .semibold))
            Button("Entsperren", systemImage: "faceid") { Task { await unlock() } }
                .buttonStyle(.primary).padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.page.ignoresSafeArea())
        .task { await unlock() }
    }

    private func unlock() async {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { onUnlock(); return }
        if (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Restwert entsperren")) == true {
            onUnlock()
        }
    }
}

// MARK: - Mitteilungen

/// Tippen auf eine Erinnerung öffnet den Gutschein; „Morgen erinnern“ plant sie einen Tag später neu.
final class NotificationHandler: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    @MainActor static var openCard: ((UUID) -> Void)?

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
            let copy = content.mutableCopy() as? UNMutableNotificationContent ?? UNMutableNotificationContent()
            let request = UNNotificationRequest(identifier: "\(raw)-snooze", content: copy,
                                                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 24 * 3600, repeats: false))
            try? await center.add(request)
        } else {
            await MainActor.run { Self.openCard?(id) }
        }
    }
}
