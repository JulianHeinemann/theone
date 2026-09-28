import Foundation

/// Übergabe aus der Teilen-Erweiterung an die App: Dateien (Fotos, PDFs, Mail-Text) liegen in der
/// gemeinsamen App Group, bis die App sie beim nächsten Öffnen einliest. Nichts verlässt das Gerät.
public enum SharedInbox {
    public static let groupID = "group.de.restwert.app"

    /// Ordner in der App Group; nil, wenn die App Group fehlt (z. B. Build ohne Berechtigung).
    public static func directory(fileManager: FileManager = .default) -> URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: groupID)?.appending(path: "Inbox", directoryHint: .isDirectory)
    }

    /// Dateiname, der die Reihenfolge der geteilten Elemente erhält („1727…-03.jpg“).
    public static func fileName(batch: Date, index: Int, extension ext: String) -> String {
        let stamp = Int(batch.timeIntervalSince1970 * 1000)
        return "\(stamp)-\(String(format: "%02d", index)).\(ext.isEmpty ? "dat" : ext.lowercased())"
    }

    /// Wartende Dateien in Teilen-Reihenfolge.
    public static func pending(in dir: URL, fileManager: FileManager = .default) -> [URL] {
        let files = (try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return files.filter { $0.pathExtension != "part" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Wartende Dateien aus der App Group in einen eigenen Ordner der App verschieben (einmal abholen, nie doppelt).
    /// Gibt die neuen Orte zurück; was sich nicht verschieben ließ, bleibt liegen und kommt beim nächsten Mal.
    public static func take(from dir: URL, to target: URL, fileManager: FileManager = .default) -> [URL] {
        let files = pending(in: dir, fileManager: fileManager)
        guard !files.isEmpty else { return [] }
        try? fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        return files.compactMap { src in
            let dst = target.appending(path: src.lastPathComponent)
            try? fileManager.removeItem(at: dst)
            return (try? fileManager.moveItem(at: src, to: dst)) != nil ? dst : nil
        }
    }
}
