import SwiftUI

@main
struct RestwertApp: App {
    @State private var store = Store()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .preferredColorScheme(.light)
                .tint(.ink)
                .onOpenURL { url in store.incomingURL = url }
        }
    }
}

enum Tab: Hashable { case home, bon, merchants, settings }

enum Route: Hashable {
    case card(UUID)
    case checkout(UUID)
    case keypad(UUID)
    case radar
    case tests
}

struct ImportRequest: Identifiable {
    let id = UUID()
    var url: URL?
    var editing: GiftCard?
}

struct ContentView: View {
    @Environment(Store.self) private var store
    @AppStorage("onboarded") private var onboarded = false
    @State private var tab: Tab = .home
    @State private var path = NavigationPath()
    @State private var addRequest: ImportRequest?

    var body: some View {
        if !onboarded {
            OnboardingView { withAnimation(.snappy) { onboarded = true } }
        } else {
            NavigationStack(path: $path) {
                Group {
                    switch tab {
                    case .home: HomeView(path: $path, onAdd: { addRequest = ImportRequest() })
                    case .bon: BonView(path: $path)
                    case .merchants: MerchantsView()
                    case .settings: SettingsView()
                    }
                }
                .toolbar(.hidden, for: .navigationBar)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    TabBar(tab: $tab) { addRequest = ImportRequest() }
                }
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .card(let id): CardDetailView(cardID: id, path: $path, onEdit: { card in addRequest = ImportRequest(editing: card) })
                    case .checkout(let id): CheckoutView(cardID: id)
                    case .keypad(let id): KeypadView(cardID: id)
                    case .radar: RadarView(path: $path)
                    case .tests: TestsView()
                    }
                }
            }
            .sheet(item: $addRequest) { req in
                AddCardView(importURL: req.url, editing: req.editing) { saved in
                    addRequest = nil
                    tab = .home
                    path = NavigationPath()
                    path.append(Route.card(saved.id))
                }
            }
            .onChange(of: store.incomingURL) { _, url in
                guard let url else { return }
                store.incomingURL = nil
                addRequest = ImportRequest(url: url)
            }
        }
    }
}

struct TabBar: View {
    @Binding var tab: Tab
    var onScan: () -> Void

    var body: some View {
        HStack {
            item(.home, "house.fill", "Start")
            item(.bon, "scroll", "Bon")
            Button(action: onScan) {
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 58)
                    .background(Color.ink, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: Color.ink.opacity(0.3), radius: 10, y: 6)
            }
            .frame(maxWidth: .infinity)
            .offset(y: -12)
            .accessibilityLabel("Karte hinzufügen")
            item(.merchants, "storefront", "Händler")
            item(.settings, "gearshape", "Einstellungen")
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .background(Color.surface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Color.line).frame(height: 1) }
    }

    private func item(_ t: Tab, _ icon: String, _ label: String) -> some View {
        Button { tab = t } label: {
            Image(systemName: icon)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(tab == t ? Color.ink : Color(hex: 0xA3A6AE))
                .frame(maxWidth: .infinity, minHeight: 48)
        }
        .accessibilityLabel(label)
        .accessibilityAddTraits(tab == t ? .isSelected : [])
    }
}

// MARK: - Onboarding

struct OnboardingView: View {
    var onStart: () -> Void
    @State private var float = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Kein Gutschein verfällt mehr.")
                .font(.system(size: 44, weight: .heavy)).kerning(-1)
                .padding(.top, 30)
            Text("Restwert holt deine Gutscheinkarten aus der Schublade aufs Handy. Mit Restguthaben, Ablauf-Radar und Barcode für die Kasse.")
                .font(.system(size: 17)).foregroundStyle(Color.ink2)
            ZStack {
                RoundedRectangle(cornerRadius: 32, style: .continuous).fill(Color.fill)
                ForEach(0..<3, id: \.self) { i in
                    FloatingCard(color: Pastel.all[i], number: ["856 279", "412 008", "731 554"][i])
                        .offset(x: CGFloat(i) * 34 - 34, y: CGFloat(i) * 78 - 78 + (float ? -8 : 8) * (i % 2 == 0 ? 1 : -1))
                }
            }
            .frame(maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            Button(action: onStart) {
                HStack {
                    Text("Los geht's").font(.system(size: 17, weight: .bold))
                    Spacer()
                    Image(systemName: "arrow.right").font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.ink)
                        .frame(width: 62, height: 48)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .foregroundStyle(.white)
                .padding(.leading, 24).padding(8)
                .background(Color.ink, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .padding(.horizontal, 20).padding(.bottom, 16)
        .background(Color.page.ignoresSafeArea())
        .onAppear { withAnimation(.easeInOut(duration: 3).repeatForever()) { float = true } }
    }

    struct FloatingCard: View {
        let color: Color
        let number: String

        var body: some View {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(color)
                .frame(width: 220, height: 138)
                .overlay(alignment: .topLeading) {
                    Text("RESTWERT").font(.system(size: 19, weight: .heavy)).kerning(1.4).padding(18)
                }
                .overlay(alignment: .bottomLeading) {
                    Text("••• \(number)").font(.system(size: 13, weight: .semibold)).kerning(1).opacity(0.7).padding(18)
                }
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: -7) {
                        Circle().fill(Color.ink.opacity(0.7)).frame(width: 18)
                        Circle().fill(Color.ink.opacity(0.35)).frame(width: 18)
                    }
                    .frame(height: 18).padding(18)
                }
                .foregroundStyle(Color.ink)
                .shadow(color: Color.ink.opacity(0.12), radius: 20, y: 20)
                .rotation3DEffect(.degrees(48), axis: (x: 1, y: 0, z: 0))
                .rotationEffect(.degrees(-28))
        }
    }
}
