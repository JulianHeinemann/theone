import SwiftUI
import RestwertKit
import UniformTypeIdentifiers
import UserNotifications
import LocalAuthentication

struct SettingsView: View {
    @Environment(Store.self) private var store
    @Environment(CloudSync.self) private var cloud
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Nur lesend, damit Schalter und Kopfzeile immer denselben Stand zeigen (CloudSync liest direkt aus UserDefaults).
    @AppStorage("iCloudSync") private var syncOn = false
    @State private var notifDenied = false
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
    /// Export läuft gerade (Datei wird erzeugt); verhindert Doppeltippen.
    @State private var exporting: ExportKind?

    private enum ExportKind { case backup, csv }

    var body: some View {
        Form {
            Section { accountSection } footer: {
                Text("Ohne eigenes Konto und ohne unseren Server: Mit iCloud-Sync liegen deine Gutscheine verschlüsselt in deinem eigenen iCloud. Den Schlüssel hat nur dein iCloud-Schlüsselbund – diese Sync-Daten können weder wir noch Apple lesen. Das iCloud-Backup deines iPhones kann Apple dagegen öffnen, solange „Erweiterter Datenschutz“ aus ist.")
            }

            Section {
                Toggle(isOn: $reminders) {
                    settingLabel("Ablauf-Erinnerungen", nil, "bell.badge")
                }
                if reminders && notifDenied {
                    Button {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    } label: {
                        settingLabel("Mitteilungen sind aus", "Erinnerungen kommen so nicht an. In den iOS-Einstellungen erlauben", "bell.slash")
                    }
                    .foregroundStyle(Color.warn)
                }
                if reminders {
                    NavigationLink {
                        ReminderSettingsView()
                    } label: {
                        settingLabel("Wann erinnern?", ReminderPrefs.describe(days: ReminderPrefs.days, hour: reminderHour), "clock")
                    }
                }
                Toggle(isOn: guarded($pinLock, reason: "PIN-Schutz ausschalten")) {
                    settingLabel("PIN mit Face ID schützen", "PIN erst nach Face ID oder Code anzeigen", "faceid")
                }
                Toggle(isOn: guarded($appLock, reason: "App-Sperre ausschalten")) {
                    settingLabel("App mit Face ID sperren", "Beim Öffnen entsperren", "lock.app.dashed")
                }
                Toggle(isOn: $maskNumber) {
                    settingLabel("Code an der Kasse verdecken", "Tippen zeigt ihn ganz", "eye.slash")
                }
            } header: {
                Text("Sicherheit & Erinnerungen")
            }
            .tint(Color.toggleOn)

            Section {
                Picker(selection: $sortRaw) {
                    ForEach(CardSortOrder.allCases) { Text($0.label).tag($0.rawValue) }
                } label: {
                    settingLabel("Liste sortieren nach", nil, "arrow.up.arrow.down")
                }
                .modifier(AdaptivePickerStyle())
                Picker(selection: $warnDays) {
                    ForEach([7, 14, 30, 60, 90], id: \.self) { Text("\($0)\u{00A0}Tagen").tag($0) }
                } label: {
                    settingLabel("Warnung ab", nil, "hourglass")
                }
                .modifier(AdaptivePickerStyle())
            } header: {
                Text("Anzeige")
            } footer: {
                Text("Ab dann steht ein Gutschein auf Start oben unter „Läuft bald ab“.")
            }

            Section {
                Label("Gespeichert auf diesem iPhone mit Dateischutz des Systems, PINs eingeschlossen. Mit iCloud-Sync zusätzlich Ende-zu-Ende verschlüsselt in deinem eigenen iCloud; PINs gehen dabei nur in den iCloud-Schlüsselbund.", systemImage: "lock")
                Label("Import: Live-Scan, Foto, PDF, E-Mail-Text oder in Mail „Teilen → Restwert“. Handschrift wird mitgelesen.", systemImage: "square.and.arrow.down")
                if SmartExtractor.isAvailable {
                    Label("Apple Intelligence liest schwierige Gutscheine direkt auf dem Gerät.", systemImage: "apple.intelligence")
                }
                Label("An der Kasse wird die Helligkeit automatisch erhöht.", systemImage: "sun.max")
            } header: {
                Text("So funktioniert Restwert")
            }
            .font(.scaled(15))
            .foregroundStyle(Color.ink2)

            Section {
                // Dateien entstehen erst beim Tippen, nicht bei jedem Neuzeichnen.
                exportButton(.backup, "Sicherung speichern", "externaldrive.badge.checkmark")
                Button("Sicherung wiederherstellen", systemImage: "arrow.counterclockwise") { showRestore = true }
                exportButton(.csv, "Als Tabelle exportieren (CSV)", "tablecells")
                if let restoreMessage {
                    Text(restoreMessage).font(.scaled(15)).foregroundStyle(Color.ink2)
                }
            } header: {
                Text("Sicherung")
            } footer: {
                Text("Deine Gutscheine sind im iCloud-Backup deines iPhones enthalten. Zusätzlich kannst du eine Sicherungsdatei speichern, z.\u{00A0}B. in iCloud Drive. Sie enthält PINs und Fotos – bewahre sie sicher auf. Die Tabelle enthält keine PINs.")
            }
            .foregroundStyle(Color.ink)

            Section {
                Button("Einführung ansehen", systemImage: "sparkles") { onboarded = false }
                if store.hasExamples {
                    Button("Beispiele entfernen", systemImage: "wand.and.stars") {
                        withAnimation(reduceMotion ? nil : .default) { store.clearExamples() }
                    }
                }
                NavigationLink {
                    PrivacyExplainer()
                } label: {
                    Label("So schützt Restwert deine Daten", systemImage: "lock.shield")
                }
                NavigationLink {
                    PrivacyPolicyView()
                } label: {
                    Label("Datenschutzerklärung", systemImage: "hand.raised")
                }
                NavigationLink {
                    ImprintView()
                } label: {
                    Label("Impressum", systemImage: "info.circle")
                }
                Button("Alles löschen", systemImage: "trash", role: .destructive) { confirmReset = true }
            } header: {
                Text("Hilfe & Rechtliches")
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
                restoreMessage = n == 0 ? "Keine neuen Gutscheine – alles ist schon aktuell."
                    : n == 1 ? "1 Gutschein aus der Sicherung übernommen." : "\(n) Gutscheine aus der Sicherung übernommen."
            } catch {
                restoreMessage = "Die Datei ist keine Restwert-Sicherung."
            }
        }
        .task {
            removeLeftoverExports()
            await checkNotifications()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await checkNotifications() } }
        }
        .onChange(of: reminders) { _, on in
            Task {
                if on { await store.requestNotifications() } else { await store.scheduleReminders() }
                await checkNotifications()
            }
        }
        .onChange(of: warnDays) { _, _ in Task { await store.scheduleReminders() } }
        .onChange(of: reminderDays) { _, _ in Task { await store.scheduleReminders() } }
        .onChange(of: reminderHour) { _, _ in Task { await store.scheduleReminders() } }
        .confirmationDialog("Alle Restwert-Daten aus deinem iCloud löschen?", isPresented: $confirmDeleteCloud, titleVisibility: .visible) {
            Button("Aus iCloud löschen", role: .destructive) {
                Task {
                    do {
                        try await cloud.deleteCloudData()
                        // Auch Sync-Schlüssel und PINs aus dem iCloud-Schlüsselbund entfernen; lokal bleiben die PINs in der Datei.
                        SyncedKeychain.set(nil, for: "cloud-key")
                        for id in store.cards.map(\.id) + Array(store.deletedIDs) { SyncedKeychain.set(nil, for: "pin-\(id.uuidString)") }
                    } catch { cloudError = error.localizedDescription }
                }
            }
        } message: {
            Text("Entfernt die Gutscheine aus iCloud sowie Schlüssel und PINs aus dem iCloud-Schlüsselbund. Auf diesem iPhone bleibt alles erhalten. Der Sync wird ausgeschaltet.")
        }
        .confirmationDialog("Alle Gutscheine, Einlösungen und Tests löschen?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Alles löschen", role: .destructive) { withAnimation(reduceMotion ? nil : .default) { store.resetAll() } }
        }
    }

    /// Einschalten sofort, Ausschalten erst nach Face ID oder Gerätecode. Ohne Gerätecode wie in der Detailansicht: direkt.
    private func guarded(_ value: Binding<Bool>, reason: String) -> Binding<Bool> {
        Binding(get: { value.wrappedValue }, set: { new in
            guard !new else { value.wrappedValue = true; return }
            Task { @MainActor in
                let context = LAContext()
                var error: NSError?
                guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { value.wrappedValue = false; return }
                if (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) == true {
                    value.wrappedValue = false
                }
            }
        })
    }

    private func exportButton(_ kind: ExportKind, _ title: String, _ icon: String) -> some View {
        Button {
            export(kind)
        } label: {
            Label {
                HStack {
                    Text(title)
                    if exporting == kind {
                        Spacer()
                        ProgressView().accessibilityLabel("Wird erstellt")
                    }
                }
            } icon: {
                Image(systemName: icon)
            }
        }
        .disabled(exporting != nil)
    }

    /// Datei erst jetzt erzeugen, teilen und danach wieder löschen.
    private func export(_ kind: ExportKind) {
        guard exporting == nil else { return }
        exporting = kind
        Task {
            await Task.yield()  // Fortschritt zuerst zeigen
            let url: URL? = switch kind {
            case .backup: store.backupFile()
            case .csv: writeCSV()
            }
            exporting = nil
            if let url {
                ExportShare.present(url)
            } else {
                restoreMessage = kind == .backup ? "Die Sicherung konnte nicht erstellt werden." : "Die Tabelle konnte nicht erstellt werden."
            }
        }
    }

    /// Wie `Store.csvFile()`, aber ohne Beispielkarten und mit Dateischutz.
    private func writeCSV() -> URL? {
        let own = store.cards.filter { !$0.isExample }
        let text = CardQueries.csv(own, warnDays: warnDays)
        let url = URL.temporaryDirectory.appending(path: "Restwert-Gutscheine-\(Date.now.formatted(.iso8601.year().month().day())).csv")
        do {
            try Data(("\u{FEFF}" + text).utf8).write(to: url, options: [.atomic, .completeFileProtection])
            return url
        } catch {
            return nil
        }
    }

    /// Reste früherer Exporte (auch aus älteren Versionen, die bei jedem Zeichnen schrieben) entfernen.
    private func removeLeftoverExports() {
        let fm = FileManager.default
        let dir = URL.temporaryDirectory
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for file in files where file.lastPathComponent.hasPrefix("Restwert-Sicherung-") || file.lastPathComponent.hasPrefix("Restwert-Gutscheine") {
            try? fm.removeItem(at: file)
        }
    }

    private func checkNotifications() async {
        notifDenied = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
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
        // Bei sehr großer Schrift Symbol über den Text, damit der Text die ganze Breite hat.
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 14))
        layout {
            // „Sicher in deinem iCloud“ erst nach einem erfolgreichen Abgleich; vorher und währenddessen neutral.
            let inCloud = syncOn && cloud.state == .idle && cloud.lastSync != nil
            let checking = syncOn && cloud.state == .syncing
            Image(systemName: inCloud ? "lock.icloud" : syncOn ? "icloud" : "iphone").font(.scaled(20, weight: .semibold))
                .frame(width: 48, height: 48).background(Color.fill, in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(inCloud ? "Sicher in deinem iCloud" : checking ? "iCloud wird geprüft" : syncOn ? "iCloud-Sync wartet" : "Nur auf diesem iPhone")
                    .font(.scaled(16, weight: .semibold))
                Text(inCloud ? "Ende-zu-Ende verschlüsselt, auf allen deinen Apple-Geräten."
                     : syncOn ? "Bis iCloud bereit ist, bleibt alles auf diesem iPhone."
                     : "Nichts geht an uns. Texterkennung läuft auf dem Gerät. Das iCloud-Backup deines iPhones enthält die Gutscheine.")
                    .font(.scaled(15)).foregroundStyle(Color.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        Toggle(isOn: Binding(get: { syncOn }, set: { cloud.isEnabled = $0 })) {
            settingLabel("iCloud-Sync", "Für iPhone, iPad und ein neues Gerät", "icloud")
        }
        .tint(Color.toggleOn)
        if syncOn {
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
            .font(.scaled(13)).foregroundStyle(Color.ink2)
            .accessibilityElement(children: .combine)
            .animation(reduceMotion ? nil : .smooth, value: cloud.state)
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
                    Toggle(d == 1 ? "1\u{00A0}Tag vorher" : "\(d)\u{00A0}Tage vorher", isOn: Binding(
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
                Text("Du kannst mehrere wählen. Unabhängig davon steht ein Gutschein ab \(warnDays)\u{00A0}Tagen vor Ablauf unter „Läuft bald ab“.")
            }
            .tint(Color.toggleOn)
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

/// Nachprüfbare Angaben, wo welche Daten liegen – in Alltagssprache.
struct PrivacyExplainer: View {
    private let rows: [(icon: String, title: String, text: String)] = [
        ("iphone", "Auf deinem iPhone", "Gutscheine, Fotos, PINs und Verlauf liegen in einer Datei, die iOS verschlüsselt, solange das iPhone gesperrt ist."),
        ("person.crop.circle.badge.xmark", "Kein Konto, kein Server von uns", "Es gibt keine Anmeldung und keine Datenbank bei uns. Wir sehen nicht, welche Gutscheine du hast."),
        ("lock.icloud", "iCloud-Sync (freiwillig)", "Jeder Gutschein wird auf dem iPhone mit AES-256 verschlüsselt, bevor er in dein eigenes iCloud geht. Der Schlüssel liegt nur in deinem iCloud-Schlüsselbund. Diese Sync-Daten können weder wir noch Apple lesen. Fotos werden nicht synchronisiert."),
        ("key", "PINs", "PINs liegen lokal in der geschützten Datei. Mit iCloud-Sync gehen sie zusätzlich nur in deinen iCloud-Schlüsselbund, nie in eine Datenbank. Angezeigt werden sie nur nach Face ID."),
        ("externaldrive.badge.icloud", "iCloud-Backup des iPhones", "Wie alle App-Daten ist die Datei im iCloud-Backup deines iPhones enthalten. Ohne „Erweiterten Datenschutz“ kann Apple dieses Backup öffnen; mit ihm ist es Ende-zu-Ende verschlüsselt."),
        ("text.viewfinder", "Scannen", "Barcode- und Texterkennung laufen auf dem iPhone. Fotos werden nirgendwohin geschickt."),
        ("chart.bar.xaxis", "Keine Tracker, keine Werbung", "Die App enthält keine Analyse- oder Werbe-Software."),
        ("externaldrive", "Sicherung", "Die Sicherungsdatei entsteht erst, wenn du sie speicherst, und enthält PINs und Fotos. Speichere sie nur dort, wo du auch Passwörter aufbewahren würdest."),
    ]

    var body: some View {
        List {
            ForEach(rows, id: \.title) { row in
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.title).font(.scaled(16, weight: .semibold))
                        Text(row.text).font(.scaled(15)).foregroundStyle(Color.ink2)
                    }
                    .padding(.vertical, 4)
                } icon: {
                    Image(systemName: row.icon).foregroundStyle(Color.ink)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .scrollContentBackground(.hidden)
        .pageBackground()
        .navigationTitle("Deine Daten")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Bei sehr großer Schrift Auswahl auf eigener Seite statt Menü, damit Titel und Wert nicht abgeschnitten werden.
private struct AdaptivePickerStyle: ViewModifier {
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        if typeSize.isAccessibilitySize {
            content.pickerStyle(.navigationLink)
        } else {
            content.pickerStyle(.menu)
        }
    }
}

/// Teilen-Blatt für eine eben erzeugte Datei. Die Datei wird gelöscht, sobald das Blatt fertig ist
/// (gesichert, gesendet oder abgebrochen) – bis dahin liegt sie nur im temporären Ordner der App.
private enum ExportShare {
    static func present(_ url: URL) {
        let remove: @Sendable () -> Void = { try? FileManager.default.removeItem(at: url) }
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              var top = scene.keyWindow?.rootViewController else { remove(); return }
        while let next = top.presentedViewController { top = next }
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        sheet.completionWithItemsHandler = { @Sendable _, _, _, _ in remove() }
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        top.present(sheet, animated: true)
    }
}
