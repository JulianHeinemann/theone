import SwiftUI

/// Pastellkarte mit Ordner-Reiter, wie in den Referenz-Entwürfen.
struct FolderCardView: View {
    let card: GiftCard
    var warnDays: Int = 30

    private var status: String {
        switch card.status(warnDays: warnDays) {
        case .expiringSoon: return "Noch \(card.daysLeft) Tage"
        case .valid: return card.kind == .giftCard ? card.merchant.category.label : card.kind.label
        case let other: return other.label
        }
    }

    private var numberGroups: [String] {
        let s = card.number.replacingOccurrences(of: " ", with: "")
        guard s.allSatisfy(\.isNumber), s.count > 8 else { return [card.number] }
        let first = String(s.prefix(4)), last = String(s.suffix(4))
        return [first, "••••", "••••", last]
    }

    var body: some View {
        let color = Pastel.color(for: card)
        VStack(spacing: -16) {
            HStack {
                UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 26, style: .continuous)
                    .fill(color)
                    .frame(width: 136, height: 32)
                    .overlay(alignment: .topLeading) {
                        if card.isExample {
                            Text("BEISPIEL").font(.system(size: 10, weight: .heavy)).kerning(1.4)
                                .foregroundStyle(Color.ink.opacity(0.5)).padding(.leading, 20).padding(.top, 5)
                        }
                    }
                Spacer()
            }
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(color)
                Rings().stroke(Color.white.opacity(0.65), lineWidth: 1)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center) {
                        Text(card.name).font(.system(size: 19, weight: .heavy)).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(status).font(.system(size: 12, weight: .bold))
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(Color.white.opacity(0.6), in: Capsule())
                    }
                    Spacer(minLength: 6)
                    Text(card.kind.isValueBased ? "Restwert" : card.kind.label).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.ink.opacity(0.6))
                    Text(card.headline).font(.system(size: 32, weight: .heavy)).monospacedDigit()
                        .minimumScaleFactor(0.7).lineLimit(1)
                    Spacer(minLength: 6)
                    HStack(alignment: .bottom) {
                        HStack(spacing: 12) {
                            ForEach(Array(numberGroups.enumerated()), id: \.offset) { _, g in
                                Text(g).font(.system(size: 15, weight: .semibold)).monospacedDigit()
                            }
                        }
                        .lineLimit(1).minimumScaleFactor(0.7)
                        Spacer()
                        HStack(spacing: -9) {
                            Circle().fill(Color.ink.opacity(0.78)).frame(width: 24, height: 24)
                            Circle().fill(Color.ink.opacity(0.38)).frame(width: 24, height: 24)
                        }
                    }
                }
                .foregroundStyle(Color.ink)
                .padding(.horizontal, 20).padding(.vertical, 18)
            }
            .aspectRatio(1.72, contentMode: .fit)
        }
        .accessibilityElement(children: .ignore)
        .opacity(card.isOpen && card.daysLeft >= 0 ? 1 : 0.55)
        .accessibilityLabel("\(card.name), \(card.headline), \(status)")
    }

    /// Dezente konzentrische Kreise oben rechts.
    private struct Rings: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            let c = CGPoint(x: rect.maxX - rect.width * 0.08, y: rect.minY + rect.height * 0.1)
            for r: CGFloat in [60, 98, 140] {
                p.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            }
            return p
        }
    }
}
