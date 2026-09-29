import SwiftUI
import UIKit
import UniformTypeIdentifiers
import LocalAuthentication
import UserNotifications
import RestwertKit

struct CardDetailView: View {
    let cardID: UUID
    @Environment(Store.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("pinLock") private var pinLock = true
    @AppStorage("reminders") private var remindersOn = true
    @AppStorage("warnDays") private var warnDays = 30

    @State private var pinVisible = false
    @State private var confirmUnprotectedPin = false
    @AppStorage("codeLock") private var codeLockSetting = false
    /// Nur wirksam mit Gerätecode; sonst stünde der Code hinter einer Abfrage, die nie gelingen kann.
    private var codeLock: Bool { codeLockSetting && DeviceSecurity.status != .noPasscode }
    @State private var codeVisible = false
    @State private var showIssuedShare = false
    @State private var confirmDelete = false
    @State private var showLocation = false
    @State private var stampVisible = false
    @State private var copied = false
    @State private var success = 0
    @State private var showPhoto = false
    @State private var notifStatus: UNAuthorizationStatus?
    /// Dekodiertes Foto, damit UIImage(data:) nicht bei jedem Neuzeichnen läuft; `source` zeigt, zu welchen Daten es gehört.
    @State private var photo: (source: Data, image: UIImage?)?

    var body: some View {
        Group {
            if let card = store.card(cardID) {
                content(card)
            } else {
                ContentUnavailableView("Gutschein entfernt", systemImage: "trash")
            }
        }
        .pageBackground()
        .readableWidth()
        .sensoryFeedback(.success, trigger: success)
        .task { await refreshNotifStatus() }
        .onChange(of: scenePhase) { _, phase in
            // PIN schon vor dem Snapshot für den App-Umschalter wieder verbergen.
            // Ebenso einen per Code-Schutz aufgedeckten Code: danach wieder verdeckt.
            if phase != .active {
                pinVisible = false
                codeVisible = false
                if codeLock { showPhoto = false }
            } else { Task { await refreshNotifStatus() } }
        }
    }

    private func content(_ card: GiftCard) -> some View {
        let status = card.status(warnDays: warnDays)
        return ScrollView {
            // Gruppen mit 12 pt innen, 24 pt zwischen den Abschnitten.
            VStack(spacing: Layout.section) {
                VStack(spacing: Layout.group) {
                    if !card.isActive && !card.isArchived {
                        archiveBanner(card, status)
                    }
                    summary(card, status)
                    if card.pendingSince != nil && card.isActive {
                        pendingBanner(card)
                    }
                }
                actionGroup(card)
                VStack(spacing: Layout.group) {
                    codeTicket(card)
                    locationRow(card)
                    // Eigene Erinnerungen plant der Store nur für echte, eigene Gutscheine.
                    if card.isActive && !card.isExample && !card.forGifting { reminderRow(card) }
                }
                CardBon(card: card)
                VStack(spacing: Layout.group) {
                    if !card.kind.isValueBased && card.redeemedAt != nil {
                        Button("Doch nicht eingelöst", systemImage: "arrow.uturn.backward") { unmarkRedeemed(card.id) }
                            .buttonStyle(.quiet)
                    }
                    if card.isArchived {
                        Button("Wiederherstellen", systemImage: "tray.and.arrow.up") { store.setArchived(card.id, false) }
                            .buttonStyle(.quiet)
                    }
                    Button("Gutschein entfernen", systemImage: "trash", role: .destructive) { confirmDelete = true }
                        .font(.scaled(15, weight: .bold)).foregroundStyle(Color.bad)
                        .frame(minHeight: Layout.tap)
                }
            }
            .padding(.horizontal, Layout.page).padding(.top, 4).padding(.bottom, Layout.section)
        }
        .scrollIndicators(.hidden)
        // Hauptaktion unten im Daumenbereich statt mitten im Inhalt.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if card.isActive {
                // Online-Codes haben keine Kasse; dieselbe Route zeigt dort den Online-Weg.
                let online = card.merchant.category == .codeOnly
                NavigationLink(value: Route.checkout(card.id)) {
                    Label(card.issuedByMe ? "Einlösen" : online ? "Code einlösen" : "An der Kasse zeigen",
                          systemImage: card.issuedByMe ? "checkmark.circle" : online ? "globe" : card.number.isEmpty ? "photo" : "barcode")
                }
                .buttonStyle(.primary)
                .frame(maxWidth: 700)
                .padding(.horizontal, Layout.page).padding(.top, Layout.group).padding(.bottom, 4)
                .frame(maxWidth: .infinity)
                .background(Color.page.ignoresSafeArea())
            }
        }
        .fullScreenCover(isPresented: $showPhoto) {
            if let image = photo?.image { PhotoViewer(image: image) }
        }
        .task(id: card.photo) { await decodePhoto(card.photo) }
        .toolbar(.hidden, for: .tabBar)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if card.issuedByMe {
                ToolbarItem(placement: .topBarTrailing) {
                    // Selbst ausgegeben: Gutscheinbild erneut teilen (z. B. wenn der Kunde es verloren hat).
                    Button("Gutscheinbild teilen", systemImage: "square.and.arrow.up") { unlockCode(card) { showIssuedShare = true } }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                // Im Formular steht der Code offen: bei Code-Schutz erst entsperren.
                Button("Bearbeiten", systemImage: "pencil") { unlockCode(card) { router.editing = card } }
            }
        }
        .confirmationDialog("Gutschein endgültig entfernen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Entfernen", role: .destructive) {
                dismiss()
                clearLaterNotification(card.id)
                store.delete(card.id)
                router.showUndo("„\(card.name)“ entfernt") { store.undoDelete(card) }
            }
        }
        .unprotectedPinConfirmation(isPresented: $confirmUnprotectedPin) { withAnimation(.snappy) { pinVisible = true } }
        .sheet(isPresented: $showIssuedShare) {
            NavigationStack {
                ScrollView { IssuedVoucherShare(card: card, message: card.greeting).padding(Layout.page) }
                    .pageBackground()
                    .navigationTitle("Gutschein teilen").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { showIssuedShare = false } } }
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
            // Gültigkeit steht im Ticket-Abschnitt, Einlösungen im Verlauf unten.
            BalanceCard(card: card, status: status)
        }
        .overlay {
            if card.redeemedAt != nil || stampVisible {
                // Nur frisch gestempelt fällt der Stempel; beim Öffnen eines alten Gutscheins liegt er schon.
                Stamp(date: card.redeemedAt ?? .now, animated: stampVisible).allowsHitTesting(false)
            }
        }
    }

    /// Neben-Aktionen als Kacheln (Icon in Ladenfarbe) statt Einstellungs-Liste; Hauptaktion bleibt „An der Kasse zeigen“.
    private func actionGroup(_ card: GiftCard) -> some View {
        let hasPin = card.kind == .giftCard && !card.pin.isEmpty
        // Codes und Coupons haben kein Guthaben: kein Link „Guthaben prüfen/ansehen“.
        let link = !card.kind.isValueBased ? nil : card.merchant.balanceURL.flatMap { url in card.merchant.balanceCheck.linkLabel.map { (url, $0) } }
        let tint = (MerchantBrand.forID(card.merchantID) ?? MerchantBrand.fallback(for: card.name)).accent
        var tiles: [AnyView] = []
        if card.isActive {
            if card.kind.isValueBased {
                tiles.append(AnyView(NavigationLink(value: Route.keypad(card.id)) { ActionTile(icon: "minus.circle", title: "Einkauf abziehen", tint: tint) }
                    .buttonStyle(.plain)))
            } else {
                tiles.append(AnyView(Button { stamp(card) } label: { ActionTile(icon: "checkmark.seal", title: "Als eingelöst markieren", tint: tint) }
                    .buttonStyle(.plain).disabled(stampVisible)))
            }
        }
        if hasPin {
            tiles.append(AnyView(Button { Task { await togglePin(card) } } label: {
                ActionTile(icon: pinVisible ? "lock.open" : DeviceSecurity.methodName == "Touch ID" ? "touchid" : "faceid", title: pinVisible ? card.pin : "PIN anzeigen", tint: tint)
                    .privacySensitive()
            }
            .buttonStyle(.plain)))
        }
        if let (url, label) = link {
            tiles.append(AnyView(Link(destination: url) { ActionTile(icon: "arrow.up.right", title: label, tint: tint) }
                .buttonStyle(.plain)))
        }
        // Zwei Spalten; eine übrige Kachel geht über die volle Breite, damit keine Lücke bleibt.
        // Bei sehr großer Schrift eine Spalte, sonst brechen die Titel mitten im Wort.
        let perRow = typeSize.isAccessibilitySize ? 1 : 2
        return VStack(spacing: Layout.group) {
            ForEach(Array(stride(from: 0, to: tiles.count, by: perRow)), id: \.self) { start in
                HStack(spacing: Layout.group) {
                    ForEach(start..<min(start + perRow, tiles.count), id: \.self) { i in tiles[i] }
                }
            }
        }
    }

    /// Code/Coupon als eingelöst stempeln; Doppeltipp stempelt nur einmal.
    private func stamp(_ card: GiftCard) {
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
    }

    /// Nach „Später eintragen“ an der Kasse: Betrag nachtragen oder verwerfen.
    private func pendingBanner(_ card: GiftCard) -> some View {
        // Neutraler Hinweis mit Streifen statt farbiger Fläche; eine Aktion, die zweite leise daneben.
        // Bei großer Schrift die Knöpfe untereinander, damit nichts abgeschnitten wird.
        let buttons = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        return VStack(alignment: .leading, spacing: 8) {
            Label("Betrag offen", systemImage: "clock")
                .font(.scaled(15, weight: .semibold)).foregroundStyle(Color.ink)
                .labelStyle(PendingLabelStyle())
            // Zwei echte Knöpfe mit 44 pt: leise Kontur für „Nicht bezahlt“, gefüllt für „Jetzt eintragen“.
            buttons {
                Button { dismissPending(card) } label: {
                    Text("Nicht bezahlt").font(.scaled(15, weight: .semibold)).foregroundStyle(Color.ink)
                        .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: Layout.tap)
                        .overlay(RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous).strokeBorder(Color.line, lineWidth: 1.5))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Entfernt den Hinweis und die Nachfrage. Rückgängig möglich.")
                NavigationLink(value: Route.keypad(card.id)) {
                    Text("Einkauf abziehen").font(.scaled(15, weight: .semibold)).foregroundStyle(Color.onInk)
                        .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: Layout.tap)
                        .background(Color.ink, in: .rect(cornerRadius: Layout.controlRadius, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, Layout.inset + 4).padding(.trailing, Layout.inset).padding(.vertical, Layout.group)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface, in: .rect(cornerRadius: Layout.buttonRadius, style: .continuous))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: Layout.buttonRadius, bottomLeadingRadius: Layout.buttonRadius)
                .fill(Color.notice).frame(width: 4)
        }
    }

    /// „Nicht bezahlt“: Hinweis sofort weg, mit Rückgängig. Die geplante Nachfrage wird vorher gemerkt
    /// (der Store löscht sie beim Zurücksetzen) und beim Rückgängigmachen wieder eingeplant.
    private func dismissPending(_ card: GiftCard) {
        let id = card.id
        Task {
            let key = "\(id.uuidString)-later"
            let center = UNUserNotificationCenter.current()
            let saved = await center.pendingNotificationRequests().first { $0.identifier == key }
            // Doppeltipp: nur einmal zurücksetzen.
            guard store.card(id)?.pendingSince != nil else { return }
            withAnimation(.smooth) { store.setPending(id, false) }
            clearLaterNotification(id)
            router.showUndo("„Betrag offen“ entfernt") {
                withAnimation(.smooth) { store.setPending(id, true) }
                if let saved { Task { try? await center.add(saved) } }
            }
        }
    }

    /// Foto einmal im Hintergrund dekodieren, nicht bei jedem Neuzeichnen.
    private func decodePhoto(_ data: Data?) async {
        guard let data else { photo = nil; return }
        if photo?.source == data { return }
        let image = await Task.detached(priority: .userInitiated) { UIImage(data: data)?.preparingForDisplay() ?? UIImage(data: data) }.value
        guard !Task.isCancelled else { return }
        photo = (data, image)
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
                router.showUndo("„\(card.name)“ archiviert") { store.setArchived(card.id, false) }
                dismiss()
            }
            .font(.scaled(15, weight: .semibold))
            .buttonStyle(.glass)
        }
        .foregroundStyle(Color.ink)
        .padding(14)
        .flatSurface()
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
            .tint(Color.toggleOn)
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
        .flatSurface()
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
                Image(systemName: card.location.symbol).font(.scaled(17, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44)
                    .background(Color.fill, in: .rect(cornerRadius: Layout.controlRadius, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Aufbewahrt: \(card.location.label)").font(.scaled(16, weight: .semibold))
                    Text(card.locationNote.isEmpty ? "Notiz hinzufügen" : card.locationNote)
                        .font(.scaled(13)).foregroundStyle(Color.muted).lineLimit(2)
                }
                Spacer()
                Text("Ändern").font(.scaled(15, weight: .bold))
            }
            .foregroundStyle(Color.ink).padding(Layout.inset).flatSurface()
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
            if card.photo != nil && photo?.source != card.photo {
                // Wird gerade dekodiert.
                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            } else if photo?.image != nil, codeLock && !codeVisible {
                // Auf dem Foto steht der Code: bei Code-Schutz ebenfalls verdeckt.
                Button { unlockCode(card) } label: {
                    BarcodeView(number: card.number, format: .text, height: 120, concealed: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Geschützt. Tippen und entsperren")
            } else if let image = photo?.image {
                Button { showPhoto = true } label: {
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 260)
                        .clipShape(.rect(cornerRadius: Layout.buttonRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Foto des Gutscheins groß anzeigen")
                Text("An der Kasse das Foto zeigen oder das Original mitnehmen.").font(.scaled(13)).foregroundStyle(Color.ink2)
            } else {
                Text("Kein Foto und kein Code gespeichert. Tipp oben auf den Stift, um eins hinzuzufügen.")
                    .font(.scaled(15)).foregroundStyle(Color.ink2)
            }
        }
        .foregroundStyle(Color.ink)
        .padding(Layout.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .flatSurface()
    }

    /// Code als Text zum Kopieren; den Barcode gibt es nur an der Kasse, damit er nicht doppelt erscheint.
    private func barcodeTicket(_ card: GiftCard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                let hidden = codeLock && !codeVisible
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.kind == .discountCode ? "Rabattcode" : "Code").font(.scaled(13)).foregroundStyle(Color.muted)
                    // Geschützt: gar keine Ziffern, auch nicht die letzten vier (Kinder, Mitbenutzer).
                    Text(hidden ? "•••• ••••" : ScanResultView.codeDisplay(card.number, format: card.format)).font(.scaled(17, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.ink).textSelection(.enabled).lineLimit(2).minimumScaleFactor(0.7)
                        .accessibilityLabel(hidden ? "Code verdeckt" : ScanResultView.codeDisplay(card.number, format: card.format))
                }
                Spacer(minLength: 8)
                if hidden {
                    // „Codes erst nach Face ID zeigen“: erst entsperren, dann kopieren.
                    Button { unlockCode(card) } label: {
                        Label("Entsperren", systemImage: "lock.open").font(.scaled(15, weight: .semibold))
                            .padding(.horizontal, 12)
                            .frame(minWidth: Layout.tap, minHeight: Layout.tap)
                            .background(Color.fill, in: .capsule)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.ink)
                } else {
                Button {
                    // Nur auf diesem Gerät und nach 10 Minuten wieder weg.
                    UIPasteboard.general.setItems([[UTType.plainText.identifier: card.number]],
                                                  options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(Clipboard.lifetime)])
                    copied = true
                    success += 1
                    Task {
                        try? await Task.sleep(for: .seconds(4))
                        withAnimation { copied = false }
                    }
                } label: {
                    Label(copied ? "Kopiert" : "Kopieren", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.scaled(15, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                        .padding(.horizontal, 12)
                        .frame(minWidth: Layout.tap, minHeight: Layout.tap)
                        .background(Color.fill, in: .capsule)
                        .contentShape(.capsule)
                }
                .accessibilityHint("Nur auf diesem \(Device.name), 10 Minuten lang. Nie am Telefon oder per Nachricht weitergeben.")
                .buttonStyle(.plain)
                .foregroundStyle(Color.ink)
                }
            }
            if let m = card.minOrder {
                Label("Gilt ab \(m.euro) Einkauf", systemImage: "cart")
                    .font(.scaled(15, weight: .medium)).foregroundStyle(Color.ink2)
            }
            if copied {
                // Beim Kopieren an den häufigsten Betrug erinnern.
                Label("Kopiert. Nur im Shop einfügen, nie am Telefon oder per Nachricht weitergeben.", systemImage: "exclamationmark.shield")
                    .font(.scaled(13)).foregroundStyle(Color.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
            if card.photo != nil {
                Button("Original-Foto ansehen", systemImage: "photo") { unlockCode(card) { showPhoto = true } }
                    .frame(minHeight: Layout.tap)
                    .font(.scaled(15, weight: .medium)).foregroundStyle(Color.ink2)
                    .disabled(photo?.image == nil)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .flatSurface()
    }

    /// Stempel zurücknehmen (Store entfernt Einlösedatum und Verlaufseintrag).
    private func unmarkRedeemed(_ id: UUID) {
        withAnimation(.smooth) {
            store.undoMarkRedeemed(id)
            stampVisible = false
        }
    }

    /// „Codes erst nach Face ID zeigen“: Code und Foto (auf dem der Code steht) erst nach Face ID oder Code.
    private func unlockCode(_ card: GiftCard, then action: @escaping () -> Void = {}) {
        guard codeLock && !codeVisible else { action(); return }
        Task {
            if await DeviceSecurity.revealCode(of: card.name, spoken: card.number) {
                withAnimation(.snappy) { codeVisible = true }
                action()
            }
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
        guard DeviceSecurity.canAuthenticate else {
            // Kein iPhone-Code: nicht still zeigen, sondern sagen, dass der Schutz so nicht wirkt.
            confirmUnprotectedPin = true
            return
        }
        if await DeviceSecurity.guardSensitive("PIN von \(card.name) anzeigen") {
            withAnimation(.snappy) { pinVisible = true }
            AccessibilityNotification.Announcement("PIN: \(card.pin)").post()
        }
    }
}

// MARK: - Bausteine

/// Roter Stempel „Eingelöst“, fällt mit Wucht aufs Papier.
struct Stamp: View {
    let date: Date
    @State private var landed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `animated: false` für schon eingelöste Gutscheine: Stempel liegt still, ohne Fall und ohne Haptik.
    init(date: Date, animated: Bool = true) {
        self.date = date
        _landed = State(initialValue: !animated)
    }

    var body: some View {
        VStack(spacing: 2) {
            Text("EINGELÖST").font(.scaled(28, weight: .black, design: .rounded)).kerning(3)
            Text(date.dayMonthYear).font(.scaled(13, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(Color.bad.opacity(0.85))
        .padding(.horizontal, 18).padding(.vertical, 10)
        .overlay(RoundedRectangle(cornerRadius: Layout.controlRadius).stroke(Color.bad.opacity(0.85), lineWidth: 4))
        .rotationEffect(.degrees(landed || reduceMotion ? -14 : -30))
        .scaleEffect(landed || reduceMotion ? 1 : 2.4)
        .opacity(landed || reduceMotion ? 1 : 0)
        .onAppear {
            guard !landed else { return }
            if reduceMotion { landed = true } else { withAnimation(.spring(duration: 0.45, bounce: 0.5)) { landed = true } }
        }
        .accessibilityElement(children: .combine)
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
            Text("Wo liegt der Gutschein?").font(.scaled(22, weight: .heavy)).padding(.top, 24)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(StorageLocation.allCases) { loc in
                    Button { withAnimation(.snappy) { location = loc } } label: {
                        VStack(spacing: 8) {
                            Image(systemName: loc.symbol).font(.scaled(22, weight: .semibold))
                                .symbolEffect(.bounce, value: location == loc)
                            Text(loc.label).font(.scaled(13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .foregroundStyle(location == loc ? Color.onInk : Color.ink)
                        .frame(maxWidth: .infinity, minHeight: 84)
                        .background(location == loc ? Color.ink : Color.fill, in: .rect(cornerRadius: Layout.buttonRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .sensoryFeedback(.selection, trigger: location)
            LabeledField(label: "Notiz", placeholder: "z.\u{00A0}B. oberste Schublade im Flur", text: $note)
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
                    Text("Einlöse-Verlauf").font(.scaled(20, weight: .heavy)).accessibilityAddTraits(.isHeader)
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
                Text(title).font(.scaled(15, weight: bold ? .heavy : .semibold, design: .monospaced))
                if !sub.isEmpty {
                    Text(sub).font(.scaled(12, design: .monospaced)).foregroundStyle(Color.muted)
                }
            }
            Spacer()
            Text(amount).font(.scaled(15, weight: bold ? .heavy : .semibold, design: .monospaced))
        }
    }
}

/// Uhr in Hinweisfarbe vor dem Titel; bei sehr großer Schrift nur der Text.
private struct PendingLabelStyle: LabelStyle {
    @Environment(\.dynamicTypeSize) private var typeSize

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            if !typeSize.isAccessibilitySize {
                configuration.icon.foregroundStyle(Color.notice)
            }
            configuration.title
        }
    }
}

/// Kachel für Neben-Aktionen: 72 pt hoch, Icon in Ladenfarbe, kein Pfeil.
private struct ActionTile: View {
    let icon: String
    let title: String
    let tint: Color
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Ladenfarbe nur im Hellen; im Dunkeln wären dunkle Ladenfarben auf der Fläche zu schwach.
            Image(systemName: icon).font(.scaled(20, weight: .semibold)).foregroundStyle(scheme == .dark ? Color.ink2 : tint)
                .accessibilityHidden(true)
            Text(title).font(.scaled(15, weight: .semibold)).foregroundStyle(Color.ink)
                .lineLimit(2).minimumScaleFactor(0.8).multilineTextAlignment(.leading)
        }
        .padding(Layout.inset)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .background(Color.surface, in: .rect(cornerRadius: Layout.buttonRadius, style: .continuous))
        .contentShape(.rect)
    }
}
