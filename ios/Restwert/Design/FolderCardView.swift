import SwiftUI
import RestwertKit

/// Pastellkarte mit Ordner-Reiter, wie in den Referenz-Entwürfen.
struct FolderCardView: View {
    let card: GiftCard
    var warnDays: Int = 30

    private var statusText: String {
        switch card.status(warnDays: warnDays) {
        case .expiringSoon: "Noch \(card.daysLeft) Tage"
        case .valid: card.kind == .giftCard ? card.merchant.category.label : card.kind.label
        case let other: other.label
        }
    }

    private var numberGroups: [String] {
        let s = card.number.replacingOccurrences(of: " ", with: "")
        guard s.allSatisfy(\.isNumber), s.count > 8 else { return [card.number] }
        return [String(s.prefix(4)), "••••", "••••", String(s.suffix(4))]
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
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(color.gradient)
                Rings().stroke(Color.white.opacity(0.65), lineWidth: 1)
                    .clipShape(.rect(cornerRadius: 24, style: .continuous))
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center) {
                        Text(card.name).font(.system(size: 19, weight: .heavy)).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(statusText).font(.system(size: 12, weight: .bold))
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(Color.white.opacity(0.6), in: .capsule)
                    }
                    Spacer(minLength: 6)
                    Text(card.kind.isValueBased ? "Restwert" : card.kind.label)
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.ink.opacity(0.6))
                    Text(card.headline).font(.system(size: 32, weight: .heavy)).monospacedDigit()
                        .contentTransition(.numericText(value: card.balance))
                        .minimumScaleFactor(0.7).lineLimit(1)
                    Spacer(minLength: 6)
                    HStack(alignment: .bottom) {
                        HStack(spacing: 12) {
                            ForEach(Array(numberGroups.enumerated()), id: \.offset) { _, group in
                                Text(group).font(.system(size: 15, weight: .semibold)).monospacedDigit()
                            }
                        }
                        .lineLimit(1).minimumScaleFactor(0.7)
                        Spacer()
                        Image(systemName: card.kind.symbol)
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.55), in: .circle)
                    }
                }
                .foregroundStyle(Color.ink)
                .padding(.horizontal, 20).padding(.vertical, 18)
            }
            .aspectRatio(1.72, contentMode: .fit)
        }
        .opacity(card.isActive ? 1 : 0.55)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(card.name), \(card.headline), \(statusText)")
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

/// Kompakte Zeile für Listen.
struct CardRow: View {
    let card: GiftCard
    var warnDays: Int = 30

    var body: some View {
        let status = card.status(warnDays: warnDays)
        HStack(spacing: 14) {
            LetterTile(text: card.name, color: Pastel.color(for: card))
            VStack(alignment: .leading, spacing: 2) {
                Text(card.name).font(.system(size: 16, weight: .bold)).foregroundStyle(Color.ink)
                HStack(spacing: 4) {
                    Image(systemName: card.location.symbol)
                    Text("bis \(card.expires.dayMonthYear)")
                    if status != .valid {
                        Text("· " + (status == .expiringSoon ? "noch \(card.daysLeft) T." : status.label))
                            .fontWeight(.bold)
                            .foregroundStyle(status.tint)
                    }
                }
                .font(.system(size: 13)).foregroundStyle(Color.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(card.headline).font(.system(size: 17, weight: .heavy)).monospacedDigit().foregroundStyle(Color.ink)
                    .contentTransition(.numericText(value: card.balance))
                Text(card.kind.isValueBased ? "von \(card.value.euro)" : card.kind.label)
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.muted)
            }
        }
        .padding(12)
        .background(Color.surface, in: .rect(cornerRadius: 20, style: .continuous))
        .opacity(card.isActive ? 1 : 0.6)
        .contentShape(.rect)
    }
}
