import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

let ctx = CIContext()
func ci(_ f: CIFilter) -> NSImage? {
    guard let out = f.outputImage else { return nil }
    let scaled = out.transformed(by: CGAffineTransform(scaleX: 6, y: 6))
    guard let cg = ctx.createCGImage(scaled, from: scaled.extent) else { return nil }
    return NSImage(cgImage: cg, size: scaled.extent.size)
}
func code128(_ s: String) -> NSImage? { let f = CIFilter.code128BarcodeGenerator(); f.message = s.data(using: .ascii)!; f.quietSpace = 7; return ci(f) }
func qr(_ s: String) -> NSImage? { let f = CIFilter.qrCodeGenerator(); f.message = s.data(using: .utf8)!; f.correctionLevel = "M"; return ci(f) }
func pdf417(_ s: String) -> NSImage? { let f = CIFilter.pdf417BarcodeGenerator(); f.message = s.data(using: .ascii)!; return ci(f) }
func aztec(_ s: String) -> NSImage? { let f = CIFilter.aztecCodeGenerator(); f.message = s.data(using: .ascii)!; return ci(f) }

// EAN-13 selbst zeichnen
let L = ["0001101","0011001","0010011","0111101","0100011","0110001","0101111","0111011","0110111","0001011"]
let G = ["0100111","0110011","0011011","0100001","0011101","0111001","0000101","0010001","0001001","0010111"]
let R = ["1110010","1100110","1101100","1000010","1011100","1001110","1010000","1000100","1001000","1110100"]
let P = ["LLLLLL","LLGLGG","LLGGLG","LLGGGL","LGLLGG","LGGLLG","LGGGLL","LGLGLG","LGLGGL","LGGLGL"]
func eanCheck(_ s12: String) -> Int { let d = s12.compactMap{$0.wholeNumberValue}; var sum = 0; for (i,v) in d.enumerated() { sum += v * (i % 2 == 0 ? 1 : 3) }; return (10 - sum % 10) % 10 }
func ean13(_ code: String) -> NSImage {
    let d = code.compactMap{$0.wholeNumberValue}
    var bits = "101"
    let par = P[d[0]]
    for i in 1...6 { bits += (Array(par)[i-1] == "L" ? L : G)[d[i]] }
    bits += "01010"
    for i in 7...12 { bits += R[d[i]] }
    bits += "101"
    let m: CGFloat = 5, h: CGFloat = 220
    let w = CGFloat(bits.count + 22) * m
    let img = NSImage(size: NSSize(width: w, height: h + 50))
    img.lockFocus()
    NSColor.white.setFill(); NSRect(x: 0, y: 0, width: w, height: h + 50).fill()
    NSColor.black.setFill()
    for (i, b) in bits.enumerated() where b == "1" { NSRect(x: CGFloat(i + 11) * m, y: 50, width: m, height: h).fill() }
    (code as NSString).draw(at: NSPoint(x: 11 * m, y: 5), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 34, weight: .regular)])
    img.unlockFocus()
    return img
}

struct Line { var text: String; var size: CGFloat; var weight: NSFont.Weight = .regular; var italic = false; var color: NSColor = .black; var font: String? = nil }
func voucher(_ name: String, bg: NSColor, lines: [Line], code: NSImage? = nil, codeW: CGFloat = 700, rotate: CGFloat = 0, noise: Bool = false, blur: Bool = false, size: NSSize = NSSize(width: 1200, height: 800)) {
    let img = NSImage(size: size)
    img.lockFocus()
    NSColor(white: 0.55, alpha: 1).setFill(); NSRect(origin: .zero, size: size).fill()
    let t = NSAffineTransform(); t.translateX(by: size.width/2, yBy: size.height/2); t.rotate(byDegrees: rotate); t.translateX(by: -size.width/2, yBy: -size.height/2); t.concat()
    bg.setFill(); NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: size.width - 80, height: size.height - 80), xRadius: 30, yRadius: 30).fill()
    var y = size.height - 110
    for l in lines {
        var font: NSFont = l.font.flatMap { NSFont(name: $0, size: l.size) } ?? NSFont.systemFont(ofSize: l.size, weight: l.weight)
        if l.italic { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        (l.text as NSString).draw(at: NSPoint(x: 90, y: y), withAttributes: [.font: font, .foregroundColor: l.color])
        y -= l.size * 1.45
    }
    if let code { let r = code.size.height / code.size.width; code.draw(in: NSRect(x: 90, y: 70, width: codeW, height: min(codeW * r, y - 80))) }
    if noise { for _ in 0..<4000 { NSColor(white: CGFloat.random(in: 0...1), alpha: 0.25).setFill(); NSRect(x: .random(in: 0...size.width), y: .random(in: 0...size.height), width: 2, height: 2).fill() } }
    img.unlockFocus()
    var out = img
    if blur, let tiff = img.tiffRepresentation, let ciImg = CIImage(data: tiff) {
        let f = CIFilter.gaussianBlur(); f.inputImage = ciImg; f.radius = 2.2
        if let o = f.outputImage, let cg = ctx.createCGImage(o, from: ciImg.extent) { out = NSImage(cgImage: cg, size: size) }
    }
    let rep = NSBitmapImageRep(data: out.tiffRepresentation!)!
    try! rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])!.write(to: URL(fileURLWithPath: name + ".jpg"))
    print("✓", name)
}

let ean = "400638133393"; let eanFull = ean + String(eanCheck(ean))
var eanBad = eanFull; eanBad.removeLast(); eanBad += String((eanCheck(ean) + 3) % 10)

voucher("v01-douglas-ean13", bg: .white, lines: [
    Line(text: "DOUGLAS", size: 64, weight: .heavy),
    Line(text: "Geschenkkarte  ·  Wert: 50,00 €", size: 38),
    Line(text: "Kartennummer: \(eanFull)", size: 30),
    Line(text: "Gültig bis 31.12.2029", size: 30)], code: ean13(eanFull), codeW: 560)
voucher("v02-thalia-code128-pin", bg: NSColor(red: 1, green: 0.95, blue: 0.9, alpha: 1), lines: [
    Line(text: "Thalia Geschenkkarte", size: 56, weight: .bold, color: NSColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 1)),
    Line(text: "Guthaben 25 €", size: 40),
    Line(text: "Kartennr. 6280 1234 5678 9012", size: 30),
    Line(text: "PIN: 4821    gültig bis 30.06.2028", size: 30)], code: code128("6280123456789012"), codeW: 700)
voucher("v03-ikea-qr-rotated", bg: .white, lines: [
    Line(text: "IKEA Gutschein", size: 60, weight: .heavy, color: NSColor(red: 0, green: 0.32, blue: 0.64, alpha: 1)),
    Line(text: "100,00 EUR", size: 44, weight: .bold),
    Line(text: "Code: IK-9934-2281-4410", size: 32),
    Line(text: "3 Jahre gültig ab Ausstellung", size: 28)], code: qr("IK-9934-2281-4410"), codeW: 300, rotate: 8)
voucher("v04-cafe-handschrift", bg: NSColor(red: 0.98, green: 0.95, blue: 0.86, alpha: 1), lines: [
    Line(text: "GUTSCHEIN", size: 66, weight: .heavy, color: .brown),
    Line(text: "Café Sonnenschein", size: 46, color: .darkGray, font: "Bradley Hand"),
    Line(text: "über 30,– Euro", size: 46, color: .darkGray, font: "Bradley Hand"),
    Line(text: "für Oma Gisela", size: 40, color: .darkGray, font: "Bradley Hand"),
    Line(text: "gültig bis Ende 2027", size: 40, color: .darkGray, font: "Bradley Hand")])
voucher("v05-zalando-rabatt-mbw", bg: .black, lines: [
    Line(text: "ZALANDO", size: 60, weight: .heavy, color: .orange),
    Line(text: "15 % Rabatt auf alles – ab 50 € Mindestbestellwert", size: 32, color: .white),
    Line(text: "Gutscheincode: ZAL15SOMMER26", size: 34, weight: .bold, color: .white),
    Line(text: "einlösbar bis 15.10.2026", size: 30, color: .white)])
voucher("v06-mediamarkt-falsche-pruefziffer", bg: .white, lines: [
    Line(text: "MediaMarkt Geschenkkarte", size: 52, weight: .heavy, color: .red),
    Line(text: "Wert 200 €", size: 40),
    Line(text: "Kundennummer: 88812345678", size: 28),
    Line(text: "gültig bis 01.03.2030", size: 28)], code: ean13(eanBad), codeW: 560)
voucher("v07-abgelaufen", bg: .white, lines: [
    Line(text: "H&M Geschenkkarte", size: 56, weight: .bold),
    Line(text: "Wert: 20,00 €", size: 40),
    Line(text: "Kartennummer 7002 5566 7788 9900", size: 30),
    Line(text: "gültig bis 31.12.2024", size: 30)], code: code128("7002556677889900"))
voucher("v08-unscharf-rauschen", bg: .white, lines: [
    Line(text: "Rossmann Geschenkkarte", size: 54, weight: .bold, color: .red),
    Line(text: "15 €", size: 44, weight: .bold),
    Line(text: "Nummer 9120 4455 1234", size: 30),
    Line(text: "gültig bis 12/28", size: 30)], code: code128("912044551234"), noise: true, blur: true)
voucher("v09-amazon-online", bg: NSColor(red: 0.14, green: 0.18, blue: 0.24, alpha: 1), lines: [
    Line(text: "amazon.de Gutschein", size: 56, weight: .bold, color: .white),
    Line(text: "Betrag: 1.250,00 €", size: 40, color: .white),
    Line(text: "Gutscheincode: AQ7K-2ZPM4H-R8TX", size: 34, weight: .bold, color: .orange),
    Line(text: "Guthaben ist 10 Jahre gültig", size: 28, color: .white)])
voucher("v10-kino-pdf417-englisch", bg: .white, lines: [
    Line(text: "CinemaxX Gift Card", size: 54, weight: .bold),
    Line(text: "Value: EUR 40", size: 40),
    Line(text: "Card number 5021 0099 3344 7781", size: 30),
    Line(text: "Valid thru Dec 31, 2028", size: 30)], code: pdf417("5021009933447781"), codeW: 800)
voucher("v11-leer-kein-gutschein", bg: .white, lines: [
    Line(text: "Einkaufsliste", size: 50, weight: .bold),
    Line(text: "Milch, Brot, Äpfel", size: 36, font: "Bradley Hand")])
voucher("v12-aztec-stadtgutschein", bg: NSColor(red: 0.9, green: 0.97, blue: 0.9, alpha: 1), lines: [
    Line(text: "Kassel Stadtgutschein", size: 54, weight: .heavy, color: NSColor(red: 0, green: 0.4, blue: 0.2, alpha: 1)),
    Line(text: "Wert 10 Euro", size: 40),
    Line(text: "Seriennummer KS-2026-004711", size: 30),
    Line(text: "Gültigkeit: 24 Monate", size: 30)], code: aztec("KS-2026-004711"), codeW: 260)

// PDF (E-Mail-Anhang) mit Textebene
let pdfURL = URL(fileURLWithPath: "v13-otto-anhang.pdf") as CFURL
var box = CGRect(x: 0, y: 0, width: 595, height: 842)
let pdf = CGContext(pdfURL, mediaBox: &box, nil)!
pdf.beginPDFPage(nil)
let ns = NSGraphicsContext(cgContext: pdf, flipped: false)
NSGraphicsContext.current = ns
for (i, s) in ["OTTO Geschenkgutschein", "Gutscheinwert: 75,00 €", "Bestellnummer: 55512349876", "Gutscheincode: OT-7731-5520-9912", "PIN 5531", "Einlösbar bis 28. Februar 2029"].enumerated() {
    (s as NSString).draw(at: NSPoint(x: 50, y: 760 - i * 40), withAttributes: [.font: NSFont.systemFont(ofSize: i == 0 ? 26 : 16, weight: i == 0 ? .bold : .regular)])
}
code128("OT773155209912")!.draw(in: NSRect(x: 50, y: 400, width: 400, height: 90))
NSGraphicsContext.current = nil
pdf.endPDFPage(); pdf.closePDF()
print("✓ v13 pdf")
