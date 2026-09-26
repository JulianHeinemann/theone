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

    /// Simulator und Geräte ohne Neural Engine haben keinen Live-Scanner.
    private var supported: Bool { DataScannerViewController.isSupported }
    private var canUse: Bool { supported && access == .authorized && DataScannerViewController.isAvailable }
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
            Task {
                reading = true
                defer { reading = false }
                guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
                let result = await Importer.analyze(image: image)
                onDone(result)
                dismiss()
            }
        }
        .overlay(alignment: .topTrailing) {
            Button("Schließen", systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly)
                .font(.system(size: 17, weight: .bold))
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .padding(16)
        }
        .sensoryFeedback(.success, trigger: model.barcode)
    }

    /// Ohne Kamera (Simulator) oder ohne Erlaubnis: gleicher Scan, aber aus einem Foto.
    private var fallback: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer()
            Image(systemName: supported ? "camera.fill" : "photo.on.rectangle")
                .font(.system(size: 30)).foregroundStyle(Color.ink2)
            Text(supported ? "Kamera nicht freigegeben" : "Keine Kamera verfügbar")
                .font(.system(size: 22, weight: .bold))
            Text(supported
                 ? "Erlaube Restwert in den Einstellungen den Zugriff auf die Kamera. Oder wähl ein Foto der Karte, das wird genauso gelesen."
                 : "Auf diesem Gerät läuft der Live-Scan nicht, zum Beispiel im Simulator. Wähl ein Foto der Karte, Barcode und Text werden genauso gelesen.")
                .font(.system(size: 15)).foregroundStyle(Color.ink2)
            Spacer()
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label(reading ? "Wird gelesen …" : "Foto der Karte wählen", systemImage: "photo")
            }
            .buttonStyle(.accent)
            .disabled(reading)
            if supported {
                Button("Kamera in Einstellungen erlauben") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(.quiet)
            }
        }
        .foregroundStyle(Color.ink)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pageBackground()
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: model.barcode == nil ? "barcode.viewfinder" : "checkmark.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(model.barcode == nil ? Color.muted : Color.good)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.barcode == nil ? "Halte die Rückseite ins Bild" : "\(model.format?.label ?? "Barcode") erkannt")
                        .font(.system(size: 15, weight: .bold))
                    Text(model.barcode ?? "\(model.texts.count) Textzeilen erkannt, auch Handschrift")
                        .font(.system(size: 13)).foregroundStyle(Color.ink2).lineLimit(1)
                        .contentTransition(.numericText())
                }
                Spacer()
            }
            .foregroundStyle(Color.ink)
            Button {
                Task {
                    let photo = await model.capturePhoto()
                    onDone(ScanOutcome(barcode: model.barcode, format: model.format,
                                       text: model.texts.values.joined(separator: "\n"), photo: photo))
                    dismiss()
                }
            } label: {
                Text("Übernehmen")
            }
            .buttonStyle(.accent)
            .disabled(!hasSomething)
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 28, style: .continuous))
        .padding(16)
        .animation(.smooth, value: model.barcode)
    }
}

@Observable
final class LiveScanModel {
    var barcode: String?
    var format: CodeFormat?
    var texts: [UUID: String] = [:]
    @ObservationIgnored weak var controller: DataScannerViewController?

    func handle(_ items: [RecognizedItem]) {
        for item in items {
            switch item {
            case .barcode(let b):
                guard let payload = b.payloadStringValue, !payload.isEmpty else { continue }
                let f = CodeFormat(vision: b.observation.symbology)
                // Strichcode behalten, sobald einer gefunden ist; 2D-Codes nur als Notlösung
                if barcode == nil || (format?.isTwoDimensional == true && !f.isTwoDimensional) {
                    barcode = payload
                    format = f
                }
            case .text(let t):
                texts[item.id] = t.transcript
            @unknown default:
                break
            }
        }
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
