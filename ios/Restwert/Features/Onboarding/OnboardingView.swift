import SwiftUI
import RestwertKit

/// Einstieg: zeigt direkt, wie die App aussieht, statt Deko-Grafik.
struct OnboardingView: View {
    var onStart: () -> Void

    private let preview: [(id: String, name: String, due: String, dueSoon: Bool, amount: String, of: String)] = [
        ("ikea", "IKEA", "noch 9 Tage", true, "50,00 €", "von 50,00 €"),
        ("douglas", "Douglas", "bis 31.03.2027", false, "23,85 €", "von 40,00 €"),
        ("thalia", "Thalia", "bis 31.12.2028", false, "12,40 €", "von 25,00 €"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Restwert").font(.scaled(17, weight: .bold))
                .padding(.top, 24)
            Text("Deine Gutscheine,\nan einem Ort.")
                .font(.scaled(36, weight: .bold)).kerning(-0.8)
                .padding(.top, 28)
            Text("Karte abfotografieren oder Gutschein-PDF aus der Mail laden, Guthaben nachtragen, an der Kasse den Barcode zeigen. Vor dem Ablauf kommt eine Erinnerung.")
                .font(.scaled(17)).foregroundStyle(Color.ink2)
                .padding(.top, 14)
            Spacer(minLength: 24)
            Text("So sieht es aus (Beispiel)").font(.scaled(13, weight: .medium)).foregroundStyle(Color.muted)
                .padding(.horizontal, 4).padding(.bottom, 8)
            VStack(spacing: 0) {
                ForEach(Array(preview.enumerated()), id: \.offset) { i, row in
                    if i > 0 { Divider().padding(.leading, 72) }
                    HStack(spacing: 14) {
                        MerchantMark(merchantID: row.id, name: row.name)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.name).font(.scaled(16, weight: .semibold))
                            Text(row.due).font(.scaled(13, weight: row.dueSoon ? .semibold : .regular))
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
            .background(Color.surface, in: .rect(cornerRadius: 18, style: .continuous))
            .accessibilityHidden(true)
            Spacer(minLength: 24)
            Label("Kein Konto nötig. Deine Daten bleiben auf diesem iPhone.", systemImage: "lock")
                .font(.scaled(14)).foregroundStyle(Color.ink2)
                .padding(.bottom, 14)
            Button("Los geht's", action: onStart)
                .buttonStyle(.primary)
        }
        .foregroundStyle(Color.ink)
        .padding(.horizontal, 20).padding(.bottom, 16)
        .pageBackground()
    }
}
