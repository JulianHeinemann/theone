import SwiftUI
import RestwertKit

/// Markenfarben der bekannten Händler, damit man IKEA oder Douglas in der Liste auf einen Blick erkennt.
/// Eigene Gutscheine ohne bekannten Händler bekommen eine neutrale Kachel mit Initialen.
nonisolated struct MerchantBrand: Sendable {
    let background: Color
    let foreground: Color
    /// Kurzform, die in die Kachel passt (z. B. „MM“ für MediaMarkt, „DB“ für die Bahn).
    let mark: String?
    /// Farbe für Icons auf hellem Grund: die Ladenfarbe, bei sehr hellen Läden (dm, Google Play) deren Schriftfarbe.
    let accent: Color

    init(_ bg: UInt32, _ fg: UInt32, _ mark: String? = nil) {
        background = Color(hex: bg)
        foreground = Color(hex: fg)
        self.mark = mark
        let r = Double((bg >> 16) & 0xFF), g = Double((bg >> 8) & 0xFF), b = Double(bg & 0xFF)
        accent = (0.299 * r + 0.587 * g + 0.114 * b) > 215 ? Color(hex: fg) : Color(hex: bg)
    }

    static let neutral = MerchantBrand(0x3A3A3C, 0xFFFFFF)

    /// Eigene Läden: feste Farbe aus dem Namen (FNV-1a, stabil über Starts), gedeckte Töne mit Weiß darauf.
    /// Regel: Ladenkacheln sind nie Schwarz und nie Gelb – Gelb gehört der App, Tinte der Hauptaktion.
    static let palette: [UInt32] = [0x1F6F68, 0x3B5BA5, 0x7A4FB5, 0xB5475A, 0xC2410C, 0x2F7D3B, 0x0369A1, 0x6B5B3E]
    static func fallback(for name: String) -> MerchantBrand {
        var h: UInt32 = 2166136261
        for b in name.lowercased().utf8 { h = (h ^ UInt32(b)) &* 16777619 }
        return MerchantBrand(palette[Int(h % UInt32(palette.count))], 0xFFFFFF)
    }

    static func forID(_ id: String?) -> MerchantBrand? { id.flatMap { table[$0] } }

    private static let table: [String: MerchantBrand] = [
        "amazon": .init(0x232F3E, 0xFF9900, "a"),
        "zalando": .init(0xFF6900, 0xFFFFFF, "Z"),
        "otto": .init(0xD4021D, 0xFFFFFF, "OTTO"),
        "apple": .init(0x2C2C2E, 0xFFFFFF, "\u{F8FF}"),
        "googleplay": .init(0xFFFFFF, 0x01875F, "▶"),
        "spotify": .init(0x1DB954, 0x000000, "S"),
        "netflix": .init(0x2C2C2E, 0xE50914, "N"),
        "db": .init(0xEC0016, 0xFFFFFF, "DB"),
        "lieferando": .init(0xFF8000, 0xFFFFFF, "L"),
        "wunschgutschein": .init(0x1B2D5B, 0xFFFFFF, "W"),
        "eventim": .init(0x002B55, 0xFFD400, "E"),
        "ticketmaster": .init(0x026CDF, 0xFFFFFF, "t"),
        "ikea": .init(0x0058A3, 0xFFDB00, "IKEA"),
        "thalia": .init(0x1E6E6B, 0xFFFFFF, "T"),
        "zara": .init(0x2C2C2E, 0xFFFFFF, "ZARA"),
        "tkmaxx": .init(0xD6001C, 0xFFFFFF, "TK"),
        "decathlon": .init(0x3643BA, 0xFFFFFF, "D"),
        "douglas": .init(0x2C2C2E, 0xFFFFFF, "D"),
        "hm": .init(0xE50010, 0xFFFFFF, "H&M"),
        "rossmann": .init(0xC3002F, 0xFFFFFF, "R"),
        "lidl": .init(0x0050AA, 0xFFF000, "Lidl"),
        "kaufland": .init(0xE10915, 0xFFFFFF, "K"),
        "aldi": .init(0x00005F, 0xFFFFFF, "ALDI"),
        "mueller": .init(0xF26722, 0xFFFFFF, "M"),
        "tchibo": .init(0x002D5A, 0xFFFFFF, "T"),
        "cinemaxx": .init(0x2C2C2E, 0xFFFFFF, "CX"),
        "nike": .init(0x2C2C2E, 0xFFFFFF, "NIKE"),
        "mediamarkt": .init(0xDF0000, 0xFFFFFF, "MM"),
        "saturn": .init(0x2C2C2E, 0xFF7F00, "S"),
        "rewe": .init(0xCC071E, 0xFFFFFF, "REWE"),
        "stadtgutschein": .init(0x3A3A3C, 0xFFFFFF, "€"),
        "dm": .init(0xFFFFFF, 0x002878, "dm"),
        "breuninger": .init(0x2C2C2E, 0xFFFFFF, "B"),
        "ca": .init(0x0054A0, 0xFFFFFF, "C&A"),
        "primark": .init(0x00A6E2, 0xFFFFFF, "P"),
        "deichmann": .init(0x008C45, 0xFFFFFF, "D"),
        "edeka": .init(0x1A4A99, 0xFFD400, "E"),
        "netto": .init(0xE2001A, 0xFFE500, "N"),
        "penny": .init(0xCD1719, 0xFFFFFF, "P"),
        "galeria": .init(0x00553F, 0xFFFFFF, "G"),
        "adidas": .init(0x2C2C2E, 0xFFFFFF, "a"),
        "sephora": .init(0x2C2C2E, 0xFFFFFF, "S"),
    ]
}

/// Quadratische Händler-Kachel in Markenfarbe. Unbekannte Händler: neutral mit Initialen.
struct MerchantMark: View {
    let merchantID: String?
    let name: String
    var size: CGFloat = 44

    var body: some View {
        let brand = MerchantBrand.forID(merchantID)
        let text = brand?.mark ?? name.initials
        let style = brand ?? (name.isEmpty ? .neutral : MerchantBrand.fallback(for: name))
        Text(text)
            .font(.system(size: size * (text.count > 2 ? 0.26 : 0.4), weight: .black))
            .kerning(text.count > 2 ? -0.3 : 0)
            .lineLimit(1).minimumScaleFactor(0.5)
            .padding(.horizontal, 4)
            .foregroundStyle(style.foreground)
            .frame(width: size, height: size)
            .background(style.background, in: .rect(cornerRadius: size * 0.24, style: .continuous))
            .overlay {
                // Kante, damit helle Kacheln im Hellen und dunkle im Dunkeln nicht verschwinden.
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .strokeBorder(Color.ink.opacity(0.12), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}

extension MerchantMark {
    init(card: GiftCard, size: CGFloat = 44) {
        self.init(merchantID: card.merchantID, name: card.name, size: size)
    }
}

/// Der Gutschein als Karte in Markenfarbe, mit dem Restwert als größtem Element.
/// Angelehnt an echte Geschenkkarten (Scheckkartenformat), damit man die Karte aus der Schublade wiedererkennt.
struct BalanceCard: View {
    let card: GiftCard
    let status: VoucherStatus
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var tearY: CGFloat = 170

    /// Wie in der Liste: „läuft heute/morgen ab“ statt „noch 0/1 Tage“.
    private var badgeText: String {
        guard status == .expiringSoon else { return status.label }
        return card.daysLeft == 0 ? "läuft heute ab" : card.daysLeft == 1 ? "läuft morgen ab" : "noch \(card.daysLeft) Tage"
    }

    var body: some View {
        let brand = MerchantBrand.forID(card.merchantID) ?? MerchantBrand.fallback(for: card.name)
        let fg = brand.foreground
        let crossed = status == .redeemed || status == .expired
        let shape = TicketShape(radius: Layout.cardRadius, notchRadius: 9, notchFromTop: tearY + 0.5)
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 10) {
                    // Dieselbe Kachel wie in der Liste: Kartenfarbe = Farbe des Ladens.
                    MerchantMark(card: card, size: 32)
                        .overlay(RoundedRectangle(cornerRadius: 32 * 0.24, style: .continuous).strokeBorder(.white.opacity(0.55), lineWidth: 1.5))
                    Text(card.name).font(.scaled(20, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 8)
                    if status == .expiringSoon || status == .expired {
                        Text(badgeText)
                            .font(.scaled(12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                            .foregroundStyle(status.tint)
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(.white, in: .capsule)
                            .environment(\.colorScheme, .light)
                    }
                }
                Text(card.kind.isValueBased ? "Noch drauf" : card.kind.label)
                    .font(.scaled(14, weight: .medium)).opacity(0.85).lineLimit(1)
                    .padding(.top, 18)
                Group {
                    if card.kind.isValueBased {
                        AmountText(value: card.balance, size: 48)
                    } else {
                        Text(card.headline).font(.amount(48)).lineLimit(1).minimumScaleFactor(0.5)
                    }
                }
                .strikethrough(crossed, color: fg.opacity(0.7))
                if card.kind.isValueBased {
                    HStack(spacing: 10) {
                        GeometryReader { geo in
                            Capsule().fill(fg.opacity(0.25))
                                .overlay(alignment: .leading) {
                                    Capsule().fill(fg).frame(width: geo.size.width * min(max(card.remainingShare, 0), 1))
                                }
                        }
                        .frame(height: 5)
                        Text("von \(card.value.euro)").font(.scaled(13, weight: .medium)).monospacedDigit().opacity(0.85)
                            .fixedSize()
                    }
                    .padding(.top, 10)
                    .animation(.spring(duration: 0.6, bounce: 0.3), value: card.remainingShare)
                }
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 16)
            // Gemessen, damit die Kerben bei jeder Schriftgröße auf der Abrisslinie sitzen.
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { tearY = $0 }
            // Abrisslinie auf Höhe der Kerben, darunter der Abschnitt mit der Gültigkeit.
            TearLine(color: fg).padding(.horizontal, 16)
            // Bei großer Schrift untereinander, damit das Datum nicht abgeschnitten wird.
            let footerLayout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout())
            footerLayout {
                Text("gültig bis \(card.expires.dayMonthYear)")
                if !typeSize.isAccessibilitySize { Spacer() }
                if card.isActive && status != .expiringSoon {
                    Text(card.daysLeft == 1 ? "noch 1 Tag" : "noch \(card.daysLeft) Tage")
                }
            }
            .font(.scaled(13, weight: .medium)).monospacedDigit().opacity(0.85)
            .padding(.horizontal, 20).padding(.vertical, 13)
        }
        .foregroundStyle(fg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(brand.background, in: shape)
        .overlay { shape.stroke(Color.ink.opacity(0.08), lineWidth: 1) }
        .overlay(alignment: .topTrailing) {
            if card.kind.isValueBased && card.balance <= 0 {
                UsedUpStamp().padding(.top, 58).padding(.trailing, 16)
            }
        }
        .shadow(color: Color.ink.opacity(0.10), radius: 14, y: 6)
        .accessibilityElement(children: .combine)
    }
}

