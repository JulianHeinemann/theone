import SwiftUI
import RestwertKit

/// Einstieg: schwebende Pastellkarten auf lebendigem Verlauf.
struct OnboardingView: View {
    var onStart: () -> Void

    private let cards: [(color: Color, number: String)] = [
        (Pastel.all[0], "856 279"), (Pastel.all[1], "412 008"), (Pastel.all[2], "731 554"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Kein Gutschein verfällt mehr.")
                .font(.system(size: 44, weight: .heavy)).kerning(-1)
                .padding(.top, 30)
            Text("Restwert holt deine Gutscheine aus der Schublade aufs Handy. Mit Restguthaben, Ablauf-Radar und Barcode für die Kasse.")
                .font(.system(size: 17)).foregroundStyle(Color.ink2)
            ZStack {
                LivingMesh()
                TimelineView(.animation) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    ZStack {
                        ForEach(Array(cards.enumerated()), id: \.offset) { i, card in
                            let wobble = CGFloat(sin(t * 1.1 + Double(i) * 1.7)) * 9
                            FloatingCard(color: card.color, number: card.number)
                                .offset(x: CGFloat(i) * 34 - 34, y: CGFloat(i) * 78 - 78 + wobble)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .clipShape(.rect(cornerRadius: 32, style: .continuous))
            Button(action: onStart) {
                HStack {
                    Text("Los geht's").font(.system(size: 17, weight: .bold))
                    Spacer()
                    Image(systemName: "arrow.right").font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.ink)
                        .frame(width: 62, height: 48)
                        .background(.white, in: .rect(cornerRadius: 12, style: .continuous))
                        .symbolEffect(.wiggle.right, options: .repeat(.periodic(delay: 2)))
                }
                .foregroundStyle(.white)
                .padding(.leading, 24).padding(8)
                .background(Color.ink, in: .rect(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20).padding(.bottom, 16)
        .pageBackground()
    }

    private struct FloatingCard: View {
        let color: Color
        let number: String

        var body: some View {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(color.gradient)
                .frame(width: 220, height: 138)
                .overlay(alignment: .topLeading) {
                    Text("RESTWERT").font(.system(size: 19, weight: .heavy)).kerning(1.4).padding(18)
                }
                .overlay(alignment: .bottomLeading) {
                    Text("••• \(number)").font(.system(size: 13, weight: .semibold)).kerning(1).opacity(0.7).padding(18)
                }
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: -7) {
                        Circle().fill(Color.ink.opacity(0.7)).frame(width: 18)
                        Circle().fill(Color.ink.opacity(0.35)).frame(width: 18)
                    }
                    .frame(height: 18).padding(18)
                }
                .foregroundStyle(Color.ink)
                .shadow(color: Color.ink.opacity(0.12), radius: 20, y: 20)
                .rotation3DEffect(.degrees(48), axis: (x: 1, y: 0, z: 0))
                .rotationEffect(.degrees(-28))
        }
    }
}
