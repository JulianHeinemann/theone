import SwiftUI
import VisionKit
import Vision

/// Live-Scanner mit der Kamera: findet Barcodes und Text, auch Handschrift.
struct LiveScannerView: View {
    var onDone: (ScanOutcome) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var model = LiveScanModel()

    var body: some View {
        ZStack(alignment: .bottom) {
            if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                DataScannerRepresentable(model: model).ignoresSafeArea()
                ScanLine().allowsHitTesting(false)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "camera.metering.unknown").font(.system(size: 40))
                    Text("Live-Scan ist auf diesem Gerät nicht verfügbar. Nutz „Foto“ oder „Datei“.")
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(Color.muted).padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.page)
            }

            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: model.barcode == nil ? "barcode.viewfinder" : "checkmark.circle.fill")
                        .foregroundStyle(model.barcode == nil ? Color.muted : Color.good)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.barcode == nil ? "Halte die Rückseite ins Bild" : "\(model.format?.label ?? "Barcode") erkannt")
                            .font(.system(size: 15, weight: .bold))
                        Text(model.barcode ?? "\(model.texts.count) Textzeilen erkannt, auch Handschrift")
                            .font(.system(size: 13)).foregroundStyle(Color.muted).lineLimit(1)
                    }
                    Spacer()
                }
                Button {
                    Task {
                        let photo = await model.capturePhoto()
                        onDone(ScanOutcome(barcode: model.barcode, format: model.format,
                                           text: model.texts.values.joined(separator: "\n"), photo: photo))
                        dismiss()
                    }
                } label: { Text("Übernehmen") }
                .buttonStyle(FilledButtonStyle(background: .brandYellow, foreground: .ink))
                .disabled(model.barcode == nil && model.texts.isEmpty)
                .opacity(model.barcode == nil && model.texts.isEmpty ? 0.5 : 1)
            }
            .padding(18)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(16)
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).foregroundStyle(Color.ink)
                    .frame(width: 44, height: 44).background(Color.surface, in: Circle())
            }
            .padding(16)
            .accessibilityLabel("Schließen")
        }
    }
}

@MainActor
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
                if let payload = b.payloadStringValue, !payload.isEmpty {
                    let f = CodeFormat(symbology: b.observation.symbology)
                    // Strichcode behalten, sobald einer gefunden ist
                    if barcode == nil || (format == .qr && f != .qr) { barcode = payload; format = f }
                }
            case .text(let t):
                texts[item.id] = t.transcript
            @unknown default:
                break
            }
        }
    }

    func capturePhoto() async -> Data? {
        guard let controller, let img = try? await controller.capturePhoto() else { return nil }
        return img.thumbnailJPEG()
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
            Task { @MainActor in model.handle(addedItems) }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            Task { @MainActor in model.handle(updatedItems) }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            Task { @MainActor in model.handle([item]) }
        }
    }
}

/// Gelbe Scanlinie, die über den Sucher läuft.
private struct ScanLine: View {
    @State private var down = false

    var body: some View {
        GeometryReader { g in
            Rectangle()
                .fill(LinearGradient(colors: [Color.brandYellow.opacity(0), Color.brandYellow.opacity(0.35)], startPoint: .top, endPoint: .bottom))
                .frame(height: 60)
                .overlay(alignment: .bottom) { Rectangle().fill(Color.brandYellow).frame(height: 3) }
                .padding(.horizontal, 40)
                .offset(y: down ? g.size.height * 0.62 : g.size.height * 0.18)
        }
        .onAppear { withAnimation(.easeInOut(duration: 1.8).repeatForever()) { down = true } }
    }
}
