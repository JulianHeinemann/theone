import SwiftUI
import RestwertKit

/// Wohin es nach dem Einstieg geht.
enum OnboardingExit { case browse, add, scan, manual }

/// Einstieg in vier Seiten: Willkommen (Ticket), Sammeln (Liste), Erinnern (Mitteilung), Erster Gutschein.
/// Jede Seite spielt ihre kleine Animation, sobald sie sichtbar wird. Bei „Bewegung reduzieren“ steht alles sofort da.
/// Kein Login: Die App hat bewusst kein Konto. Wer schon Gutscheine hat, holt sie aus dem eigenen iCloud.
struct OnboardingView: View {
    var onFinish: (OnboardingExit) -> Void

    @Environment(Store.self) private var store
    @Environment(CloudSync.self) private var cloud
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0
    @State private var tick = 0

    private let pages = 4

    var body: some View {
        VStack(spacing: 0) {
            header
            TabView(selection: $page) {
                WelcomePage(active: page == 0).tag(0)
                CollectPage(active: page == 1).tag(1)
                RemindPage(active: page == 2).tag(2)
                FirstCardPage(active: page == 3, onPick: onFinish).tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .sensoryFeedback(.selection, trigger: page)
            dots
                .padding(.horizontal, Layout.page).padding(.bottom, Layout.section)
            actions
                .padding(.horizontal, Layout.page).padding(.bottom, 8)
        }
        .foregroundStyle(Color.ink)
        .background(Color.page.ignoresSafeArea())
    }

    private var header: some View {
        HStack {
            Wordmark(size: 28)
            Spacer()
            if page < pages - 1 {
                Button("Überspringen") { withAnimation(.smooth) { page = pages - 1 } }
                    .font(.scaled(15, weight: .medium)).foregroundStyle(Color.ink2)
                    .frame(minHeight: Layout.tap)
                    .transition(.opacity)
            }
        }
        .frame(minHeight: Layout.tap)
        .padding(.horizontal, Layout.page).padding(.top, 8)
        .animation(.smooth, value: page)
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(0..<pages, id: \.self) { i in
                Capsule().fill(i == page ? Color.ink : Color.ink.opacity(0.2))
                    .frame(width: i == page ? 24 : 7, height: 7)
            }
            Spacer()
        }
        .animation(.spring(duration: 0.35, bounce: 0.3), value: page)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Seite \(page + 1) von \(pages)")
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 4) {
            switch page {
            case 0:
                Button("Los geht's") { next() }.buttonStyle(.primary)
                quiet(" ") {}.hidden()
            case 1:
                Button("Weiter") { next() }.buttonStyle(.primary)
                quiet(" ") {}.hidden()
            case 2:
                Button("Benachrichtigungen erlauben") {
                    Task {
                        await store.requestNotifications()
                        next()
                    }
                }
                .buttonStyle(.primary)
                quiet("Später") { next() }
            default:
                Button("Gutschein hinzufügen") { onFinish(.add) }.buttonStyle(.primary)
                quiet("Erstmal umschauen") { onFinish(.browse) }
                HStack(spacing: 4) {
                    Text("Schon Gutscheine in iCloud?").foregroundStyle(Color.muted)
                    Button("Wiederherstellen") {
                        cloud.isEnabled = true
                        onFinish(.browse)
                    }
                    .fontWeight(.semibold).foregroundStyle(Color.ink)
                }
                .font(.scaled(13))
                .frame(minHeight: Layout.tap)
            }
        }
        .animation(.smooth, value: page)
    }

    private func quiet(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.scaled(15, weight: .medium)).foregroundStyle(Color.ink2)
            .frame(maxWidth: .infinity, minHeight: Layout.tap)
    }

    private func next() {
        withAnimation(.smooth) { page = min(page + 1, pages - 1) }
    }
}

// MARK: - Seitenrahmen

/// Oben die Bühne mit der Animation, unten Überschrift und Text – auf allen Seiten gleich gesetzt.
private struct PageFrame<Stage: View>: View {
    let title: String
    let text: String
    let active: Bool
    @ViewBuilder var stage: Stage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: Layout.section)
            stage.frame(maxWidth: .infinity)
            Spacer(minLength: Layout.section)
            Text(title)
                .font(.scaled(34, weight: .heavy, design: .rounded)).kerning(-0.6)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(text)
                .font(.scaled(17)).foregroundStyle(Color.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Layout.group)
        }
        .padding(.horizontal, Layout.page).padding(.bottom, Layout.section)
        .opacity(active || reduceMotion ? 1 : 0.4)
        .animation(.easeOut(duration: 0.3), value: active)
    }
}

/// Zeitgesteuerter Auftritt: zählt Schritte hoch, sobald die Seite aktiv wird; bei „Bewegung reduzieren“ sofort am Ende.
private struct Stepper: ViewModifier {
    let active: Bool
    let steps: [Int]           // Millisekunden bis zu jedem Schritt
    @Binding var step: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.task(id: active) {
            guard active else { return }
            if reduceMotion { step = steps.count; return }
            step = 0
            for (i, ms) in steps.enumerated() {
                try? await Task.sleep(for: .milliseconds(ms))
                if Task.isCancelled { return }
                step = i + 1
            }
        }
    }
}

// MARK: - 01 Willkommen

private struct WelcomePage: View {
    let active: Bool
    @State private var step = 0
    @State private var amount: Double = 0
    @State private var tearY: CGFloat = 110
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let total = 136.25

    var body: some View {
        PageFrame(title: "Kein Gutschein\nverfällt mehr.",
                  text: "Restwert behält den Überblick über alles, was du noch einlösen kannst – Karten, Codes, Stadtgutscheine.",
                  active: active) {
            ZStack {
                // Zweite Karte dahinter, schräg – wie ein Stapel in der Schublade.
                RoundedRectangle(cornerRadius: Layout.cardRadius, style: .continuous)
                    .fill(Color.surface)
                    .shadow(color: Color.shade, radius: 14, y: 6)
                    .rotationEffect(.degrees(step >= 1 ? -4 : 0))
                    .offset(x: step >= 1 ? -6 : 0, y: step >= 1 ? 10 : 0)
                ticket
                    .rotationEffect(.degrees(step >= 1 ? 0 : -6))
                    .offset(y: step >= 1 ? 0 : -60)
                    .opacity(step >= 1 ? 1 : 0)
            }
            .fixedSize(horizontal: false, vertical: true)
            .animation(.spring(duration: 0.7, bounce: 0.3), value: step)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Beispiel: Noch \(total.euro) drauf, 5 Karten, 2 bald weg")
        }
        .modifier(Stepper(active: active, steps: [150, 500, 900], step: $step))
        .task(id: step) {
            // Hochzählen, sobald das Ticket gelandet ist.
            guard step == 2 else {
                if step == 0 { amount = 0 }
                if step >= 3 || reduceMotion { amount = total }
                return
            }
            let frames = 24
            for f in 1...frames {
                let t = Double(f) / Double(frames)
                withAnimation(.snappy(duration: 0.1)) { amount = (total * (1 - pow(1 - t, 3)) * 100).rounded() / 100 }
                try? await Task.sleep(for: .milliseconds(30))
            }
            amount = total
        }
        .sensoryFeedback(.impact(weight: .light), trigger: step == 3)
    }

    private var ticket: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Noch drauf").font(.scaled(15, weight: .semibold)).opacity(0.75)
                AmountText(value: amount, size: 60)
            }
            .padding(.horizontal, Layout.ticketInset).padding(.top, Layout.ticketInset).padding(.bottom, Layout.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { tearY = $0 }
            TearLine(color: .sumText)
                .mask(alignment: .leading) {
                    GeometryReader { g in Rectangle().frame(width: step >= 3 ? g.size.width : 0) }
                }
                .animation(.easeOut(duration: 0.5), value: step)
                .padding(.horizontal, Layout.inset)
            VStack(alignment: .leading, spacing: 2) {
                Text("5 Karten · 2 bald weg").font(.scaled(15, weight: .semibold))
                Text("+ 1 Rabattcode, nicht in der Summe").font(.scaled(13)).opacity(0.75)
            }
            .padding(.horizontal, Layout.ticketInset).padding(.vertical, Layout.group)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(step >= 3 ? 1 : 0)
            .animation(.easeOut(duration: 0.3).delay(0.25), value: step)
        }
        .foregroundStyle(Color.sumText)
        .background(Color.sumFill, in: TicketShape(radius: Layout.cardRadius, notchRadius: 9, notchFromTop: tearY + 0.5))
        .shadow(color: Color.shade, radius: 14, y: 6)
    }
}

// MARK: - 02 Sammeln

private struct CollectPage: View {
    let active: Bool
    @State private var step = 0

    private let rows: [(id: String, name: String, due: String, amount: String, sub: String)] = [
        ("zalando", "Zalando", "bis 09.10.2026", "15 %", "Rabatt"),
        ("ikea", "IKEA", "bis 21.10.2026", "50,00 €", "von 50,00 €"),
        ("stadtgutschein", "Stadtgutschein", "bis 14.02.2027", "20,00 €", "von 20,00 €"),
    ]

    var body: some View {
        PageFrame(title: "Alles an einem Ort.",
                  text: "Egal ob Zalando, IKEA oder der Blumenladen um die Ecke: Gutschein rein, Restbetrag drauf, fertig.",
                  active: active) {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    if i > 0 { Divider().padding(.leading, 74).opacity(step > i ? 1 : 0) }
                    HStack(spacing: 14) {
                        MerchantMark(merchantID: row.id, name: row.name)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.name).font(.scaled(16, weight: .semibold))
                            Text(row.due).font(.scaled(13)).foregroundStyle(Color.muted)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(row.amount).font(.amount(20))
                            Text(row.sub).font(.scaled(13)).monospacedDigit().foregroundStyle(Color.muted)
                        }
                    }
                    .padding(.horizontal, Layout.inset).padding(.vertical, Layout.group)
                    // Jede Zeile gleitet von rechts in die Liste.
                    .offset(x: step > i ? 0 : 60)
                    .opacity(step > i ? 1 : 0)
                    .animation(.spring(duration: 0.5, bounce: 0.25), value: step)
                }
            }
            .background(Color.surface, in: .rect(cornerRadius: Layout.cardRadius, style: .continuous))
            .shadow(color: Color.shade, radius: 14, y: 6)
            .scaleEffect(step >= 1 ? 1 : 0.96)
            .animation(.spring(duration: 0.5), value: step)
            .accessibilityHidden(true)
        }
        .modifier(Stepper(active: active, steps: [150, 160, 160], step: $step))
    }
}

// MARK: - 03 Erinnern

private struct RemindPage: View {
    let active: Bool
    @State private var step = 0

    var body: some View {
        PageFrame(title: "Wir sagen Bescheid,\nbevor's zu spät ist.",
                  text: "Rechtzeitig vor dem Ablaufdatum bekommst du eine Erinnerung. Ohne Spam, versprochen.",
                  active: active) {
            VStack(spacing: Layout.group) {
                // Mitteilung fällt von oben herein, wie auf dem Sperrbildschirm.
                HStack(alignment: .top, spacing: 12) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(hex: 0x111111))
                        .frame(width: 40, height: 40)
                        .overlay(Circle().fill(Color.brandYellow).frame(width: 14, height: 14))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Restwert").font(.scaled(13, weight: .semibold))
                            Spacer()
                            Text("jetzt").font(.scaled(13)).foregroundStyle(Color.muted)
                        }
                        Text("Zalando läuft in 12 Tagen ab").font(.scaled(15, weight: .semibold))
                        Text("15 % Rabatt, noch nicht eingelöst. Jetzt nutzen?").font(.scaled(15)).foregroundStyle(Color.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(Layout.inset)
                .background(Color.surface, in: .rect(cornerRadius: Layout.cardRadius, style: .continuous))
                .shadow(color: Color.shade, radius: 16, y: 8)
                .offset(y: step >= 1 ? 0 : -120)
                .opacity(step >= 1 ? 1 : 0)
                .animation(.spring(duration: 0.55, bounce: 0.35), value: step)
                .zIndex(1)

                HStack(spacing: 14) {
                    MerchantMark(merchantID: "zalando", name: "Zalando")
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Zalando").font(.scaled(16, weight: .semibold))
                        Label { Text("noch 12 Tage") } icon: { Image(systemName: "clock") }
                            .labelStyle(DueLabelStyle())
                            .font(.scaled(13, weight: .semibold)).foregroundStyle(Color.warn)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.warnSoft, in: .capsule)
                            // Kurzer Puls, wenn die Mitteilung gelandet ist.
                            .scaleEffect(step == 3 ? 1.08 : 1)
                            .animation(.spring(duration: 0.3, bounce: 0.6), value: step)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("15 %").font(.amount(20))
                        Text("Rabatt").font(.scaled(13)).foregroundStyle(Color.muted)
                    }
                }
                .padding(.horizontal, Layout.inset).padding(.vertical, Layout.group)
                .background(Color.surface, in: .rect(cornerRadius: Layout.cardRadius, style: .continuous))
                .shadow(color: Color.shade, radius: 14, y: 6)
                .opacity(step >= 2 ? 1 : 0)
                .offset(y: step >= 2 ? 0 : 16)
                .animation(.easeOut(duration: 0.4), value: step)
            }
            .accessibilityHidden(true)
        }
        .modifier(Stepper(active: active, steps: [250, 350, 350, 250], step: $step))
        .sensoryFeedback(.impact(weight: .light), trigger: step == 1)
    }
}

// MARK: - 04 Erster Gutschein

private struct FirstCardPage: View {
    let active: Bool
    var onPick: (OnboardingExit) -> Void
    @State private var step = 0

    var body: some View {
        PageFrame(title: "Leg deinen ersten\nGutschein an.",
                  text: "Dauert 20 Sekunden. Die Beispiele auf dem Startscreen verschwinden dann automatisch.",
                  active: active) {
            VStack(spacing: Layout.group) {
                option(icon: "viewfinder", title: "Karte scannen", text: "Barcode oder QR-Code abfotografieren",
                       yellow: true, shown: step >= 1) { onPick(.scan) }
                option(icon: "keyboard", title: "Code eintippen", text: "Betrag, Laden und Ablaufdatum eingeben",
                       yellow: false, shown: step >= 2) { onPick(.manual) }
            }
        }
        .modifier(Stepper(active: active, steps: [150, 140], step: $step))
    }

    private func option(icon: String, title: String, text: String, yellow: Bool, shown: Bool,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.scaled(22, weight: .semibold))
                    .foregroundStyle(yellow ? Color.onBrand : Color.ink)
                    .frame(width: 56, height: 56)
                    .background(yellow ? Color.brandYellow : Color.fill, in: .rect(cornerRadius: Layout.buttonRadius, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.scaled(17, weight: .bold)).foregroundStyle(Color.ink)
                    Text(text).font(.scaled(15)).foregroundStyle(Color.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.scaled(15, weight: .semibold)).foregroundStyle(Color.muted)
            }
            .padding(Layout.inset)
            .background(Color.surface, in: .rect(cornerRadius: Layout.cardRadius, style: .continuous))
            .shadow(color: Color.shade, radius: 14, y: 6)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .offset(y: shown ? 0 : 24)
        .opacity(shown ? 1 : 0)
        .animation(.spring(duration: 0.5, bounce: 0.3), value: shown)
    }
}
