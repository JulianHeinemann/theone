import UIKit
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications
import RestwertKit

/// „Teilen“ → Restwert: markierter Mail-Text, Fotos aus der Fotos-App (bis 20), PDFs und Bilder aus Dateien.
/// Die Erweiterung liest nichts selbst aus (wenig Speicher, keine Kamera/KI), sondern legt die Dateien in die
/// gemeinsame App Group. Restwert liest sie beim nächsten Öffnen ein – wie „Aus Fotos“ mit mehreren Bildern.
final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareView(model: model) { [weak self] in self?.finish() })
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        Task { await model.store(providers) }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}

// MARK: - Übernahme

@Observable
final class ShareModel {
    enum State: Equatable {
        case working
        case done(photos: Int, documents: Int, texts: Int, preview: String?)
        case failed(String)
    }

    var state: State = .working
    /// Kleine Vorschau der ersten geteilten Bilder, damit man sieht, was übergeben wurde.
    var thumbnails: [UIImage] = []

    func store(_ providers: [NSItemProvider]) async {
        guard let dir = SharedInbox.directory() else {
            state = .failed("Restwert konnte die Daten nicht übernehmen. Öffne Restwert einmal und versuch es dann erneut.")
            return
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let batch = Date.now
        var photos = 0, documents = 0, texts = 0
        var preview: String?
        for (i, provider) in providers.prefix(20).enumerated() {
            if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier),
               await Self.copyFile(provider, type: .pdf, to: dir, name: SharedInbox.fileName(batch: batch, index: i, extension: "pdf")) {
                documents += 1
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
                      await Self.copyImage(provider, to: dir, batch: batch, index: i) {
                photos += 1
                if thumbnails.count < 4, let url = Self.saved(in: dir, batch: batch, index: i),
                   let thumb = await Self.thumbnail(url) { thumbnails.append(thumb) }
            } else if let text = await Self.text(provider), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let url = dir.appending(path: SharedInbox.fileName(batch: batch, index: i, extension: "txt"))
                if (try? Data(text.utf8).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])) != nil {
                    texts += 1
                    preview = preview ?? Self.preview(of: text)
                }
            }
        }
        if photos + documents + texts == 0 {
            state = .failed("Darin war nichts, was Restwert lesen kann. Teile ein Foto, ein PDF oder den markierten Text der Gutschein-Mail.")
            return
        }
        Self.protect(dir)
        state = .done(photos: photos, documents: documents, texts: texts, preview: preview)
        await Self.notifyReady(count: photos + documents + texts)
    }

    /// Wie die App-Daten: Übergabedateien nur lesbar, nachdem das Gerät seit dem Start einmal entsperrt wurde.
    private static func protect(_ dir: URL) {
        for url in SharedInbox.pending(in: dir) {
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                                   ofItemAtPath: url.path())
        }
    }

    /// Kurze Vorschau aus dem Text ohne KI: „Amazon · 25,00 €“.
    private static func preview(of text: String) -> String? {
        let d = TextParser.parse(text)
        let name = d.merchantID.flatMap { Merchant.byID[$0]?.name } ?? d.customName
        let amount = d.percent.map { "\(Int($0)) %" } ?? d.value.map { $0.formatted(.currency(code: "EUR").locale(Locale(identifier: "de_DE"))) }
        let parts = [name, amount].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Mitteilung „bereit zum Prüfen“: Ein Tipp darauf öffnet Restwert (Erweiterungen dürfen die App nicht selbst öffnen).
    /// Nur wenn Mitteilungen schon erlaubt sind; die Erweiterung fragt nie selbst nach.
    private static func notifyReady(count: Int) async {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = count == 1 ? "Gutschein bereit zum Prüfen" : "\(count) Gutscheine bereit zum Prüfen"
        content.body = count == 1 ? "Tippen, um ihn in Restwert einzulesen." : "Tippen, um sie in Restwert einzulesen."
        content.userInfo = ["inbox": true]
        content.threadIdentifier = "inbox"
        let request = UNNotificationRequest(identifier: "inbox-ready", content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false))
        try? await center.add(request)
    }

    /// Die gerade abgelegte Datei zu diesem Eintrag (Endung je nach Bildformat).
    private static func saved(in dir: URL, batch: Date, index: Int) -> URL? {
        let prefix = SharedInbox.fileName(batch: batch, index: index, extension: "x").dropLast(2)
        return SharedInbox.pending(in: dir).first { $0.lastPathComponent.hasPrefix(prefix) }
    }

    /// Verkleinert (max. 300 px), damit die Erweiterung mit wenig Speicher auskommt.
    private nonisolated static func thumbnail(_ url: URL) async -> UIImage? {
        guard let image = UIImage(contentsOfFile: url.path()) else { return nil }
        return await image.byPreparingThumbnail(ofSize: CGSize(width: 300, height: 300 * image.size.height / max(image.size.width, 1)))
    }

    // MARK: Laden aus dem Teilen-Blatt (Rückrufe laufen im Hintergrund; nur Sendable-Werte zurück)

    private nonisolated static func copyFile(_ provider: NSItemProvider, type: UTType, to dir: URL, name: String) async -> Bool {
        await withCheckedContinuation { cont in
            _ = provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
                // Die Datei gibt es nur während des Rückrufs: sofort kopieren.
                guard let url else { cont.resume(returning: false); return }
                let dst = dir.appending(path: name)
                try? FileManager.default.removeItem(at: dst)
                cont.resume(returning: (try? FileManager.default.copyItem(at: url, to: dst)) != nil)
            }
        }
    }

    /// Fotos als Datei (JPEG/HEIC wie in der Mediathek), sonst als Daten (z. B. Bild aus einer Mail oder einem Screenshot).
    private nonisolated static func copyImage(_ provider: NSItemProvider, to dir: URL, batch: Date, index: Int) async -> Bool {
        let type = provider.registeredTypeIdentifiers.compactMap(UTType.init).first { $0.conforms(to: .image) } ?? .image
        let ext = type.preferredFilenameExtension ?? "jpg"
        if await copyFile(provider, type: type, to: dir, name: SharedInbox.fileName(batch: batch, index: index, extension: ext)) { return true }
        let data: Data? = await withCheckedContinuation { cont in
            _ = provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in cont.resume(returning: data) }
        }
        guard let data, let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.9) else { return false }
        let url = dir.appending(path: SharedInbox.fileName(batch: batch, index: index, extension: "jpg"))
        return (try? jpeg.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])) != nil
    }

    /// Markierter Text (Mail, Notizen, Nachrichten) oder eine geteilte Textdatei.
    private nonisolated static func text(_ provider: NSItemProvider) async -> String? {
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            let s: String? = await withCheckedContinuation { cont in
                _ = provider.loadObject(ofClass: NSString.self) { obj, _ in cont.resume(returning: (obj as? NSString) as String?) }
            }
            if let s { return s }
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
            return await withCheckedContinuation { cont in
                _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.text.identifier) { data, _ in
                    cont.resume(returning: data.flatMap { String(data: $0, encoding: .utf8) })
                }
            }
        }
        return nil
    }
}

// MARK: - Oberfläche

private struct ShareView: View {
    let model: ShareModel
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                switch model.state {
                case .working:
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Wird an Restwert übergeben …").font(.headline)
                    }
                case let .done(photos, documents, texts, preview):
                    Label(title(photos: photos, documents: documents, texts: texts), systemImage: "checkmark.circle.fill")
                        .font(.title3.weight(.bold))
                        .symbolRenderingMode(.multicolor)
                    if !model.thumbnails.isEmpty {
                        HStack(spacing: 10) {
                            ForEach(Array(model.thumbnails.enumerated()), id: \.offset) { _, img in
                                Image(uiImage: img).resizable().scaledToFill()
                                    .frame(width: 72, height: 72)
                                    .clipShape(.rect(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
                            }
                        }
                        .accessibilityHidden(true)
                    }
                    if let preview {
                        Text(preview).font(.body.weight(.semibold))
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.fill.tertiary, in: .rect(cornerRadius: 12))
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("So geht es weiter").font(.headline)
                        Label("Tippe auf „Fertig“.", systemImage: "1.circle")
                        Label("Öffne Restwert – die App liest alles ein.", systemImage: "2.circle")
                        Label("Prüfen und speichern.", systemImage: "3.circle")
                    }
                    .font(.body)
                    Text("Sind Mitteilungen erlaubt, erinnert dich Restwert gleich daran.")
                        .font(.body).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Label("Bleibt auf diesem Gerät. Nichts wird hochgeladen.", systemImage: "lock")
                        .font(.footnote).foregroundStyle(.secondary)
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.body.weight(.semibold))
                        .symbolRenderingMode(.multicolor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(20)
            .navigationTitle("Restwert")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig", action: onDone).disabled(model.state == .working)
                }
            }
        }
    }

    private func title(photos: Int, documents: Int, texts: Int) -> String {
        var parts: [String] = []
        if photos > 0 { parts.append(photos == 1 ? "1 Foto" : "\(photos) Fotos") }
        if documents > 0 { parts.append(documents == 1 ? "1 PDF" : "\(documents) PDFs") }
        if texts > 0 { parts.append(texts == 1 ? "Mail-Text" : "\(texts) Texte") }
        return parts.joined(separator: ", ") + " für Restwert bereit"
    }
}
