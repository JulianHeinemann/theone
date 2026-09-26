import SwiftUI
import RestwertKit

/// Zeile in der Gutscheinliste. Hintergrund und Trennlinien kommen von der umgebenden Liste.
struct CardRow: View {
    let card: GiftCard
    var warnDays: Int = 30
    @Environment(\.dynamicTypeSize) private var typeSize

    private var dueText: (String, Color) {
        switch card.status(warnDays: warnDays) {
        case .expiringSoon: (card.daysLeft == 0 ? "läuft heute ab" : card.daysLeft == 1 ? "läuft morgen ab" : "noch \(card.daysLeft) Tage", .warn)
        case .expired: ("abgelaufen", .bad)
        case .redeemed: ("eingelöst", .muted)
        case .valid: ("bis \(card.expires.dayMonthYear)", .muted)
        }
    }

    var body: some View {
        // Bei sehr großer Schrift untereinander statt nebeneinander, damit nichts abgeschnitten wird.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 14))
        layout {
            HStack(spacing: 14) {
                MerchantMark(card: card)
                nameBlock
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
            amountBlock
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .opacity(card.isActive ? 1 : 0.5)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var nameBlock: some View {
        let due = dueText
        return VStack(alignment: .leading, spacing: 3) {
            Text(card.name).font(.scaled(16, weight: .semibold)).foregroundStyle(Color.ink)
            Label {
                Text(due.0)
            } icon: {
                if due.1 != .muted { Image(systemName: due.1 == .warn ? "clock.fill" : "exclamationmark.circle.fill") }
            }
            .labelStyle(DueLabelStyle())
            .font(.scaled(14, weight: due.1 == .muted ? .regular : .semibold))
            .foregroundStyle(due.1)
        }
    }

    private var amountBlock: some View {
        VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 3) {
            Text(card.headline).font(.scaled(20, weight: .bold)).kerning(-0.3).monospacedDigit().foregroundStyle(Color.ink)
                .contentTransition(.numericText(value: card.balance))
                .lineLimit(1).fixedSize()
            Text(card.kind.isValueBased ? "von \(card.value.euro)" : card.kind.label)
                .font(.scaled(13)).monospacedDigit().foregroundStyle(Color.muted)
                .lineLimit(1).fixedSize()
            if card.kind.isValueBased && card.balance < card.value {
                RemainingBar(share: card.remainingShare).frame(width: 64)
            }
        }
    }
}

/// Dünner Balken: wie viel vom ursprünglichen Wert noch übrig ist.
struct RemainingBar: View {
    let share: Double

    var body: some View {
        GeometryReader { geo in
            Capsule().fill(Color.line)
                .overlay(alignment: .leading) {
                    Capsule().fill(Color.ink).frame(width: geo.size.width * min(max(share, 0), 1))
                }
        }
        .frame(height: 4)
    }
}

/// Symbol und Text eng nebeneinander; ohne Symbol nur Text.
struct DueLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.icon.font(.scaled(12)); configuration.title }
    }
}
