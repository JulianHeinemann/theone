import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import RestwertKit

/// Scannen → Ergebnis prüfen → Formular. Alternativ Foto, E-Mail, Datei oder manuell.
struct ScanView: View {
    @Environment(Router.self) private var router
    @Environment(Store.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var outcome: ScanOutcome?
    @State private var busy = false
    @State private var showScanner = false
    @State private var showFiles = false
    @State private var showEmail = false
    @State private var photoItems: [PhotosPickerItem] = []
    /// Mehrere Fotos auf einmal: werden nacheinander gelesen; nach jedem Speichern kommt das nächste.
    @State private var batch: [BatchSource] = []
    @State private var batchTotal = 0
    /// Fotos der Mehrfachauswahl, die sich nicht lesen ließen – am Ende genannt.
    @State private var batchUnreadable = 0
    @State private var batchSaved = 0
    @State private var batchSkipped = 0
    @State private var formSeed: FormSeed?
    @State private var importError: String?
    /// Zählt Lesevorgänge; ein abgebrochener oder überholter Vorgang zeigt sein Ergebnis nicht mehr.
    @State private var readID = 0
    @State private var readTask: Task<Void, Never>?
    @State private var confirmAddWithWarning = false
    @State private var confirmDiscard = false
    @State private var showIssue = false
    /// Nur ob Text in der Zwischenablage liegt; gelesen wird erst nach einem Tipp.
    @State private var clipboardHasText = UIPasteboard.general.hasStrings

    /// Wunsch aus dem Einstieg einlösen: Kamera oder Formular öffnen.
    private func consumeIntent() {
        guard let intent = router.scanIntent else { return }
        router.scanIntent = nil
        switch intent {
        case .camera: showScanner = true
        case .manual: formSeed = FormSeed(outcome: nil)
        case .issue: showIssue = true
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if outcome != nil && batchTotal > 1 {
                    Text("Foto \(batchTotal - batch.count) von \(batchTotal)")
                        .font(.scaled(13, weight: .semibold)).foregroundStyle(Color.ink2)
                        .padding(.top, 8)
                }
                if let outcome {
                    ScanResultView(outcome: outcome, canSave: outcome.canSave, onReceived: { date in
                        // Kaufdatum ändert die Frist – dann einmal neu entscheiden, ob „Speichern“ reicht.
                        self.outcome?.received = date
                        if let o = self.outcome { self.outcome?.canSave = o.canSaveDirectly }
                    })
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
                } else {
                    sources
                        .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity),
                                                removal: .move(edge: .leading).combined(with: .opacity)))
                }
            }
            // Reichlich Luft unten: im Hinzufügen-Tab (Suchrolle) lag das Ende sonst unter der schwebenden Tab-Leiste.
            .padding(.horizontal, Layout.page).padding(.bottom, outcome == nil ? Layout.tap * 2 : Layout.group)
            // Während des Lesens nichts bedienbar – auch nicht per Schaltersteuerung oder Tastatur.
            .disabled(busy)
        }
        .scrollIndicators(.hidden)
        // Solange „gespeichert – Ansehen“ steht, lässt sich die letzte Zeile darüber schieben.
        .safeAreaPadding(.bottom, router.toast == nil || outcome != nil ? 0 : 88)
        .pageBackground()
        .readableWidth()
        // Aktionen fest unten statt am Ende der Liste unter der schwebenden Tab-Leiste.
        // Deckende Leiste mit Verlauf darüber: Inhalt läuft weich aus, statt mitten im Satz abgeschnitten zu werden.
        .safeAreaInset(edge: .bottom) {
            if let outcome { resultActions(outcome).frame(maxWidth: 700).frame(maxWidth: .infinity).fadingBar() }
        }
        // Im Ergebnis keine Tab-Leiste: sie verdeckte „Hinzufügen“, Zurück geht oben links.
        .toolbar(outcome == nil ? .automatic : .hidden, for: .tabBar)
        .onAppear(perform: consumeIntent)
        #if DEBUG
        .onAppear {
            // Nur für Screenshots: Mehrfachauswahl mit Dateien statt Fotos nachstellen.
            guard !Self.demoBatchDone, let list = UserDefaults.standard.string(forKey: "demoImportBatch") else { return }
            Self.demoBatchDone = true
            batch = list.split(separator: "|").map { .file(URL(fileURLWithPath: String($0))) }
            batchTotal = batch.count
            nextFromBatch()
        }
        #endif
        .onChange(of: router.scanIntent != nil) { _, _ in consumeIntent() }
        .tabTitle(outcome == nil ? "Hinzufügen" : "Ergebnis")
        .toolbar {
            if outcome != nil {
                ToolbarItem(placement: .topBarLeading) {
                    // Zurück verwirft das Gelesene: einmal nachfragen (versehentliche Tipps, Tremor).
                    Button("Zurück", systemImage: "chevron.left") { confirmDiscard = true }
                        .confirmationDialog("Ergebnis verwerfen?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                            Button("Verwerfen", role: .destructive) {
                                withAnimation(reduceMotion ? nil : .smooth) { outcome = nil }
                                // Mehrere Fotos: als übersprungen zählen und mit dem nächsten weitermachen.
                                if batchTotal > 1 { batchSkipped += 1 }
                                nextFromBatch()
                            }
                        } message: {
                            Text("Der gelesene Gutschein wird nicht gespeichert.")
                        }
                }
            }
        }
        .overlay {
            if busy {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.large)
                    VStack(spacing: 4) {
                        Text("Wird gelesen …")
                            .font(.scaled(15, weight: .semibold))
                        Text(ScanProgress.shared.step)
                            .font(.scaled(13, weight: .medium)).foregroundStyle(Color.ink)
                            .contentTransition(.opacity)
                        Text("Alles läuft auf deinem \(Device.name) und dauert ein paar Sekunden.")
                            .font(.scaled(13)).foregroundStyle(Color.ink2)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    Button("Abbrechen") { cancelReading() }
                        .buttonStyle(.quiet)
                }
                .frame(maxWidth: 280)
                .padding(28)
                .background {
                    // Hintergrund sperren, solange gelesen wird (kein versehentliches Tippen).
                    Color.black.opacity(0.001).frame(width: 4000, height: 4000).contentShape(.rect).onTapGesture {}
                }
                // Für VoiceOver modal: nichts dahinter ist bedienbar, solange gelesen wird.
                .accessibilityAddTraits(.isModal)
                .glassEffect(.regular, in: .rect(cornerRadius: Layout.cardRadius, style: .continuous))
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .smooth, value: busy)
        .onChange(of: busy) { _, reading in
            if reading { AccessibilityNotification.Announcement("Wird gelesen").post() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in
            clipboardHasText = UIPasteboard.general.hasStrings
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { clipboardHasText = UIPasteboard.general.hasStrings }
        }
        .navigationDestination(item: $formSeed) { seed in
            CardFormView(outcome: seed.outcome, autoSave: seed.autoSave) { saved in
                formSeed = nil
                outcome = nil
                // Immer im Hinzufügen-Tab bleiben (mehrere hintereinander, gleich welche Quelle); „Ansehen“ öffnet ihn.
                router.toast = Toast(message: "„\(saved.name)“ gespeichert", undo: { [router] in router.showCard(saved.id) }, actionTitle: "Ansehen")
                if batchTotal > 1 { batchSaved += 1 }
                nextFromBatch()
            }
        }
        .fullScreenCover(isPresented: $showScanner) {
            LiveScannerView { live in read { await finishLive(live) } }
        }
        .sheet(isPresented: $showIssue) {
            NavigationStack {
                IssueVoucherView { card in router.showCard(card.id) }
            }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.pdf, .image, .plainText, .text]) { result in
            switch result {
            case .success(let url): read { await Importer.analyze(url: url) }
            case .failure: importError = "Datei konnte nicht geöffnet werden."
            }
        }
        .sheet(isPresented: $showEmail) {
            EmailImportSheet(hasClipboard: clipboardHasText) { text in read { await Importer.analyze(text: text) } }
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            photoItems = []
            batchUnreadable = 0; batchSaved = 0; batchSkipped = 0
            batch = items.map { .photo($0) }
            batchTotal = items.count
            nextFromBatch()
        }
        .task(id: router.pendingImport) {
            // Erst nach der Analyse zurücksetzen: eine neue task-id würde diesen Task sonst abbrechen.
            guard let url = router.pendingImport else { return }
            // Über read(), damit auch „Teilen“-Importe abbrechbar sind.
            read { await Importer.analyze(url: url) }
            await readTask?.value
            if router.pendingImport == url { router.pendingImport = nil }
        }
        .alert("Import fehlgeschlagen", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
    }

    // MARK: Quellen

    /// Scannen ist der Hauptweg; die anderen drei stehen leiser darunter.
    private var sources: some View {
        VStack(alignment: .leading, spacing: Layout.section) {
            VStack(alignment: .leading, spacing: Layout.group) {
                Button { showScanner = true } label: { ViewfinderTeaser() }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Gutschein scannen")
                    .accessibilityHint("Öffnet die Kamera. Barcode und Text werden automatisch gelesen.")
                // Hinweis direkt beim Scannen, nicht als letzte Zeile unter der Tab-Leiste.
                Label("Texterkennung läuft nur auf deinem \(Device.name).", systemImage: "lock")
                    .font(.scaled(13)).foregroundStyle(Color.ink2).padding(.horizontal, 4)
            }
            VStack(alignment: .leading, spacing: Layout.group) {
                Text("Oder anders hinzufügen").font(.scaled(15, weight: .semibold)).foregroundStyle(Color.ink2)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) {
                    PhotosPicker(selection: $photoItems, maxSelectionCount: 20, selectionBehavior: .ordered, matching: .images) {
                        SourceRow(icon: "photo", title: "Aus Fotos", subtitle: "Fotos oder Screenshots, auch mehrere auf einmal")
                    }
                    Divider().padding(.leading, 56)
                    Button { showEmail = true } label: {
                        SourceRow(icon: "envelope", title: "Aus dem Text einer E-Mail", subtitle: "Text kopieren und hier einfügen")
                    }
                    if clipboardHasText {
                        Button(action: pasteFromClipboard) {
                            Label("Aus Zwischenablage einfügen", systemImage: "doc.on.clipboard")
                                .font(.scaled(15, weight: .semibold)).foregroundStyle(Color.ink)
                                .padding(.horizontal, Layout.inset)
                                .frame(minHeight: Layout.tap)
                                .background(Color.fill, in: .capsule)
                                .contentShape(.capsule)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 56).padding(.trailing, 14).padding(.bottom, Layout.group)
                        .accessibilityHint("Liest den kopierten Text und sucht darin nach dem Gutschein")
                        .transition(.opacity)
                    }
                    Divider().padding(.leading, 56)
                    Button { showFiles = true } label: {
                        SourceRow(icon: "doc", title: "Aus einer Datei",
                                  subtitle: "PDF oder Bild. Anhang aus Mail: lange drücken, „Teilen“, Rest\u{2060}wert wählen")
                    }
                    Divider().padding(.leading, 56)
                    Button { formSeed = FormSeed(outcome: nil) } label: {
                        SourceRow(icon: "keyboard", title: "Von Hand eingeben", subtitle: "Laden, Betrag und Code selbst eintippen")
                    }
                    Divider().padding(.leading, 56)
                    Button { showIssue = true } label: {
                        SourceRow(icon: "storefront", title: "Eigenen Gutschein ausgeben",
                                  subtitle: "Für Läden und Cafés: Gutschein mit QR-Code erstellen und teilen")
                    }
                }
                .buttonStyle(.plain)
                .background(Color.surface, in: .rect(cornerRadius: Layout.cardRadius, style: .continuous)).modifier(ContrastEdge())
                .animation(reduceMotion ? nil : .smooth, value: clipboardHasText)
            }
        }
        .padding(.top, 8)
    }

    // MARK: Logik

    private func run(_ work: () async -> ScanOutcome) async {
        // Offenes Formular schließen, damit das neue Ergebnis sichtbar wird
        formSeed = nil
        readID += 1
        let id = readID
        busy = true
        let result = await work()
        guard !Task.isCancelled else { return }
        // Inzwischen abgebrochen oder von einem neueren Lesevorgang abgelöst: Ergebnis verwerfen.
        guard id == readID else { return }
        busy = false
        if result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && result.barcode == nil && result.photo == nil {
            // Mehrere Fotos: ein unlesbares überspringen statt die Reihe anzuhalten, am Ende nennen.
            if batchTotal > 1 { batchUnreadable += 1; nextFromBatch(); return }
            importError = "Datei oder Foto konnte nicht gelesen werden. Versuch ein anderes Format oder gib den Gutschein von Hand ein."
            return
        }
        show(result)
    }

    /// Live-Scan liefert Barcode und Text; Apple Intelligence strukturiert den Text danach.
    private func finishLive(_ live: ScanOutcome) async -> ScanOutcome {
        var result = live
        if let smart = await SmartExtractor.extract(from: live.text) {
            result.smart = smart
            result.usedAppleIntelligence = true
        }
        return result
    }

    /// Lesen als eigener Task, damit „Abbrechen“ die laufende Arbeit wirklich stoppt.
    private func read(_ work: @escaping @MainActor () async -> ScanOutcome) {
        readTask?.cancel()
        readTask = Task { await run(work) }
    }

    private func cancelReading() {
        readID += 1
        readTask?.cancel()
        readTask = nil
        busy = false
        // Abbrechen in einer Mehrfachauswahl: Rest als übersprungen zählen und mit Bilanz beenden.
        if batchTotal > 1 {
            batchSkipped += batch.count + 1
            batch = []
            nextFromBatch()
        }
    }

    /// „Hinzufügen“ bzw. bei Nicht-Gutscheinen „Erneut scannen“ als Hauptaktion.
    private func resultActions(_ outcome: ScanOutcome) -> some View {
        let canSave = outcome.canSave
        return VStack(spacing: 14) {
            if let dup = outcome.duplicateID {
                if batchTotal <= 1 {
                    Button("Gespeicherten Gutschein öffnen") {
                        withAnimation(reduceMotion ? nil : .smooth) { self.outcome = nil }
                        router.showCard(dup)
                    }
                    .buttonStyle(.primary)
                } else {
                    // Mehrere Fotos: die Dublette einfach auslassen.
                    skipButton.buttonStyle(.primary)
                }
                // Untereinander: „Trotzdem hinzufügen“ bräche nebeneinander zweizeilig um.
                Button("Trotzdem hinzufügen") { formSeed = FormSeed(outcome: outcome) }.buttonStyle(.quiet)
                // In einer Reihe steht „Überspringen“ schon oben; einzeln „Erneut scannen“.
                if batchTotal <= 1 { Button("Erneut scannen") { rescan() }.buttonStyle(.quiet) }
            } else if canSave {
                // Alles sicher erkannt: ein Tipp genügt. Wer prüfen will, öffnet das Formular.
                Button("Speichern") { formSeed = FormSeed(outcome: outcome, autoSave: true) }.buttonStyle(.primary)
                HStack(spacing: 10) {
                    Button("Prüfen und ändern") { formSeed = FormSeed(outcome: outcome) }
                        .buttonStyle(.quiet)
                    rescanOrSkip
                }
            } else if outcome.looksLikeVoucher {
                Button("Hinzufügen") {
                    // Mit Warnung (abgelaufen, hoher Wert, Prüfziffer) einmal nachfragen.
                    if outcome.hasWarnings { confirmAddWithWarning = true } else { formSeed = FormSeed(outcome: outcome) }
                }
                .buttonStyle(.primary)
                .confirmationDialog("Trotz Warnung hinzufügen?", isPresented: $confirmAddWithWarning, titleVisibility: .visible) {
                    Button("Hinzufügen und prüfen") { formSeed = FormSeed(outcome: outcome) }
                } message: {
                    let expired = outcome.warningTexts.contains { $0.contains("abgelaufen") }
                    Text(outcome.warningTexts.joined(separator: "\n\n")
                         + (expired ? "\n\nOft trotzdem nicht verloren: Frag beim Laden nach Einlösung oder Erstattung." : "")
                         + "\n\nDu kannst alles im nächsten Schritt korrigieren.")
                }
                rescanOrSkip
            } else if batchTotal > 1 {
                // Mehrere Fotos: Nicht-Gutschein einfach auslassen (auch beim letzten Foto, dann mit Abschlussmeldung).
                skipButton.buttonStyle(.primary)
                Button("Trotzdem von Hand eintragen") { formSeed = FormSeed(outcome: nil) }.buttonStyle(.quiet)
            } else {
                Button("Erneut scannen") { rescan() }.buttonStyle(.primary)
                Button("Trotzdem von Hand eintragen") { formSeed = FormSeed(outcome: nil) }.buttonStyle(.quiet)
            }
        }
        .padding(.horizontal, Layout.page).padding(.top, 10).padding(.bottom, 8)
    }

    /// Mehrere Fotos: aktuelles Ergebnis auslassen, weiter mit dem nächsten.
    private var skipButton: some View {
        Button(batch.isEmpty ? "Überspringen – fertig" : "Überspringen – nächstes Foto") {
            batchSkipped += 1
            withAnimation(reduceMotion ? nil : .smooth) { self.outcome = nil }
            nextFromBatch()
        }
    }

    /// Nebenknopf: einzeln „Erneut scannen“; in einer Mehrfachauswahl „Überspringen“, damit die restlichen Fotos nicht still verloren gehen.
    @ViewBuilder private var rescanOrSkip: some View {
        if batchTotal > 1 {
            skipButton.buttonStyle(.quiet)
        } else {
            Button("Erneut scannen") { rescan() }.buttonStyle(.quiet)
        }
    }

    /// Nächstes Foto aus der Mehrfachauswahl lesen; am Ende eine ehrliche Bilanz.
    private func nextFromBatch() {
        guard !batch.isEmpty else {
            if batchTotal > 1 {
                var parts: [String] = []
                if batchSaved > 0 { parts.append("\(batchSaved) gespeichert") }
                if batchSkipped > 0 { parts.append("\(batchSkipped) übersprungen") }
                if batchUnreadable > 0 { parts.append("\(batchUnreadable) nicht lesbar") }
                router.toast = Toast(message: "\(batchTotal) Fotos: " + parts.joined(separator: ", "), undo: nil)
            }
            batchTotal = 0; batchUnreadable = 0; batchSaved = 0; batchSkipped = 0
            return
        }
        let source = batch.removeFirst()
        read {
            switch source {
            case .file(let url): return await Importer.analyze(url: url)
            case .photo(let item):
                guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                    return ScanOutcome()
                }
                return await Importer.analyze(image: image)
            }
        }
    }

    private func rescan() {
        // Altes Ergebnis bleibt stehen, bis ein neues da ist: Abbrechen im Scanner verliert nichts.
        // Eine laufende Mehrfachauswahl endet hier: sonst käme nach dem Kamera-Scan unerwartet das nächste Foto.
        batch = []; batchTotal = 0; batchUnreadable = 0; batchSaved = 0; batchSkipped = 0
        showScanner = true
    }

    private func show(_ result: ScanOutcome) {
        // Eigener, selbst ausgegebener Gutschein: gleich zur Kasse zum Abbuchen statt ihn neu anzulegen.
        func plain(_ s: String) -> String { s.filter { $0.isLetter || $0.isNumber }.uppercased() }
        if let scanned = result.barcode ?? result.draft.number,
           let own = store.cards.first(where: { $0.issuedByMe && plain($0.number) == plain(scanned) }) {
            withAnimation(reduceMotion ? nil : .smooth) { outcome = nil }
            // Eigener Café-Gutschein in einer Reihe: die Reihe endet hier (Einlösen hat Vorrang).
            batch = []; batchTotal = 0; batchUnreadable = 0; batchSaved = 0; batchSkipped = 0
            router.tab = .home
            router.homePath = [.checkout(own.id)]
            router.toast = Toast(message: "Dein Gutschein: noch \(own.balance.euro) offen", undo: nil)
            return
        }
        var result = result
        // Betrugsmuster: mehrere hohe Gutscheine in kurzer Zeit (oft auf Anweisung von Betrügern gekauft).
        let weekAgo = Date.now.addingTimeInterval(-7 * 24 * 3600)
        // Schon gespeichert? Dann nicht doppelt anlegen, sondern öffnen anbieten.
        if let code = result.displayCode, let dup = store.cards.first(where: { !$0.issuedByMe && !$0.isExample && !$0.number.isEmpty && plain($0.number) == plain(code) }) {
            result.duplicateName = dup.name
            result.duplicateID = dup.id
        }
        result.recentHighValueCount = store.cards.filter { !$0.isExample && !$0.issuedByMe && $0.value >= 100 && $0.addedOrReceived >= weekAgo }.count
        // Erst nach Dublette und Betrugsmuster entscheiden: beide schließen „Speichern mit einem Tipp“ aus.
        result.canSave = result.canSaveDirectly
        withAnimation(reduceMotion ? nil : .smooth) { outcome = result }
        #if DEBUG
        // Nur für Screenshots: `-demoOpenForm YES` öffnet nach dem Lesen gleich das Formular.
        if UserDefaults.standard.bool(forKey: "demoOpenForm") {
            formSeed = FormSeed(outcome: result, autoSave: UserDefaults.standard.bool(forKey: "demoAutoSave"))
        }
        #endif
    }

    /// Erst hier wird die Zwischenablage gelesen (iOS fragt dann ggf. nach Erlaubnis).
    private func pasteFromClipboard() {
        guard let text = UIPasteboard.general.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            importError = "In der Zwischenablage ist kein Text. Kopier zuerst den Text der Gutschein-E-Mail."
            return
        }
        read { await Importer.analyze(text: text) }
    }
}

#if DEBUG
extension ScanView {
    /// Nur einmal je Start (Launch-Argumente lassen sich nicht entfernen).
    @MainActor static var demoBatchDone = false
}
#endif

/// Ein Eintrag der Mehrfachauswahl: Foto aus der Mediathek oder (für Screenshots) eine Datei.
private enum BatchSource {
    case photo(PhotosPickerItem)
    case file(URL)
}

/// Startwert für das Formular; identifiziert über eine eigene ID.
struct FormSeed: Identifiable, Hashable {
    let id = UUID()
    let outcome: ScanOutcome?
    /// Direkt speichern (alles sicher erkannt), Formular nur bei Problemen zeigen.
    var autoSave = false

    static func == (a: FormSeed, b: FormSeed) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

private struct SourceRow: View {
    let icon: String
    let title: String
    let subtitle: String?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.scaled(17)).foregroundStyle(Color.ink2).frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.scaled(16, weight: .semibold)).foregroundStyle(Color.ink)
                if let subtitle {
                    Text(subtitle).font(.scaled(13)).foregroundStyle(Color.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.scaled(13, weight: .semibold)).foregroundStyle(Color.muted)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14).padding(.vertical, Layout.group)
        .frame(minHeight: Layout.tap)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// E-Mail-Text einfügen und auswerten.
private struct EmailImportSheet: View {
    var hasClipboard: Bool
    var onAnalyze: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Kopier in Mail den Text der Gutschein-E-Mail und füg ihn hier ein. Rest\u{2060}wert sucht Laden, Wert, Code, PIN und Ablaufdatum heraus.")
                    .font(.scaled(15)).foregroundStyle(Color.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                if hasClipboard {
                    // Systemknopf: liest die Zwischenablage erst beim Tipp, ohne Rückfrage.
                    PasteButton(payloadType: String.self) { strings in
                        Task { @MainActor in text = strings.joined(separator: "\n") }
                    }
                    .labelStyle(.titleAndIcon)
                    .tint(Color.ink)
                }
                TextEditor(text: $text)
                    .font(.scaled(15))
                    .accessibilityLabel("Text der E-Mail")
                    .scrollContentBackground(.hidden)
                    .padding(Layout.group)
                    .background(Color.fill, in: .rect(cornerRadius: Layout.buttonRadius, style: .continuous))
                Button("Auswerten") {
                    dismiss()
                    onAnalyze(text)
                }
                .buttonStyle(.primary)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(16)
            .navigationTitle("Aus E-Mail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen", systemImage: "xmark") { dismiss() } }
            }
        }
        .presentationDetents([.large])
    }
}

/// Großer Einstieg in den Kamera-Scanner.
/// Im Hellen Tinte mit weißer Schrift; im Dunkeln eine dunkle Fläche mit Kante, damit das Ticket nicht blendet.
struct ViewfinderTeaser: View {
    @Environment(\.colorScheme) private var scheme

    private var dark: Bool { scheme == .dark }
    private var fill: Color { dark ? .fill : .ink }
    private var text: Color { dark ? .ink : .onInk }

    var body: some View {
        let shape = TicketShape(radius: Layout.cardRadius, notchRadius: 9, notchY: 0.5)
        VStack(alignment: .leading, spacing: 0) {
            ViewfinderCorners()
                .stroke(text.opacity(0.9), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 64, height: 44)
                .accessibilityHidden(true)
            Spacer(minLength: 28)
            Text("Gutschein scannen").font(.scaled(22, weight: .bold))
            Text("Barcode und Text auf der Rückseite werden automatisch gelesen.")
                .font(.scaled(15)).foregroundStyle(text.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
        .foregroundStyle(text)
        .padding(Layout.ticketInset)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .leading)
        // Hauptaktion als Ticket: hier entsteht ein neuer Gutschein.
        .background(fill, in: shape)
        .overlay { if dark { shape.stroke(Color.line, lineWidth: 1) } }
        .contentShape(.rect)
    }
}

/// Vier Eckwinkel eines Suchers, sauber an den Ecken des Rahmens.
struct ViewfinderCorners: Shape {
    var length: CGFloat = 14

    func path(in r: CGRect) -> Path {
        var p = Path()
        let l = min(length, r.width / 2, r.height / 2)
        p.move(to: CGPoint(x: r.minX, y: r.minY + l)); p.addLine(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.minX + l, y: r.minY))
        p.move(to: CGPoint(x: r.maxX - l, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY + l))
        p.move(to: CGPoint(x: r.maxX, y: r.maxY - l)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX - l, y: r.maxY))
        p.move(to: CGPoint(x: r.minX + l, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY - l))
        return p
    }
}

/// Gelbe Scanlinie, die zeitgesteuert über den Sucher läuft.
struct ScanLine: View {
    var travel: ClosedRange<Double> = 0.18...0.62
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            // Bewegung reduzieren: Linie steht still in der Mitte.
            TimelineView(.animation(paused: reduceMotion)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let wave = reduceMotion ? 0.5 : (sin(t * 2 * .pi / 3.2) + 1) / 2
                let y = travel.lowerBound + (travel.upperBound - travel.lowerBound) * wave
                Rectangle()
                    .fill(LinearGradient(colors: [Color.brandYellow.opacity(0), Color.brandYellow.opacity(0.4)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(height: 50)
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.brandYellow).frame(height: 3) }
                    .padding(.horizontal, 36)
                    .offset(y: geo.size.height * y - 50)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
