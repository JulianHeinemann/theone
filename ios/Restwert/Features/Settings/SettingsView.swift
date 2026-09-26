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
    @AppStorage(ReminderPrefs.daysKey) private var reminderDays = "30,7"
    @AppStorage(ReminderPrefs.hourKey) private var reminderHour = 10
    @State private var showAuth = false
    @State private var confirmDeleteAccount = false
    @State private var confirmReset = false
    @State private var accountError: String?

    var body: some View {
        Form {
            Section { accountSection }

            Section {
                Toggle(isOn: $reminders) {
                    settingLabel("Ablauf-Erinnerungen", nil, "bell.badge")
                }
                if reminders {
                    NavigationLink {
                        ReminderSettingsView()
                    } label: {
                        settingLabel("Wann erinnern?", ReminderPrefs.describe(days: ReminderPrefs.days, hour: reminderHour), "clock")
                    }
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
                    settingLabel("„Läuft bald ab“ ab \(warnDays) Tagen", "Ab dann steht ein Gutschein oben unter „Läuft bald ab“", "hourglass")
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
            .font(.scaled(14))
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
        .onChange(of: reminderDays) { _, _ in Task { await store.scheduleReminders() } }
        .onChange(of: reminderHour) { _, _ in Task { await store.scheduleReminders() } }
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
                Text(title).font(.scaled(16, weight: .semibold))
                if let subtitle { Text(subtitle).font(.scaled(13)).foregroundStyle(Color.muted) }
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
                    .font(.scaled(16, weight: .heavy)).foregroundStyle(Color.ink)
                    .frame(width: 48, height: 48).background(Color.brandYellow, in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.name.isEmpty ? "Dein Konto" : user.name).font(.scaled(17, weight: .bold))
                    Text(user.email).font(.scaled(13)).foregroundStyle(Color.muted)
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
            .font(.scaled(13.5)).foregroundStyle(Color.ink2)
            .animation(.smooth, value: account.syncState)
            Button("Jetzt synchronisieren", systemImage: "arrow.triangle.2.circlepath") { Task { await account.syncNow() } }
                .foregroundStyle(Color.ink)
            Button("Abmelden", systemImage: "rectangle.portrait.and.arrow.right") { account.logout() }
                .foregroundStyle(Color.ink)
            Button("Konto löschen", systemImage: "person.crop.circle.badge.xmark", role: .destructive) { confirmDeleteAccount = true }
            if let accountError {
                Text(accountError).font(.scaled(13)).foregroundStyle(Color.bad)
            }
        } else {
            HStack(spacing: 14) {
                Image(systemName: "iphone").font(.scaled(20, weight: .semibold))
                    .frame(width: 48, height: 48).background(Color.fill, in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Deine Daten bleiben auf diesem iPhone").font(.scaled(16, weight: .semibold))
                    Text("Kein Konto nötig. Nichts wird hochgeladen.").font(.scaled(14)).foregroundStyle(Color.ink2)
                }
            }
            Button { showAuth = true } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Optional: Konto für mehrere Geräte").foregroundStyle(Color.ink)
                    Text("Synchronisiert verschlüsselt, ohne Fotos und PINs").font(.scaled(13)).foregroundStyle(Color.muted)
                }
            }
        }
    }
}

/// Vorlaufzeiten und Uhrzeit der Ablauf-Erinnerungen.
struct ReminderSettingsView: View {
    @AppStorage(ReminderPrefs.daysKey) private var reminderDays = "30,7"
    @AppStorage(ReminderPrefs.hourKey) private var reminderHour = 10
    @AppStorage("warnDays") private var warnDays = 30

    private var selected: Set<Int> { Set(reminderDays.split(separator: ",").compactMap { Int($0) }) }

    var body: some View {
        Form {
            Section {
                ForEach(ReminderPrefs.choices, id: \.self) { d in
                    Toggle(d == 1 ? "1 Tag vorher" : "\(d) Tage vorher", isOn: Binding(
                        get: { selected.contains(d) },
                        set: { on in
                            var set = selected
                            if on { set.insert(d) } else { set.remove(d) }
                            reminderDays = set.sorted(by: >).map(String.init).joined(separator: ",")
                        }))
                }
            } header: {
                Text("Vorlaufzeit")
            } footer: {
                Text("Du kannst mehrere wählen. Unabhängig davon steht ein Gutschein ab \(warnDays) Tagen vor Ablauf unter „Läuft bald ab“.")
            }
            .tint(Color.good)
            Section("Uhrzeit") {
                Picker("Erinnern um", selection: $reminderHour) {
                    ForEach(6...22, id: \.self) { h in Text("\(h):00 Uhr").tag(h) }
                }
            }
        }
        .navigationTitle("Erinnerungen")
        .navigationBarTitleDisplayMode(.inline)
    }
}
