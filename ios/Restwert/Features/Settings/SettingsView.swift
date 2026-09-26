import SwiftUI
import RestwertKit

struct SettingsView: View {
    @Environment(Store.self) private var store
    @Environment(Account.self) private var account
    @AppStorage("reminders") private var reminders = true
    @AppStorage("pinLock") private var pinLock = true
    @AppStorage("onboarded") private var onboarded = true
    @AppStorage("sortOrder") private var sortRaw = CardSortOrder.expiry.rawValue
    @AppStorage("warnDays") private var warnDays = 30
    @State private var showAuth = false
    @State private var confirmDeleteAccount = false
    @State private var confirmReset = false
    @State private var accountError: String?

    var body: some View {
        Form {
            Section { accountSection }

            Section {
                Toggle(isOn: $reminders) {
                    settingLabel("Ablauf-Erinnerungen", "30 und 7 Tage vor dem Ablauf, um 10 Uhr", "bell.badge")
                }
                Toggle(isOn: $pinLock) {
                    settingLabel("PIN mit Face ID schützen", "PIN erst nach Face ID oder Code anzeigen", "faceid")
                }
            } header: {
                Text("Sicherheit & Erinnerungen")
            }
            .tint(Color.good)

            Section {
                Picker(selection: $sortRaw) {
                    ForEach(CardSortOrder.allCases) { Text($0.label).tag($0.rawValue) }
                } label: {
                    settingLabel("Liste sortieren nach", nil, "arrow.up.arrow.down")
                }
                Stepper(value: $warnDays, in: 7...180, step: 7) {
                    settingLabel("„Läuft bald ab“ ab \(warnDays) Tagen", "Warnfrist für Status, Radar und Hinweise", "hourglass")
                        .contentTransition(.numericText(value: Double(warnDays)))
                        .animation(.snappy, value: warnDays)
                }
            } header: {
                Text("Anzeige")
            }

            Section {
                Label("Gespeichert auf diesem iPhone mit Dateischutz des Systems. Mit Konto zusätzlich verschlüsselt übertragen, ohne Fotos und PINs.", systemImage: "lock")
                Label("Import: Live-Scan, Foto, PDF, E-Mail-Text oder in Mail „Teilen → Restwert“. Handschrift wird mitgelesen.", systemImage: "square.and.arrow.down")
                if SmartExtractor.isAvailable {
                    Label("Apple Intelligence liest schwierige Gutscheine direkt auf dem Gerät.", systemImage: "apple.intelligence")
                }
                Label("An der Kasse wird die Helligkeit automatisch auf Maximum gestellt.", systemImage: "sun.max")
            } header: {
                Text("So funktioniert Restwert")
            }
            .font(.system(size: 14))
            .foregroundStyle(Color.ink2)

            Section {
                Button("Einführung ansehen", systemImage: "sparkles") { onboarded = false }
                ShareLink(item: store.exportJSON()) { Label("Daten exportieren", systemImage: "square.and.arrow.up") }
                if store.hasExamples {
                    Button("Beispiele entfernen", systemImage: "wand.and.stars") { withAnimation { store.clearExamples() } }
                }
                Link(destination: APIConfig.baseURL.appending(path: "datenschutz")) {
                    Label("Datenschutz", systemImage: "hand.raised")
                }
                Link(destination: APIConfig.baseURL.appending(path: "impressum")) {
                    Label("Impressum", systemImage: "info.circle")
                }
                Button("Alles löschen", systemImage: "trash", role: .destructive) { confirmReset = true }
            }
            .foregroundStyle(Color.ink)
        }
        .scrollContentBackground(.hidden)
        .pageBackground()
        .navigationTitle("Einstellungen")
        .onChange(of: reminders) { _, on in
            Task {
                if on { await store.requestNotifications() } else { await store.scheduleReminders() }
            }
        }
        .onChange(of: warnDays) { _, _ in Task { await store.scheduleReminders() } }
        .sheet(isPresented: $showAuth) {
            NavigationStack { AuthView() }
        }
        .confirmationDialog("Konto und alle Daten auf dem Server endgültig löschen?", isPresented: $confirmDeleteAccount, titleVisibility: .visible) {
            Button("Konto löschen", role: .destructive) {
                Task {
                    do { try await account.deleteAccount() } catch { accountError = error.localizedDescription }
                }
            }
        }
        .confirmationDialog("Alle Gutscheine, Einlösungen und Tests löschen?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Alles löschen", role: .destructive) { withAnimation { store.resetAll() } }
        }
    }

    private func settingLabel(_ title: String, _ subtitle: String?, _ icon: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 16, weight: .semibold))
                if let subtitle { Text(subtitle).font(.system(size: 13)).foregroundStyle(Color.muted) }
            }
        } icon: {
            Image(systemName: icon).foregroundStyle(Color.ink)
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        if let user = account.user {
            HStack(spacing: 14) {
                Text((user.name.isEmpty ? user.email : user.name).initials)
                    .font(.system(size: 16, weight: .heavy)).foregroundStyle(Color.ink)
                    .frame(width: 48, height: 48).background(Color.brandYellow, in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.name.isEmpty ? "Dein Konto" : user.name).font(.system(size: 17, weight: .bold))
                    Text(user.email).font(.system(size: 13)).foregroundStyle(Color.muted)
                }
            }
            HStack(spacing: 8) {
                switch account.syncState {
                case .syncing:
                    ProgressView().controlSize(.small)
                    Text("Synchronisiere …")
                case .failed(let message):
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.warn)
                    Text(message).lineLimit(2)
                case .idle:
                    Image(systemName: "checkmark.icloud.fill").foregroundStyle(Color.good)
                        .symbolEffect(.bounce, value: account.lastSync)
                    Text(account.lastSync.map { "Zuletzt synchronisiert \($0.formatted(.relative(presentation: .named)))" }
                         ?? "Noch nicht synchronisiert")
                }
            }
            .font(.system(size: 13.5)).foregroundStyle(Color.ink2)
            .animation(.smooth, value: account.syncState)
            Button("Jetzt synchronisieren", systemImage: "arrow.triangle.2.circlepath") { Task { await account.syncNow() } }
                .foregroundStyle(Color.ink)
            Button("Abmelden", systemImage: "rectangle.portrait.and.arrow.right") { account.logout() }
                .foregroundStyle(Color.ink)
            Button("Konto löschen", systemImage: "person.crop.circle.badge.xmark", role: .destructive) { confirmDeleteAccount = true }
            if let accountError {
                Text(accountError).font(.system(size: 13)).foregroundStyle(Color.bad)
            }
        } else {
            HStack(spacing: 14) {
                Image(systemName: "icloud").font(.system(size: 20, weight: .semibold))
                    .frame(width: 48, height: 48).background(Color.brandYellow, in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kein Konto").font(.system(size: 17, weight: .bold))
                    Text("Alles liegt nur auf diesem iPhone.").font(.system(size: 13)).foregroundStyle(Color.muted)
                }
            }
            Button("Anmelden oder Konto erstellen") { showAuth = true }
                .buttonStyle(.primary)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
        }
    }
}
