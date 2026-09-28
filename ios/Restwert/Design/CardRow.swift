import SwiftUI
import RestwertKit

/// Zeile in der Gutscheinliste. Hintergrund und Trennlinien kommen von der umgebenden Liste.
struct CardRow: View {
    let card: GiftCard
    var warnDays: Int = 30
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityDifferentiateWithoutColor) private var noColor

    /// Fristangabe der Zeile, einmal pro Durchlauf berechnet (Restlaufzeit kostet eine Kalenderrechnung).
    private struct Due {
        enum Level { case calm, soon, urgent, bad }
        let text: String
        let level: Level
        /// Ablaufdatum nur geschätzt (gesetzliche Frist), nicht vom Gutschein abgelesen.
        let estimated: Bool

        var color: Color {
            switch level {
            case .calm: .muted
            case .soon: .soon
            case .urgent: .warn
            case .bad: .bad
            }
        }

        /// Bis 14 Tage Ausrufezeichen, danach Uhr – unterscheidbar auch ohne Farbe.
        var symbol: String? {
            switch level {
            case .urgent: "exclamationmark.circle.fill"
            case .soon: "clock"
            case .calm, .bad: nil
            }
        }
    }

    private var due: Due {
        let days = card.daysLeft
        let status = card.status(warnDays: warnDays)
        let estimated = card.expiresEstimated && card.isOpen && days >= 0 && !card.isArchived
        // Archiviert, aber noch gültig: so anzeigen und ansagen. Eingelöst und abgelaufen behalten ihren Status.
        if card.isArchived, status == .valid || status == .expiringSoon { return Due(text: "archiviert", level: .calm, estimated: false) }
        return switch status {
        case .expiringSoon where days <= 14:
            Due(text: days == 0 ? "läuft heute ab" : days == 1 ? "läuft morgen ab" : "noch \(days)\u{00A0}Tage", level: .urgent, estimated: estimated)
        case .expiringSoon: Due(text: "noch \(days)\u{00A0}Tage", level: .soon, estimated: estimated)
        case .expired: Due(text: "abgelaufen", level: .bad, estimated: false)
        case .redeemed: Due(text: "eingelöst", level: .calm, estimated: false)
        // Geschätzt (gesetzliche Frist): direkt beim Datum sagen, nicht als loses „geschätzt“ daneben.
        // Geschätzt (gesetzliche Frist): kurz und direkt am Datum, damit es nie abgeschnitten wird.
        case .valid: Due(text: estimated ? "bis ca. \(card.expires.dayMonthYear)" : "bis \(card.expires.dayMonthYear)",
                         level: .calm, estimated: estimated)
        }
    }

    var body: some View {
        let due = due
        // Bei sehr großer Schrift untereinander statt nebeneinander, damit nichts abgeschnitten wird.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 14))
        layout {
            HStack(spacing: 14) {
                MerchantMark(card: card)
                nameBlock(due)
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
            amountBlock
                // Gestapelt: an der Textkante ausrichten (Logo 44 + Abstand 14), nicht an der Zellkante.
                .padding(.leading, typeSize.isAccessibilitySize ? 58 : 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, Layout.inset).padding(.trailing, 4).padding(.vertical, Layout.group)
        .opacity(card.isActive ? 1 : 0.5)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(due))
    }

    /// Ein Satz für VoiceOver, z. B. „Thalia, 12,40 € von 25,00 €, bis 31.12.2028, Datum geschätzt“.
    private func spoken(_ due: Due) -> String {
        let amount = card.kind.isValueBased ? "\(card.headline) von \(card.value.euro)" : card.headline == card.kind.label ? card.kind.label : "\(card.headline) \(card.kind.label)"
        let who = card.owner.isEmpty ? "" : ", für \(card.owner)"
        let open = card.pendingSince != nil && card.isActive ? ", Betrag offen" : ""
        let urgent = due.level == .urgent ? ", dringend" : ""
        let estimated = due.estimated ? ", Ablaufdatum geschätzt" : ""
        return "\(card.name)\(who)\(open), \(amount), \(due.text)\(urgent)\(estimated)\(card.forGifting ? ", zum Verschenken" : "")\(card.issuedByMe ? (card.issuedTo.isEmpty ? ", selbst ausgestellt" : ", selbst ausgestellt für \(card.issuedTo)") : "")"
    }

    private func nameBlock(_ due: Due) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            // Name einzeilig; Zusatz-Etiketten stehen in der zweiten Zeile, damit der Name nicht umbricht.
            HStack(spacing: 6) {
                Text(card.name).font(.scaled(16, weight: .semibold)).foregroundStyle(Color.ink)
                    .lineLimit(1).truncationMode(.tail).layoutPriority(1)
                if card.forGifting {
                    Image(systemName: "gift").font(.scaled(13)).foregroundStyle(Color.ink2)
                        .accessibilityLabel("zum Verschenken")
                }
                if !card.owner.isEmpty {
                    // „für Mia“ bekommt zuerst Platz, lieber kürzt sich der Ladenname.
                    Text("für \(card.owner)").font(.scaled(13)).foregroundStyle(Color.ink2).lineLimit(1)
                        .layoutPriority(2)
                }
            }
            // Zwei Stufen: bis 14 Tage Pille mit Ausrufezeichen, danach nur Text mit Uhr.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { dueLabel(due); tags(due) }
                VStack(alignment: .leading, spacing: 3) { dueLabel(due); HStack(spacing: 6) { tags(due) } }
            }
        }
    }

    @ViewBuilder
    private func tags(_ due: Due) -> some View {
        // Ruhige Zusätze als Text mit Trennpunkt statt eigener Pillen.
        // Selbst ausgegeben: in der zweiten Zeile, damit der Ladenname ganz sichtbar bleibt.
        if card.issuedByMe {
            Text(card.issuedTo.isEmpty ? "· selbst ausgestellt" : "· für \(card.issuedTo)").font(.scaled(13, weight: .semibold)).foregroundStyle(Color.ink2)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        // Nur bei „noch X Tage“ zusätzlich nennen; beim Datum steht es schon im Text.
        if due.estimated && due.level != .calm {
            Text("· Datum geschätzt").font(.scaled(13)).foregroundStyle(Color.muted).fixedSize()
        }
        if card.pendingSince != nil && card.isActive {
            Text("· Betrag offen").font(.scaled(13, weight: .semibold)).foregroundStyle(Color.warn).fixedSize()
        }
    }

    private func dueLabel(_ due: Due) -> some View {
        let urgent = due.level == .urgent
        return Label {
            // Ohne Farbunterscheidung steht „dringend“ zusätzlich im Text.
            Text(urgent && noColor ? "\(due.text) · dringend" : due.text)
        } icon: {
            if let symbol = due.symbol { Image(systemName: symbol) }
        }
        .labelStyle(DueLabelStyle())
        // Gleich groß wie „von 25,00 €“ darunter/daneben: nicht verkleinern, lieber umbrechen.
        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
        .font(.scaled(13, weight: due.level == .calm ? .regular : .semibold))
        .foregroundStyle(due.color)
        .padding(.horizontal, urgent ? 8 : 0).padding(.vertical, urgent ? 3 : 0)
        .background(urgent ? Color.warnSoft : Color.clear, in: .capsule)
    }

    private var amountBlock: some View {
        VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 3) {
            if card.kind.isValueBased {
                Text(card.headline).font(.amount(typeSize.isAccessibilitySize ? 16 : 20)).foregroundStyle(Color.ink)
                    .contentTransition(.numericText(value: card.balance))
                    .lineLimit(1).fixedSize()
                // Klein und grau wie das Datum: der Ursprungsbetrag.
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
            // Restbalken nur nach einer Teileinlösung.
            if card.kind.isValueBased && card.balance < card.value {
                RemainingBar(share: card.remainingShare).frame(width: 64)
                    .accessibilityHidden(true)
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
