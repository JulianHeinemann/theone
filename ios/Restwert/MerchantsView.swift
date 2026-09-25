import SwiftUI

struct MerchantsView: View {
    @Environment(Store.self) private var store
    @State private var query = ""
    @State private var category: MerchantCategory?

    private var items: [Merchant] {
        Merchant.all
            .filter { category == nil || $0.category == category }
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
            .sorted {
                let a = MerchantCategory.allCases.firstIndex(of: $0.category) ?? 0
                let b = MerchantCategory.allCases.firstIndex(of: $1.category) ?? 0
                return a == b ? $0.name.localizedCompare($1.name) == .orderedAscending : a < b
            }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Wo geht es ohne Plastik?").font(.system(size: 32, weight: .heavy))
                    Text("Recherche vom 25.09.2026 zu rund 45 Karten in Deutschland. Offiziell bestätigt kein Händler, dass ein Foto der Plastikkarte reicht.")
                        .font(.system(size: 14)).foregroundStyle(Color.muted)
                }
                .padding(.top, 8)
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Color.muted)
                    TextField("Händler suchen", text: $query)
                }
                .padding(.horizontal, 16).frame(height: 54)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        segment("Alle", category == nil) { category = nil }
                        ForEach(MerchantCategory.allCases) { c in segment(c.label, category == c) { category = c } }
                    }
                }
                .scrollIndicators(.hidden)
                ForEach(items) { m in row(m) }
            }
            .padding(.horizontal, 16).padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background(Color.page.ignoresSafeArea())
    }

    private func segment(_ title: String, _ on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(on ? Color.ink : Color.muted)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(on ? Color.surface : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func row(_ m: Merchant) -> some View {
        let mine = store.tests.filter { $0.merchantID == m.id && !$0.isExample }
        let ok = mine.filter(\.success).count
        return HStack(alignment: .top, spacing: 14) {
            LetterTile(text: m.name, color: Pastel.color(for: m.id))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(m.name).font(.system(size: 16, weight: .bold))
                    Chip(text: m.category.label, fg: m.category.tint, bg: m.category.soft)
                    if !mine.isEmpty {
                        Chip(text: "Dein Test \(ok)/\(mine.count)", fg: ok * 2 >= mine.count ? .good : .bad, bg: ok * 2 >= mine.count ? .goodSoft : .badSoft)
                    }
                }
                Text(m.tip).font(.system(size: 13.5)).foregroundStyle(Color.ink2)
                if let url = m.balanceURL {
                    Link(destination: url) { Label("Guthaben-Seite", systemImage: "arrow.up.right").font(.system(size: 13, weight: .bold)) }
                        .foregroundStyle(Color.ink)
                } else {
                    Text("Guthaben nur an der Kasse").font(.system(size: 13)).foregroundStyle(Color.muted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12).cardSurface(radius: 20)
    }
}

struct SettingsView: View {
    @Environment(Store.self) private var store
    @Environment(Account.self) private var account
    @State private var showAuth = false
    @State private var confirmDeleteAccount = false
    @State private var accountError: String?
    @AppStorage("reminders") private var reminders = true
    @AppStorage("pinLock") private var pinLock = true
    @AppStorage("onboarded") private var onboarded = true
    @AppStorage("sortOrder") private var sortRaw = CardSortOrder.expiry.rawValue
    @AppStorage("warnDays") private var warnDays = 30
    @State private var confirmReset = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Einstellungen").font(.system(size: 32, weight: .heavy)).padding(.top, 8)
                accountCard
                VStack(spacing: 0) {
                    Toggle(isOn: $reminders) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ablauf-Erinnerungen").font(.system(size: 16, weight: .bold))
                            Text("30 und 7 Tage vor dem Ablauf, um 10 Uhr").font(.system(size: 13)).foregroundStyle(Color.muted)
                        }
                    }
                    .padding(16)
                    Divider().padding(.leading, 16)
                    Toggle(isOn: $pinLock) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("PIN mit Face ID schützen").font(.system(size: 16, weight: .bold))
                            Text("PIN erst nach Face ID oder Code anzeigen").font(.system(size: 13)).foregroundStyle(Color.muted)
                        }
                    }
                    .padding(16)
                }
                .tint(Color.good)
                .cardSurface(radius: 24)

                VStack(alignment: .leading, spacing: 14) {
                    Text("Anzeige").font(.system(size: 16, weight: .bold))
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Liste sortieren nach").font(.system(size: 13)).foregroundStyle(Color.muted)
                        Picker("Sortierung", selection: $sortRaw) {
                            ForEach(CardSortOrder.allCases) { Text($0.label).tag($0.rawValue) }
                        }
                        .pickerStyle(.segmented)
                    }
                    Stepper(value: $warnDays, in: 7...180, step: 7) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("„Läuft bald ab“ ab \(warnDays) Tagen").font(.system(size: 15, weight: .semibold))
                            Text("Warnfrist für Status und Hinweise").font(.system(size: 13)).foregroundStyle(Color.muted)
                        }
                    }
                }
                .padding(16)
                .cardSurface(radius: 24)
                .onChange(of: reminders) { _, on in Task { if on { await store.requestNotifications() } else { await store.scheduleReminders() } } }

                VStack(alignment: .leading, spacing: 8) {
                    Label("Gespeichert nur auf diesem iPhone, mit Dateischutz des Systems.", systemImage: "lock")
                    Label("Import: Live-Scan, Foto, PDF, E-Mail-Text oder in Mail „Teilen → Restwert“. Handschrift wird mitgelesen.", systemImage: "square.and.arrow.down")
                    Label("An der Kasse wird die Helligkeit automatisch auf Maximum gestellt.", systemImage: "sun.max")
                }
                .font(.system(size: 14)).foregroundStyle(Color.ink2)
                .padding(16).frame(maxWidth: .infinity, alignment: .leading).cardSurface(radius: 24)

                VStack(spacing: 10) {
                    Button("Einführung ansehen") { onboarded = false }.buttonStyle(FilledButtonStyle(background: .surface, foreground: .ink))
                    ShareLink(item: store.exportJSON()) { Text("Daten exportieren") }.buttonStyle(FilledButtonStyle(background: .surface, foreground: .ink))
                    if store.hasExamples {
                        Button("Beispiele entfernen") { store.clearExamples() }.buttonStyle(FilledButtonStyle(background: .surface, foreground: .ink))
                    }
                    Button("Alles löschen") { confirmReset = true }.buttonStyle(FilledButtonStyle(background: .badSoft, foreground: .bad))
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 30)
        }
        .background(Color.page.ignoresSafeArea())
        .sheet(isPresented: $showAuth) { AuthView() }
        .confirmationDialog("Konto und alle Daten auf dem Server endgültig löschen?", isPresented: $confirmDeleteAccount, titleVisibility: .visible) {
            Button("Konto löschen", role: .destructive) {
                Task {
                    do { try await account.deleteAccount() } catch { accountError = error.localizedDescription }
                }
            }
        }
        .confirmationDialog("Alle Karten, Einlösungen und Tests löschen?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Alles löschen", role: .destructive) { store.resetAll() }
        }
    }
}

extension SettingsView {
    @ViewBuilder
    var accountCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let user = account.user {
                HStack(spacing: 14) {
                    Text((user.name.isEmpty ? user.email : user.name).initials)
                        .font(.system(size: 16, weight: .heavy)).foregroundStyle(Color.ink)
                        .frame(width: 48, height: 48).background(Color.brandYellow, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.name.isEmpty ? "Dein Konto" : user.name).font(.system(size: 17, weight: .bold))
                        Text(user.email).font(.system(size: 13)).foregroundStyle(Color.muted)
                    }
                    Spacer()
                }
                HStack(spacing: 8) {
                    switch account.syncState {
                    case .syncing:
                        ProgressView().controlSize(.small)
                        Text("Synchronisiere …")
                    case .failed(let msg):
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.warn)
                        Text(msg).lineLimit(2)
                    case .idle:
                        Image(systemName: "checkmark.icloud.fill").foregroundStyle(Color.good)
                        Text(account.lastSync.map { "Zuletzt synchronisiert \($0.formatted(.relative(presentation: .named)))" } ?? "Noch nicht synchronisiert")
                    }
                    Spacer()
                }
                .font(.system(size: 13.5)).foregroundStyle(Color.ink2)
                HStack(spacing: 10) {
                    Button("Jetzt synchronisieren") { Task { await account.syncNow() } }
                        .buttonStyle(FilledButtonStyle(background: .fill, foreground: .ink))
                    Button("Abmelden") { account.logout() }
                        .buttonStyle(FilledButtonStyle(background: .fill, foreground: .ink))
                }
                Button("Konto löschen") { confirmDeleteAccount = true }
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(Color.bad)
                if let accountError { Text(accountError).font(.system(size: 13)).foregroundStyle(Color.bad) }
            } else {
                HStack(spacing: 14) {
                    Image(systemName: "icloud").font(.system(size: 20, weight: .semibold))
                        .frame(width: 48, height: 48).background(Color.brandYellow, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Kein Konto").font(.system(size: 17, weight: .bold))
                        Text("Alles liegt nur auf diesem iPhone.").font(.system(size: 13)).foregroundStyle(Color.muted)
                    }
                    Spacer()
                }
                Button("Anmelden oder Konto erstellen") { showAuth = true }
                    .buttonStyle(FilledButtonStyle())
            }
        }
        .padding(16)
        .cardSurface(radius: 24)
        .animation(.snappy, value: account.user)
    }
}
