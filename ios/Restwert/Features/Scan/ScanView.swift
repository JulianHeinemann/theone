import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import RestwertKit

/// Scannen → Ergebnis prüfen → Formular. Alternativ Foto, E-Mail, Datei oder manuell.
struct ScanView: View {
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var outcome: ScanOutcome?
    @State private var busy = false
    @State private var showScanner = false
    @State private var showFiles = false
    @State private var showEmail = false
    @State private var photoItem: PhotosPickerItem?
    @State private var formSeed: FormSeed?
    @State private var importError: String?
    /// Nur ob Text in der Zwischenablage liegt; gelesen wird erst nach einem Tipp.
    @State private var clipboardHasText = UIPasteboard.general.hasStrings

    /// Wunsch aus dem Einstieg einlösen: Kamera oder Formular öffnen.
    private func consumeIntent() {
        guard let intent = router.scanIntent else { return }
        router.scanIntent = nil
        switch intent {
        case .camera: showScanner = true
        case .manual: formSeed = FormSeed(outcome: nil)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let outcome {
                    ScanResultView(outcome: outcome,
                                   onAdd: { formSeed = FormSeed(outcome: outcome) },
                                   onRescan: {
                                       withAnimation(reduceMotion ? nil : .smooth) { self.outcome = nil }
                                       showScanner = true
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
            .padding(.horizontal, Layout.page).padding(.bottom, Layout.tap * 2)
        }
        .scrollIndicators(.hidden)
        .pageBackground()
        .onAppear(perform: consumeIntent)
        .onChange(of: router.scanIntent != nil) { _, _ in consumeIntent() }
        .navigationTitle(outcome == nil ? "Hinzufügen" : "Ergebnis")
        .toolbar {
            if outcome != nil {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Zurück", systemImage: "chevron.left") { withAnimation(reduceMotion ? nil : .smooth) { outcome = nil } }
                }
            }
        }
        .overlay {
            if busy {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.large)
                    Text("Wird gelesen …")
                        .font(.scaled(15, weight: .semibold))
                }
                .accessibilityElement(children: .combine)
                .padding(28)
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
            CardFormView(outcome: seed.outcome) { saved in
                formSeed = nil
                outcome = nil
                router.showCard(saved.id)
            }
        }
        .fullScreenCover(isPresented: $showScanner) {
            LiveScannerView { live in Task { await finishLive(live) } }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.pdf, .image, .plainText, .text]) { result in
            switch result {
            case .success(let url): Task { await run { await Importer.analyze(url: url) } }
            case .failure: importError = "Datei konnte nicht geöffnet werden."
            }
        }
        .sheet(isPresented: $showEmail) {
            EmailImportSheet(hasClipboard: clipboardHasText) { text in Task { await run { await Importer.analyze(text: text) } } }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task {
                await run {
                    guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                        return ScanOutcome()
                    }
                    return await Importer.analyze(image: image)
                }
            }
        }
        .task(id: router.pendingImport) {
            // Erst nach der Analyse zurücksetzen: eine neue task-id würde diesen Task sonst abbrechen.
            guard let url = router.pendingImport else { return }
            await run { await Importer.analyze(url: url) }
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
                Label("Texterkennung läuft nur auf deinem iPhone.", systemImage: "lock")
                    .font(.scaled(13)).foregroundStyle(Color.ink2).padding(.horizontal, 4)
            }
            VStack(alignment: .leading, spacing: Layout.group) {
                Text("Oder anders hinzufügen").font(.scaled(15, weight: .semibold)).foregroundStyle(Color.ink2)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        SourceRow(icon: "photo", title: "Aus Fotos", subtitle: "Foto oder Screenshot eines Gutscheins")
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
                }
                .buttonStyle(.plain)
                .background(Color.surface, in: .rect(cornerRadius: Layout.cardRadius, style: .continuous))
                .animation(reduceMotion ? nil : .smooth, value: clipboardHasText)
            }
        }
        .padding(.top, 8)
    }

    // MARK: Logik

    private func run(_ work: () async -> ScanOutcome) async {
        // Offenes Formular schließen, damit das neue Ergebnis sichtbar wird
        formSeed = nil
        busy = true
        let result = await work()
        busy = false
        if result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && result.barcode == nil && result.photo == nil {
            importError = "Datei oder Foto konnte nicht gelesen werden. Versuch ein anderes Format oder gib den Gutschein von Hand ein."
            return
        }
        show(result)
    }

    /// Live-Scan liefert Barcode und Text; Apple Intelligence strukturiert den Text danach.
    private func finishLive(_ live: ScanOutcome) async {
        await run {
            var result = live
            if let smart = await SmartExtractor.extract(from: live.text) {
                result.smart = smart
                result.usedAppleIntelligence = true
            }
            return result
        }
    }

    private func show(_ result: ScanOutcome) {
        withAnimation(reduceMotion ? nil : .smooth) { outcome = result }
    }

    /// Erst hier wird die Zwischenablage gelesen (iOS fragt dann ggf. nach Erlaubnis).
    private func pasteFromClipboard() {
        guard let text = UIPasteboard.general.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            importError = "In der Zwischenablage ist kein Text. Kopier zuerst den Text der Gutschein-E-Mail."
            return
        }
        Task { await run { await Importer.analyze(text: text) } }
    }
}

/// Startwert für das Formular; identifiziert über eine eigene ID.
struct FormSeed: Identifiable, Hashable {
    let id = UUID()
    let outcome: ScanOutcome?

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
