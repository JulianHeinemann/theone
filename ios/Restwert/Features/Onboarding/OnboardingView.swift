import SwiftUI
import RestwertKit

/// Wohin es nach dem Einstieg geht.
enum OnboardingExit { case browse, add, scan, manual }

/// Einstieg in vier Seiten: Willkommen (Ticket), Sammeln (Liste), Erinnern (Mitteilung), Erster Gutschein.
/// Jede Seite spielt ihre kleine Animation, sobald sie sichtbar wird. Bei „Bewegung reduzieren“ steht alles sofort da.
/// Kein Login: Die App hat bewusst kein Konto. Wer schon Gutscheine hat, holt sie aus der eigenen iCloud.
/// Nach der Mitteilungs-Erlaubnis fragt erst das Formular beim ersten Speichern – nicht der Einstieg.
struct OnboardingView: View {
    var onFinish: (OnboardingExit) -> Void

    @Environment(CloudSync.self) private var cloud
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0

    private let pages = 4
    /// Alle Knopftexte liegen übereinander im Knopf, damit er auf jeder Seite gleich hoch ist.
    private let primaryTitles = ["Los geht’s", "Weiter", "Weiter", "Gutschein hinzufügen"]

    var body: some View {
        VStack(spacing: 0) {
            header
            TabView(selection: $page) {
                WelcomePage(active: page == 0).tag(0)
                CollectPage(active: page == 1).tag(1)
                RemindPage(active: page == 2).tag(2)
                FirstCardPage(active: page == 3, onPick: onFinish, onRestore: restore).tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .sensoryFeedback(.selection, trigger: page)
            // Aktionszone: auf allen Seiten gleich aufgebaut und gleich hoch – Punkte und Knöpfe springen nicht.
            VStack(spacing: Layout.group) {
                dots
                actions
            }
            .padding(.horizontal, Layout.page).padding(.top, Layout.group).padding(.bottom, 8)
            // Knöpfe wachsen mit, aber nur bis AX2: darüber fräße die feste Aktionszone (inkl. reserviertem
            // „Erstmal umschauen“) so viel Höhe, dass für den scrollenden Seitentext kaum etwas bleibt.
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .background(Color.page)
        }
        .foregroundStyle(Color.ink)
        .background(Color.page.ignoresSafeArea())
    }

    /// Wortmarke wie auf dem Start: gleiche Größe, 16 pt Rand, 44 pt hohe Leiste direkt unter der Statusleiste.
    /// Auf dem Start steht sie als Element der Navigationsleiste; die lässt sie bis zur größten Nicht-AX-Stufe
    /// mitwachsen (bei XL/XXL gemessen größer als mit Deckel xLarge). Dieselbe Grenze hier, sonst springt der Übergang.
    private var header: some View {
        HStack {
            Wordmark(size: 28).fixedSize()
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            Spacer()
            Button("Überspringen") { go(to: pages - 1) }
                .font(.scaled(15, weight: .medium)).foregroundStyle(Color.ink2)
                .frame(minWidth: Layout.tap, minHeight: Layout.tap)
                .contentShape(.rect)
                .opacity(page < pages - 1 ? 1 : 0)
                .disabled(page == pages - 1)
                .accessibilityHidden(page == pages - 1)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: page)
        }
        .frame(minHeight: Layout.tap)
        .lineLimit(1)
        // „Überspringen“ wächst nur bis zu einer Größe, bei der es neben der Wortmarke in eine Zeile passt.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .padding(.horizontal, Layout.page)
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(0..<pages, id: \.self) { i in
                Capsule().fill(i == page ? Color.ink : Color.ink.opacity(0.2))
                    .frame(width: i == page ? 24 : 7, height: 7)
            }
            Spacer()
        }
        .frame(height: 7)
        .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.3), value: page)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Seite \(page + 1) von \(pages)")
    }

    private var actions: some View {
        VStack(spacing: 4) {
            Button(action: primary) {
                ZStack {
                    ForEach(primaryTitles.indices, id: \.self) { i in
                        Text(primaryTitles[i]).opacity(i == page ? 1 : 0)
                    }
                }
            }
            .buttonStyle(.primary)
            .accessibilityLabel(primaryTitles[page])

            // Zweiter Knopf nur auf der letzten Seite; der Platz ist überall reserviert.
            Button("Erstmal umschauen") { onFinish(.browse) }
                .font(.scaled(15, weight: .medium)).foregroundStyle(Color.ink2)
                .frame(maxWidth: .infinity, minHeight: Layout.tap)
                .contentShape(.rect)
                .opacity(page == pages - 1 ? 1 : 0)
                .disabled(page != pages - 1)
                .accessibilityHidden(page != pages - 1)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: page)
    }

    private func primary() {
        if page == pages - 1 { onFinish(.add) } else { go(to: page + 1) }
    }

    private func restore() {
        cloud.isEnabled = true
        onFinish(.browse)
    }

    private func go(to target: Int) {
        let target = min(target, pages - 1)
        if reduceMotion { page = target } else { withAnimation(.smooth) { page = target } }
    }
}

// MARK: - Seitenrahmen

/// Oben die Bühne mit der Animation, unten Überschrift und Text – auf allen Seiten gleich gesetzt.
/// Passt alles, steht der Text unten; bei großer Schrift scrollt die Seite und ein Verlauf am unteren Rand zeigt, dass mehr kommt.
private struct PageFrame<Stage: View>: View {
    let title: String
    let text: String
    let active: Bool
    /// Reines Anschauungsbild (für VoiceOver zusammengefasst oder ausgeblendet): wächst nur mäßig mit der Schrift,
    /// damit bei großer Schrift der Fließtext Platz hat. Seite 4 zeigt echte Knöpfe, die wachsen voll mit.
    var decorativeStage = true
    @ViewBuilder var stage: Stage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var moreBelow = false
    /// Eigener Zähler: Scroll-Indikator blitzt, wenn die Seite aktiv wird oder sich herausstellt, dass Text unten fehlt.
    @State private var flashes = 0

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: Layout.section)
                    stage.frame(maxWidth: .infinity)
                        .dynamicTypeSize(...(decorativeStage ? DynamicTypeSize.xxLarge : .accessibility5))
                    Spacer(minLength: Layout.section)
                    copy
                }
                .padding(.horizontal, Layout.page).padding(.bottom, Layout.section)
                .frame(minHeight: geo.size.height, alignment: .bottom)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.visible)
            // Beim ersten Erscheinen (Seite 1 ist dann schon aktiv, ein Wechsel von `active` bleibt aus) und danach per Zähler.
            .scrollIndicatorsFlash(onAppear: true)
            .scrollIndicatorsFlash(trigger: flashes)
            .onScrollGeometryChange(for: Bool.self) { g in
                g.visibleRect.maxY < g.contentSize.height - 4
            } action: { _, more in
                moreBelow = more
                if more && active { flashes += 1 }
            }
            .onChange(of: active) { _, now in
                if now && moreBelow { flashes += 1 }
            }
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [Color.page.opacity(0), Color.page], startPoint: .top, endPoint: .bottom)
                    .frame(height: Layout.section + 8)
                    .opacity(moreBelow ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        // Inaktive Seiten gedimmt – als Papier-Schleier obenauf statt `.opacity` auf der ganzen Seite:
        // Gruppen-Deckkraft zwänge die komplette Seite samt Schatten in jedem Bild in eine Zwischenebene.
        .overlay {
            Color.page.opacity(active || reduceMotion ? 0 : 0.6)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: active)
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: Layout.group) {
            Text(title)
                .font(.scaled(34, weight: .heavy, design: .rounded)).kerning(-0.6)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(text)
                .font(.scaled(17)).foregroundStyle(Color.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Zeitgesteuerter Auftritt: zählt Schritte hoch, sobald die Seite aktiv wird; bei „Bewegung reduzieren“ sofort am Ende.
/// Verlässt man die Seite, springt sie ohne Animation auf den Anfang zurück, damit sie beim Wiederkommen neu spielt –
/// aber erst, wenn sie hinausgeglitten ist: „Weiter“ wechselt die Seite sofort, die Bühne bleibt noch 0,5 s sichtbar.
/// Kommt man vorher zurück, bleibt die fertige Bühne stehen statt von vorn zu spielen.
private struct Stepper: ViewModifier {
    let active: Bool
    let steps: [Int]           // Millisekunden Pause vor jedem Schritt
    @Binding var step: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.task(id: active) {
            if reduceMotion { step = steps.count; return }
            guard active else {
                try? await Task.sleep(for: .milliseconds(600))
                if Task.isCancelled { return }
                var reset = Transaction()
                reset.disablesAnimations = true
                withTransaction(reset) { step = 0 }
                return
            }
            guard step == 0 else { return }
            for (i, ms) in steps.enumerated() {
                try? await Task.sleep(for: .milliseconds(ms))
                if Task.isCancelled { return }
                step = i + 1
            }
        }
    }
}

/// Implizite Animation, die bei „Bewegung reduzieren“ entfällt: dann stehen sofort die Endzustände da.
private struct Motion<V: Equatable>: ViewModifier {
    let animation: Animation
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

private extension View {
    func motion<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(Motion(animation: animation, value: value))
    }
}

// MARK: - 01 Willkommen

private struct WelcomePage: View {
    let active: Bool
    @State private var step = 0
    @State private var countStart: Date?
    @State private var tearY: CGFloat = 110
    @State private var landed = 0
    private let total = 136.25
    private let countDuration = 0.8

    var body: some View {
        PageFrame(title: "Kein Gutschein\nverfällt mehr.",
                  text: "Restwert behält den Überblick über alles, was du noch einlösen kannst – Geschenkkarten, Rabattcodes, Stadtgutscheine.",
                  active: active) {
            ZStack {
                // Zweite Karte dahinter, schräg – wie ein Stapel in der Schublade.
                Color.clear.cardSurface()
                    .rotationEffect(.degrees(step >= 1 ? -4 : 0))
                    .offset(x: step >= 1 ? -6 : 0, y: step >= 1 ? 10 : 0)
                ticket
                    .rotationEffect(.degrees(step >= 1 ? 0 : -6))
                    .offset(y: step >= 1 ? 0 : -60)
                    .opacity(step >= 1 ? 1 : 0)
            }
            .fixedSize(horizontal: false, vertical: true)
            .motion(.spring(duration: 0.7, bounce: 0.3), value: step)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Beispiel: Noch \(total.euro) drauf, 5 Gutscheine, 2 laufen bald ab")
        }
        .modifier(Stepper(active: active, steps: [150, 500, 900], step: $step))
        .onChange(of: step) { _, s in
            // Hochzählen startet, sobald das Ticket gelandet ist; Haptik genau einmal, wenn die Abrisslinie steht.
            countStart = s == 2 ? .now : nil
            if s == 3 { landed += 1 }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: landed)
    }

    /// Betrag zum Zeitpunkt `date`: vorher 0, danach der Endwert, dazwischen weich abgebremst (kubisch).
    private func amount(at date: Date) -> Double {
        if step < 2 { return 0 }
        guard step == 2 else { return total }
        let t = min(1, max(0, date.timeIntervalSince(countStart ?? date) / countDuration))
        return (total * (1 - pow(1 - t, 3)) * 100).rounded() / 100
    }

    private var ticket: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Guthaben").font(.scaled(15, weight: .semibold)).opacity(0.75)
                // Eine durchgehende Zählbewegung pro Bildschirmbild statt vieler Einzelübergänge.
                TimelineView(.animation(paused: step != 2)) { context in
                    AmountText(value: amount(at: context.date), size: 60)
                        .transaction { $0.animation = nil }
                }
            }
            .padding(.horizontal, Layout.ticketInset).padding(.top, Layout.ticketInset).padding(.bottom, Layout.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { tearY = $0 }
            TearLine(color: .sumText)
                .mask(alignment: .leading) {
                    GeometryReader { g in Rectangle().frame(width: step >= 3 ? g.size.width : 0) }
                }
                .motion(.easeOut(duration: 0.5), value: step)
                .padding(.horizontal, Layout.inset)
            VStack(alignment: .leading, spacing: 2) {
                Text("5 Gutscheine · 2 laufen bald ab").font(.scaled(15, weight: .semibold))
                Text("+ 1 Rabattcode, nicht in der Summe").font(.scaled(13)).opacity(0.75)
            }
            .padding(.horizontal, Layout.ticketInset).padding(.vertical, Layout.group)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(step >= 3 ? 1 : 0)
            .motion(.easeOut(duration: 0.3).delay(0.25), value: step)
        }
        .foregroundStyle(Color.sumText)
        // Schatten auf der deckenden Ticketfläche, nicht auf dem Inhalt: Der Zähler ändert den Text in jedem Bild;
        // eine Gruppe mit Schatten müsste dann jedes Mal neu gezeichnet und weichgezeichnet werden.
        .background {
            TicketShape(radius: Layout.cardRadius, notchRadius: 9, notchFromTop: tearY + 0.5)
                .fill(Color.sumFill)
                .shadow(color: Color.shade, radius: Shadow.card, y: 6)
        }
    }
}

// MARK: - 02 Sammeln

private struct CollectPage: View {
    let active: Bool
    @State private var step = 0

    private let rows: [(id: String, name: String, due: String, amount: String, sub: String)] = [
        ("zalando", "Zalando", "bis 09.10.2026", "15\u{00A0}%", "Rabatt"),
        ("ikea", "IKEA", "bis 21.10.2026", "50,00\u{00A0}€", "von 50,00\u{00A0}€"),
        ("stadtgutschein", "Stadtgutschein", "bis 14.02.2027", "20,00\u{00A0}€", "von 20,00\u{00A0}€"),
    ]

    var body: some View {
        PageFrame(title: "Alles an einem Ort.",
                  text: "Egal ob Zalando, IKEA oder der Blumenladen um die Ecke: Gutschein rein, Restbetrag drauf, fertig. An der Kasse zeigst du den Code groß und ziehst ab, was du bezahlt hast.",
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
                    .motion(.spring(duration: 0.5, bounce: 0.25), value: step)
                }
            }
            .cardSurface()
            .scaleEffect(step >= 1 ? 1 : 0.96)
            .motion(.spring(duration: 0.5), value: step)
            .accessibilityHidden(true)
        }
        .modifier(Stepper(active: active, steps: [150, 160, 160], step: $step))
    }
}

// MARK: - 03 Erinnern

private struct RemindPage: View {
    let active: Bool
    @State private var step = 0
    @State private var arrived = 0

    var body: some View {
        PageFrame(title: "Wir sagen Bescheid,\nbevor’s zu spät ist.",
                  text: "Rechtzeitig vor dem Ablaufdatum bekommst du eine Erinnerung. Ohne Spam, versprochen. Wir fragen erst nach deinem ersten Gutschein, ob wir dir Mitteilungen schicken dürfen.",
                  active: active) {
            VStack(spacing: Layout.group) {
                // Mitteilung fällt von oben herein, wie auf dem Sperrbildschirm.
                HStack(alignment: .top, spacing: 12) {
                    AppIconMark()
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Restwert").font(.scaled(13, weight: .semibold))
                            Spacer()
                            Text("jetzt").font(.scaled(13)).foregroundStyle(Color.muted)
                        }
                        Text("Zalando läuft in 12\u{00A0}Tagen ab").font(.scaled(15, weight: .semibold))
                        Text("15\u{00A0}% Rabatt, noch nicht eingelöst. Jetzt nutzen?").font(.scaled(15)).foregroundStyle(Color.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(Layout.inset)
                .cardSurface(shadow: Shadow.float, y: 8)
                .offset(y: step >= 1 ? 0 : -120)
                .opacity(step >= 1 ? 1 : 0)
                .motion(.spring(duration: 0.55, bounce: 0.35), value: step)
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
                            .motion(.spring(duration: 0.3, bounce: 0.6), value: step)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("15\u{00A0}%").font(.amount(20))
                        Text("Rabatt").font(.scaled(13)).foregroundStyle(Color.muted)
                    }
                }
                .padding(.horizontal, Layout.inset).padding(.vertical, Layout.group)
                .cardSurface()
                .opacity(step >= 2 ? 1 : 0)
                .offset(y: step >= 2 ? 0 : 16)
                .motion(.easeOut(duration: 0.4), value: step)
            }
            .accessibilityHidden(true)
        }
        .modifier(Stepper(active: active, steps: [150, 350, 350, 250], step: $step))
        .onChange(of: step) { _, s in if s == 1 { arrived += 1 } }
        .sensoryFeedback(.impact(weight: .light), trigger: arrived)
    }
}

/// Das App-Icon im Kleinen – dasselbe Bild wie auf dem Home-Bildschirm (Asset „AppLogo“, hell und dunkel).
private struct AppIconMark: View {
    var body: some View {
        Image("AppLogo")
            .resizable()
            .interpolation(.high)
            .frame(width: 40, height: 40)
            .clipShape(.rect(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.line.opacity(0.6), lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}

// MARK: - 04 Erster Gutschein

private struct FirstCardPage: View {
    let active: Bool
    var onPick: (OnboardingExit) -> Void
    var onRestore: () -> Void
    @State private var step = 0

    var body: some View {
        PageFrame(title: "Leg deinen ersten\nGutschein an.",
                  text: "Dauert 20 Sekunden. Die Beispiele auf „Start“ verschwinden dann automatisch.",
                  active: active, decorativeStage: false) {
            VStack(spacing: Layout.group) {
                option(icon: "viewfinder", title: "Gutschein scannen", text: "Barcode, QR-Code oder Text abfotografieren",
                       strong: true, shown: step >= 1) { onPick(.scan) }
                option(icon: "keyboard", title: "Von Hand eingeben", text: "Laden, Guthaben und Ablaufdatum eintippen",
                       strong: false, shown: step >= 2) { onPick(.manual) }
                restoreLink
                    .opacity(step >= 2 ? 1 : 0)
                    .motion(.easeOut(duration: 0.3), value: step)
            }
        }
        .modifier(Stepper(active: active, steps: [150, 140], step: $step))
    }

    /// Kein Konto: „Wiederherstellen“ schaltet nur den iCloud-Abgleich ein.
    private var restoreLink: some View {
        Button(action: onRestore) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Schon Gutscheine in iCloud? \(Text("Wiederherstellen").fontWeight(.semibold).foregroundStyle(Color.ink))")
                    .font(.scaled(15)).foregroundStyle(Color.ink2)
                Text("Holt deine Gutscheine aus deiner iCloud – ganz ohne Konto.")
                    .font(.scaled(13)).foregroundStyle(Color.muted)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: Layout.tap, alignment: .leading)
            .padding(.horizontal, Layout.inset)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Wiederherstellen")
        .accessibilityHint("Holt deine Gutscheine aus deiner iCloud – ganz ohne Konto.")
    }

    /// `strong`: Hauptweg in Tinte (Gelb bleibt der Marke vorbehalten), sonst neutrale Fläche.
    private func option(icon: String, title: String, text: String, strong: Bool, shown: Bool,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.scaled(22, weight: .semibold))
                    .foregroundStyle(strong ? Color.onInk : Color.ink)
                    .frame(width: 56, height: 56)
                    .background(strong ? Color.ink : Color.fill, in: .rect(cornerRadius: Layout.buttonRadius, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.scaled(17, weight: .bold)).foregroundStyle(Color.ink)
                    Text(text).font(.scaled(15)).foregroundStyle(Color.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.scaled(15, weight: .semibold)).foregroundStyle(Color.muted)
                    .accessibilityHidden(true)
            }
            .padding(Layout.inset)
            .cardSurface()
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .offset(y: shown ? 0 : 24)
        .opacity(shown ? 1 : 0)
        .motion(.spring(duration: 0.5, bounce: 0.3), value: shown)
    }
}
