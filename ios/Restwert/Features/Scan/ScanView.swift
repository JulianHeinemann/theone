import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import RestwertKit

/// Scannen → Ergebnis prüfen → Formular. Alternativ Foto, E-Mail, Datei oder manuell.
struct ScanView: View {
    @Environment(Router.self) private var router

    @State private var outcome: ScanOutcome?
    @State private var busy = false
    @State private var showScanner = false
    @State private var showFiles = false
    @State private var showEmail = false
    @State private var photoItem: PhotosPickerItem?
    @State private var formSeed: FormSeed?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let outcome {
                    ScanResultView(outcome: outcome,
                                   onAdd: { formSeed = FormSeed(outcome: outcome) },
                                   onRescan: {
                                       withAnimation(.smooth) { self.outcome = nil }
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
            .padding(.horizontal, 16).padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .pageBackground()
        .navigationTitle(outcome == nil ? "Hinzufügen" : "Ergebnis")
        .toolbar {
            if outcome != nil {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Zurück", systemImage: "chevron.left") { withAnimation(.smooth) { outcome = nil } }
                }
            }
        }
        .overlay {
            if busy {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.large)
                    Text(SmartExtractor.isAvailable ? "Wird gelesen …" : "Wird gelesen …")
                        .font(.scaled(15, weight: .semibold))
                }
                .padding(28)
                .glassEffect(.regular, in: .rect(cornerRadius: 24, style: .continuous))
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .animation(.smooth, value: busy)
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
            if case .success(let url) = result { Task { await run { await Importer.analyze(url: url) } } }
        }
        .sheet(isPresented: $showEmail) {
            EmailImportSheet { text in Task { await run { await Importer.analyze(text: text) } } }
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
            guard let url = router.pendingImport else { return }
            router.pendingImport = nil
            await run { await Importer.analyze(url: url) }
        }
    }

    // MARK: Quellen

    private var sources: some View {
        VStack(alignment: .leading, spacing: 20) {
            Button { showScanner = true } label: { ViewfinderTeaser() }
                .buttonStyle(.plain)
            VStack(spacing: 0) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    SourceRow(icon: "photo", title: "Aus Fotos", subtitle: "Foto oder Screenshot eines Gutscheins")
                }
                Divider().padding(.leading, 56)
                Button { showEmail = true } label: {
                    SourceRow(icon: "envelope", title: "Aus einer E-Mail", subtitle: "Text der Mail einfügen")
                }
                Divider().padding(.leading, 56)
                Button { showFiles = true } label: {
                    SourceRow(icon: "doc", title: "Aus einer Datei", subtitle: "PDF oder Bild, z. B. aus einem Mail-Anhang")
                }
                Divider().padding(.leading, 56)
                Button { formSeed = FormSeed(outcome: nil) } label: {
                    SourceRow(icon: "keyboard", title: "Von Hand eingeben", subtitle: nil)
                }
            }
            .buttonStyle(.plain)
            .background(Color.surface, in: .rect(cornerRadius: 18, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Label("PDF aus einer Mail übernehmen", systemImage: "envelope.open").font(.scaled(15, weight: .semibold))
                Text("1. Anhang in Mail lange drücken  2. „Teilen“  3. Restwert wählen")
                    .font(.scaled(14)).foregroundStyle(Color.ink2)
            }
            .foregroundStyle(Color.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.surface, in: .rect(cornerRadius: 18, style: .continuous))
            Label("Texterkennung läuft nur auf deinem iPhone.", systemImage: "lock")
                .font(.scaled(13)).foregroundStyle(Color.muted).padding(.horizontal, 4)
        }
        .padding(.top, 8)
    }

    // MARK: Logik

    private func run(_ work: () async -> ScanOutcome) async {
        busy = true
        let result = await work()
        busy = false
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
        withAnimation(.smooth) { outcome = result }
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
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.scaled(16)).foregroundStyle(Color.ink)
                if let subtitle { Text(subtitle).font(.scaled(13)).foregroundStyle(Color.muted) }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.scaled(13, weight: .semibold)).foregroundStyle(Color.muted.opacity(0.7))
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
        .contentShape(.rect)
    }
}

/// E-Mail-Text einfügen und auswerten.
private struct EmailImportSheet: View {
    var onAnalyze: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Kopier in Mail den Text der Gutschein-E-Mail und füg ihn hier ein. Restwert sucht Shop, Wert, Code, PIN und Ablaufdatum heraus.")
                    .font(.scaled(14)).foregroundStyle(Color.ink2)
                PasteButton(payloadType: String.self) { strings in
                    Task { @MainActor in text = strings.joined(separator: "\n") }
                }
                .labelStyle(.titleAndIcon)
                TextEditor(text: $text)
                    .font(.scaled(14))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(Color.fill, in: .rect(cornerRadius: 16, style: .continuous))
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
struct ViewfinderTeaser: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ViewfinderCorners()
                .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 64, height: 44)
            Spacer(minLength: 28)
            Text("Karte scannen").font(.scaled(22, weight: .bold))
            Text("Barcode und Text auf der Rückseite werden automatisch gelesen.")
                .font(.scaled(14)).foregroundStyle(.white.opacity(0.7))
                .padding(.top, 4)
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .leading)
        .background(Color(light: 0x0E0E10, dark: 0x26262B), in: .rect(cornerRadius: 22, style: .continuous))
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

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let wave = (sin(t * 2 * .pi / 3.2) + 1) / 2
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
    }
}
