import SwiftUI
import RestwertKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(Store.self) private var store
    @Environment(CloudSync.self) private var cloud
    @AppStorage("reminders") private var reminders = true
    @AppStorage("pinLock") private var pinLock = true
    @AppStorage("maskNumber") private var maskNumber = false
    @AppStorage("appLock") private var appLock = false
    @AppStorage("onboarded") private var onboarded = true
    @AppStorage("sortOrder") private var sortRaw = CardSortOrder.expiry.rawValue
    @AppStorage("warnDays") private var warnDays = 30
    @AppStorage(ReminderPrefs.daysKey) private var reminderDays = "30,7"
    @AppStorage(ReminderPrefs.hourKey) private var reminderHour = 10
    @State private var confirmReset = false
    @State private var cloudError: String?
    @State private var confirmDeleteCloud = false
    @State private var showRestore = false
    @State private var restoreMessage: String?

    var body: some View {
        Form {
            Section { accountSection } footer: {
                Text("Ohne eigenes Konto und ohne unseren Server: Mit iCloud-Sync liegen deine Gutscheine verschlüsselt in deinem eigenen iCloud. Den Schlüssel hat nur dein iCloud-Schlüsselbund – wir können nichts lesen, Apple auch nicht.")
            }

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
                Toggle(isOn: $appLock) {
                    settingLabel("App mit Face ID sperren", "Beim Öffnen entsperren", "lock.app.dashed")
                }
                Toggle(isOn: $maskNumber) {
                    settingLabel("Kartennummer an der Kasse verdecken", "Tippen zeigt sie ganz", "eye.slash")
                }
            } header: {
                Text("Sicherheit & Erinnerungen")
            }
            .tint(Color.ink)

            Section {
                Picker(selection: $sortRaw) {
                    ForEach(CardSortOrder.allCases) { Text($0.label).tag($0.rawValue) }
                } label: {
                    settingLabel("Liste sortieren nach", nil, "arrow.up.arrow.down")
                }
                Picker(selection: $warnDays) {
                    ForEach([7, 14, 30, 60, 90], id: \.self) { Text("\($0) Tagen").tag($0) }
                } label: {
                    settingLabel("Warnung ab", nil, "hourglass")
                }
            } header: {
                Text("Anzeige")
            } footer: {
                Text("Ab dann steht ein Gutschein auf Start oben unter „Läuft bald ab“.")
            }

            Section {
                Label("Gespeichert auf diesem iPhone mit Dateischutz des Systems. Mit Konto werden Gutscheine verschlüsselt übertragen (HTTPS), ohne Fotos und PINs.", systemImage: "lock")
                Label("Import: Live-Scan, Foto, PDF, E-Mail-Text oder in Mail „Teilen → Restwert“. Handschrift wird mitgelesen.", systemImage: "square.and.arrow.down")
                if SmartExtractor.isAvailable {
                    Label("Apple Intelligence liest schwierige Gutscheine direkt auf dem Gerät.", systemImage: "apple.intelligence")
                }
                Label("An der Kasse wird die Helligkeit automatisch erhöht.", systemImage: "sun.max")
            } header: {
                Text("So funktioniert Restwert")
            }
            .font(.scaled(14))
            .foregroundStyle(Color.ink2)

            Section {
                if let url = store.backupFile() {
                    ShareLink(item: url) { Label("Sicherung speichern", systemImage: "externaldrive.badge.checkmark") }
                }
                Button("Sicherung wiederherstellen", systemImage: "arrow.counterclockwise") { showRestore = true }
                if let url = store.csvFile() {
                    ShareLink(item: url) { Label("Als Tabelle exportieren (CSV)", systemImage: "tablecells") }
                }
                if let restoreMessage {
                    Text(restoreMessage).font(.scaled(14)).foregroundStyle(Color.ink2)
                }
            } header: {
                Text("Sicherung")
            } footer: {
                Text("Deine Gutscheine sind im iCloud-Backup deines iPhones enthalten. Zusätzlich kannst du eine Sicherungsdatei speichern, z. B. in iCloud Drive. Sie enthält PINs, aber keine Fotos – bewahre sie sicher auf.")
            }
            .foregroundStyle(Color.ink)

            Section {
                Button("Einführung ansehen", systemImage: "sparkles") { onboarded = false }
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
        .fileImporter(isPresented: $showRestore, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            do {
                let n = try store.restore(from: url)
                restoreMessage = "\(n) Gutscheine aus der Sicherung übernommen."
            } catch {
                restoreMessage = "Die Datei ist keine Restwert-Sicherung."
            }
        }
        .onChange(of: reminders) { _, on in
            Task {
                if on { await store.requestNotifications() } else { await store.scheduleReminders() }
            }
        }
        .onChange(of: warnDays) { _, _ in Task { await store.scheduleReminders() } }
        .onChange(of: reminderDays) { _, _ in Task { await store.scheduleReminders() } }
        .onChange(of: reminderHour) { _, _ in Task { await store.scheduleReminders() } }
        .confirmationDialog("Alle Restwert-Daten aus deinem iCloud löschen?", isPresented: $confirmDeleteCloud, titleVisibility: .visible) {
            Button("Aus iCloud löschen", role: .destructive) {
                Task {
                    do { try await cloud.deleteCloudData() } catch { cloudError = error.localizedDescription }
                }
            }
        } message: {
            Text("Auf diesem iPhone bleibt alles erhalten. Der Sync wird ausgeschaltet.")
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
        HStack(spacing: 14) {
            let inCloud: Bool = {
                switch cloud.state {
                case .idle, .syncing: cloud.isEnabled
                default: false
                }
            }()
            Image(systemName: inCloud ? "lock.icloud" : "iphone").font(.scaled(20, weight: .semibold))
                .frame(width: 48, height: 48).background(Color.fill, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(inCloud ? "Sicher in deinem iCloud" : "Nur auf diesem iPhone").font(.scaled(16, weight: .semibold))
                Text(inCloud ? "Ende-zu-Ende verschlüsselt, auf allen deinen Apple-Geräten."
                             : "Nichts verlässt dein iPhone. Texterkennung läuft auf dem Gerät.")
                    .font(.scaled(14)).foregroundStyle(Color.ink2)
            }
        }
        Toggle(isOn: Binding(get: { cloud.isEnabled }, set: { cloud.isEnabled = $0 })) {
            settingLabel("iCloud-Sync", "Für iPhone, iPad und ein neues Gerät", "icloud")
        }
        .tint(Color.ink)
        if cloud.isEnabled {
            HStack(spacing: 8) {
                switch cloud.state {
                case .syncing:
                    ProgressView().controlSize(.small)
                    Text("Wird abgeglichen …")
                case .waitingForKey:
                    Image(systemName: "key").foregroundStyle(Color.warn)
                    Text("Warte auf den Schlüssel aus dem iCloud-Schlüsselbund. Bitte dort „Passwörter und Schlüsselbund“ einschalten.")
                case .unavailable(let message), .failed(let message):
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.warn)
                    Text(message)
                case .idle, .off:
                    Image(systemName: "checkmark.icloud.fill").foregroundStyle(Color.good)
                    Text(cloud.lastSync.map { "Abgeglichen \($0.formatted(.relative(presentation: .named)))" } ?? "Noch nicht abgeglichen")
                }
            }
            .font(.scaled(13.5)).foregroundStyle(Color.ink2)
            .animation(.smooth, value: cloud.state)
            Button("Jetzt abgleichen", systemImage: "arrow.triangle.2.circlepath") { Task { await cloud.syncNow() } }
                .foregroundStyle(Color.ink)
            Button("Daten aus iCloud löschen", systemImage: "icloud.slash", role: .destructive) { confirmDeleteCloud = true }
            if let cloudError { Text(cloudError).font(.scaled(13)).foregroundStyle(Color.bad) }
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
            .tint(Color.ink)
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
