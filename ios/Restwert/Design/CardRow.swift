import SwiftUI
import RestwertKit

/// Zeile in der Gutscheinliste. Hintergrund und Trennlinien kommen von der umgebenden Liste.
struct CardRow: View {
    let card: GiftCard
    var warnDays: Int = 30
    @Environment(\.dynamicTypeSize) private var typeSize

    private var dueText: (String, Color) {
        let status = card.status(warnDays: warnDays)
        // Archiviert, aber noch gültig: so anzeigen und ansagen. Eingelöst und abgelaufen behalten ihren Status.
        if card.isArchived, status == .valid || status == .expiringSoon { return ("archiviert", .muted) }
        return switch status {
        case .expiringSoon:
            // Bis 14 Tage dringend (rote Pill), danach nur orangener Text.
            card.daysLeft <= 14
                ? (card.daysLeft == 0 ? "Heute weg" : card.daysLeft == 1 ? "Morgen weg" : "noch \(card.daysLeft) Tage", .warn)
                : ("noch \(card.daysLeft) Tage", .soon)
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
                // Gestapelt: an der Textkante ausrichten (Logo 44 + Abstand 14), nicht an der Zellkante.
                .padding(.leading, typeSize.isAccessibilitySize ? 58 : 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .opacity(card.isActive ? 1 : 0.5)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    /// Ein Satz für VoiceOver, z. B. „Thalia, 12,40 € von 25,00 €, bis 31.12.2028“.
    private var spoken: String {
        let amount = card.kind.isValueBased ? "\(card.headline) von \(card.value.euro)" : card.headline == card.kind.label ? card.kind.label : "\(card.headline) \(card.kind.label)"
        let who = card.owner.isEmpty ? "" : ", für \(card.owner)"
        let open = card.pendingSince != nil && card.isActive ? ", Betrag offen" : ""
        return "\(card.name)\(who)\(open), \(amount), \(dueText.0)\(card.forGifting ? ", zum Verschenken" : "")"
    }

    private var nameBlock: some View {
        let due = dueText
        return VStack(alignment: .leading, spacing: 3) {
            // Name einzeilig; Zusatz-Etiketten stehen in der zweiten Zeile, damit der Name nicht umbricht.
            HStack(spacing: 6) {
                Text(card.name).font(.scaled(16, weight: .semibold)).foregroundStyle(Color.ink)
                    .lineLimit(1).truncationMode(.tail).layoutPriority(1)
                if card.forGifting {
                    Image(systemName: "gift").font(.scaled(13)).foregroundStyle(Color.ink2)
                        .accessibilityLabel("zum Verschenken")
                }
                if !card.owner.isEmpty {
                    Text("für \(card.owner)").font(.scaled(13)).foregroundStyle(Color.ink2).lineLimit(1)
                }
            }
            // Zwei Stufen: bis 14 Tage gefüllt mit Ausrufezeichen, danach nur umrandet mit Uhr.
            let urgent = due.1 == .warn
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { dueLabel(due, urgent); tags }
                VStack(alignment: .leading, spacing: 3) { dueLabel(due, urgent); HStack(spacing: 6) { tags } }
            }
        }
    }

    @ViewBuilder
    private var tags: some View {
        // Ruhige Zusätze als Text mit Trennpunkt statt eigener Pillen.
        if card.pendingSince != nil && card.isActive {
            Text("· Betrag offen").font(.scaled(13, weight: .semibold)).foregroundStyle(Color.warn).fixedSize()
        }
    }

    private func dueLabel(_ due: (String, Color), _ urgent: Bool) -> some View {
            Label {
                Text(due.0)
            } icon: {
                if due.1 == .warn || due.1 == .soon { Image(systemName: "clock") }
            }
            .labelStyle(DueLabelStyle())
            .lineLimit(1).minimumScaleFactor(0.75)
            .font(.scaled(13, weight: due.1 == .muted ? .regular : .semibold))
            .foregroundStyle(due.1)
            .padding(.horizontal, urgent ? 8 : 0).padding(.vertical, urgent ? 3 : 0)
            .background(urgent ? Color.warnSoft : Color.clear, in: .capsule)
    }

    private var amountBlock: some View {
        VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 3) {
            if card.kind.isValueBased {
                Text(card.headline).font(.amount(typeSize.isAccessibilitySize ? 16 : 20)).foregroundStyle(Color.ink)
                    .contentTransition(.numericText(value: card.balance))
                    .lineLimit(1).fixedSize()
                Text("von \(card.value.euro)")
                    .font(.scaled(13)).monospacedDigit().foregroundStyle(Color.muted)
                    .lineLimit(1).fixedSize()
            } else {
                // Rabattcodes sind kein Geld: Etikett-Symbol vor dem Wert, darunter „Rabatt“ statt „von … €“.
                let hasValue = (card.percent ?? 0) > 0 || card.value > 0
                HStack(spacing: 4) {
                    Image(systemName: "tag.fill").font(.scaled(13)).foregroundStyle(Color.ink2)
                    Text(hasValue ? card.headline : card.kind.label)
                        .font(hasValue ? .amount(typeSize.isAccessibilitySize ? 16 : 19) : .scaled(15, weight: .bold))
                        .foregroundStyle(Color.ink)
                }
                .lineLimit(1).fixedSize()
                Text(hasValue ? "Rabatt" : "Code").font(.scaled(13)).foregroundStyle(Color.muted)
                    .lineLimit(1).fixedSize()
            }
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
