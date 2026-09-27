import SwiftUI
import RestwertKit

/// Einstieg: zeigt direkt, wie die App aussieht, statt Deko-Grafik.
struct OnboardingView: View {
    var onStart: () -> Void
    @State private var tearY: CGFloat = 100

    /// Bewusst gemischt: Kette, Papierzettel vom Café, Online-Code, Stadtgutschein.
    private let preview: [(id: String?, name: String, due: String, dueSoon: Bool, amount: String, of: String)] = [
        ("dm", "dm", "noch 9 Tage", true, "15,00 €", "von 25,00 €"),
        (nil, "Café am Markt", "Papier · bis 31.12.2027", false, "20,00 €", "von 20,00 €"),
        ("googleplay", "Google Play", "Code aus einer Mail", false, "10,00 €", "von 10,00 €"),
        ("stadtgutschein", "Stadtgutschein", "bis 13.02.2027", false, "30,00 €", "von 50,00 €"),
    ]

    var body: some View {
        // Scrollbar, damit bei großer Schrift alles lesbar bleibt; der Knopf bleibt fest unten.
        ScrollView {
            content.padding(.horizontal, Layout.page).padding(.bottom, Layout.inset)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            Button("Los geht's", action: onStart)
                .buttonStyle(.primary)
                .padding(.horizontal, Layout.page).padding(.top, 8).padding(.bottom, Layout.inset)
                .background(Color.page)
        }
        .foregroundStyle(Color.ink)
        .background(Color.page.ignoresSafeArea())
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            Wordmark()
                .padding(.top, Layout.section)
            Text("Kein Restwert\nbleibt liegen.")
                .font(.scaled(34, weight: .heavy, design: .rounded)).kerning(-0.6)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Layout.section)
            Text("Karte, Papierzettel vom Café oder Code aus einer Mail: fotografieren, fertig. Vor dem Ablauf kommt eine Erinnerung, an der Kasse zeigst du den Code.")
                .font(.scaled(17)).foregroundStyle(Color.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Layout.group)
            Text("So sieht es aus (Beispiel)").font(.scaled(13, weight: .medium)).foregroundStyle(Color.muted)
                .padding(.top, Layout.section).padding(.bottom, Layout.group)
            VStack(spacing: Layout.group) {
                // Dasselbe gelbe Ticket wie auf dem Start: die Marke gleich beim ersten Kontakt.
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Noch drauf").font(.scaled(15, weight: .semibold)).opacity(0.75)
                        AmountText(value: 75, size: 48)
                    }
                    .padding(.horizontal, Layout.ticketInset).padding(.top, Layout.ticketInset).padding(.bottom, Layout.inset)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { tearY = $0 }
                    TearLine(color: .sumText).padding(.horizontal, Layout.inset)
                    Text("4 Karten · 1 bald weg").font(.scaled(15, weight: .semibold))
                        .padding(.horizontal, Layout.ticketInset).padding(.vertical, Layout.group)
                }
                .foregroundStyle(Color.sumText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.sumFill, in: TicketShape(radius: Layout.cardRadius, notchRadius: 9, notchFromTop: tearY + 0.5))
                VStack(spacing: 0) {
                    ForEach(Array(preview.enumerated()), id: \.offset) { i, row in
                        if i > 0 { Divider().padding(.leading, 74) }
                        HStack(spacing: 14) {
                            MerchantMark(merchantID: row.id, name: row.name)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.name).font(.scaled(16, weight: .semibold))
                                Label {
                                    Text(row.due)
                                } icon: {
                                    if row.dueSoon { Image(systemName: "clock") }
                                }
                                .labelStyle(DueLabelStyle())
                                .font(.scaled(13, weight: row.dueSoon ? .semibold : .regular))
                                .fixedSize(horizontal: false, vertical: true)
                                .foregroundStyle(row.dueSoon ? Color.warn : Color.muted)
                                .padding(.horizontal, row.dueSoon ? 8 : 0).padding(.vertical, row.dueSoon ? 3 : 0)
                                .background(row.dueSoon ? Color.warnSoft : Color.clear, in: .capsule)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(row.amount).font(.amount(20))
                                Text(row.of).font(.scaled(13)).monospacedDigit().foregroundStyle(Color.muted)
                            }
                        }
                        .padding(.horizontal, Layout.inset).padding(.vertical, Layout.group)
                    }
                }
                .foregroundStyle(Color.ink)
                .background(Color.surface, in: .rect(cornerRadius: Layout.cardRadius, style: .continuous))
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Label("Kein Konto, keine Werbung, keine Tracker", systemImage: "person.crop.circle.badge.xmark")
                Label("Kein Server von uns: Wir sehen deine Gutscheine nie", systemImage: "lock")
            }
            .fixedSize(horizontal: false, vertical: true)
            .font(.scaled(15)).foregroundStyle(Color.ink2)
            .padding(.top, Layout.section)
        }
    }
}
