import SwiftUI

// MARK: - Colors

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

// MARK: - Buttons

struct FilledButtonStyle: ButtonStyle {
    var background: Color = .ink
    var foreground: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

struct CircleButton: View {
    let systemImage: String
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.ink)
                .frame(width: 48, height: 48)
                .background(Color.surface, in: Circle())
                .overlay(Circle().stroke(Color.line, lineWidth: 1))
        }
        .accessibilityLabel(label)
    }
}

// MARK: - Small building blocks

struct LetterTile: View {
    let text: String
    let color: Color
    var size: CGFloat = 46

    var body: some View {
        Text(text.initials)
            .font(.system(size: size * 0.33, weight: .heavy))
            .foregroundStyle(Color.ink)
            .frame(width: size, height: size)
            .background(color, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
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
            .background(bg, in: Capsule())
    }
}

struct SectionHeader: View {
    let title: String
    var trailing: String?
    var action: (() -> Void)?

    var body: some View {
        HStack {
            Text(title).font(.system(size: 20, weight: .bold))
            Spacer()
            if let trailing {
                if let action {
                    Button(trailing, action: action).font(.system(size: 15, weight: .bold)).foregroundStyle(Color.ink)
                } else {
                    Text(trailing).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.muted)
                }
            }
        }
    }
}

/// Perforierte Trennlinie wie bei einem Ticket.
struct Perforation: View {
    var holeColor: Color = .page

    var body: some View {
        ZStack {
            Line().stroke(style: StrokeStyle(lineWidth: 2, dash: [6, 6])).foregroundStyle(Color.line).frame(height: 2).padding(.horizontal, 22)
            HStack {
                Circle().fill(holeColor).frame(width: 28, height: 28).offset(x: -14)
                Spacer()
                Circle().fill(holeColor).frame(width: 28, height: 28).offset(x: 14)
            }
        }
        .frame(height: 28)
    }

    struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return p
        }
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
        if top {
            p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tooth / 2))
            for i in 0..<count {
                let x = rect.minX + CGFloat(i) * w
                p.addLine(to: CGPoint(x: x + w / 2, y: rect.minY))
                p.addLine(to: CGPoint(x: x + w, y: rect.minY + tooth / 2))
            }
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        } else {
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - tooth / 2))
            for i in 0..<count {
                let x = rect.minX + CGFloat(i) * w
                p.addLine(to: CGPoint(x: x + w / 2, y: rect.maxY))
                p.addLine(to: CGPoint(x: x + w, y: rect.maxY - tooth / 2))
            }
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
        p.closeSubpath()
        return p
    }
}

extension View {
    func cardSurface(radius: CGFloat = 26) -> some View {
        background(Color.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: Color.ink.opacity(0.06), radius: 14, y: 6)
    }
}
