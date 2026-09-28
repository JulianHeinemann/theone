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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Simulator und Geräte ohne Neural Engine haben keinen Live-Scanner.
    private var supported: Bool { DataScannerViewController.isSupported }
    private var canUse: Bool { supported && access == .authorized && DataScannerViewController.isAvailable }
    private var denied: Bool { access == .denied }
    private var hasSomething: Bool { model.barcode != nil || !model.texts.isEmpty }

    var body: some View {
        ZStack(alignment: .bottom) {
            if canUse {
                DataScannerRepresentable(model: model).ignoresSafeArea()
                ScanLine()
                controls
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
        !supported ? "Keine Kamera verfügbar" : denied ? "Kamera nicht freigegeben" : "Scanner gerade nicht verfügbar"
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
                Task {
                    let photo = await model.capturePhoto()
                    onDone(ScanOutcome(barcode: model.barcode, format: model.format,
                                       text: model.orderedText, photo: photo, source: .camera))
                    dismiss()
                }
            } label: {
                Text("Übernehmen")
            }
            .buttonStyle(.accent)
            .disabled(!hasSomething)
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
    var texts: [UUID: TextLine] = [:]
    @ObservationIgnored weak var controller: DataScannerViewController?

    func handle(_ items: [RecognizedItem]) {
        for item in items {
            switch item {
            case .barcode(let b):
                guard let payload = b.payloadStringValue, !payload.isEmpty else { continue }
                let f = CodeFormat(vision: b.observation.symbology)
                // UPC-E als UPC-A mit 12 Ziffern, damit Prüfziffer und Barcode stimmen
                let value = b.observation.symbology == .upce ? (BarcodeEncoder.expandUPCE(payload) ?? payload) : payload
                // Strichcode behalten, sobald einer gefunden ist; 2D-Codes nur als Notlösung
                if barcode == nil || (format?.isTwoDimensional == true && !f.isTwoDimensional) {
                    barcode = value
                    format = f
                }
            case .text(let t):
                texts[item.id] = TextLine(text: t.transcript,
                                          top: min(t.bounds.topLeft.y, t.bounds.topRight.y), left: t.bounds.topLeft.x)
            @unknown default:
                break
            }
        }
    }

    /// Zeilen in Leserichtung: oben nach unten, in einer Zeile links nach rechts.
    var orderedText: String {
        texts.values
            .sorted { abs($0.top - $1.top) > 8 ? $0.top < $1.top : $0.left < $1.left }
            .map(\.text).joined(separator: "\n")
    }

    func capturePhoto() async -> Data? {
        guard let controller, let image = try? await controller.capturePhoto() else { return nil }
        return image.thumbnailJPEG()
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
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        if !vc.isScanning { try? vc.startScanning() }
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
    }
}
