import Foundation
import CoreGraphics
import CoreImage
import CoreText
import Testing
@testable import RestwertKit

/// Testbilder werden zur Laufzeit gezeichnet: Gutschein mit Barcode und Text, dann absichtlich verschlechtert.
private enum Fixture {
    static let ci = CIContext()

    /// Weiße Karte mit Text oben und Barcode unten.
    static func voucher(width: Int = 1600, height: Int = 1000, lines: [String], barcode: CGImage?,
                        barcodeWidth: CGFloat = 1100, ink: CGFloat = 0, paper: CGFloat = 1) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: paper, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        var y = CGFloat(height) - 110
        for line in lines {
            draw(line, in: ctx, at: CGPoint(x: 80, y: y), size: 54, gray: ink)
            y -= 84
        }
        if let barcode {
            let h = min(CGFloat(barcode.height) * barcodeWidth / CGFloat(barcode.width), 320)
            ctx.interpolationQuality = .none
            ctx.draw(barcode, in: CGRect(x: (CGFloat(width) - barcodeWidth) / 2, y: 60, width: barcodeWidth, height: h))
        }
        return ctx.makeImage()!
    }

    static func draw(_ text: String, in ctx: CGContext, at p: CGPoint, size: CGFloat, gray: CGFloat) {
        let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: gray, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        ctx.textPosition = p
        CTLineDraw(line, ctx)
    }

    /// Barcode über CoreImage-Generatoren (Code 128, QR, PDF417, Aztec).
    static func generated(_ filter: String, _ payload: String) -> CGImage {
        let f = CIFilter(name: filter)!
        f.setValue(payload.data(using: .ascii), forKey: "inputMessage")
        if filter == "CICode128BarcodeGenerator" { f.setValue(10, forKey: "inputQuietSpace") }
        let img = f.outputImage!.transformed(by: CGAffineTransform(scaleX: 6, y: 6))
        return ci.createCGImage(img, from: img.extent)!
    }

    /// EAN-13/EAN-8/ITF über den eigenen Kodierer als Balken zeichnen (CoreImage kann kein EAN).
    static func bars(_ payload: String, _ format: CodeFormat, module: Int = 6, height: Int = 260) -> CGImage {
        let modules = BarcodeEncoder.modules(for: payload, format: format)!
        let quiet = 12
        let width = (modules.count + 2 * quiet) * module
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        for (i, on) in modules.enumerated() where on {
            ctx.fill(CGRect(x: (quiet + i) * module, y: 0, width: module, height: height))
        }
        return ctx.makeImage()!
    }

    static func apply(_ image: CGImage, _ transform: (CIImage) -> CIImage) -> CGImage {
        let input = CIImage(cgImage: image)
        let out = transform(input)
        let extent = out.extent.isInfinite ? input.extent : out.extent
        return ci.createCGImage(out, from: extent)!
    }

    static func rotated(_ image: CGImage, degrees: CGFloat) -> CGImage {
        apply(image) { img in
            let r = img.transformed(by: CGAffineTransform(rotationAngle: degrees * .pi / 180))
            // Weißer Hintergrund statt Transparenz, wie auf einem Foto.
            return r.composited(over: CIImage(color: .white).cropped(to: r.extent))
        }
    }

    static func blurred(_ image: CGImage, radius: CGFloat) -> CGImage {
        apply(image) { $0.clampedToExtent().applyingGaussianBlur(sigma: radius).cropped(to: $0.extent) }
    }

    /// Winziger Gutschein in der Ecke eines sehr großen, grauen „Fotos“.
    static func smallInHugePhoto(_ voucher: CGImage, canvas: CGSize = CGSize(width: 6000, height: 4500), scale: CGFloat = 0.35) -> CGImage {
        let ctx = CGContext(data: nil, width: Int(canvas.width), height: Int(canvas.height), bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 0.55, alpha: 1)); ctx.fill(CGRect(origin: .zero, size: canvas))
        let w = CGFloat(voucher.width) * scale, h = CGFloat(voucher.height) * scale
        ctx.interpolationQuality = .high
        ctx.draw(voucher, in: CGRect(x: canvas.width * 0.62, y: canvas.height * 0.08, width: w, height: h))
        return ctx.makeImage()!
    }
}

@Suite("Scannen: Barcode und Text aus Bildern")
struct VoucherScannerTests {
    private let number = "6300981274561234"
    private let lines = ["Thalia Geschenkkarte", "Wert 25,00 EUR", "PIN 4711", "gueltig bis 31.12.2027"]

    @Test("Sauberer Gutschein: Code 128 und Text")
    func clean() async {
        let img = Fixture.voucher(lines: lines, barcode: Fixture.generated("CICode128BarcodeGenerator", number))
        let r = await VoucherScanner.read(img)
        #expect(r.best?.payload == number)
        #expect(r.best?.format == .code128)
        let d = TextParser.parse(r.text)
        #expect(d.merchantID == "thalia")
        #expect(d.value == 25)
        #expect(d.pin == "4711")
        #expect(d.expires != nil)
    }

    @Test("EAN-13 wird erkannt und behält die Prüfziffer")
    func ean13() async {
        let ean = "4006381333931"
        let img = Fixture.voucher(lines: ["Douglas Geschenkkarte"], barcode: Fixture.bars(ean, .ean13), barcodeWidth: 900)
        let r = await VoucherScanner.read(img)
        #expect(r.best?.payload == ean)
        #expect(r.best?.format == .ean13)
    }

    @Test("Schief fotografiert (12°)")
    func rotatedSlightly() async {
        let img = Fixture.rotated(Fixture.voucher(lines: lines, barcode: Fixture.generated("CICode128BarcodeGenerator", number)), degrees: 12)
        let r = await VoucherScanner.read(img)
        #expect(r.best?.payload == number)
    }

    @Test("Hochkant fotografiert (90°)")
    func rotatedPortrait() async {
        let img = Fixture.rotated(Fixture.voucher(lines: lines, barcode: Fixture.generated("CICode128BarcodeGenerator", number)), degrees: 90)
        let r = await VoucherScanner.read(img)
        #expect(r.best?.payload == number)
    }

    @Test("Leicht unscharf")
    func blurred() async {
        let img = Fixture.blurred(Fixture.voucher(lines: lines, barcode: Fixture.generated("CICode128BarcodeGenerator", number)), radius: 1.6)
        let r = await VoucherScanner.read(img)
        #expect(r.best?.payload == number)
    }

    @Test("Blasser Druck auf grauem Papier")
    func lowContrast() async {
        let code = Fixture.apply(Fixture.generated("CICode128BarcodeGenerator", number)) {
            $0.applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 0.35, kCIInputBrightnessKey: 0.18])
        }
        let img = Fixture.voucher(lines: lines, barcode: code, ink: 0.45, paper: 0.82)
        let r = await VoucherScanner.read(img)
        #expect(r.best?.payload == number)
        #expect(TextParser.parse(r.text).value == 25)
    }

    @Test("Kleiner Gutschein in einem riesigen Foto")
    func smallInHugePhoto() async {
        let voucher = Fixture.voucher(lines: lines, barcode: Fixture.generated("CICode128BarcodeGenerator", number))
        let img = Fixture.smallInHugePhoto(voucher)
        let r = await VoucherScanner.read(img)
        #expect(r.best?.payload == number)
    }

    @Test("Strichcode und QR-Code: der Strichcode gewinnt")
    func prefersLinear() async {
        let ctxImg = Fixture.voucher(lines: ["Gutschein"], barcode: Fixture.generated("CICode128BarcodeGenerator", number), barcodeWidth: 800)
        // QR daneben einsetzen
        let qr = Fixture.generated("CIQRCodeGenerator", "https://example.com/gutschein/abc")
        let ctx = CGContext(data: nil, width: ctxImg.width, height: ctxImg.height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(ctxImg, in: CGRect(x: 0, y: 0, width: ctxImg.width, height: ctxImg.height))
        ctx.interpolationQuality = .none
        ctx.draw(qr, in: CGRect(x: 1180, y: 600, width: 340, height: 340))
        let r = await VoucherScanner.read(ctx.makeImage()!)
        #expect(r.codes.count >= 2)
        #expect(r.best?.payload == number)
    }

    @Test("Nur QR-Code (Stadtgutschein)")
    func qrOnly() async {
        let img = Fixture.voucher(lines: ["Stadtgutschein Koeln", "20,00 EUR"],
                                  barcode: Fixture.generated("CIQRCodeGenerator", "STADT-7F3K-99QX-2210"), barcodeWidth: 320)
        let r = await VoucherScanner.read(img)
        #expect(r.best?.payload == "STADT-7F3K-99QX-2210")
        #expect(r.best?.format == .qr)
    }

    @Test("PDF417 und Aztec (Tickets, Bahn)")
    func twoDimensional() async {
        for (filter, format) in [("CIPDF417BarcodeGenerator", CodeFormat.pdf417), ("CIAztecCodeGenerator", .aztec)] {
            let img = Fixture.voucher(lines: ["Ticket"], barcode: Fixture.generated(filter, "RW1234567890"), barcodeWidth: 520)
            let r = await VoucherScanner.read(img)
            #expect(r.best?.payload == "RW1234567890", "\(filter)")
            #expect(r.best?.format == format, "\(filter)")
        }
    }

    @Test("Papiergutschein ohne Code: nur Text")
    func textOnly() async {
        let img = Fixture.voucher(lines: ["GUTSCHEIN", "Cafe am Markt", "ueber 20,00 EUR", "gueltig bis 31.12.2027"], barcode: nil)
        let r = await VoucherScanner.read(img)
        #expect(r.best == nil)
        #expect(r.text.contains("Markt"))
        #expect(TextParser.parse(r.text).value == 20)
    }

    @Test("Leeres Bild liefert nichts, stürzt nicht ab")
    func empty() async {
        let img = Fixture.voucher(width: 400, height: 300, lines: [], barcode: nil)
        let r = await VoucherScanner.read(img)
        #expect(r.best == nil)
        #expect(r.codes.isEmpty)
    }

    @Test("Auswahl: falsche Prüfziffer verliert gegen Code 128")
    func scoring() {
        let wrongEAN = ScanReading.Code(payload: "4006381333932", format: .ean13)
        let c128 = ScanReading.Code(payload: "ABC123456", format: .code128)
        let qr = ScanReading.Code(payload: "https://x", format: .qr)
        #expect(VoucherScanner.bestCode([wrongEAN, c128, qr]) == c128)
        let goodEAN = ScanReading.Code(payload: "4006381333931", format: .ean13)
        #expect(VoucherScanner.bestCode([c128, goodEAN]) == goodEAN)
        #expect(VoucherScanner.bestCode([qr]) == qr)
    }
}

@Suite("Scannen: Härtefälle")
struct VoucherScannerHardTests {
    private let number = "6300981274561234"

    @Test("Winziger Gutschein im 27-MP-Foto: nur über Ausschnitte aus dem Original lesbar")
    func tinyInHugePhoto() async {
        let base = Fixture.voucher(lines: ["Thalia Geschenkkarte"], barcode: Fixture.generated("CICode128BarcodeGenerator", number))
        let img = Fixture.smallInHugePhoto(base, scale: 0.2)
        // Die einfache Erkennung auf dem ganzen Bild scheitert hier …
        #expect(await VoucherScanner.detect(img).first?.payload != number)
        // … die gestufte Erkennung findet den Code.
        #expect(await VoucherScanner.read(img).best?.payload == number)
    }
}

@Suite("Beträge in Kurzschreibweise (Papiergutscheine)")
struct ShortAmountTests {
    @Test("20,- / 20,– / 20.- werden zu 20,00", arguments: [
        ("über 20,- Euro", 20.0), ("Wert: 20,– €", 20.0), ("50.- EUR", 50.0), ("Gutschein über 15,-- Euro", 15.0),
    ])
    func shortForms(_ text: String, _ expected: Double) {
        #expect(TextParser.amount(in: text) == expected)
    }

    @Test("Bindestrich in Datum oder Code wird nicht zum Betrag")
    func noFalsePositive() {
        #expect(TextParser.amount(in: "Code 1234-5678 gültig bis 2027-12-31") == nil)
    }
}
