import Foundation

/// Selbst ausgegebene Gutscheine (z. B. vom eigenen Café): eindeutiger, gut lesbarer Code.
public enum IssuedVoucher {
    /// Ohne leicht verwechselbare Zeichen (0/O, 1/I/L), damit man den Code auch abtippen kann.
    static let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")

    /// Code wie „CAFE-7K3M-9QX2“: Präfix aus den Buchstaben des Namens (max. 4, ohne I/L/O), dann 2×4 Zufallszeichen.
    /// `existing` verhindert Doppelungen mit schon ausgegebenen Codes.
    public static func makeCode(for name: String, existing: Set<String> = []) -> String {
        let letters = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de_DE"))
            .uppercased().filter { alphabet.contains($0) && $0.isLetter }
        let prefix = letters.isEmpty ? "GS" : String(letters.prefix(4))
        var rng = SystemRandomNumberGenerator()
        while true {
            let block = { String((0..<4).map { _ in alphabet.randomElement(using: &rng)! }) }
            let code = "\(prefix)-\(block())-\(block())"
            if !existing.contains(code) { return code }
        }
    }
}
