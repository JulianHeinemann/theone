import SwiftUI
import AVFoundation
import PhotosUI
import VisionKit
import Vision
import RestwertKit

/// Live-Scanner mit der Kamera: findet Barcodes und Text, auch Handschrift.
struct LiveScannerView: View {
    var onDone: (ScanOutcome) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = LiveScanModel()
    @State private var access = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var photoItem: PhotosPickerItem?
    @State private var reading = false
    @State private var loadFailed = false
    @State private var capturing = false
    @State private var torchOn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Simulator und Geräte ohne Neural Engine haben keinen Live-Scanner.
    private var supported: Bool { DataScannerViewController.isSupported }
    private var canUse: Bool { supported && access == .authorized && DataScannerViewController.isAvailable && !model.startFailed }
    private var denied: Bool { access == .denied }
    private var hasSomething: Bool { model.barcode != nil || !model.texts.isEmpty }

    var body: some View {
        ZStack(alignment: .bottom) {
            if canUse {
                DataScannerRepresentable(model: model).ignoresSafeArea()
                ScanLine()
                controls
                    .overlay(alignment: .topLeading) { torchButton.offset(y: -64) }
            } else if supported && access == .notDetermined {
                Color.black.ignoresSafeArea()
            } else {
                fallback
            }
        }
        .task {
            // Beim ersten Öffnen direkt nach der Kamera fragen, statt eine Fehlermeldung zu zeigen.
            guard supported, access == .notDetermined else { return }
            _ = await AVCaptureDevice.requestAccess(for: .video)
            access = AVCaptureDevice.authorizationStatus(for: .video)
        }
        .onChange(of: scenePhase) { _, phase in
            // Nach dem Umweg über die Einstellungen die neue Freigabe übernehmen.
            if phase == .active { access = AVCaptureDevice.authorizationStatus(for: .video) }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil // gleiches Foto bleibt erneut wählbar
            Task {
                reading = true
                defer { reading = false }
                guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                    loadFailed = true
                    return
                }
                let result = await Importer.analyze(image: image)
                onDone(result)
                dismiss()
            }
        }
        .overlay(alignment: .topTrailing) {
            Button("Schließen", systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly)
                .font(.scaled(17, weight: .bold))
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .padding(16)
        }
        .onDisappear { setTorch(false) }
        .sensoryFeedback(.success, trigger: model.barcode)
        .onChange(of: model.barcode) { _, code in
            if code != nil { AccessibilityNotification.Announcement("\(model.format?.label ?? "Barcode") erkannt").post() }
        }
        .alert("Foto konnte nicht geladen werden", isPresented: $loadFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Prüf die Verbindung (iCloud-Foto) oder wähl ein anderes Foto.")
        }
    }

    /// Ohne Kamera (Simulator) oder ohne Erlaubnis: gleicher Scan, aber aus einem Foto.
    /// Passt der Inhalt nicht (große Schrift), wird gescrollt.
    private var fallback: some View {
        ViewThatFits(in: .vertical) {
            fallbackContent(spacers: true)
            ScrollView { fallbackContent(spacers: false).padding(.top, 60) }
        }
        .foregroundStyle(Color.ink)
        .pageBackground()
    }

    private var fallbackTitle: String {
        !supported ? "Keine Kamera verfügbar" : denied ? "Kamera nicht freigegeben"
            : model.startFailed ? "Kamera ließ sich nicht starten" : "Scanner gerade nicht verfügbar"
    }

    private var fallbackText: String {
        if !supported { return "Auf diesem Gerät läuft der Live-Scan nicht, zum Beispiel im Simulator. Wähl ein Foto des Gutscheins. Barcode und Text werden genauso gelesen." }
        if denied { return "Erlaube Restwert in den Einstellungen den Zugriff auf die Kamera. Oder wähl ein Foto des Gutscheins. Es wird genauso gelesen." }
        return "Die Kamera ist im Moment gesperrt oder belegt. Wähl ein Foto des Gutscheins. Es wird genauso gelesen."
    }

    private func fallbackContent(spacers: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if spacers { Spacer() }
            Image(systemName: supported ? "camera.fill" : "photo.on.rectangle")
                .font(.scaled(28)).foregroundStyle(Color.ink2)
                .accessibilityHidden(true)
            Text(fallbackTitle)
                .font(.scaled(22, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            Text(fallbackText)
                .font(.scaled(15)).foregroundStyle(Color.ink2)
                .fixedSize(horizontal: false, vertical: true)
            if spacers { Spacer() }
            let pickTitle = reading ? "Wird gelesen …" : "Foto des Gutscheins wählen"
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label(pickTitle, systemImage: "photo")
            }
            .buttonStyle(.accent)
            .disabled(reading)
            if supported && denied {
                Button("Kamera in Einstellungen erlauben") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(.quiet)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Standbild aufnehmen und gründlich auswerten (Kontrast, Ausschnitte), mit dem Live-Ergebnis zusammenführen.
    /// So kommt man immer weiter – auch wenn der Live-Scan nichts sicher erkannt hat.
    private func finish() async {
        capturing = true
        defer { capturing = false }
        let still = await model.captureImage()
        var outcome = ScanOutcome(barcode: model.barcode, format: model.format, text: model.orderedText)
        if let still, let cg = still.normalizedCGImage {
            let deep = await Importer.analyze(cgImage: cg)
            // Live-Barcode ist bestätigt (mehrfach gesehen); sonst den aus dem Standbild nehmen.
            if outcome.barcode == nil || !model.barcodeConfirmed, let b = deep.barcode {
                outcome.barcode = b
                outcome.format = deep.format
            }
            if deep.text.count > outcome.text.count { outcome.text = deep.text }
            outcome.smart = deep.smart
            outcome.usedAppleIntelligence = deep.usedAppleIntelligence
            outcome.photo = still.thumbnailJPEG()
        }
        setTorch(false)
        onDone(outcome)
        dismiss()
    }

    private var torchButton: some View {
        Button {
            setTorch(!torchOn)
        } label: {
            Image(systemName: torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                .font(.scaled(17, weight: .semibold))
                .frame(width: Layout.tap, height: Layout.tap)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .padding(.leading, 16)
        .accessibilityLabel(torchOn ? "Licht aus" : "Licht an")
        .opacity(AVCaptureDevice.default(for: .video)?.hasTorch == true ? 1 : 0)
    }

    /// Taschenlampe für dunkle Läden. Fehler (keine Lampe, belegt) werden still ignoriert.
    private func setTorch(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch, (try? device.lockForConfiguration()) != nil else { return }
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
        torchOn = on && device.torchMode == .on
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: model.barcode == nil ? "barcode.viewfinder" : "checkmark.circle.fill")
                    .font(.scaled(22, weight: .semibold))
                    .foregroundStyle(model.barcode == nil ? Color.ink2 : Color.good)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.barcode == nil ? "Halte die Rückseite ins Bild" : "\(model.format?.label ?? "Barcode") erkannt")
                        .font(.scaled(15, weight: .bold))
                    Text(model.barcode?.grouped ?? "\(model.texts.count) Textzeilen erkannt, auch Handschrift")
                        .font(.scaled(13)).foregroundStyle(Color.ink2).lineLimit(2)
                        .contentTransition(.numericText())
                }
                Spacer()
            }
            .foregroundStyle(Color.ink)
            .accessibilityElement(children: .combine)
            Button {
                Task { await finish() }
            } label: {
                Text(capturing ? "Wird gelesen …" : hasSomething ? "Übernehmen" : "Foto aufnehmen und lesen")
            }
            .buttonStyle(.accent)
            .disabled(capturing)
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: Layout.cardRadius, style: .continuous))
        .padding(16)
        .animation(reduceMotion ? nil : .smooth, value: model.barcode)
    }
}

@Observable
final class LiveScanModel {
    /// Erkannte Zeile mit Position, für die Leserichtung.
    struct TextLine {
        let text: String
        let top: CGFloat
        let left: CGFloat
    }

    var barcode: String?
    var format: CodeFormat?
    /// Barcode ist bestätigt: mindestens zweimal gleich gelesen oder mit gültiger Prüfziffer.
    var barcodeConfirmed = false
    var texts: [UUID: TextLine] = [:]
    /// Kamera ließ sich nicht starten – dann zeigt die Ansicht den Foto-Weg.
    var startFailed = false
    @ObservationIgnored weak var controller: DataScannerViewController?
    /// Wie oft jeder Code gesehen wurde – ein einzelner Fehlscan soll nicht gewinnen.
    @ObservationIgnored private var sightings: [ScanReading.Code: Int] = [:]

    func handle(_ items: [RecognizedItem]) {
        for item in items {
            switch item {
            case .barcode(let b):
                guard let payload = b.payloadStringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !payload.isEmpty else { continue }
                let f = CodeFormat(vision: b.observation.symbology)
                // UPC-E als UPC-A mit 12 Ziffern, damit Prüfziffer und Barcode stimmen
                let value = b.observation.symbology == .upce ? (BarcodeEncoder.expandUPCE(payload) ?? payload) : payload
                let code = ScanReading.Code(payload: value, format: f)
                sightings[code, default: 0] += 1
                chooseBarcode()
            case .text(let t):
                texts[item.id] = TextLine(text: t.transcript,
                                          top: min(t.bounds.topLeft.y, t.bounds.topRight.y), left: t.bounds.topLeft.x)
            @unknown default:
                break
            }
        }
    }

    func remove(_ items: [RecognizedItem]) {
        // Text von früheren Kamerapositionen nicht mitschleppen; Barcodes bleiben (sie sind gezählt).
        for item in items { if case .text = item { texts[item.id] = nil } }
    }

    /// Bester Kandidat: bestätigte Codes zuerst, dann nach Kassen-Tauglichkeit (Strichcode, Prüfziffer, Länge) und Häufigkeit.
    private func chooseBarcode() {
        func confirmed(_ c: ScanReading.Code) -> Bool {
            (sightings[c] ?? 0) >= 2 || BarcodeEncoder.hasValidChecksum(c.payload, format: c.format) == true
        }
        let best = sightings.keys.max { a, b in
            let ka = (confirmed(a) ? 10_000 : 0) + VoucherScanner.score(a) + min(sightings[a] ?? 0, 50)
            let kb = (confirmed(b) ? 10_000 : 0) + VoucherScanner.score(b) + min(sightings[b] ?? 0, 50)
            return ka < kb
        }
        guard let best else { return }
        if barcode != best.payload { barcode = best.payload; format = best.format }
        barcodeConfirmed = confirmed(best)
    }

    /// Zeilen in Leserichtung: oben nach unten, in einer Zeile links nach rechts.
    var orderedText: String {
        texts.values
            .sorted { abs($0.top - $1.top) > 8 ? $0.top < $1.top : $0.left < $1.left }
            .map(\.text).joined(separator: "\n")
    }

    /// Standbild in voller Auflösung für die gründliche Auswertung.
    func captureImage() async -> UIImage? {
        guard let controller else { return nil }
        return try? await controller.capturePhoto()
    }
}

private extension CodeFormat {
    init(vision symbology: VNBarcodeSymbology) {
        switch symbology {
        case .ean13: self = .ean13
        case .ean8: self = .ean8
        case .upce: self = .upca
        case .itf14, .i2of5, .i2of5Checksum: self = .itf
        case .code39, .code39Checksum, .code39FullASCII, .code39FullASCIIChecksum: self = .code39
        case .qr, .microQR: self = .qr
        case .pdf417, .microPDF417: self = .pdf417
        case .aztec: self = .aztec
        case .dataMatrix: self = .dataMatrix
        default: self = .code128
        }
    }
}

private struct DataScannerRepresentable: UIViewControllerRepresentable {
    let model: LiveScanModel

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode(), .text(languages: ["de-DE", "en-US"])],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        model.controller = vc
        start(vc)
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        if !vc.isScanning && !model.startFailed { start(vc) }
    }

    /// Start kann scheitern (Kamera belegt, gesperrt) – dann nicht schwarz bleiben, sondern den Foto-Weg zeigen.
    private func start(_ vc: DataScannerViewController) {
        do { try vc.startScanning() } catch {
            let model = model
            Task { @MainActor in model.startFailed = true }
        }
    }

    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: Coordinator) {
        vc.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let model: LiveScanModel
        init(model: LiveScanModel) { self.model = model }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            model.handle(addedItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            model.handle(updatedItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            model.handle([item])
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didRemove removedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            model.remove(removedItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            model.startFailed = true
        }
    }
}
