import SwiftUI
import RestwertKit

/// Einstieg als kleine Inszenierung der Marke: Wortmarke mit Punkt, das gelbe Ticket fällt ins Bild,
/// der Betrag zählt hoch, die Abrisslinie zieht sich, dann landen die Gutscheine auf dem Verfallsradar.
/// Mit „Los geht's“ reißt der untere Abschnitt ab. Bei „Bewegung reduzieren“ steht alles sofort da.
struct OnboardingView: View {
    var onStart: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0
    @State private var amount: Double = 0
    @State private var tearY: CGFloat = 100
    @State private var torn = false
    @State private var pop = 0
    @State private var tear = 0

    private let total: Double = 75

    /// Beispiel-Gutscheine relativ zu heute, damit der Radar immer passt.
    private let radarItems: [RadarItem] = {
        func days(_ d: Int) -> Date { Calendar.current.date(byAdding: .day, value: d, to: .now) ?? .now }
        return [
            RadarItem(merchantID: "dm", name: "dm", expires: days(9), urgent: true),
            RadarItem(merchantID: "googleplay", name: "Google Play", expires: days(46)),
            RadarItem(merchantID: nil, name: "Café am Markt", expires: days(84)),
            RadarItem(merchantID: "stadtgutschein", name: "Stadtgutschein", expires: days(128)),
            RadarItem(merchantID: "ikea", name: "IKEA", expires: days(400)),
        ]
    }()

    var body: some View {
        ScrollView {
            content.padding(.horizontal, Layout.page).padding(.bottom, Layout.inset)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            Button("Los geht's") { start() }
                .buttonStyle(.primary)
                .padding(.horizontal, Layout.page).padding(.top, 8).padding(.bottom, Layout.inset)
                .background(Color.page)
                .opacity(step >= 6 ? 1 : 0)
                .offset(y: step >= 6 || reduceMotion ? 0 : 20)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: step)
        }
        .foregroundStyle(Color.ink)
        .background(Color.page.ignoresSafeArea())
        .sensoryFeedback(.impact(weight: .light), trigger: pop)
        .sensoryFeedback(.impact(weight: .medium), trigger: tear)
        .task { await play() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            wordmark
                .padding(.top, Layout.section)
            Text("Kein Restwert\nbleibt liegen.")
                .font(.scaled(34, weight: .heavy, design: .rounded)).kerning(-0.6)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Layout.section)
                .reveal(step >= 2)
            Text("Karte, Papierzettel vom Café oder Code aus einer Mail: fotografieren, fertig. Vor dem Ablauf kommt eine Erinnerung, an der Kasse zeigst du den Code.")
                .font(.scaled(17)).foregroundStyle(Color.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Layout.group)
                .reveal(step >= 2, delay: 0.1)

            ticket
                .padding(.top, Layout.section)

            if step >= 5 {
                ExpiryRadarSection(items: radarItems, animateIn: !reduceMotion)
                    .padding(.top, Layout.section)
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("Kein Konto, keine Werbung, keine Tracker", systemImage: "person.crop.circle.badge.xmark")
                Label("Kein Server von uns: Wir sehen deine Gutscheine nie", systemImage: "lock")
            }
            .fixedSize(horizontal: false, vertical: true)
            .font(.scaled(15)).foregroundStyle(Color.ink2)
            .padding(.top, Layout.section)
            .reveal(step >= 6)
        }
    }

    /// Wortmarke, deren Punkt nach dem Schriftzug aufploppt.
    private var wordmark: some View {
        HStack(alignment: .lastTextBaseline, spacing: 3) {
            Text("Restwert").font(.scaled(28, weight: .heavy, design: .rounded))
                .reveal(step >= 1)
            Circle().fill(Color.brandYellow).frame(width: 10, height: 10)
                .overlay(Circle().strokeBorder(Color.ink.opacity(0.2), lineWidth: 0.5))
                .scaleEffect(step >= 2 ? 1 : 0.01)
                .animation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.6), value: step)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Restwert")
        .accessibilityAddTraits(.isHeader)
    }

    /// Das gelbe Ticket: fällt ins Bild, zählt hoch, die Abrisslinie zieht sich, beim Start reißt der Abschnitt ab.
    private var ticket: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Noch drauf").font(.scaled(15, weight: .semibold)).opacity(0.75)
                AmountText(value: amount, size: 56)
            }
            .padding(.horizontal, Layout.ticketInset).padding(.top, Layout.ticketInset).padding(.bottom, Layout.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { tearY = $0 }
            // Die Abrisslinie zieht sich von links nach rechts.
            TearLine(color: .sumText)
                .mask(alignment: .leading) {
                    GeometryReader { g in Rectangle().frame(width: step >= 4 ? g.size.width : 0) }
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.5), value: step)
                .padding(.horizontal, Layout.inset)
            Text("5 Gutscheine · 1 bald weg").font(.scaled(15, weight: .semibold))
                .padding(.horizontal, Layout.ticketInset).padding(.vertical, Layout.group)
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(step >= 4 ? 1 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.3).delay(0.3), value: step)
                .rotationEffect(.degrees(torn ? 8 : 0), anchor: .topLeading)
                .offset(y: torn ? 90 : 0)
                .opacity(torn ? 0 : 1)
        }
        .foregroundStyle(Color.sumText)
        .background(Color.sumFill, in: TicketShape(radius: Layout.cardRadius, notchRadius: 9, notchFromTop: tearY + 0.5))
        .shadow(color: Color.shade, radius: 14, y: 6)
        // Fällt leicht gedreht von oben ins Bild.
        .rotationEffect(.degrees(step >= 3 || reduceMotion ? 0 : -4))
        .offset(y: step >= 3 || reduceMotion ? 0 : -50)
        .opacity(step >= 3 ? 1 : 0)
        .animation(reduceMotion ? nil : .spring(duration: 0.6, bounce: 0.3), value: step)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Beispiel: Noch \(total.euro) drauf, 5 Gutscheine, 1 läuft bald ab")
    }

    // MARK: Ablauf

    private func play() async {
        if reduceMotion {
            amount = total
            step = 6
            return
        }
        func wait(_ ms: Int) async { try? await Task.sleep(for: .milliseconds(ms)) }
        await wait(150)
        step = 1
        await wait(350)
        step = 2
        pop += 1
        await wait(450)
        step = 3
        await wait(250)
        // Hochzählen mit abbremsender Kurve.
        let frames = 26
        for f in 1...frames {
            let t = Double(f) / Double(frames)
            withAnimation(.snappy(duration: 0.12)) { amount = (total * (1 - pow(1 - t, 3)) * 100).rounded() / 100 }
            await wait(32)
        }
        amount = total
        pop += 1
        step = 4
        await wait(550)
        withAnimation(.easeOut(duration: 0.3)) { step = 5 }
        await wait(700)
        step = 6
    }

    /// Abschnitt abreißen, dann in die App.
    private func start() {
        tear += 1
        guard !reduceMotion else { onStart(); return }
        withAnimation(.easeIn(duration: 0.35)) { torn = true }
        Task {
            try? await Task.sleep(for: .milliseconds(380))
            onStart()
        }
    }
}

private extension View {
    /// Einblenden von unten; ohne Bewegung nur Deckkraft.
    func reveal(_ on: Bool, delay: Double = 0) -> some View {
        modifier(Reveal(on: on, delay: delay))
    }
}

private struct Reveal: ViewModifier {
    let on: Bool
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(on ? 1 : 0)
            .offset(y: on || reduceMotion ? 0 : 14)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.45).delay(delay), value: on)
    }
}
