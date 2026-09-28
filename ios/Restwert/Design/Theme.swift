import SwiftUI
import UIKit
import RestwertKit

// MARK: - Farben

extension Color {
    nonisolated init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }

    /// Farbe mit eigenem Wert für den Dunkelmodus und optional kräftigeren Werten bei „Kontrast erhöhen“.
    nonisolated init(light: UInt32, dark: UInt32, highLight: UInt32, highDark: UInt32) {
        func ui(_ hex: UInt32) -> UIColor {
            UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        self.init(uiColor: UIColor { t in
            let high = t.accessibilityContrast == .high
            return t.userInterfaceStyle == .dark ? ui(high ? highDark : dark) : ui(high ? highLight : light)
        })
    }

    /// Farbe mit eigenem Wert für den Dunkelmodus.
    nonisolated init(light: UInt32, dark: UInt32) {
        func ui(_ hex: UInt32) -> UIColor {
            UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
    }

    // Papier statt Systemgrau: warmer Grund, Tinte statt reinem Schwarz.
    static let page = Color(light: 0xF6F4EF, dark: 0x141311)
    static let surface = Color(light: 0xFFFFFF, dark: 0x1E1D1B)
    // Kacheln: bei „Kontrast erhöhen“ deutlich vom Papier abgesetzt.
    static let fill = Color(light: 0xEFECE5, dark: 0x2A2926, highLight: 0xDCD7CB, highDark: 0x3D3B37)
    static let ink = Color(light: 0x111111, dark: 0xF2F0EA)
    // Grautöne warm wie das Papier, keine kalten Systemgraus. muted hält ≥ 4,5:1 auch auf `fill`.
    // Bei „Kontrast erhöhen“ (Bedienungshilfen) kräftiger: Nebentexte fast wie Haupttext, Linien sichtbar.
    static let ink2 = Color(light: 0x3A3833, dark: 0xCFCDC6, highLight: 0x1F1D1A, highDark: 0xEAE8E2)
    static let muted = Color(light: 0x5C5953, dark: 0xA9A59C, highLight: 0x33312D, highDark: 0xD6D3CB)
    static let line = Color(light: 0xE6E2D9, dark: 0x34322E, highLight: 0x8C877C, highDark: 0x77736A)
    /// Text auf `ink`-Flächen (Hauptknopf, aktive Chips): weiß im Hellen, Tinte im Dunkeln.
    static let onInk = Color(light: 0xFFFFFF, dark: 0x111111)
    /// Text auf Markengelb: immer Tinte.
    static let onBrand = Color(hex: 0x111111)
    /// Markengelb: die App selbst (Summe, Stempel, Widget). Nie Ladenfarbe, nie Aktionsknopf. In beiden Modi hell genug, kein Senf.
    static let brandYellow = Color(light: 0xFFD84D, dark: 0xF5CE3E)
    static let keyBlue = Color(hex: 0x2451FF)
    /// Summenkarte: in beiden Modi gelbe Fläche mit Tinte darauf.
    static let sumFill = brandYellow
    static let sumText = Color(hex: 0x111111)
    static let sumAmount = Color(hex: 0x111111)
    /// Symbole auf `ink`-Flächen (Toast): jeweils die Variante des anderen Modus, weil `ink` die Helligkeit umkehrt.
    /// Hell #4CC38A/#FF7A70 auf #111111, dunkel #1F7A4D/#C4221A auf #F2F0EA – alle ≥ 4,5:1.
    static let goodOnInk = Color(light: 0x4CC38A, dark: 0x1F7A4D)
    static let warnOnInk = Color(light: 0xFF7A70, dark: 0xC4221A)
    static let good = Color(light: 0x1F7A4D, dark: 0x4CC38A)
    static let goodSoft = Color(light: 0xD9F0E2, dark: 0x173628)
    static let bad = Color(light: 0xC4221A, dark: 0xFF7A70)
    static let badSoft = Color(light: 0xF9DEDC, dark: 0x3D1714)
    /// Frist bis 14 Tage (dringend) – als Pill mit 12 % Tönung.
    static let warn = Color(light: 0xC4221A, dark: 0xFF7A70)
    static let warnSoft = Color(light: 0xC4221A, dark: 0xFF7A70).opacity(0.12)
    /// Frist 15–30 Tage – nur als Text. Hell ≥ 5:1 auf page, surface und fill (#9A4C00: 5,6 / 6,2 / 5,2), dunkel ≥ 8:1.
    static let soon = Color(light: 0x9A4C00, dark: 0xFFB340)
    /// Hinweis-Streifen (z. B. „Betrag offen“): dieselbe Tönung wie Fristen 15–30 Tage, kein eigenes Orange.
    static let notice = soon
    /// Schalter „an“: Grün wie iOS, weil Tinte im Dunkeln hell ist und der weiße Knopf sonst verschwindet.
    static let toggleOn = Color(light: 0x1F7A4D, dark: 0x34A76E)
    /// Schatten: im Hellen zarte Tinte, im Dunkeln echtes Schwarz (helle Tinte würde grau schimmern).
    static let shade = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor.black.withAlphaComponent(0.45) : UIColor(red: 0.07, green: 0.07, blue: 0.07, alpha: 0.08) })
    static let paper = Color(light: 0xFBF9F4, dark: 0x24221E)
    static let disabledFill = Color(light: 0xE4E0D7, dark: 0x2E2D2A)
    static let disabledText = muted
}

extension MerchantCategory {
    var symbol: String {
        switch self {
        case .official: "iphone"
        case .codeOnly: "globe"
        case .merchantApp: "app.badge"
        case .untested: "questionmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .official: .good
        case .codeOnly: .ink2
        case .merchantApp, .untested: .warn
        }
    }

    var soft: Color {
        switch self {
        case .official: .goodSoft
        case .codeOnly: .line
        case .merchantApp, .untested: .warnSoft
        }
    }
}

extension VoucherStatus {
    var tint: Color {
        switch self {
        case .valid: .good
        case .expiringSoon: .warn
        case .redeemed: .ink2
        case .expired: .bad
        }
    }

    var soft: Color {
        switch self {
        case .valid: .goodSoft
        case .expiringSoon: .warnSoft
        case .redeemed: .line
        case .expired: .badSoft
        }
    }
}

// MARK: - Buttons

// MARK: - Raster

/// Ein Raster für alle Screens: Stufen 4/8/12/16/20/24/32, 16 pt Seitenrand, 24 pt zwischen Abschnitten, feste Radien.
enum Layout {
    static let page: CGFloat = 16
    static let section: CGFloat = 24
    static let group: CGFloat = 12
    /// Innenabstand aller Karten und Kacheln; Tickets bekommen etwas mehr.
    static let inset: CGFloat = 16
    static let ticketInset: CGFloat = 20
    /// Mindestgröße für Tippziele.
    static let tap: CGFloat = 44
    /// Radien: groß 24 (Karten), mittel 16 (Knöpfe, Kacheln), klein 10 (Felder); sonst Capsule.
    static let cardRadius: CGFloat = 24
    static let buttonRadius: CGFloat = 16
    static let controlRadius: CGFloat = 10
}

extension Font {
    /// Beträge in Listen: SF Rounded, fett, gleich breite Ziffern (damit Spalten fluchten).
    static func amount(_ size: CGFloat) -> Font {
        .scaled(size, weight: .heavy, design: .rounded).monospacedDigit()
    }

    /// Große Einzelbeträge: proportionale Ziffern, sonst klafft hinter der „1“ ein Loch.
    static func display(_ size: CGFloat) -> Font {
        .scaled(size, weight: .heavy, design: .rounded)
    }
}

/// Haupt-Button: pro Screen genau einer, immer Schwarz (im Dunkeln Weiß). Gelb ist Marke, keine Aktionsfarbe.
struct FilledButtonStyle: ButtonStyle {
    var background: Color = .ink
    var foreground: Color = .onInk
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.scaled(16, weight: .bold))
            .multilineTextAlignment(.center)
            .padding(.horizontal, Layout.inset).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(isEnabled ? foreground : Color.disabledText)
            .background(isEnabled ? background : Color.disabledFill, in: .rect(cornerRadius: Layout.buttonRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.4), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == FilledButtonStyle {
    static var primary: FilledButtonStyle { FilledButtonStyle() }
    /// Früher Gelb; jetzt wie `primary`, damit es pro Screen nur eine laute Farbe für Aktionen gibt.
    static var accent: FilledButtonStyle { FilledButtonStyle() }
    static var quiet: FilledButtonStyle { FilledButtonStyle(background: .surface, foreground: .ink) }
}

// MARK: - Bausteine

/// Auswahl-Chip für alle Filter der App: Tinte = aktiv, Fläche = inaktiv, 44 pt hoch.
struct FilterChip: View {
    let title: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.scaled(15, weight: .semibold))
                .foregroundStyle(on ? Color.onInk : Color.ink)
                .padding(.horizontal, Layout.inset).frame(minHeight: Layout.tap)
                .background(on ? Color.ink : Color.surface, in: .capsule)
                // Inaktiv: feine Kante, sonst verschwimmt Weiß auf dem Papiergrund.
                .overlay { if !on { Capsule().strokeBorder(Color.line, lineWidth: 1) } }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

struct Chip: View {
    let text: String
    var fg: Color = .ink2
    var bg: Color = .line

    var body: some View {
        Text(text)
            .font(.scaled(12, weight: .bold))
            .foregroundStyle(fg)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(bg, in: .capsule)
    }
}

/// Eingabefeld im Stil der grauen Kästen mit kleiner Beschriftung.
struct LabeledBox<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.scaled(12, weight: .semibold)).foregroundStyle(Color.muted)
            content.font(.scaled(16, weight: .semibold))
        }
        .padding(.horizontal, 4).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.line).frame(height: 0.5) }
    }
}

struct LabeledField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default

    var body: some View {
        LabeledBox(label: label) {
            TextField(placeholder, text: $text).keyboardType(keyboard)
        }
    }
}

struct HLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}

/// Gestrichelte Linie mit gleichmäßig verteilten Strichen: beginnt und endet immer mit einem vollen Strich.
/// Eine Strichelung für die ganze App (Ticket, Bon).
struct DashLine: Shape {
    var dash: CGFloat = 4
    var gap: CGFloat = 4

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let n = max(1, Int(((rect.width + gap) / (dash + gap)).rounded(.down)))
        let step = n > 1 ? (rect.width - dash) / CGFloat(n - 1) : 0
        for i in 0..<n {
            let x = rect.minX + CGFloat(i) * step
            p.addRect(CGRect(x: x, y: rect.midY - 0.5, width: dash, height: 1))
        }
        return p
    }
}

struct DashedRule: View {
    var body: some View {
        DashLine().fill(Color.muted.opacity(0.6)).frame(height: 1).accessibilityHidden(true)
    }
}

/// Gezackte Kante für den Bon.
struct ZigZag: Shape {
    var tooth: CGFloat = 10
    var top = true

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let count = max(1, Int(rect.width / tooth))
        let w = rect.width / CGFloat(count)
        let edge = top ? rect.minY : rect.maxY
        let base = top ? rect.minY + tooth / 2 : rect.maxY - tooth / 2
        p.move(to: CGPoint(x: rect.minX, y: top ? rect.maxY : rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: base))
        for i in 0..<count {
            let x = rect.minX + CGFloat(i) * w
            p.addLine(to: CGPoint(x: x + w / 2, y: edge))
            p.addLine(to: CGPoint(x: x + w, y: base))
        }
        p.addLine(to: CGPoint(x: rect.maxX, y: top ? rect.maxY : rect.minY))
        p.closeSubpath()
        return p
    }
}

/// Papier-Bon mit gezackten Kanten.
struct ReceiptPaper<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            ZigZag(top: true).fill(Color.paper).frame(height: 10)
            content
                .padding(.horizontal, Layout.inset).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.paper)
            ZigZag(top: false).fill(Color.paper).frame(height: 10)
        }
        .foregroundStyle(Color.ink)
        .ticketShadow(radius: 12)
    }
}

/// Wackeln bei falscher Eingabe.
struct Shake: GeometryEffect {
    var amount: CGFloat = 8
    var shakes: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: amount * sin(animatableData * .pi * shakes), y: 0))
    }
}

// MARK: - Schatten

/// Schatten der App: zwei Stufen, beide in `Color.shade`.
/// Regel: Schatten immer über `.compositingGroup()` – sonst wirft jeder Text und jedes Symbol auf der Karte
/// einen eigenen Schatten (im Dunkeln 45 % Schwarz: Gelb wird Senf, Text bekommt einen braunen Hof).
enum Shadow {
    /// Karten, Tickets, Bon.
    static let card: CGFloat = 14
    /// Schwebendes über allem (Toast).
    static let float: CGFloat = 16
}

extension View {
    /// Schatten für Karten und Tickets: erst zu einer Ebene zusammenfassen, dann ein einziger Schatten.
    func ticketShadow(radius: CGFloat = Shadow.card, y: CGFloat = 6) -> some View {
        compositingGroup().shadow(color: Color.shade, radius: radius, y: y)
    }

    func cardSurface(radius: CGFloat = Layout.cardRadius) -> some View {
        background(Color.surface, in: .rect(cornerRadius: radius, style: .continuous))
            .ticketShadow()
    }

    /// Einheitlicher Seitenhintergrund mit weicher Scroll-Kante oben auf allen Screens.
    /// Unten ebenfalls weich, damit Inhalt unter Tab-Leiste und `safeAreaBar`-Leisten ausblendet statt hart zu enden.
    /// Achtung: Leisten per `safeAreaInset` bekommen keinen Kanteneffekt – dafür `safeAreaBar` nehmen.
    func pageBackground() -> some View {
        scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
            // Die schwebende Tab-Leiste steckt schon in der Safe Area; nur ein Abschnittsabstand Luft dazu.
            .contentMargins(.bottom, Layout.section, for: .scrollContent)
            .background(Color.page.ignoresSafeArea())
    }
}

// MARK: - Schrift

extension Font {
    /// Systemschrift, die mit „Größerer Text“ in den iOS-Einstellungen mitwächst.
    /// Relativ zu einem Textstil skaliert: SwiftUI löst die Größe erst beim Zeichnen auf,
    /// daher passt sich die Schrift ohne Neuaufbau der Ansichten an.
    /// Große Zahlen hängen an „Large Title“, der am wenigsten wächst, damit Beträge nicht umbrechen;
    /// kleinere Schrift an „Title 2“ (bis etwa Faktor 2,5 bei der größten Stufe).
    static func scaled(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        let (style, base): (Font.TextStyle, CGFloat) = size >= 28 ? (.largeTitle, 34) : (.title2, 22)
        return .system(style, design: design, weight: weight).scaled(by: size / base)
    }
}

// MARK: - Ticket (Signaturform)

/// Die Signaturform der App: ein Abschnitt mit zwei ausgestanzten Kerben links und rechts.
/// Nur für Summenkarte, Detailkarte, Kassen-Ticket, Stempel und Leerzustände – nirgends sonst.
struct TicketShape: Shape {
    var radius: CGFloat = 24
    var notchRadius: CGFloat = 9
    /// Höhe der Kerben als Anteil der Höhe (0…1) oder fester Abstand von oben.
    var notchY: CGFloat = 0.62
    var notchFromTop: CGFloat? = nil
    var notchFromBottom: CGFloat? = nil
    var sides: Edges = [.leading, .trailing]

    struct Edges: OptionSet { let rawValue: Int; static let leading = Edges(rawValue: 1); static let trailing = Edges(rawValue: 2) }

    func notchCenter(in rect: CGRect) -> CGFloat {
        if let b = notchFromBottom { return rect.maxY - b }
        return notchFromTop.map { rect.minY + $0 } ?? rect.minY + rect.height * notchY
    }

    func path(in rect: CGRect) -> Path {
        var p = Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
        let y = notchCenter(in: rect)
        var cut = Path()
        if sides.contains(.leading) { cut.addEllipse(in: CGRect(x: rect.minX - notchRadius, y: y - notchRadius, width: notchRadius * 2, height: notchRadius * 2)) }
        if sides.contains(.trailing) { cut.addEllipse(in: CGRect(x: rect.maxX - notchRadius, y: y - notchRadius, width: notchRadius * 2, height: notchRadius * 2)) }
        p = p.subtracting(cut)
        return p
    }
}

/// Eine Hälfte eines Tickets zum Abreißen: außen gerundet, an der Naht gerade mit halben Kerben.
struct TicketHalf: Shape {
    var top: Bool
    var radius: CGFloat = 24
    var notchRadius: CGFloat = 9

    func path(in rect: CGRect) -> Path {
        let r = top ? RectangleCornerRadii(topLeading: radius, topTrailing: radius)
                    : RectangleCornerRadii(bottomLeading: radius, bottomTrailing: radius)
        var p = UnevenRoundedRectangle(cornerRadii: r, style: .continuous).path(in: rect)
        let y = top ? rect.maxY : rect.minY
        var cut = Path()
        cut.addEllipse(in: CGRect(x: rect.minX - notchRadius, y: y - notchRadius, width: notchRadius * 2, height: notchRadius * 2))
        cut.addEllipse(in: CGRect(x: rect.maxX - notchRadius, y: y - notchRadius, width: notchRadius * 2, height: notchRadius * 2))
        p = p.subtracting(cut)
        return p
    }
}

/// Gestrichelte Abrisslinie zwischen den Kerben.
struct TearLine: View {
    var color: Color = .ink
    var body: some View {
        DashLine().fill(color.opacity(0.3))
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

// MARK: - Betrag

/// Beträge wie auf einem Preisschild: große Euro mit Komma auf der Grundlinie, kleine hochgestellte Cent und €-Zeichen.
/// Die Cent schließen oben mit den Euro-Ziffern ab.
///
/// Unterschneidung gemessen an SF Rounded Heavy (proportionale Ziffern, je Anteil der Schriftgröße):
/// Ziffern haben rechts ~0,04 Fleisch, die „1“ aber ~0,105 – dahinter klaffte ein Loch. Das Komma hat rechts ~0,075,
/// die kleine Cent-Ziffer links ~0,02 – das ergab „136, 25“. Tabellarische Ziffern wären noch schlimmer (die „1“ dort ~0,19).
struct AmountText: View {
    let value: Double
    var size: CGFloat = 56
    /// Alle Beträge hängen an „Large Title“ (Font.scaled ab 28 pt); Abstände wachsen mit.
    @ScaledMetric(relativeTo: .largeTitle) private var scale: CGFloat = 1

    private var parts: (String, String) {
        let s = value.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "de_DE")))
        let comps = s.split(separator: ",", maxSplits: 1).map(String.init)
        return (comps.first ?? s, comps.count > 1 ? comps[1] : "00")
    }

    private var attributed: AttributedString {
        let (euros, cents) = parts
        let em = size * scale
        var text = AttributedString()
        for ch in euros {
            var digit = AttributedString(String(ch))
            digit.font = .display(size)
            // Grundunterschneidung -0,02; nach der „1“ zusätzlich ihr überschüssiges Fleisch abziehen.
            digit.kern = -em * (ch == "1" ? 0.085 : 0.02)
            text += digit
        }
        var comma = AttributedString(",")
        comma.font = .display(size)
        // Komma rückt an die Cent heran: bleibt ~1 pt Luft, keine sichtbare Lücke.
        comma.kern = -em * 0.075
        text += comma
        var small = AttributedString("\(cents) €")
        // Fest an „Large Title“ wie die Euro: über `.display` hinge die kleine Größe (< 28) an „Title 2“,
        // die bei großen Textgrößen stärker wächst – dann kippt das Verhältnis und die Hochstellung passt nicht mehr.
        small.font = .system(.largeTitle, design: .rounded, weight: .heavy).scaled(by: size * 0.46 / 34)
        small.baselineOffset = em * 0.40
        text += small
        return text
    }

    var body: some View {
        Text(attributed)
            .contentTransition(.numericText(value: value))
            .lineLimit(1).minimumScaleFactor(0.5)
            .accessibilityLabel(value.euro)
    }
}

/// Stempel „Aufgebraucht“ in der Betragsschrift, leicht schräg.
struct UsedUpStamp: View {
    var text = "AUFGEBRAUCHT"
    @State private var landed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(text)
            .font(.scaled(22, weight: .heavy, design: .rounded)).kerning(3)
            // Immer Tinte auf Gelb – `ink` wäre im Dunkeln hell und damit unlesbar.
            .foregroundStyle(Color.onBrand)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .overlay(RoundedRectangle(cornerRadius: Layout.controlRadius).strokeBorder(Color.onBrand, lineWidth: 3))
            .background(Color.brandYellow, in: .rect(cornerRadius: Layout.controlRadius))
            .rotationEffect(.degrees(-8))
            .scaleEffect(landed || reduceMotion ? 1 : 1.3)
            .opacity(landed || reduceMotion ? 1 : 0)
            .onAppear { withAnimation(.spring(duration: 0.25, bounce: 0.3)) { landed = true } }
            .accessibilityLabel("Aufgebraucht")
    }
}

// MARK: - Wortmarke

/// Wortmarke: „Restwert“ in der Betragsschrift mit gelbem Punkt. Überall dieselbe, der Punkt wächst mit der Schrift.
struct Wordmark: View {
    var size: CGFloat = 30
    @ScaledMetric(relativeTo: .largeTitle) private var scale: CGFloat = 1

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: size * 0.1) {
            Text("Restwert").font(.scaled(size, weight: .heavy, design: .rounded)).foregroundStyle(Color.ink)
            Circle().fill(Color.brandYellow).frame(width: size * 0.36 * scale, height: size * 0.36 * scale)
                .overlay(Circle().strokeBorder(Color.ink.opacity(0.2), lineWidth: 0.5))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Restwert")
        .accessibilityAddTraits(.isHeader)
    }
}


// MARK: - Gerät und Lesebreite

/// „iPhone“ oder „iPad“ – für Texte wie „nur auf diesem iPad“ oder „iPad-Code“.
nonisolated enum Device {
    static let name: String = {
        var id = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? ""
        if id.isEmpty {
            var info = utsname()
            uname(&info)
            id = withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        }
        return id.hasPrefix("iPad") ? "iPad" : "iPhone"
    }()
}

/// Auf breiten Bildschirmen (iPad, Querformat) Inhalt mittig auf lesbare Breite begrenzen, Scrollbereich bleibt voll.
struct ReadableWidth: ViewModifier {
    var maxWidth: CGFloat = 700
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .contentMargins(.horizontal, max(0, (width - maxWidth) / 2), for: .scrollContent)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

extension View {
    func readableWidth(_ maxWidth: CGFloat = 700) -> some View { modifier(ReadableWidth(maxWidth: maxWidth)) }
}
