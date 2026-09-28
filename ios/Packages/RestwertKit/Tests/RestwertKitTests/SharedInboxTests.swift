import Foundation
import Testing
@testable import RestwertKit

@Suite("Teilen-Übergabe (App Group)")
struct SharedInboxTests {
    @Test("Dateien werden in Teilen-Reihenfolge genau einmal abgeholt")
    func takeOnce() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "inbox-\(UUID().uuidString)")
        let inbox = root.appending(path: "Inbox"), target = root.appending(path: "taken")
        try fm.createDirectory(at: inbox, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let batch = Date(timeIntervalSince1970: 1_800_000_000)
        for (i, ext) in ["jpg", "txt", "PDF"].enumerated().reversed() {
            try Data([UInt8(i)]).write(to: inbox.appending(path: SharedInbox.fileName(batch: batch, index: i, extension: ext)))
        }
        // Halb geschriebene Dateien bleiben liegen.
        try Data().write(to: inbox.appending(path: "x.part"))
        let taken = SharedInbox.take(from: inbox, to: target)
        #expect(taken.map(\.pathExtension) == ["jpg", "txt", "pdf"])
        #expect(SharedInbox.take(from: inbox, to: target).isEmpty)
        #expect(SharedInbox.pending(in: inbox).isEmpty)
        #expect(fm.fileExists(atPath: inbox.appending(path: "x.part").path))
    }
}
