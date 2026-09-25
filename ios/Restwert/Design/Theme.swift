import SwiftUI
import RestwertKit

// MARK: - Farben

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }

    static let page = Color(hex: 0xF1F2F4)
    static let surface = Color.white
    static let fill = Color(hex: 0xF5F6F8)
    static let ink = Color(hex: 0x0E0E10)
    static let ink2 = Color(hex: 0x3A3C42)
    static let muted = Color(hex: 0x8A8D96)
    static let line = Color(hex: 0xE7E8EB)
    static let brandYellow = Color(hex: 0xFFE14D)
    static let keyBlue = Color(hex: 0x2451FF)
    static let good = Color(hex: 0x1E9E5A)
    static let goodSoft = Color(hex: 0xCFF0DC)
    static let bad = Color(hex: 0xE0413A)
    static let badSoft = Color(hex: 0xFBDCDA)
    static let warn = Color(hex: 0xE98A1E)
    static let warnSoft = Color(hex: 0xFDE8CC)
    static let paper = Color(hex: 0xFBF9F4)
}

enum Pastel {
    static let all: [Color] = [0xE4D7FB, 0xCDEFE3, 0xF1EFD9, 0xC9EEF0, 0xFBE1CF, 0xF9D8E8, 0xE6F5C9, 0xD9E2FB].map { Color(hex: $0) }

    static func color(for key: String) -> Color {
        var h: UInt32 = 11
        for u in key.unicodeScalars { h = h &* 31 &+ u.value }
        return all[Int(h % UInt32(all.count))]
    }

    static func color(for card: GiftCard) -> Color { color(for: card.merchantID + card.customName) }
}

extension MerchantCategory {
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

/// Kräftiger Haupt-Button in Markenfarbe (Schwarz oder Gelb).
struct FilledButtonStyle: ButtonStyle {
    var background: Color = .ink
    var foreground: Color = .white
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(background, in: .rect(cornerRadius: 18, style: .continuous))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.4), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == FilledButtonStyle {
    static var primary: FilledButtonStyle { FilledButtonStyle() }
    static var accent: FilledButtonStyle { FilledButtonStyle(background: .brandYellow, foreground: .ink) }
    static var quiet: FilledButtonStyle { FilledButtonStyle(background: .surface, foreground: .ink) }
}

// MARK: - Bausteine

struct LetterTile: View {
    let text: String
    let color: Color
    var size: CGFloat = 46

    var body: some View {
        Text(text.initials)
            .font(.system(size: size * 0.33, weight: .heavy))
            .foregroundStyle(Color.ink)
            .frame(width: size, height: size)
            .background(color, in: .rect(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct Chip: View {
    let text: String
    var fg: Color = .ink2
    var bg: Color = .line

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(fg)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(bg, in: .capsule)
    }
}

struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            Text(title).font(.system(size: 20, weight: .bold))
            Spacer()
            trailing
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: String) {
        self.title = title
        self.trailing = EmptyView()
    }
}

/// Eingabefeld im Stil der grauen Kästen mit kleiner Beschriftung.
struct LabeledBox<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.muted)
            content.font(.system(size: 16, weight: .semibold))
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.fill, in: .rect(cornerRadius: 16, style: .continuous))
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

/// Perforierte Trennlinie wie bei einem Ticket.
struct Perforation: View {
    var holeColor: Color = .page

    var body: some View {
        ZStack {
            HLine().stroke(style: StrokeStyle(lineWidth: 2, dash: [6, 6])).foregroundStyle(Color.line)
                .frame(height: 2).padding(.horizontal, 22)
            HStack {
                Circle().fill(holeColor).frame(width: 28, height: 28).offset(x: -14)
                Spacer()
                Circle().fill(holeColor).frame(width: 28, height: 28).offset(x: 14)
            }
        }
        .frame(height: 28)
        .accessibilityHidden(true)
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

struct DashedRule: View {
    var body: some View {
        HLine().stroke(style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])).foregroundStyle(Color.muted.opacity(0.6)).frame(height: 1)
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
                .padding(.horizontal, 18).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.paper)
            ZigZag(top: false).fill(Color.paper).frame(height: 10)
        }
        .foregroundStyle(Color.ink)
        .shadow(color: Color.ink.opacity(0.08), radius: 12, y: 6)
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

extension View {
    func cardSurface(radius: CGFloat = 26) -> some View {
        background(Color.surface, in: .rect(cornerRadius: radius, style: .continuous))
            .shadow(color: Color.ink.opacity(0.06), radius: 14, y: 6)
    }

    /// Einheitlicher Seitenhintergrund.
    func pageBackground() -> some View {
        background(Color.page.ignoresSafeArea())
    }
}
