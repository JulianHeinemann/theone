import Foundation

/// Kodiert 1D-Barcodes als Modulfolge (true = Strich). Code 128, QR, PDF417 und Aztec erzeugt die App mit Core Image.
public enum BarcodeEncoder {
    /// Inhalt, der in den Barcode kommt: Ziffernfolgen ohne Anzeige-Leerzeichen („6280 1234“ → „62801234“),
    /// andere Codes unverändert – ein Leerzeichen in „GUTSCHEIN 42“ gehört zum Code.
    public static func payload(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let compact = t.replacingOccurrences(of: " ", with: "")
        return !compact.isEmpty && compact.allSatisfy(\.isNumber) ? compact : t
    }

    public static func modules(for raw: String, format: CodeFormat) -> [Bool]? {
        let value = payload(raw)
        switch format {
        case .ean13: return ean13(value)
        case .upca: return ean13("0" + value)
        case .ean8: return ean8(value)
        case .itf: return itf(value)
        case .code39: return code39(value.uppercased())
        default: return nil
        }
    }

    /// Prüfziffer von EAN/UPC stimmt. nil bei Formaten ohne Prüfziffer (Code 128, QR, …).
    public static func hasValidChecksum(_ raw: String, format: CodeFormat) -> Bool? {
        guard [.ean13, .ean8, .upca].contains(format) else { return nil }
        let value = raw.replacingOccurrences(of: " ", with: "")
        guard let d = digits(value) else { return false }
        switch format {
        case .ean13 where d.count == 13: return checkDigit(Array(d.prefix(12))) == d[12]
        case .ean8 where d.count == 8: return checkDigit(Array(d.prefix(7))) == d[7]
        case .upca where d.count == 12: return checkDigit([0] + Array(d.prefix(11))) == d[11]
        default: return false
        }
    }

    /// UPC-E (6, 7 oder 8 Ziffern) auf die 12 Ziffern von UPC-A erweitern. Eine gelesene Prüfziffer bleibt erhalten.
    public static func expandUPCE(_ raw: String) -> String? {
        let value = raw.replacingOccurrences(of: " ", with: "")
        guard var d = digits(value), (6...8).contains(d.count) else { return nil }
        if d.count == 6 { d.insert(0, at: 0) }
        guard d[0] == 0 || d[0] == 1 else { return nil }
        let x = Array(d[1...6])
        let body: [Int]
        switch x[5] {
        case 0...2: body = [x[0], x[1], x[5], 0, 0, 0, 0, x[2], x[3], x[4]]
        case 3: body = [x[0], x[1], x[2], 0, 0, 0, 0, 0, x[3], x[4]]
        case 4: body = [x[0], x[1], x[2], x[3], 0, 0, 0, 0, 0, x[4]]
        default: body = [x[0], x[1], x[2], x[3], x[4], 0, 0, 0, 0, x[5]]
        }
        let first11 = [d[0]] + body
        let check = d.count == 8 ? d[7] : checkDigit(first11)
        return (first11 + [check]).map(String.init).joined()
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
        // ITF kodiert Ziffernpaare. Ungerade Länge nicht still mit 0 auffüllen (der Scanner läse einen anderen Code):
        // dann zeichnet die App den Inhalt unverändert als Code 128.
        guard let d = digits(s), d.count % 2 == 0 else { return nil }
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

    // MARK: Data Matrix (ECC 200)

    /// Data Matrix ECC 200 als Modulmatrix (true = dunkel), quadratische Symbole bis 48×48 (bis 174 Datenwörter).
    /// ASCII-Kodierung mit Ziffernpaaren, Füllwörter nach Norm, Reed-Solomon über GF(256) mit Polynom 301.
    public static func dataMatrix(_ raw: String) -> [[Bool]]? {
        let text = payload(raw)
        guard !text.isEmpty else { return nil }
        // Latin-1 wie in der Norm vorgesehen; sonst UTF-8-Bytes mit ECI 26 davor, damit Scanner „€“ richtig lesen.
        let latin1 = text.data(using: .isoLatin1)
        let bytes = Array(latin1 ?? Data(text.utf8))
        var data: [Int] = latin1 == nil ? [241, 27] : []
        var i = 0
        while i < bytes.count {
            let b = Int(bytes[i])
            if i + 1 < bytes.count, (48...57).contains(b), (48...57).contains(Int(bytes[i + 1])) {
                data.append(130 + (b - 48) * 10 + Int(bytes[i + 1]) - 48)
                i += 2
            } else if b < 128 {
                data.append(b + 1); i += 1
            } else {
                data.append(235); data.append(b - 128 + 1); i += 1
            }
        }
        // (Seitenlänge, Datenwörter, Fehlerkorrekturwörter, Regionen je Seite)
        let sizes: [(Int, Int, Int, Int)] = [(10, 3, 5, 1), (12, 5, 7, 1), (14, 8, 10, 1), (16, 12, 12, 1), (18, 18, 14, 1),
                                             (20, 22, 18, 1), (22, 30, 20, 1), (24, 36, 24, 1), (26, 44, 28, 1), (32, 62, 36, 2),
                                             (36, 86, 42, 2), (40, 114, 48, 2), (44, 144, 56, 2), (48, 174, 68, 2)]
        guard let (size, dataCount, eccCount, regions) = sizes.first(where: { $0.1 >= data.count }) else { return nil }
        // Füllen: erst 129, danach „zufällige“ Füllwörter nach Norm (253-Zustands-Algorithmus).
        if data.count < dataCount {
            data.append(129)
            while data.count < dataCount {
                var pad = 129 + ((149 * (data.count + 1)) % 253) + 1
                if pad > 254 { pad -= 254 }
                data.append(pad)
            }
        }
        let codewords = data + reedSolomon(data, eccCount)

        let regionSide = size / regions - 2
        let n = regionSide * regions
        let placed = placeECC200(codewords, rows: n, cols: n)
        var m = Array(repeating: Array(repeating: false, count: size), count: size)
        let block = regionSide + 2
        for ry in 0..<regions {
            for rx in 0..<regions {
                let y0 = ry * block, x0 = rx * block
                for k in 0..<block {
                    m[y0 + block - 1][x0 + k] = true             // unten durchgehend
                    m[y0 + k][x0] = true                         // links durchgehend
                    m[y0][x0 + k] = k % 2 == 0                   // oben abwechselnd
                    m[y0 + k][x0 + block - 1] = k % 2 == 1       // rechts abwechselnd
                }
                for r in 0..<regionSide {
                    for c in 0..<regionSide {
                        m[y0 + 1 + r][x0 + 1 + c] = placed[ry * regionSide + r][rx * regionSide + c]
                    }
                }
            }
        }
        return m
    }

    // Galois-Feld GF(256) mit Polynom x^8 + x^5 + x^3 + x^2 + 1 (301).
    private static let gf: (exp: [Int], log: [Int]) = {
        var exp = [Int](repeating: 0, count: 512), log = [Int](repeating: 0, count: 256)
        var x = 1
        for i in 0..<255 {
            exp[i] = x; log[x] = i
            x <<= 1
            if x >= 256 { x ^= 301 }
        }
        for i in 255..<512 { exp[i] = exp[i - 255] }
        return (exp, log)
    }()

    private static func gfMul(_ a: Int, _ b: Int) -> Int {
        a == 0 || b == 0 ? 0 : gf.exp[gf.log[a] + gf.log[b]]
    }

    static func reedSolomon(_ data: [Int], _ n: Int) -> [Int] {
        // Generatorpolynom (x - α^1)…(x - α^n), Koeffizienten vom höchsten Grad an.
        var g = [1]
        for i in 1...n {
            let a = gf.exp[i]
            var next = [Int](repeating: 0, count: g.count + 1)
            for j in 0..<next.count {
                next[j] = (j < g.count ? g[j] : 0) ^ (j > 0 ? gfMul(g[j - 1], a) : 0)
            }
            g = next
        }
        var ecc = [Int](repeating: 0, count: n)
        for d in data {
            let m = d ^ ecc[0]
            ecc.removeFirst(); ecc.append(0)
            for i in 0..<n { ecc[i] ^= gfMul(m, g[i + 1]) }
        }
        return ecc
    }

    /// Platzierung der Codewörter nach ISO/IEC 16022 Anhang F (ECC 200).
    static func placeECC200(_ cw: [Int], rows nr: Int, cols nc: Int) -> [[Bool]] {
        var bits = Array(repeating: Array(repeating: Int8(-1), count: nc), count: nr)
        func module(_ r0: Int, _ c0: Int, _ pos: Int, _ bit: Int) {
            var r = r0, c = c0
            if r < 0 { r += nr; c += 4 - ((nr + 4) % 8) }
            if c < 0 { c += nc; r += 4 - ((nc + 4) % 8) }
            let v = pos < cw.count ? (cw[pos] >> (8 - bit)) & 1 : 0
            bits[r][c] = Int8(v)
        }
        func utah(_ r: Int, _ c: Int, _ p: Int) {
            module(r - 2, c - 2, p, 1); module(r - 2, c - 1, p, 2); module(r - 1, c - 2, p, 3); module(r - 1, c - 1, p, 4)
            module(r - 1, c, p, 5); module(r, c - 2, p, 6); module(r, c - 1, p, 7); module(r, c, p, 8)
        }
        func corner1(_ p: Int) {
            module(nr - 1, 0, p, 1); module(nr - 1, 1, p, 2); module(nr - 1, 2, p, 3); module(0, nc - 2, p, 4)
            module(0, nc - 1, p, 5); module(1, nc - 1, p, 6); module(2, nc - 1, p, 7); module(3, nc - 1, p, 8)
        }
        func corner2(_ p: Int) {
            module(nr - 3, 0, p, 1); module(nr - 2, 0, p, 2); module(nr - 1, 0, p, 3); module(0, nc - 4, p, 4)
            module(0, nc - 3, p, 5); module(0, nc - 2, p, 6); module(0, nc - 1, p, 7); module(1, nc - 1, p, 8)
        }
        func corner3(_ p: Int) {
            module(nr - 3, 0, p, 1); module(nr - 2, 0, p, 2); module(nr - 1, 0, p, 3); module(0, nc - 2, p, 4)
            module(0, nc - 1, p, 5); module(1, nc - 1, p, 6); module(2, nc - 1, p, 7); module(3, nc - 1, p, 8)
        }
        func corner4(_ p: Int) {
            module(nr - 1, 0, p, 1); module(nr - 1, nc - 1, p, 2); module(0, nc - 3, p, 3); module(0, nc - 2, p, 4)
            module(0, nc - 1, p, 5); module(1, nc - 3, p, 6); module(1, nc - 2, p, 7); module(1, nc - 1, p, 8)
        }
        var pos = 0, r = 4, c = 0
        repeat {
            if r == nr && c == 0 { corner1(pos); pos += 1 }
            if r == nr - 2 && c == 0 && nc % 4 != 0 { corner2(pos); pos += 1 }
            if r == nr - 2 && c == 0 && nc % 8 == 4 { corner3(pos); pos += 1 }
            if r == nr + 4 && c == 2 && nc % 8 == 0 { corner4(pos); pos += 1 }
            repeat {
                if r < nr && c >= 0 && bits[r][c] < 0 { utah(r, c, pos); pos += 1 }
                r -= 2; c += 2
            } while r >= 0 && c < nc
            r += 1; c += 3
            repeat {
                if r >= 0 && c < nc && bits[r][c] < 0 { utah(r, c, pos); pos += 1 }
                r += 2; c -= 2
            } while r < nr && c >= 0
            r += 3; c += 1
        } while r < nr || c < nc
        if bits[nr - 1][nc - 1] < 0 {
            bits[nr - 1][nc - 1] = 1; bits[nr - 2][nc - 2] = 1
            bits[nr - 1][nc - 2] = 0; bits[nr - 2][nc - 1] = 0
        }
        return bits.map { $0.map { $0 == 1 } }
    }
}
