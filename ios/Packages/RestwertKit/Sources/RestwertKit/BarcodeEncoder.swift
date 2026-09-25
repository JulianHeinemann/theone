import Foundation

/// Kodiert 1D-Barcodes als Modulfolge (true = Strich). Code 128, QR, PDF417 und Aztec erzeugt die App mit Core Image.
public enum BarcodeEncoder {
    public static func modules(for raw: String, format: CodeFormat) -> [Bool]? {
        let value = raw.replacingOccurrences(of: " ", with: "")
        switch format {
        case .ean13: return ean13(value)
        case .upca: return ean13("0" + value)
        case .ean8: return ean8(value)
        case .itf: return itf(value)
        case .code39: return code39(value.uppercased())
        default: return nil
        }
    }

    /// Prüfziffer von EAN/UPC stimmt.
    public static func hasValidChecksum(_ raw: String, format: CodeFormat) -> Bool? {
        let value = raw.replacingOccurrences(of: " ", with: "")
        guard let d = digits(value) else { return false }
        switch format {
        case .ean13 where d.count == 13: return checkDigit(Array(d.prefix(12))) == d[12]
        case .ean8 where d.count == 8: return checkDigit(Array(d.prefix(7))) == d[7]
        case .upca where d.count == 12: return checkDigit([0] + Array(d.prefix(11))) == d[11]
        case .ean13, .ean8, .upca: return false
        default: return nil
        }
    }

    // MARK: EAN / UPC

    private static let L = ["0001101", "0011001", "0010011", "0111101", "0100011", "0110001", "0101111", "0111011", "0110111", "0001011"]
    private static let G = ["0100111", "0110011", "0011011", "0100001", "0011101", "0111001", "0000101", "0010001", "0001001", "0010111"]
    private static let R = ["1110010", "1100110", "1101100", "1000010", "1011100", "1001110", "1010000", "1000100", "1001000", "1110100"]
    private static let parity = ["LLLLLL", "LLGLGG", "LLGGLG", "LLGGGL", "LGLLGG", "LGGLLG", "LGGGLL", "LGLGLG", "LGLGGL", "LGGLGL"]

    static func digits(_ s: String) -> [Int]? {
        let d = s.compactMap(\.wholeNumberValue)
        return !s.isEmpty && d.count == s.count ? d : nil
    }

    /// Gewichte 3/1 von rechts.
    public static func checkDigit(_ d: [Int]) -> Int {
        var sum = 0
        for (i, v) in d.reversed().enumerated() { sum += v * (i % 2 == 0 ? 3 : 1) }
        return (10 - sum % 10) % 10
    }

    private static func bits(_ s: String) -> [Bool] { s.map { $0 == "1" } }

    public static func ean13(_ s: String) -> [Bool]? {
        guard var d = digits(s), d.count == 12 || d.count == 13 else { return nil }
        if d.count == 12 { d.append(checkDigit(d)) }
        guard checkDigit(Array(d.prefix(12))) == d[12] else { return nil }
        let par = Array(parity[d[0]])
        var out = bits("101")
        for i in 1...6 { out += bits(par[i - 1] == "L" ? L[d[i]] : G[d[i]]) }
        out += bits("01010")
        for i in 7...12 { out += bits(R[d[i]]) }
        out += bits("101")
        return out
    }

    public static func ean8(_ s: String) -> [Bool]? {
        guard var d = digits(s), d.count == 7 || d.count == 8 else { return nil }
        if d.count == 7 { d.append(checkDigit(d)) }
        guard checkDigit(Array(d.prefix(7))) == d[7] else { return nil }
        var out = bits("101")
        for i in 0...3 { out += bits(L[d[i]]) }
        out += bits("01010")
        for i in 4...7 { out += bits(R[d[i]]) }
        out += bits("101")
        return out
    }

    // MARK: ITF (Interleaved 2 of 5)

    private static let itfPatterns = ["nnwwn", "wnnnw", "nwnnw", "wwnnn", "nnwnw", "wnwnn", "nwwnn", "nnnww", "wnnwn", "nwnwn"]

    public static func itf(_ s: String) -> [Bool]? {
        guard var d = digits(s) else { return nil }
        if d.count % 2 == 1 { d.insert(0, at: 0) }
        func run(_ bar: Bool, _ wide: Bool) -> [Bool] { Array(repeating: bar, count: wide ? 3 : 1) }
        var out = bits("1010")
        var i = 0
        while i < d.count {
            let a = Array(itfPatterns[d[i]]), b = Array(itfPatterns[d[i + 1]])
            for k in 0..<5 {
                out += run(true, a[k] == "w")
                out += run(false, b[k] == "w")
            }
            i += 2
        }
        out += run(true, true) + run(false, false) + run(true, false)
        return out
    }

    // MARK: Code 39

    private static let c39: [Character: String] = [
        "0": "nnnwwnwnn", "1": "wnnwnnnnw", "2": "nnwwnnnnw", "3": "wnwwnnnnn", "4": "nnnwwnnnw",
        "5": "wnnwwnnnn", "6": "nnwwwnnnn", "7": "nnnwnnwnw", "8": "wnnwnnwnn", "9": "nnwwnnwnn",
        "A": "wnnnnwnnw", "B": "nnwnnwnnw", "C": "wnwnnwnnn", "D": "nnnnwwnnw", "E": "wnnnwwnnn",
        "F": "nnwnwwnnn", "G": "nnnnnwwnw", "H": "wnnnnwwnn", "I": "nnwnnwwnn", "J": "nnnnwwwnn",
        "K": "wnnnnnnww", "L": "nnwnnnnww", "M": "wnwnnnnwn", "N": "nnnnwnnww", "O": "wnnnwnnwn",
        "P": "nnwnwnnwn", "Q": "nnnnnnwww", "R": "wnnnnnwwn", "S": "nnwnnnwwn", "T": "nnnnwnwwn",
        "U": "wwnnnnnnw", "V": "nwwnnnnnw", "W": "wwwnnnnnn", "X": "nwnnwnnnw", "Y": "wwnnwnnnn",
        "Z": "nwwnwnnnn", "-": "nwnnnnwnw", ".": "wwnnnnwnn", " ": "nwwnnnwnn", "*": "nwnnwnwnn",
    ]

    public static func code39(_ s: String) -> [Bool]? {
        let chars = Array("*" + s + "*")
        guard !s.isEmpty, chars.allSatisfy({ c39[$0] != nil }) else { return nil }
        var out: [Bool] = []
        for (idx, ch) in chars.enumerated() {
            guard let pattern = c39[ch] else { return nil }
            let p = Array(pattern)
            for k in 0..<9 { out += Array(repeating: k % 2 == 0, count: p[k] == "w" ? 3 : 1) }
            if idx < chars.count - 1 { out.append(false) }
        }
        return out
    }
}
