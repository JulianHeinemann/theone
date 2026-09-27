import SwiftUI
import RestwertKit

/// Einstieg: zeigt direkt, wie die App aussieht, statt Deko-Grafik.
struct OnboardingView: View {
    var onStart: () -> Void

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
            content.padding(.horizontal, 20).padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            Button("Los geht's", action: onStart)
                .buttonStyle(.primary)
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 16)
                .background(Color.page)
        }
        .foregroundStyle(Color.ink)
        .background(Color.page.ignoresSafeArea())
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Restwert").font(.scaled(17, weight: .bold))
                .padding(.top, 24)
            Text("Deine Gutscheine,\nan einem Ort.")
                .font(.scaled(36, weight: .bold)).kerning(-0.8)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 28)
            Text("Ob Karte, Papierzettel vom Café oder Code aus einer Mail: fotografieren, Betrag eintragen, fertig. Vor dem Ablauf kommt eine Erinnerung, an der Kasse zeigst du den Barcode.")
                .font(.scaled(17)).foregroundStyle(Color.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
            Text("So sieht es aus (Beispiel)").font(.scaled(13, weight: .medium)).foregroundStyle(Color.muted)
                .padding(.horizontal, 4).padding(.top, 24).padding(.bottom, 8)
            VStack(spacing: 0) {
                ForEach(Array(preview.enumerated()), id: \.offset) { i, row in
                    if i > 0 { Divider().padding(.leading, 72) }
                    HStack(spacing: 14) {
                        MerchantMark(merchantID: row.id, name: row.name)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.name).font(.scaled(16, weight: .semibold))
                            Text(row.due).font(.scaled(13, weight: row.dueSoon ? .semibold : .regular))
                                .fixedSize(horizontal: false, vertical: true)
                                .foregroundStyle(row.dueSoon ? Color.warn : Color.muted)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(row.amount).font(.scaled(17, weight: .semibold)).monospacedDigit()
                            Text(row.of).font(.scaled(12)).foregroundStyle(Color.muted)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                }
            }
            .foregroundStyle(Color.ink)
            .background(Color.surface, in: .rect(cornerRadius: Layout.cardRadius, style: .continuous))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Label("Kein Konto, keine Werbung, keine Tracker", systemImage: "person.crop.circle.badge.xmark")
                Label("Kein Server von uns: Wir sehen deine Gutscheine nie", systemImage: "lock")
            }
            .fixedSize(horizontal: false, vertical: true)
            .font(.scaled(14)).foregroundStyle(Color.ink2)
            .padding(.top, 24)
        }
    }
}
