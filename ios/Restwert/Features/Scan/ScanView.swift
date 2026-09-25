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
        .navigationTitle(outcome == nil ? "Scannen" : "Ergebnis")
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
                    Text(SmartExtractor.isAvailable ? "Wird gelesen, Apple Intelligence hilft …" : "Wird gelesen …")
                        .font(.system(size: 15, weight: .semibold))
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
        VStack(alignment: .leading, spacing: 16) {
            Button { showScanner = true } label: { ViewfinderTeaser() }
                .buttonStyle(.plain)
            Text("Oder auf anderem Weg").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.muted).padding(.top, 4)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    SourceTile(icon: "photo", title: "Foto", subtitle: "Auch Screenshots und Handschrift", color: Pastel.all[0])
                }
                .buttonStyle(.plain)
                Button { showEmail = true } label: {
                    SourceTile(icon: "envelope", title: "E-Mail", subtitle: "Text einfügen", color: Pastel.all[1])
                }
                .buttonStyle(.plain)
                Button { showFiles = true } label: {
                    SourceTile(icon: "doc.richtext", title: "PDF / Datei", subtitle: "Aus Mail-Anhang oder Dateien", color: Pastel.all[2])
                }
                .buttonStyle(.plain)
                Button { formSeed = FormSeed(outcome: nil) } label: {
                    SourceTile(icon: "keyboard", title: "Manuell", subtitle: "Alles selbst eintippen", color: Pastel.all[4])
                }
                .buttonStyle(.plain)
            }
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "square.and.arrow.up")
                Text("Tipp: In Mail einen Gutschein-Anhang lange drücken, „Teilen“ und dann Restwert wählen.")
            }
            .font(.system(size: 13.5)).foregroundStyle(Color.ink2)
            .padding(14)
            .background(Color.surface, in: .rect(cornerRadius: 18, style: .continuous))
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

private struct SourceTile: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon).font(.system(size: 19, weight: .semibold)).foregroundStyle(Color.ink)
                .frame(width: 44, height: 44)
                .background(color, in: .rect(cornerRadius: 14, style: .continuous))
            Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(Color.ink)
            Text(subtitle).font(.system(size: 12.5)).foregroundStyle(Color.muted).lineLimit(2, reservesSpace: true)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: 22)
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
                    .font(.system(size: 14)).foregroundStyle(Color.ink2)
                PasteButton(payloadType: String.self) { strings in
                    Task { @MainActor in text = strings.joined(separator: "\n") }
                }
                .labelStyle(.titleAndIcon)
                TextEditor(text: $text)
                    .font(.system(size: 14))
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

/// Kamera-Sucher-Vorschau mit laufender Scanlinie; öffnet den echten Scanner.
struct ViewfinderTeaser: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color(hex: 0xE9ECF2))
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.ink, style: StrokeStyle(lineWidth: 2.5, dash: [26, 200]))
                .padding(28)
            ScanLine(travel: 0.18...0.72)
            VStack(spacing: 10) {
                Image(systemName: "camera.viewfinder").font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .frame(width: 58, height: 58)
                    .glassEffect(.regular.tint(Color.brandYellow).interactive(), in: .circle)
                    .symbolEffect(.breathe)
                Text("Gutschein scannen").font(.system(size: 18, weight: .bold)).foregroundStyle(Color.ink)
                Text("Barcode, gedruckter Text und Handschrift").font(.system(size: 13)).foregroundStyle(Color.muted)
            }
        }
        .aspectRatio(1.45, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 28, style: .continuous))
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
