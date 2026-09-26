import SwiftUI
import UIKit
import UniformTypeIdentifiers
import LocalAuthentication
import UserNotifications
import RestwertKit

struct CardDetailView: View {
    let cardID: UUID
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("pinLock") private var pinLock = true
    @AppStorage("reminders") private var remindersOn = true
    @AppStorage("warnDays") private var warnDays = 30

    @State private var pinVisible = false
    @State private var confirmDelete = false
    @State private var showLocation = false
    @State private var stampVisible = false
    @State private var copied = false
    @State private var success = 0
    @State private var showPhoto = false
    @State private var notifStatus: UNAuthorizationStatus?

    var body: some View {
        Group {
            if let card = store.card(cardID) {
                content(card)
            } else {
                ContentUnavailableView("Gutschein entfernt", systemImage: "trash")
            }
        }
        .pageBackground()
        .sensoryFeedback(.success, trigger: success)
        .task { await refreshNotifStatus() }
        .onChange(of: scenePhase) { _, phase in
            // PIN schon vor dem Snapshot für den App-Umschalter wieder verbergen.
            if phase != .active { pinVisible = false } else { Task { await refreshNotifStatus() } }
        }
    }

    private func content(_ card: GiftCard) -> some View {
        let status = card.status(warnDays: warnDays)
        return ScrollView {
            VStack(spacing: 16) {
                if !card.isActive && !card.isArchived {
                    archiveBanner(card, status)
                }
                if card.pendingSince != nil && card.isActive {
                    pendingBanner(card)
                }
                summary(card, status)
                if card.isActive {
                    NavigationLink(value: Route.checkout(card.id)) {
                        Label("An der Kasse zeigen", systemImage: "barcode")
                    }
                    .buttonStyle(.primary)
                }
                secondaryActions(card)
                if card.isActive {
                    if card.kind.isValueBased { partialRedeem(card) } else { markRedeemedBlock(card) }
                }
                codeTicket(card)
                locationRow(card)
                // Eigene Erinnerungen plant der Store nur für echte, eigene Gutscheine.
                if card.isActive && !card.isExample && !card.forGifting { reminderRow(card) }
                CardBon(card: card).padding(.top, 6)
                if !card.kind.isValueBased && card.redeemedAt != nil {
                    Button("Doch nicht eingelöst", systemImage: "arrow.uturn.backward") { unmarkRedeemed(card.id) }
                        .buttonStyle(.quiet)
                }
                if card.isArchived {
                    Button("Wiederherstellen", systemImage: "tray.and.arrow.up") { store.setArchived(card.id, false) }
                        .buttonStyle(.quiet)
                }
                Button("Gutschein entfernen", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    .font(.scaled(15, weight: .bold)).padding(.top, 6)
            }
            .padding(.horizontal, 16).padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .fullScreenCover(isPresented: $showPhoto) {
            if let data = card.photo, let image = UIImage(data: data) { PhotoViewer(image: image) }
        }
        .toolbar(.hidden, for: .tabBar)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Bearbeiten", systemImage: "pencil") { router.editing = card }
            }
        }
        .confirmationDialog("Gutschein endgültig entfernen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Entfernen", role: .destructive) {
                dismiss()
                clearLaterNotification(card.id)
                store.delete(card.id)
            }
        }
        .sheet(isPresented: $showLocation) {
            LocationSheet(location: card.location, note: card.locationNote) { location, note in
                store.setLocation(card.id, location, note: note)
            }
            .presentationDetents([.medium, .large])
        }
        .onChange(of: card.pendingSince == nil) { _, done in
            // Betrag eingetragen oder verworfen: „Hast du bezahlt?“-Nachfrage nicht mehr schicken.
            if done { clearLaterNotification(card.id) }
        }
    }

    // MARK: Übersicht

    private func summary(_ card: GiftCard, _ status: VoucherStatus) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            BalanceCard(card: card, status: status)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                cell("Gültig bis", card.expires.dayMonthYear)
                let count = redemptionCount(card)
                cell("Einlösungen", count == 0 ? "noch keine" : "\(count)")
            }
            .padding(.horizontal, 4)
        }
        .overlay {
            if card.redeemedAt != nil || stampVisible {
                Stamp(date: card.redeemedAt ?? .now).allowsHitTesting(false)
            }
        }
    }

    private func cell(_ label: String, _ value: String, tint: Color = .ink) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.scaled(12)).foregroundStyle(Color.muted)
            Text(value).font(.scaled(16, weight: .semibold)).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.7)
                .contentTransition(.numericText())
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// PIN und Guthaben-Link als gleichrangige, kleinere Knöpfe unter dem Hauptknopf.
    @ViewBuilder
    private func secondaryActions(_ card: GiftCard) -> some View {
        let hasPin = card.kind == .giftCard && !card.pin.isEmpty
        let link = card.merchant.balanceURL.flatMap { url in card.merchant.balanceCheck.linkLabel.map { (url, $0) } }
        if hasPin || link != nil {
            HStack(spacing: 8) {
                if hasPin {
                    Button { Task { await togglePin(card) } } label: {
                        Label(pinVisible ? card.pin : "PIN anzeigen", systemImage: pinVisible ? "lock.open" : "faceid")
                            .contentTransition(.numericText())
                            .privacySensitive()
                            .modifier(SecondaryPill())
                    }
                    .buttonStyle(.plain)
                }
                if let (url, label) = link {
                    Link(destination: url) {
                        Label(hasPin ? shortLinkLabel(card.merchant.balanceCheck) ?? label : label, systemImage: "arrow.up.right")
                            .modifier(SecondaryPill())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Nach „Später eintragen“ an der Kasse: Betrag nachtragen oder verwerfen.
    private func pendingBanner(_ card: GiftCard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Betrag offen", systemImage: "clock.badge.exclamationmark").font(.scaled(16, weight: .semibold))
            Text("Du hast \(card.name) an der Kasse benutzt, aber noch keinen Betrag eingetragen.")
                .font(.scaled(14)).foregroundStyle(Color.ink2)
            HStack(spacing: 8) {
                NavigationLink(value: Route.keypad(card.id)) {
                    Text("Jetzt eintragen").modifier(SecondaryPill())
                }
                .buttonStyle(.plain)
                Button {
                    store.setPending(card.id, false)
                    clearLaterNotification(card.id)
                } label: {
                    Text("Nicht bezahlt").modifier(SecondaryPill())
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(Color.ink)
        .padding(14)
        .background(Color.warnSoft, in: .rect(cornerRadius: 18, style: .continuous))
    }

    /// Aufgebraucht oder abgelaufen: direkt oben anbieten, den Gutschein aus der Liste zu nehmen.
    private func archiveBanner(_ card: GiftCard, _ status: VoucherStatus) -> some View {
        HStack(spacing: 12) {
            Image(systemName: status == .expired ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .font(.scaled(20)).foregroundStyle(status == .expired ? Color.bad : Color.good)
            Text(status == .expired ? "Abgelaufen" : "Aufgebraucht").font(.scaled(16, weight: .semibold))
            Spacer()
            Button("Archivieren") {
                store.setArchived(card.id, true)
                dismiss()
            }
            .font(.scaled(15, weight: .semibold))
            .buttonStyle(.glass)
        }
        .foregroundStyle(Color.ink)
        .padding(14)
        .background(Color.surface, in: .rect(cornerRadius: 18, style: .continuous))
    }

    /// Eigene Erinnerung nur für diesen Gutschein.
    private func reminderRow(_ card: GiftCard) -> some View {
        let range = reminderRange(card)
        return VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(
                get: { card.reminderAt != nil },
                set: { on in
                    store.setReminder(card.id, on ? defaultReminder(card) : nil)
                    if on && notifStatus == .notDetermined {
                        Task {
                            await store.requestNotifications()
                            await refreshNotifStatus()
                        }
                    }
                })) {
                Label("Eigene Erinnerung", systemImage: "bell")
                    .font(.scaled(16, weight: .semibold))
            }
            .tint(Color.ink)
            if let date = card.reminderAt {
                DatePicker("Am", selection: Binding(get: { min(max(date, range.lowerBound), range.upperBound) },
                                                   set: { store.setReminder(card.id, $0) }),
                           in: range, displayedComponents: [.date, .hourAndMinute])
                    .environment(\.locale, Locale(identifier: "de_DE"))
                    .font(.scaled(15))
                if notifStatus == .denied {
                    Button("Mitteilungen sind aus – in den Einstellungen erlauben", systemImage: "bell.slash") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .font(.scaled(13, weight: .medium)).foregroundStyle(Color.bad)
                } else if !remindersOn {
                    Label("Erinnerungen sind in den Restwert-Einstellungen ausgeschaltet.", systemImage: "bell.slash")
                        .font(.scaled(13, weight: .medium)).foregroundStyle(Color.bad)
                }
            }
        }
        .foregroundStyle(Color.ink)
        .padding(14)
        .background(Color.surface, in: .rect(cornerRadius: 18, style: .continuous))
    }

    /// Von jetzt bis zum Ende des Ablauftags; nie ein leerer Bereich, auch nicht am Ablauftag selbst.
    private func reminderRange(_ card: GiftCard) -> ClosedRange<Date> {
        let now = Date.now
        let end = Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: card.expires) ?? card.expires
        return now...max(end, now)
    }

    /// Vorschlag: 3 Tage vor Ablauf zur gewohnten Erinnerungszeit, frühestens in einer Stunde, spätestens am Ablauftag.
    private func defaultReminder(_ card: GiftCard) -> Date {
        let cal = Calendar.current
        let range = reminderRange(card)
        let day = cal.date(byAdding: .day, value: -3, to: card.expires) ?? card.expires
        let proposal = cal.date(bySettingHour: ReminderPrefs.hour, minute: 0, second: 0, of: day) ?? day
        return min(max(proposal, range.lowerBound.addingTimeInterval(3600)), range.upperBound)
    }

    private func refreshNotifStatus() async {
        notifStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private func clearLaterNotification(_ id: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["\(id.uuidString)-later"])
    }

    /// Nur echte Abzüge und gestempelte Codes, keine Aufladungen oder Korrekturen.
    private func redemptionCount(_ card: GiftCard) -> Int {
        card.history.filter { r in
            r.amount > 0 ? r.note != "Stand korrigiert" : r.amount == 0 && r.note == "\(card.kind.label) eingelöst"
        }.count
    }

    /// Kurze Beschriftung neben dem PIN-Knopf, passend zum Prüfweg.
    private func shortLinkLabel(_ check: BalanceCheck) -> String? {
        switch check {
        case .form: "Guthaben prüfen"
        case .account: "Kundenkonto"
        case .info: "Infos zum Guthaben"
        case .none: nil
        }
    }

    private func locationRow(_ card: GiftCard) -> some View {
        Button { showLocation = true } label: {
            HStack(spacing: 14) {
                Image(systemName: card.location.symbol).font(.scaled(18, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44)
                    .background(Color.fill, in: .rect(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Aufbewahrt: \(card.location.label)").font(.scaled(16, weight: .semibold))
                    Text(card.locationNote.isEmpty ? "Notiz hinzufügen" : card.locationNote)
                        .font(.scaled(13)).foregroundStyle(Color.muted).lineLimit(2)
                }
                Spacer()
                Text("Ändern").font(.scaled(14, weight: .bold))
            }
            .foregroundStyle(Color.ink).padding(12).cardSurface(radius: 20)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func codeTicket(_ card: GiftCard) -> some View {
        if card.number.isEmpty {
            photoTicket(card)
        } else {
            barcodeTicket(card)
        }
    }

    /// Papiergutschein ohne Code: das Foto ist der Gutschein.
    private func photoTicket(_ card: GiftCard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Original").font(.scaled(16, weight: .bold))
            if let data = card.photo, let image = UIImage(data: data) {
                Button { showPhoto = true } label: {
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 260)
                        .clipShape(.rect(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Foto des Gutscheins groß anzeigen")
                Text("An der Kasse das Foto zeigen oder das Original mitnehmen.").font(.scaled(13)).foregroundStyle(Color.ink2)
            } else {
                Text("Kein Foto und kein Code gespeichert. Tipp oben auf den Stift, um eins hinzuzufügen.")
                    .font(.scaled(14)).foregroundStyle(Color.ink2)
            }
        }
        .foregroundStyle(Color.ink)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: 28)
    }

    private func barcodeTicket(_ card: GiftCard) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("Code").font(.scaled(16, weight: .bold))
                Spacer()
                Button {
                    // Nur auf diesem Gerät und nach 2 Minuten wieder weg.
                    UIPasteboard.general.setItems([[UTType.plainText.identifier: card.number]],
                                                  options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(120)])
                    copied = true
                    success += 1
                    Task {
                        try? await Task.sleep(for: .seconds(1.6))
                        copied = false
                    }
                } label: {
                    Label(copied ? "Kopiert" : "Code kopieren", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.scaled(14, weight: .bold))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.glassProminent)
                .tint(Color.brandYellow)
                .foregroundStyle(Color.onBrand)
            }
            .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 4)
            Perforation()
            VStack(spacing: 8) {
                BarcodeView(number: card.number, format: card.format, height: 84)
                if card.format != .text {
                    Text(card.number.grouped).font(.scaled(17, weight: .bold)).kerning(2).textSelection(.enabled)
                }
                if card.photo != nil {
                    Button("Original-Foto ansehen", systemImage: "photo") { showPhoto = true }
                        .font(.scaled(14, weight: .medium)).foregroundStyle(Color.ink2).padding(.top, 4)
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 18)
        }
        .cardSurface(radius: 28)
    }

    // MARK: Teileinlösung mit Abriss

    /// Ein einziger Weg zum Abziehen: dasselbe Tastenfeld wie nach „Bezahlt“ an der Kasse.
    private func partialRedeem(_ card: GiftCard) -> some View {
        NavigationLink(value: Route.keypad(card.id)) {
            HStack(spacing: 14) {
                Image(systemName: "minus.circle.fill").font(.scaled(24))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Einkauf eintragen").font(.scaled(17, weight: .bold))
                    Text("Betrag wird vom Guthaben abgezogen").font(.scaled(14)).foregroundStyle(Color.onBrand.opacity(0.75))
                }
                Spacer()
                Image(systemName: "chevron.right").font(.scaled(14, weight: .semibold)).foregroundStyle(Color.onBrand.opacity(0.75))
            }
            .foregroundStyle(Color.onBrand)
            .padding(16)
            .background(Color.brandYellow, in: .rect(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func markRedeemedBlock(_ card: GiftCard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(card.kind.label) benutzt?").font(.scaled(20, weight: .bold))
            Text("Rabattcodes und Coupons gelten meist nur einmal. Markier ihn nach dem Einkauf, dann erscheint er im Verlauf.")
                .font(.scaled(14)).foregroundStyle(Color.muted)
            Button {
                // Doppeltipp: nur der erste Tipp stempelt.
                guard !stampVisible else { return }
                stampVisible = true
                success += 1
                let id = card.id
                let label = card.kind.label
                Task {
                    try? await Task.sleep(for: .milliseconds(650))
                    guard store.card(id)?.redeemedAt == nil else { return }
                    withAnimation(.smooth) { store.markRedeemed(id) }
                    router.showUndo("\(label) als eingelöst markiert.") { unmarkRedeemed(id) }
                }
            } label: {
                Label("Als eingelöst markieren", systemImage: "seal")
            }
            .buttonStyle(.accent)
            .disabled(stampVisible)
        }
        .padding(18)
        .cardSurface(radius: 28)
    }

    /// Stempel zurücknehmen: Einlösedatum und den zugehörigen Verlaufseintrag entfernen.
    private func unmarkRedeemed(_ id: UUID) {
        guard var c = store.card(id), c.redeemedAt != nil else { return }
        c.redeemedAt = nil
        if let i = c.history.lastIndex(where: { $0.amount == 0 && $0.note == "\(c.kind.label) eingelöst" }) {
            c.history.remove(at: i)
        }
        withAnimation(.smooth) {
            store.upsert(c)
            stampVisible = false
        }
    }

    private func togglePin(_ card: GiftCard) async {
        if pinVisible {
            withAnimation(.snappy) { pinVisible = false }
            return
        }
        guard pinLock else {
            withAnimation(.snappy) { pinVisible = true }
            return
        }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            withAnimation(.snappy) { pinVisible = true }
            return
        }
        let ok = (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "PIN von \(card.name) anzeigen")) ?? false
        if ok { withAnimation(.snappy) { pinVisible = true } }
    }
}

// MARK: - Bausteine

/// Roter Stempel „Eingelöst“, fällt mit Wucht aufs Papier.
struct Stamp: View {
    let date: Date
    @State private var landed = false

    var body: some View {
        VStack(spacing: 2) {
            Text("EINGELÖST").font(.scaled(28, weight: .black, design: .rounded)).kerning(3)
            Text(date.dayMonthYear).font(.scaled(13, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(Color.bad.opacity(0.85))
        .padding(.horizontal, 18).padding(.vertical, 10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.bad.opacity(0.85), lineWidth: 4))
        .rotationEffect(.degrees(landed ? -14 : -30))
        .scaleEffect(landed ? 1 : 2.4)
        .opacity(landed ? 1 : 0)
        .onAppear { withAnimation(.spring(duration: 0.45, bounce: 0.5)) { landed = true } }
        .sensoryFeedback(.impact(weight: .heavy), trigger: landed)
    }
}

/// Auswahl-Sheet für den Aufbewahrungsort.
struct LocationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var location: StorageLocation
    @State var note: String
    var onSave: (StorageLocation, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Wo liegt der Gutschein?").font(.scaled(24, weight: .heavy)).padding(.top, 24)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(StorageLocation.allCases) { loc in
                    Button { withAnimation(.snappy) { location = loc } } label: {
                        VStack(spacing: 8) {
                            Image(systemName: loc.symbol).font(.scaled(22, weight: .semibold))
                                .symbolEffect(.bounce, value: location == loc)
                            Text(loc.label).font(.scaled(13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .foregroundStyle(location == loc ? Color.onBrand : Color.ink)
                        .frame(maxWidth: .infinity, minHeight: 84)
                        .background(location == loc ? Color.brandYellow : Color.fill, in: .rect(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .sensoryFeedback(.selection, trigger: location)
            LabeledField(label: "Notiz", placeholder: "z. B. oberste Schublade im Flur", text: $note)
            Spacer()
            Button("Speichern") {
                onSave(location, note.trimmingCharacters(in: .whitespaces))
                dismiss()
            }
            .buttonStyle(.primary)
        }
        .padding(.horizontal, 20).padding(.bottom, 16)
    }
}

/// Mini-Bon eines Gutscheins: alle Einlösungen mit Restwert danach.
struct CardBon: View {
    let card: GiftCard

    var body: some View {
        ReceiptPaper {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Einlöse-Verlauf").font(.scaled(20, weight: .heavy))
                    Spacer()
                    Text(card.name.uppercased()).font(.scaled(12, weight: .bold, design: .monospaced)).foregroundStyle(Color.muted)
                }
                DashedRule()
                row(card.kind.isValueBased ? "Erhalten" : "Hinzugefügt", card.received.dayMonthYear,
                    card.kind.isValueBased ? "+" + card.value.euro : card.headline)
                ForEach(card.history.sorted { $0.date < $1.date }) { r in
                    row(r.store.isEmpty ? (r.amount > 0 ? "Eingelöst" : r.note) : r.store, subline(r),
                        r.amount > 0 ? "−" + r.amount.euro : r.amount < 0 ? "+" + (-r.amount).euro : "✓")
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if card.history.isEmpty {
                    Text("Noch nichts eingelöst.").font(.scaled(13, design: .monospaced)).foregroundStyle(Color.muted)
                }
                DashedRule()
                row(card.kind.isValueBased ? "RESTWERT" : "STATUS", "",
                    card.kind.isValueBased ? card.balance.euro : (card.redeemedAt == nil ? "OFFEN" : "EINGELÖST"), bold: true)
            }
            .animation(.smooth, value: card.history.count)
        }
    }

    private func subline(_ r: Redemption) -> String {
        var s = r.date.dayMonthYear
        if !r.note.isEmpty && r.amount > 0 { s += " · \(r.note)" }
        if card.kind.isValueBased { s += " · Rest \(r.balanceAfter.euro)" }
        return s
    }

    private func row(_ title: String, _ sub: String, _ amount: String, bold: Bool = false) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.scaled(14, weight: bold ? .heavy : .semibold, design: .monospaced))
                if !sub.isEmpty {
                    Text(sub).font(.scaled(11.5, design: .monospaced)).foregroundStyle(Color.muted)
                }
            }
            Spacer()
            Text(amount).font(.scaled(14, weight: bold ? .heavy : .semibold, design: .monospaced))
        }
    }
}

/// Kleiner weißer Knopf, halb so hoch wie der Hauptknopf.
private struct SecondaryPill: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.scaled(15, weight: .medium)).foregroundStyle(Color.ink)
            .lineLimit(1).minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Color.surface, in: .rect(cornerRadius: 14, style: .continuous))
    }
}
