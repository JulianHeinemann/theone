import SwiftUI
import RestwertKit

@main
struct RestwertApp: App {
    @State private var store = Store()
    @State private var account = Account()
    @State private var router = Router()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(account)
                .environment(router)
                .preferredColorScheme(.light)
                .tint(Color.ink)
                .onOpenURL { url in router.openImport(url) }
                .task {
                    account.attach(store)
                    await account.syncNow()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await account.syncNow() } }
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

    func openImport(_ url: URL) {
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
    @AppStorage("onboarded") private var onboarded = false
    @AppStorage("authDecided") private var authDecided = false

    var body: some View {
        ZStack {
            if !onboarded {
                OnboardingView { withAnimation(.smooth(duration: 0.5)) { onboarded = true } }
                    .transition(.blurReplace)
            } else if !authDecided {
                NavigationStack {
                    AuthView(isFirstRun: true) { withAnimation(.smooth(duration: 0.5)) { authDecided = true } }
                }
                .transition(.push(from: .trailing))
            } else {
                MainTabView()
                    .transition(.blurReplace)
            }
        }
    }
}

struct MainTabView: View {
    @Environment(Router.self) private var router
    @Environment(Store.self) private var store
    @AppStorage("warnDays") private var warnDays = 30
    @Namespace private var zoom

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("Start", systemImage: "house", value: AppTab.home) {
                NavigationStack(path: $router.homePath) {
                    HomeView(zoom: zoom).appDestinations(zoom: zoom)
                }
            }
            .badge(store.soonCount(warnDays: warnDays))

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

            Tab("Scannen", systemImage: "barcode.viewfinder", value: AppTab.scan, role: .search) {
                NavigationStack { ScanView() }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .sheet(item: $router.editing) { card in
            NavigationStack {
                CardFormView(editing: card) { _ in router.editing = nil }
            }
        }
    }
}
