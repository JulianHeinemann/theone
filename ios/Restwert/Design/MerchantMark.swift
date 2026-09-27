import SwiftUI
import RestwertKit

/// Markenfarben der bekannten Händler, damit man IKEA oder Douglas in der Liste auf einen Blick erkennt.
/// Eigene Gutscheine ohne bekannten Händler bekommen eine neutrale Kachel mit Initialen.
nonisolated struct MerchantBrand: Sendable {
    let background: Color
    let foreground: Color
    /// Kurzform, die in die Kachel passt (z. B. „MM“ für MediaMarkt, „DB“ für die Bahn).
    let mark: String?

    init(_ bg: UInt32, _ fg: UInt32, _ mark: String? = nil) {
        background = Color(hex: bg)
        foreground = Color(hex: fg)
        self.mark = mark
    }

    static let neutral = MerchantBrand(0xE7E8EB, 0x0E0E10)

    static func forID(_ id: String?) -> MerchantBrand? { id.flatMap { table[$0] } }

    private static let table: [String: MerchantBrand] = [
        "amazon": .init(0x232F3E, 0xFF9900, "a"),
        "zalando": .init(0xFF6900, 0xFFFFFF, "Z"),
        "otto": .init(0xD4021D, 0xFFFFFF, "OTTO"),
        "apple": .init(0x000000, 0xFFFFFF, "\u{F8FF}"),
        "googleplay": .init(0xFFFFFF, 0x01875F, "▶"),
        "spotify": .init(0x1DB954, 0x000000, "S"),
        "netflix": .init(0x000000, 0xE50914, "N"),
        "db": .init(0xEC0016, 0xFFFFFF, "DB"),
        "lieferando": .init(0xFF8000, 0xFFFFFF, "L"),
        "wunschgutschein": .init(0x1B2D5B, 0xFFFFFF, "W"),
        "eventim": .init(0x002B55, 0xFFD400, "E"),
        "ticketmaster": .init(0x026CDF, 0xFFFFFF, "t"),
        "ikea": .init(0x0058A3, 0xFFDB00, "IKEA"),
        "thalia": .init(0x1E6E6B, 0xFFFFFF, "T"),
        "zara": .init(0x000000, 0xFFFFFF, "ZARA"),
        "tkmaxx": .init(0xD6001C, 0xFFFFFF, "TK"),
        "decathlon": .init(0x3643BA, 0xFFFFFF, "D"),
        "douglas": .init(0x000000, 0xFFFFFF, "D"),
        "hm": .init(0xE50010, 0xFFFFFF, "H&M"),
        "rossmann": .init(0xC3002F, 0xFFFFFF, "R"),
        "lidl": .init(0x0050AA, 0xFFF000, "Lidl"),
        "kaufland": .init(0xE10915, 0xFFFFFF, "K"),
        "aldi": .init(0x00005F, 0xFFFFFF, "ALDI"),
        "mueller": .init(0xF26722, 0xFFFFFF, "M"),
        "tchibo": .init(0x002D5A, 0xFFFFFF, "T"),
        "cinemaxx": .init(0x000000, 0xFFFFFF, "CX"),
        "nike": .init(0x111111, 0xFFFFFF, "NIKE"),
        "mediamarkt": .init(0xDF0000, 0xFFFFFF, "MM"),
        "saturn": .init(0x000000, 0xFF7F00, "S"),
        "rewe": .init(0xCC071E, 0xFFFFFF, "REWE"),
        "stadtgutschein": .init(0x0E0E10, 0xFFE14D, "€"),
        "dm": .init(0xFFFFFF, 0x002878, "dm"),
        "breuninger": .init(0x000000, 0xFFFFFF, "B"),
        "ca": .init(0x0054A0, 0xFFFFFF, "C&A"),
        "primark": .init(0x00A6E2, 0xFFFFFF, "P"),
        "deichmann": .init(0x008C45, 0xFFFFFF, "D"),
        "edeka": .init(0x1A4A99, 0xFFD400, "E"),
        "netto": .init(0xFFE500, 0xE2001A, "N"),
        "penny": .init(0xCD1719, 0xFFFFFF, "P"),
        "galeria": .init(0x00553F, 0xFFFFFF, "G"),
        "adidas": .init(0x000000, 0xFFFFFF, "a"),
        "sephora": .init(0x000000, 0xFFFFFF, "S"),
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
        let style = brand ?? .neutral
        Text(text)
            .font(.system(size: size * (text.count > 2 ? 0.26 : 0.4), weight: .black))
            .kerning(text.count > 2 ? -0.3 : 0)
            .lineLimit(1).minimumScaleFactor(0.5)
            .padding(.horizontal, 4)
            .foregroundStyle(style.foreground)
            .frame(width: size, height: size)
            .background(style.background, in: .rect(cornerRadius: size * 0.24, style: .continuous))
            .overlay {
                // Weiße Kacheln (dm, Google Play) brauchen eine Kante, sonst verschwinden sie.
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .strokeBorder(Color.ink.opacity(0.08), lineWidth: 1)
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

    /// Wie in der Liste: „läuft heute/morgen ab“ statt „noch 0/1 Tage“.
    private var badgeText: String {
        guard status == .expiringSoon else { return status.label }
        return card.daysLeft == 0 ? "läuft heute ab" : card.daysLeft == 1 ? "läuft morgen ab" : "noch \(card.daysLeft) Tage"
    }

    var body: some View {
        let brand = MerchantBrand.forID(card.merchantID) ?? MerchantBrand(0x0E0E10, 0xFFFFFF)
        let fg = brand.foreground
        let crossed = status == .redeemed || status == .expired
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(card.name).font(.scaled(20, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                if status != .valid {
                    Text(badgeText)
                        .font(.scaled(12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                        .foregroundStyle(status.tint)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(.white, in: .capsule)
                        // Festes helles Etikett: Schrift immer in der dunklen Hell-Variante, auch im Dunkelmodus.
                        .environment(\.colorScheme, .light)
                }
            }
            Spacer(minLength: 12)
            Text(card.kind.isValueBased ? "Guthaben" : card.kind.label)
                .font(.scaled(14, weight: .medium)).opacity(0.75).lineLimit(1).minimumScaleFactor(0.7)
            Text(card.headline)
                .font(.amount(58)).kerning(-1.5)
                .contentTransition(.numericText(value: card.balance))
                .strikethrough(crossed, color: fg.opacity(0.7))
                .minimumScaleFactor(0.5).lineLimit(1)
            if card.kind.isValueBased {
                HStack(spacing: 10) {
                    GeometryReader { geo in
                        Capsule().fill(fg.opacity(0.25))
                            .overlay(alignment: .leading) {
                                Capsule().fill(fg).frame(width: geo.size.width * min(max(card.remainingShare, 0), 1))
                            }
                    }
                    .frame(height: 5)
                    Text("von \(card.value.euro)").font(.scaled(13, weight: .medium)).monospacedDigit().opacity(0.75)
                        .fixedSize()
                }
                .padding(.top, 10)
                .animation(.spring(duration: 0.6, bounce: 0.3), value: card.remainingShare)
            }
        }
        .foregroundStyle(fg)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Bei Bedienungshilfen-Größen wächst die Karte mit dem Inhalt statt im Scheckkartenformat abzuschneiden.
        .cardFormat(!typeSize.isAccessibilitySize)
        .background(brand.background, in: .rect(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.ink.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: Color.ink.opacity(0.12), radius: 16, y: 8)
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    /// Scheckkartenformat nur, solange der Inhalt hineinpasst.
    @ViewBuilder
    func cardFormat(_ fixed: Bool) -> some View {
        if fixed { aspectRatio(1.586, contentMode: .fit) } else { self }
    }
}
