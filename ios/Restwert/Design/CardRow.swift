import SwiftUI
import RestwertKit

/// Zeile in der Gutscheinliste. Hintergrund und Trennlinien kommen von der umgebenden Liste.
struct CardRow: View {
    let card: GiftCard
    var warnDays: Int = 30

    private var dueText: (String, Color) {
        switch card.status(warnDays: warnDays) {
        case .expiringSoon: (card.daysLeft == 0 ? "läuft heute ab" : card.daysLeft == 1 ? "läuft morgen ab" : "noch \(card.daysLeft) Tage", .warn)
        case .expired: ("abgelaufen", .bad)
        case .redeemed: ("eingelöst", .muted)
        case .valid: ("bis \(card.expires.dayMonthYear)", .muted)
        }
    }

    var body: some View {
        let due = dueText
        HStack(spacing: 14) {
            MerchantMark(card: card)
            VStack(alignment: .leading, spacing: 3) {
                Text(card.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.ink)
                Label {
                    Text(due.0)
                } icon: {
                    if due.1 != .muted { Image(systemName: due.1 == .warn ? "clock.fill" : "exclamationmark.circle.fill") }
                }
                .labelStyle(DueLabelStyle())
                .font(.system(size: 14, weight: due.1 == .muted ? .regular : .semibold))
                .foregroundStyle(due.1)
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(card.headline).font(.system(size: 20, weight: .bold)).kerning(-0.3).monospacedDigit().foregroundStyle(Color.ink)
                    .contentTransition(.numericText(value: card.balance))
                Text(card.kind.isValueBased ? "von \(card.value.euro)" : card.kind.label)
                    .font(.system(size: 13)).monospacedDigit().foregroundStyle(Color.muted)
                if card.kind.isValueBased && card.balance < card.value {
                    RemainingBar(share: card.remainingShare).frame(width: 64)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .opacity(card.isActive ? 1 : 0.5)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
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
        HStack(spacing: 4) { configuration.icon.font(.system(size: 12)); configuration.title }
    }
}
