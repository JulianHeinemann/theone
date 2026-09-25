import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

/// Baut den Barcode im Originalformat der Karte nach.
/// Code 128, QR, PDF417 und Aztec kommen aus Core Image, EAN, UPC, ITF und Code 39 werden selbst kodiert.
enum BarcodeRenderer {
    private static let context = CIContext()

    enum Output {
        case bars([Bool])
        case image(UIImage)
    }

    static func render(_ raw: String, format: CodeFormat) -> Output? {
        let value = raw.replacingOccurrences(of: " ", with: "")
        guard !value.isEmpty else { return nil }
        switch format {
        case .ean13: return ean13(value).map(Output.bars) ?? code128(value)
        case .upca: return ean13("0" + value).map(Output.bars) ?? code128(value)
        case .ean8: return ean8(value).map(Output.bars) ?? code128(value)
        case .itf: return itf(value).map(Output.bars) ?? code128(value)
        case .code39: return code39(value.uppercased()).map(Output.bars) ?? code128(value)
        case .code128: return code128(value)
        case .qr:
            let f = CIFilter.qrCodeGenerator()
            f.message = Data(value.utf8)
            f.correctionLevel = "M"
            return image(f.outputImage).map(Output.image)
        case .pdf417:
            let f = CIFilter.pdf417BarcodeGenerator()
            f.message = Data(value.utf8)
            return image(f.outputImage).map(Output.image)
        case .aztec:
            let f = CIFilter.aztecCodeGenerator()
            f.message = Data(value.utf8)
            return image(f.outputImage).map(Output.image)
        case .dataMatrix, .text:
            return nil
        }
    }

    static func isTwoDimensional(_ format: CodeFormat) -> Bool { [.qr, .aztec].contains(format) }

    private static func code128(_ value: String) -> Output? {
        let f = CIFilter.code128BarcodeGenerator()
        f.message = Data(value.utf8)
        f.quietSpace = 10
        return image(f.outputImage).map(Output.image)
    }

    private static func image(_ ci: CIImage?) -> UIImage? {
        guard let ci else { return nil }
        let scaled = ci.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    // MARK: EAN / UPC

    private static let L = ["0001101", "0011001", "0010011", "0111101", "0100011", "0110001", "0101111", "0111011", "0110111", "0001011"]
    private static let G = ["0100111", "0110011", "0011011", "0100001", "0011101", "0111001", "0000101", "0010001", "0001001", "0010111"]
    private static let R = ["1110010", "1100110", "1101100", "1000010", "1011100", "1001110", "1010000", "1000100", "1001000", "1110100"]
    private static let parity = ["LLLLLL", "LLGLGG", "LLGGLG", "LLGGGL", "LGLLGG", "LGGLLG", "LGGGLL", "LGLGLG", "LGLGGL", "LGGLGL"]

    private static func digits(_ s: String) -> [Int]? {
        let d = s.compactMap(\.wholeNumberValue)
        return d.count == s.count ? d : nil
    }

    private static func checkDigit(_ d: [Int]) -> Int {
        // Gewichte 1/3 von rechts beginnend mit 3
        var sum = 0
        for (i, v) in d.reversed().enumerated() { sum += v * (i % 2 == 0 ? 3 : 1) }
        return (10 - sum % 10) % 10
    }

    private static func bits(_ s: String) -> [Bool] { s.map { $0 == "1" } }

    static func ean13(_ s: String) -> [Bool]? {
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

    static func ean8(_ s: String) -> [Bool]? {
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

    static func itf(_ s: String) -> [Bool]? {
        guard var d = digits(s), !d.isEmpty else { return nil }
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

    static func code39(_ s: String) -> [Bool]? {
        let chars = Array("*" + s + "*")
        guard chars.allSatisfy({ c39[$0] != nil }) else { return nil }
        var out: [Bool] = []
        for (idx, ch) in chars.enumerated() {
            let p = Array(c39[ch]!)
            for k in 0..<9 { out += Array(repeating: k % 2 == 0, count: p[k] == "w" ? 3 : 1) }
            if idx < chars.count - 1 { out.append(false) }
        }
        return out
    }
}

/// Zeigt den Barcode einer Karte. Für Formate ohne Generator fällt die Ansicht auf die Nummer zurück.
struct BarcodeView: View {
    let number: String
    let format: CodeFormat
    var height: CGFloat = 90

    var body: some View {
        switch BarcodeRenderer.render(number, format: format) {
        case .bars(let mods)?:
            let padded = Array(repeating: false, count: 10) + mods + Array(repeating: false, count: 10)
            Canvas { ctx, size in
                let w = size.width / CGFloat(padded.count)
                for (i, on) in padded.enumerated() where on {
                    ctx.fill(Path(CGRect(x: CGFloat(i) * w, y: 0, width: w + 0.35, height: size.height)), with: .color(.black))
                }
            }
            .frame(height: height)
            .background(Color.white)
            .accessibilityLabel("Barcode \(format.label)")
        case .image(let img)?:
            Image(uiImage: img)
                .interpolation(.none)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: BarcodeRenderer.isTwoDimensional(format) ? height * 2.4 : height)
                .accessibilityLabel("Barcode \(format.label)")
        case nil:
            Text(number)
                .font(.system(size: 26, weight: .heavy)).kerning(2)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .padding(.vertical, 12)
        }
    }
}
