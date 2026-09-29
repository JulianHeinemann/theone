import SwiftUI
import PhotosUI
import LocalAuthentication
import UserNotifications
import RestwertKit

/// Formular zum Hinzufügen oder Bearbeiten eines Gutscheins, vorbefüllt aus einem Scan.
struct CardFormView: View {
    var outcome: ScanOutcome?
    var editing: GiftCard?
    var onSaved: (GiftCard) -> Void

    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var kind: VoucherKind = .giftCard
    @State private var merchantID = ""
    @State private var customName = ""
    @State private var number = ""
    @State private var format: CodeFormat = .code128
    @State private var pin = ""
    @State private var valueText = ""
    @State private var balanceText = ""
    @State private var percentText = ""
    /// Mindestbestellwert („ab 50 € Einkauf“), optional.
    @State private var minOrderText = ""
    /// Angebot eines Coupons ohne Betrag („2 für 1“, „Gratis Kaffee“).
    @State private var benefitText = ""
    @State private var received = Date.now
    @State private var expires = GiftCard.legalExpiry(from: .now)
    @State private var location: StorageLocation = .drawer
    @State private var locationNote = ""
    @State private var owner = ""
    @State private var forGifting = false
    @State private var photo: Data?
    /// Dekodiertes Foto, nur bei Änderung neu erzeugt (nicht bei jedem Tastendruck).
    @State private var photoImage: UIImage?
    /// Foto der Rückseite (Nummer, PIN, Rubbelfeld), optional.
    @State private var photoBack: Data?
    @State private var photoBackImage: UIImage?
    @State private var backPhotoItem: PhotosPickerItem?
    @State private var showBackCamera = false
    @State private var showBackPhoto = false
    @State private var errors: [String] = []
    /// Format kommt aus Scan, Nutzerwahl oder gespeicherter Karte und wird nicht mehr automatisch gesetzt.
    @State private var formatLocked = false
    /// „Gültig bis“ ist nur der gesetzliche Vorschlag und darf „Erhalten am“ folgen.
    @State private var expiresIsSuggestion = true
    /// „Gültig bis“ aus einer Laufzeit berechnet („3 Jahre gültig“): fest, aber als berechnet markiert.
    @State private var expiresFromDuration = false
    /// Formular kam aus Scan oder Import: dann ist ein fehlendes Datum ein Befund, kein Normalfall.
    @State private var fromScan = false
    /// Beim Bearbeiten war schon eine PIN gespeichert: nur die bleibt verdeckt.
    @State private var hadStoredPin = false
    @State private var loaded = false
    /// Stand beim Öffnen: Abweichung heißt ungespeicherte Änderungen.
    @State private var initial: Snapshot?
    @State private var confirmDiscard = false
    @State private var saving = false
    @State private var savedCard: GiftCard?
    @State private var askNotify = false
    @State private var shake = 0
    @State private var showMore = false
    @State private var pinRevealed = false
    @State private var confirmUnprotectedPin = false
    /// Barcode im Scan nicht gelesen: Barcode-Art hervorheben, bis der Nutzer sie wählt.
    @State private var formatNeedsChoice = false
    /// Gelesene Laufzeit („3 Jahre gültig“): bei geändertem „Erhalten am“ neu rechnen.
    @State private var validity: Validity?
    @State private var shopText = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showPhoto = false
    @AppStorage("pinLock") private var pinLock = true
    /// Nach dem ersten Speichern einmal mit Erklärung nach Mitteilungen fragen, nicht bei jedem Speichern.
    @AppStorage("askedNotifyAfterSave") private var askedNotify = false
    /// Von Hand eingegeben: Dublette oder Betrugsmuster einmal nachfragen (der Scan fragt selbst).
    @State private var riskMessage: String?
    @State private var riskConfirmed = false
    /// Gescannte Barcode-Art, die Restwert als Code 128 zeigt (Code 93, Codabar, DataBar): an der Kasse nennen.
    @State private var convertedFrom: String?

    /// „Speichern“ direkt aus dem Scan-Ergebnis: vorbefüllen, prüfen und ohne weiteren Tipp speichern.
    /// Findet die Prüfung doch etwas, bleibt das Formular mit den Hinweisen offen.
    var autoSave = false

    init(outcome: ScanOutcome? = nil, editing: GiftCard? = nil, autoSave: Bool = false, onSaved: @escaping (GiftCard) -> Void) {
        self.outcome = outcome
        self.editing = editing
        self.autoSave = autoSave
        self.onSaved = onSaved
    }

    private struct Snapshot: Equatable {
        var kind: VoucherKind, shop: String, number: String, pin: String
        var value: String, balance: String, percent: String
        var received: Date, expires: Date, location: StorageLocation, locationNote: String
        var owner: String, forGifting: Bool, photo: Data?
        var benefit: String, photoBack: Data?
    }

    private var snapshot: Snapshot {
        Snapshot(kind: kind, shop: shopText.trimmingCharacters(in: .whitespaces), number: Self.normalizedCode(number), pin: pin,
                 value: valueText, balance: balanceText, percent: percentText, received: received, expires: expires,
                 location: location, locationNote: locationNote, owner: owner, forGifting: forGifting, photo: photo,
                 benefit: benefitText, photoBack: photoBack)
    }

    private var isDirty: Bool { initial.map { $0 != snapshot } ?? false }

    private func animate(_ animation: Animation = .snappy, _ change: () -> Void) {
        withAnimation(reduceMotion ? nil : animation, change)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Layout.group) {
                photoSlot
                fields
                if !errors.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(errors, id: \.self) { Label($0, systemImage: "exclamationmark.circle.fill") }
                    }
                    .font(.scaled(15, weight: .semibold)).foregroundStyle(Color.bad)
                    .padding(Layout.inset).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.badSoft, in: .rect(cornerRadius: Layout.buttonRadius, style: .continuous))
                    .modifier(Shake(animatableData: CGFloat(shake)))
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                Button(editing != nil ? "Änderungen speichern" : "Speichern", action: save)
                    .buttonStyle(.primary)
                    .disabled(saving)
            }
            .padding(.horizontal, Layout.page).padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
        .pageBackground()
        .readableWidth()
        .navigationTitle(editing != nil ? "Bearbeiten" : "Gutschein hinzufügen")
        .navigationBarTitleDisplayMode(.inline)
        // Ungespeicherte Änderungen: Wegwischen und Zurück-Wischen sperren, stattdessen nachfragen.
        .interactiveDismissDisabled(isDirty)
        .navigationBarBackButtonHidden(editing == nil && isDirty)
        .toolbar {
            if editing != nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", systemImage: "xmark") { leave() }
                }
            } else if isDirty {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Zurück", systemImage: "chevron.left") { leave() }
                }
            }
        }
        .confirmationDialog("Änderungen verwerfen?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Verwerfen", role: .destructive) { dismiss() }
            Button("Weiter bearbeiten", role: .cancel) {}
        } message: {
            Text("Was du eingegeben hast, ist noch nicht gespeichert.")
        }
        .confirmationDialog("Trotzdem speichern?", isPresented: Binding(get: { riskMessage != nil }, set: { if !$0 { riskMessage = nil } }),
                            titleVisibility: .visible) {
            Button("Trotzdem speichern") { riskConfirmed = true; riskMessage = nil; save() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text(riskMessage ?? "")
        }
        .alert("An den Ablauf erinnern?", isPresented: $askNotify, presenting: savedCard) { card in
            Button("Erinnern") {
                Task {
                    await store.requestNotifications()
                    onSaved(card)
                }
            }
            Button("Nicht jetzt", role: .cancel) { onSaved(card) }
        } message: { _ in
            Text("Restwert schickt dir eine Mitteilung, bevor ein Gutschein abläuft. Alles wird nur auf deinem \(Device.name) geplant. In den Einstellungen kannst du das jederzeit ändern.")
        }
        .sensoryFeedback(.error, trigger: shake)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let editing { load(editing); showMore = true } else if let outcome { apply(outcome) }
            if shopText.isEmpty, let m = Merchant.byID[merchantID] { shopText = merchantID == "other" ? customName : m.name }
            initial = snapshot
            if autoSave && validate().isEmpty { save() }
        }
        .onChange(of: shopText) { _, text in matchShop(text) }
        .onChange(of: number) { _, new in
            // Ziffern in Vierergruppen anzeigen; gespeichert wird ohne Leerzeichen.
            let g = new.grouped
            if g != new { number = g }
        }
        .onChange(of: photo, initial: true) { _, data in photoImage = data.flatMap(UIImage.init(data:)) }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    photo = image.thumbnailJPEG()
                }
                photoItem = nil
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker { image in photo = image.thumbnailJPEG() }.ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showPhoto) {
            if let photoImage { PhotoViewer(image: photoImage) }
        }
        .onChange(of: photoBack, initial: true) { _, data in photoBackImage = data.flatMap(UIImage.init(data:)) }
        .onChange(of: backPhotoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    photoBack = image.thumbnailJPEG()
                }
                backPhotoItem = nil
            }
        }
        .sheet(isPresented: $showBackCamera) {
            CameraPicker { image in photoBack = image.thumbnailJPEG() }.ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showBackPhoto) {
            if let photoBackImage { PhotoViewer(image: photoBackImage) }
        }
        .onChange(of: received) { _, new in
            if expiresIsSuggestion {
                expires = GiftCard.legalExpiry(from: new)
            } else if expiresFromDuration, let validity, let e = validity.expiry(from: new) {
                expires = e
            }
        }
        .unprotectedPinConfirmation(isPresented: $confirmUnprotectedPin) { pinRevealed = true }
        .onChange(of: merchantID) { _, _ in
            if !formatLocked { format = autoFormat }
        }
    }

    private func leave() {
        if isDirty { confirmDiscard = true } else { dismiss() }
    }

    /// Format ohne Scan oder Nutzerwahl: Codes und reine Online-Händler als Text, sonst das Händlerformat.
    private var autoFormat: CodeFormat { .automatic(kind: kind, merchantID: merchantID) }

    // MARK: Felder

    /// Vier gleich breite Segmente; „Andere“ zeigt darunter die seltenen Arten.
    private var kindPicker: some View {
        let others: [VoucherKind] = [.coupon, .custom]
        return VStack(alignment: .leading, spacing: 8) {
            Text("Art").font(.scaled(12, weight: .semibold)).foregroundStyle(Color.muted)
                .accessibilityHidden(true)
            Picker("Art", selection: Binding(
                get: { others.contains(kind) ? .coupon : kind },
                set: { setKind($0 == .coupon && others.contains(kind) ? kind : $0) })) {
                Text("Karte").tag(VoucherKind.giftCard)
                Text("Gutschein").tag(VoucherKind.valueVoucher)
                Text("Rabattcode").tag(VoucherKind.discountCode)
                Text("Andere").tag(VoucherKind.coupon)
            }
            .pickerStyle(.segmented)
            if others.contains(kind) {
                Picker("Welche Art?", selection: Binding(get: { kind }, set: { setKind($0) })) {
                    ForEach(others) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.top, 8)
        .sensoryFeedback(.selection, trigger: kind)
    }

    private func setKind(_ k: VoucherKind) {
        animate {
            kind = k
            if !formatLocked { format = autoFormat }
        }
    }

    /// Foto zuerst: reicht auch allein, z. B. für Papiergutscheine ohne Barcode.
    /// Darunter die Rückseite, sobald es ein Foto gibt (Nummer, PIN oder Rubbelfeld stehen oft hinten).
    private var photoSlot: some View {
        VStack(alignment: .leading, spacing: Layout.group) {
            frontPhotoRow
            if photoImage != nil || photoBackImage != nil {
                Divider()
                backPhotoRow
            }
        }
        .padding(Layout.inset)
        .background(Color.surface, in: .rect(cornerRadius: Layout.cardRadius, style: .continuous)).modifier(ContrastEdge())
        .padding(.top, 8)
    }

    /// Rückseite: kleines Vorschaubild mit Ersetzen/Entfernen oder die Knöpfe zum Aufnehmen.
    private var backPhotoRow: some View {
        HStack(spacing: 14) {
            if let photoBackImage {
                Button { showBackPhoto = true } label: {
                    Image(uiImage: photoBackImage).resizable().scaledToFill()
                        .frame(width: 84, height: 84).clipShape(.rect(cornerRadius: Layout.buttonRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Foto der Rückseite ansehen")
                VStack(alignment: .leading, spacing: 8) {
                    Text("Rückseite").font(.scaled(16, weight: .semibold))
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { backPhotoActionsFilled }
                        VStack(alignment: .leading, spacing: 8) { backPhotoActionsFilled }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Rückseite (optional)").font(.scaled(16, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text("Stehen Nummer, PIN oder Rubbelfeld hinten? Dann auch die Rückseite fotografieren.")
                        .font(.scaled(13)).foregroundStyle(Color.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { backPhotoActionsEmpty }
                        VStack(alignment: .leading, spacing: 8) { backPhotoActionsEmpty }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var backPhotoActionsEmpty: some View {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            Button { showBackCamera = true } label: { Label("Foto machen", systemImage: "camera") }
                .buttonStyle(SoftButtonStyle())
                .accessibilityLabel("Rückseite fotografieren")
        }
        PhotosPicker(selection: $backPhotoItem, matching: .images) { Label("Aus Fotos", systemImage: "photo") }
            .buttonStyle(SoftButtonStyle())
            .accessibilityLabel("Rückseite aus Fotos wählen")
    }

    @ViewBuilder private var backPhotoActionsFilled: some View {
        PhotosPicker(selection: $backPhotoItem, matching: .images) { Text("Ersetzen") }
            .buttonStyle(SoftButtonStyle())
            .accessibilityLabel("Foto der Rückseite ersetzen")
        Button("Entfernen", role: .destructive) { photoBack = nil }
            .buttonStyle(SoftButtonStyle(foreground: .bad))
            .accessibilityLabel("Foto der Rückseite entfernen")
    }

    private var frontPhotoRow: some View {
        HStack(spacing: 14) {
            if let photoImage {
                Button { showPhoto = true } label: {
                    Image(uiImage: photoImage).resizable().scaledToFill()
                        .frame(width: 84, height: 84).clipShape(.rect(cornerRadius: Layout.buttonRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Foto ansehen")
                VStack(alignment: .leading, spacing: 8) {
                    Text("Foto gespeichert").font(.scaled(16, weight: .semibold))
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { photoActionsFilled }
                        VStack(alignment: .leading, spacing: 8) { photoActionsFilled }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Foto vom Gutschein").font(.scaled(16, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text("Reicht auch allein, z.\u{00A0}B. für Papierzettel ohne Barcode. An der Kasse zeigst du dann das Foto.")
                        .font(.scaled(13)).foregroundStyle(Color.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { photoActionsEmpty }
                        VStack(alignment: .leading, spacing: 8) { photoActionsEmpty }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var photoActionsEmpty: some View {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            Button { showCamera = true } label: { Label("Foto machen", systemImage: "camera") }
                .buttonStyle(SoftButtonStyle())
        }
        PhotosPicker(selection: $photoItem, matching: .images) { Label("Aus Fotos", systemImage: "photo") }
            .buttonStyle(SoftButtonStyle())
    }

    @ViewBuilder private var photoActionsFilled: some View {
        PhotosPicker(selection: $photoItem, matching: .images) { Text("Ersetzen") }
            .buttonStyle(SoftButtonStyle())
            .accessibilityLabel("Foto ersetzen")
        Button("Entfernen", role: .destructive) { photo = nil }
            .buttonStyle(SoftButtonStyle(foreground: .bad))
            .accessibilityLabel("Foto entfernen")
    }

    /// Freitext mit Vorschlägen: bekannte Händler werden erkannt, alles andere ist ein eigener Laden.
    private var shopSuggestions: [Merchant] {
        let t = shopText.trimmingCharacters(in: .whitespaces)
        guard t.count >= 1, Merchant.byID[merchantID]?.name != t else { return [] }
        return Merchant.all.filter { $0.name.localizedCaseInsensitiveContains(t) }.prefix(4).map { $0 }
    }

    private func matchShop(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { merchantID = ""; customName = ""; return }
        if let m = Merchant.all.first(where: { $0.name.compare(t, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            merchantID = m.id
            customName = ""
        } else {
            merchantID = "other"
            customName = t
        }
    }

    /// Erklärung unter „Laden“: sichtbar statt nur im Platzhalter.
    private var shopNote: String? {
        if merchantID == "other", !customName.isEmpty {
            return "Eigener Laden. Er erscheint unter „Läden“ bei „Deine Läden“."
        }
        if merchantID.isEmpty { return "Wähl einen Vorschlag oder schreib den Namen deines Ladens." }
        return nil
    }

    /// Namen, die schon bei anderen Gutscheinen unter „Für wen?“ stehen.
    private var knownOwners: [String] {
        Array(Set(store.cards.map { $0.owner.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }))
            .sorted { $0.localizedCompare($1) == .orderedAscending }
            .prefix(5).map { $0 }
    }

    private var fields: some View {
        VStack(spacing: 2) {
            FormField(label: "Laden", note: shopNote, prompt: "z.\u{00A0}B. dm oder Café am Markt", text: $shopText)
            if !shopSuggestions.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(shopSuggestions) { m in
                            Button { shopText = m.name } label: {
                                HStack(spacing: 6) {
                                    MerchantMark(merchantID: m.id, name: m.name, size: 22)
                                    Text(m.name).font(.scaled(15, weight: .medium)).foregroundStyle(Color.ink)
                                }
                                .padding(.horizontal, Layout.group).frame(minHeight: Layout.tap)
                                .background(Color.fill, in: .capsule)
                                .contentShape(.capsule)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(m.name)
                            .accessibilityHint("Als Laden übernehmen")
                        }
                    }
                    .padding(.vertical, 6)
                }
                .scrollIndicators(.hidden)
            }
            if let m = Merchant.byID[merchantID], merchantID != "other" {
                merchantInfo(m).transition(.opacity)
            }
            if kind.isValueBased {
                FormField(label: "Guthaben in €", prompt: "z.\u{00A0}B. 25,00", text: $valueText, keyboard: .decimalPad)
            } else {
                let pair = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 2)) : AnyLayout(HStackLayout(spacing: 16))
                pair {
                    FormField(label: "Rabatt in %", prompt: "z.\u{00A0}B. 15", text: $percentText, keyboard: .decimalPad)
                    FormField(label: "oder Wert in €", prompt: "z.\u{00A0}B. 5,00", text: $valueText, keyboard: .decimalPad)
                }
                FormField(label: "Angebot", note: "Ohne Rabatt oder Wert, z.\u{00A0}B. „2 für 1“ oder „Gratis Kaffee“.",
                          prompt: "z.\u{00A0}B. 2 für 1", text: $benefitText)
            }
            if !kind.isValueBased || !minOrderText.isEmpty {
                FormField(label: "Mindestbestellwert in € (optional)", note: "Gilt der Code erst ab einem Einkaufswert? Dann hier eintragen.",
                          prompt: "z.\u{00A0}B. 50", text: $minOrderText, keyboard: .decimalPad)
            }
            dateBox(expiresIsSuggestion ? "Gültig bis · geschätzt" : expiresFromDuration ? "Gültig bis · berechnet" : "Gültig bis",
                    Binding(get: { expires }, set: { expires = $0; expiresIsSuggestion = false; expiresFromDuration = false; validity = nil }))
            if expiresIsSuggestion { estimateHint }
            FormField(label: kind == .discountCode ? "Rabattcode" : "Code",
                      note: kind == .discountCode ? nil : "Falls vorhanden. Beim Scannen wird er automatisch ausgefüllt.",
                      prompt: kind == .discountCode ? "z.\u{00A0}B. SOMMER15" : "z.\u{00A0}B. 6300 9812 7456 1234",
                      text: $number, code: true)
            // Barcode im Scan nicht gelesen: Auswahl gleich unter dem Code, nicht versteckt unter „Mehr“.
            if formatNeedsChoice && !number.isEmpty { formatPicker }
            ownerSection
            moreButton
            if showMore {
                kindPicker.padding(.bottom, 6)
                if kind.isValueBased {
                    FormField(label: "Guthaben jetzt", note: "Nur ausfüllen, wenn schon etwas abgezogen wurde.",
                              prompt: "z.\u{00A0}B. 12,40", text: $balanceText, keyboard: .decimalPad)
                }
                if kind == .giftCard { pinField }
                if !formatNeedsChoice { formatPicker }
                dateBox("Erhalten am", $received)
                LabeledBox(label: "Aufbewahrungsort") {
                    Picker("Aufbewahrungsort", selection: $location) {
                        ForEach(StorageLocation.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                    }
                    .labelsHidden().tint(Color.ink)
                }
                FormField(label: "Notiz zum Ort (optional)", prompt: "z.\u{00A0}B. rotes Portemonnaie", text: $locationNote)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
        .background(Color.surface, in: .rect(cornerRadius: Layout.cardRadius, style: .continuous)).modifier(ContrastEdge())
        .animation(reduceMotion ? nil : .snappy, value: kind)
        .animation(reduceMotion ? nil : .snappy, value: merchantID)
    }

    /// Kurz: wie der Laden digitale Karten nimmt, dazu der Tipp. Stadt- und Wunschgutschein bekommen eine Anleitung.
    @ViewBuilder
    private func merchantInfo(_ m: Merchant) -> some View {
        if let howTo = m.redeemHowTo {
            VStack(alignment: .leading, spacing: 4) {
                Text("So löst du ihn ein").font(.scaled(15, weight: .semibold)).foregroundStyle(Color.ink)
                Text(howTo).font(.scaled(13)).foregroundStyle(Color.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, Layout.inset + 4).padding(.trailing, Layout.inset).padding(.vertical, Layout.group)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.fill, in: .rect(cornerRadius: Layout.buttonRadius, style: .continuous))
            .overlay(alignment: .leading) {
                UnevenRoundedRectangle(topLeadingRadius: Layout.buttonRadius, bottomLeadingRadius: Layout.buttonRadius)
                    .fill(Color.ink2).frame(width: 4)
            }
            .accessibilityElement(children: .combine)
            .padding(.vertical, 6)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Label(m.category.label, systemImage: m.category.symbol)
                    .font(.scaled(13, weight: .semibold)).foregroundStyle(m.category.tint)
                Text(m.tip).font(.scaled(13)).foregroundStyle(Color.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4).padding(.vertical, 6)
            .accessibilityElement(children: .combine)
        }
    }

    /// „Für wen?“ und „Zum Verschenken“ gehören sichtbar ins Formular, nicht unter „Mehr“.
    private var ownerSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            FormField(label: "Für wen?", note: "Leer lassen, wenn der Gutschein für dich ist.",
                      prompt: "z.\u{00A0}B. Mia oder Oma", text: $owner)
            let names = knownOwners
            if !names.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(names, id: \.self) { name in
                            FilterChip(title: name, on: owner == name) { owner = owner == name ? "" : name }
                                .accessibilityHint("Als Person übernehmen")
                        }
                    }
                    .padding(.vertical, 6)
                }
                .scrollIndicators(.hidden)
            }
            Toggle(isOn: $forGifting) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Zum Verschenken").font(.scaled(16, weight: .semibold))
                    Text("Zählt nicht zu deinem Guthaben").font(.scaled(13)).foregroundStyle(Color.ink2)
                }
            }
            .tint(Color.toggleOn)
            .padding(.horizontal, 4).padding(.vertical, 10)
        }
    }

    private var moreButton: some View {
        Button {
            animate { showMore.toggle() }
        } label: {
            HStack {
                Text(showMore ? "Weniger" : "Mehr: Art, PIN, schon benutzt, Ort")
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "chevron.down").rotationEffect(.degrees(showMore ? 180 : 0))
                    .accessibilityHidden(true)
            }
            .font(.scaled(15, weight: .semibold)).foregroundStyle(Color.ink)
            .padding(.horizontal, 4).padding(.vertical, 10)
            .frame(minHeight: Layout.tap)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showMore ? "Weniger Felder" : "Mehr Felder: Art, PIN, schon benutzt, Ort")
        .accessibilityValue(showMore ? "aufgeklappt" : "zugeklappt")
    }

    /// Gespeicherte PIN verdeckt, wie im Detail: Aufdecken nur nach Face ID, wenn die Einstellung an ist.
    /// Eine neue PIN lässt sich immer eintippen, auch ins verdeckte Feld (ersetzt die alte).
    private var pinField: some View {
        LabeledBox(label: "PIN (falls vorhanden)") {
            HStack {
                let prompt = Text("z.\u{00A0}B. 1234").foregroundStyle(Color.muted)
                Group {
                    if pinRevealed || !hadStoredPin {
                        TextField("PIN", text: $pin, prompt: prompt)
                    } else {
                        SecureField("PIN", text: $pin, prompt: prompt)
                    }
                }
                .keyboardType(.numberPad)
                .font(.scaled(16, weight: .semibold, design: .monospaced))
                .frame(minHeight: Layout.tap)
                if hadStoredPin {
                    Button(pinRevealed ? "PIN verbergen" : "PIN zeigen", systemImage: pinRevealed ? "eye.slash" : "eye") {
                        Task { await revealPin() }
                    }
                    .labelStyle(.iconOnly).foregroundStyle(Color.ink2)
                    .frame(minWidth: Layout.tap, minHeight: Layout.tap)
                    .contentShape(.rect)
                }
            }
        }
    }

    private func revealPin() async {
        if pinRevealed { pinRevealed = false; return }
        guard pinLock else { pinRevealed = true; return }
        let context = LAContext()
        guard DeviceSecurity.canAuthenticate else { confirmUnprotectedPin = true; return }
        _ = context
        pinRevealed = await DeviceSecurity.guardSensitive("PIN zeigen")
    }

    private var formatPicker: some View {
        LabeledBox(label: formatNeedsChoice ? "Barcode-Art: nicht gelesen – bitte wählen, wie auf dem Gutschein" : "Barcode-Art (wird meist automatisch erkannt)") {
            // Nicht gelesen: nichts vorauswählen, sonst ließe sich die schon gewählte Art nicht bestätigen.
            Picker("Barcode-Art", selection: Binding<CodeFormat?>(get: { formatNeedsChoice ? nil : format },
                                                                set: { if let f = $0 { format = f; formatLocked = true; formatNeedsChoice = false } })) {
                if formatNeedsChoice { Text("Bitte wählen").tag(CodeFormat?.none) }
                ForEach(CodeFormat.allCases) { Text(ScanResultView.friendly($0)).tag(Optional($0)) }
            }
            .labelsHidden().tint(Color.ink)
        }
        .overlay {
            if formatNeedsChoice {
                RoundedRectangle(cornerRadius: Layout.buttonRadius, style: .continuous).strokeBorder(Color.soon, lineWidth: 1.5)
            }
        }
    }

    /// Hinweis, dass „Gültig bis“ nur die gesetzliche Frist ist. Nach einem Scan deutlich, sonst leise.
    @ViewBuilder
    private var estimateHint: some View {
        if fromScan {
            VStack(alignment: .leading, spacing: 4) {
                Text("Kein Ablaufdatum gefunden").font(.scaled(15, weight: .semibold)).foregroundStyle(Color.ink)
                Text("Vorausgefüllt ist die gesetzliche Frist: \(expires.dayMonthYear), drei Jahre ab Ende des Kaufjahres. Steht auf dem Gutschein ein anderes Datum, trag es oben ein.")
                    .font(.scaled(13)).foregroundStyle(Color.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, Layout.inset + 4).padding(.trailing, Layout.inset).padding(.vertical, Layout.group)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.fill, in: .rect(cornerRadius: Layout.buttonRadius, style: .continuous))
            .overlay(alignment: .leading) {
                UnevenRoundedRectangle(topLeadingRadius: Layout.buttonRadius, bottomLeadingRadius: Layout.buttonRadius)
                    .fill(Color.notice).frame(width: 4)
            }
            .accessibilityElement(children: .combine)
        } else {
            Text("Kein Datum auf dem Gutschein? Dann gilt er meist drei Jahre, gerechnet ab Ende des Kaufjahres. So ist es vorausgefüllt.")
                .font(.scaled(13)).foregroundStyle(Color.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4).padding(.vertical, 6)
        }
    }

    private func dateBox(_ label: String, _ date: Binding<Date>) -> some View {
        LabeledBox(label: label) {
            DatePicker(label, selection: date, displayedComponents: .date)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "de_DE"))
                .frame(minHeight: Layout.tap)
        }
    }

    // MARK: Logik

    /// Reine Ziffernfolgen ohne Leerzeichen speichern (Anzeige in Vierergruppen), andere Codes nur getrimmt.
    private static func normalizedCode(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let compact = t.replacingOccurrences(of: " ", with: "")
        return !compact.isEmpty && compact.allSatisfy(\.isNumber) ? compact : t
    }

    private func apply(_ o: ScanOutcome) {
        let d = o.draft
        fromScan = true
        convertedFrom = o.convertedSymbology
        if let r = o.received { received = r }
        if let id = d.merchantID {
            merchantID = id
        } else if let name = d.customName {
            // Laden, den die Texterkennung gelesen hat, der aber nicht in der Händlerliste steht.
            merchantID = "other"; customName = name; shopText = name
        }
        // Rabatt, fester Nachlass oder Angebot: Rabattcode (Code ohne Barcode) oder Aktionsgutschein.
        if let k = d.suggestedKind(hasBarcode: o.barcode != nil) { kind = k }
        if let p = d.percent { percentText = p.formatted() }
        // Fester Rabatt („10 € Rabatt“) gehört ins Feld „oder Wert in €“, nicht ins Guthaben.
        if d.isDiscount, d.percent == nil, let off = d.discountValue { valueText = Self.money(off) }
        if let b = d.benefit { benefitText = b }
        let online = Merchant.byID[merchantID]?.category == .codeOnly
        if !d.isDiscount, online || o.source == .text {
            // Online-Code aus Mail oder von einem reinen Online-Laden: kein Plastik, liegt im Postfach.
            kind = .valueVoucher
        }
        if o.source == .text || o.source == .document || online { location = .inbox }
        if o.barcode != nil, let code = o.displayCode {
            number = code.grouped
            // Online-Code: an der Kasse gibt es keinen Barcode, nur den Code zum Eintippen.
            format = online ? .text : (o.format ?? Merchant.byID[merchantID]?.format ?? format)
            formatLocked = true
        } else {
            if let n = d.number { number = n.grouped }
            // Dieselbe Regel wie im Scan-Ergebnis: gültige EAN aus der Nummer, sonst automatisch nach Laden.
            if let resolved = o.resolvedFormat, resolved.origin == .number {
                format = resolved.format
                formatLocked = true
            } else {
                format = autoFormat
                // Barcode nicht gelesen: Barcode-Art sichtbar machen und aktiv fragen statt still vorzubelegen.
                if o.photo != nil, d.number != nil, format != .text { formatNeedsChoice = true }
            }
        }
        if let p = d.pin { pin = p }
        if let v = d.value, !d.isDiscount || valueText.isEmpty { valueText = Self.money(v) }
        // Aus einer Laufzeit berechnet: als „geschätzt“ zeigen, aber nicht bei „Erhalten am“ neu rechnen.
        if let e = d.expires {
            expires = e; expiresIsSuggestion = false; expiresFromDuration = d.expiresIsEstimate
            validity = d.validity
        }
        if let r = d.recipient { owner = r }
        if let m = d.minOrder { minOrderText = Self.money(m) }
        photo = o.photo
        photoBack = o.backPhoto
    }

    private func load(_ c: GiftCard) {
        kind = c.kind
        merchantID = c.merchantID
        customName = c.customName
        number = c.number.grouped
        format = c.format
        pin = c.pin
        hadStoredPin = !c.pin.isEmpty
        received = c.received
        expires = c.expires
        // Geschätzt ist entweder der gesetzliche Vorschlag oder ein aus der Laufzeit berechnetes Datum;
        // Letzteres nicht beim Ändern von „Erhalten am“ durch die gesetzliche Frist ersetzen.
        let legal = Calendar.current.isDate(c.expires, inSameDayAs: GiftCard.legalExpiry(from: c.received))
        expiresIsSuggestion = c.expiresEstimated && legal
        expiresFromDuration = c.expiresEstimated && !legal
        location = c.location
        locationNote = c.locationNote
        owner = c.owner
        forGifting = c.forGifting
        photo = c.photo
        photoBack = c.photoBack
        benefitText = c.benefit
        // Ohne Code war .text keine echte Wahl: beim Ergänzen eines Codes gilt wieder das automatische Format
        formatLocked = !c.number.isEmpty
        valueText = c.value > 0 ? Self.money(c.value) : ""
        balanceText = c.kind.isValueBased ? Self.money(c.balance) : ""
        percentText = c.percent.map { $0.formatted() } ?? ""
        minOrderText = c.minOrder.map { Self.money($0) } ?? ""
    }

    private static func money(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(2)).grouping(.never).locale(Locale(identifier: "de_DE")))
    }

    /// Unbenutzte Karte, Guthaben-Feld unverändert: Guthaben folgt einem korrigierten Betrag.
    private var balanceFollowsValue: Bool {
        guard let c = editing, c.kind.isValueBased else { return false }
        return c.history.isEmpty && c.balance == c.value && balanceText == Self.money(c.balance)
    }

    private func validate() -> [String] {
        var e: [String] = []
        if shopText.trimmingCharacters(in: .whitespaces).isEmpty { e.append("Gib den Laden ein.") }
        if !minOrderText.isEmpty && parseMoney(minOrderText) == nil { e.append("„Mindestbestellwert“ ist keine gültige Zahl.") }
        if formatNeedsChoice && !number.isEmpty {
            e.append("Wähl die Barcode-Art, die auf dem Gutschein zu sehen ist (oder „Nur Code“, wenn es keinen Barcode gibt).")
        }
        if number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && photo == nil {
            e.append("Fotografier den Gutschein oder tipp den Code ab.")
        }
        let value = parseMoney(valueText)
        let balance = parseMoney(balanceText)
        let percent = parseMoney(percentText)
        if kind.isValueBased {
            if (value ?? 0) <= 0 { e.append("Gib das Guthaben in Euro ein, z.\u{00A0}B. 25,00.") }
            if !balanceText.isEmpty && balance == nil { e.append("„Guthaben jetzt“ ist keine gültige Zahl.") }
            if let b = balance, b < 0 { e.append("„Guthaben jetzt“ darf nicht negativ sein.") }
            if !balanceFollowsValue, let v = value, let b = balance, b > v { e.append("„Guthaben jetzt“ ist größer als das Guthaben beim Kauf.") }
        } else {
            if percent == nil && value == nil && benefitText.trimmingCharacters(in: .whitespaces).isEmpty {
                e.append("Gib einen Rabatt in %, einen Wert in € oder ein Angebot ein.")
            }
            if let p = percent, p < 1 || p > 100 { e.append("Der Rabatt muss zwischen 1 und 100\u{00A0}% liegen.") }
            if let v = value, v < 0 { e.append("Der Wert darf nicht negativ sein.") }
        }
        // Tagesgenau: gleicher Tag ist gültig, Uhrzeiten spielen keine Rolle
        let cal = Calendar.current
        if cal.startOfDay(for: expires) < cal.startOfDay(for: received) { e.append("„Gültig bis“ liegt vor dem Erhalt-Datum.") }
        return e
    }

    /// Beim Neuanlegen: schon gespeicherter Code oder hoher Wert (Betrugsmuster) – dieselben Regeln wie beim Scan.
    /// Nach einem Scan hat das Ergebnis die Dublette schon geprüft und bei hohem Betrag schon gefragt; fand der Scan
    /// keinen (hohen) Betrag und tippt man ihn hier ein, fragt das Formular.
    private func manualRisk() -> String? {
        guard editing == nil else { return nil }
        // Beide Hinweise zusammen, wenn beides zutrifft (Dublette und hoher Wert).
        var notes: [String] = []
        if outcome == nil, let dup = CardQueries.duplicate(of: number, in: store.cards) {
            notes.append("Diesen Code hast du schon gespeichert („\(dup.name)“).")
        }
        if let scanned = outcome?.draft.value, scanned >= CardQueries.patternValue { return nil }
        let value = parseMoney(valueText) ?? 0
        let recent = CardQueries.recentHighValueCount(store.cards)
        if value >= ScanResultView.highValue || (value >= CardQueries.patternValue && recent >= 1) {
            notes.append("Hat dich jemand am Telefon oder per Nachricht gebeten, Gutscheine zu kaufen und die Codes durchzugeben? Dann ist es Betrug. Gib nichts weiter.\n\n\(ScanResultView.nextStep)")
        }
        return notes.isEmpty ? nil : notes.joined(separator: "\n\n")
    }

    private func save() {
        guard !saving else { return }
        let problems = validate()
        animate { errors = problems }
        guard problems.isEmpty else {
            withAnimation(reduceMotion ? nil : .linear(duration: 0.4)) { shake += 1 }
            AccessibilityNotification.Announcement(problems.joined(separator: " ")).post()
            return
        }
        if let risk = manualRisk(), !riskConfirmed {
            riskMessage = risk
            return
        }
        saving = true
        let value = parseMoney(valueText) ?? 0
        let balance = balanceFollowsValue ? value : (parseMoney(balanceText) ?? value)
        let code = Self.normalizedCode(number)

        var card = editing ?? GiftCard(merchantID: merchantID, number: code, format: format, value: 0, balance: 0,
                                       received: received, expires: expires)
        card.kind = kind
        card.merchantID = merchantID
        card.customName = merchantID == "other" ? customName.trimmingCharacters(in: .whitespaces) : ""
        card.number = code
        card.format = code.isEmpty ? .text : (formatLocked ? format : autoFormat)
        card.pin = kind == .giftCard ? pin.trimmingCharacters(in: .whitespaces) : ""
        card.value = value
        if kind.isValueBased, let old = editing, old.kind.isValueBased, !balanceFollowsValue {
            // Geändertes Guthaben landet mit der Differenz im Verlauf
            _ = card.setBalance(balance)
        } else {
            card.balance = kind.isValueBased ? balance : value
        }
        card.percent = kind.isValueBased ? nil : parseMoney(percentText)
        card.minOrder = parseMoney(minOrderText).flatMap { $0 > 0 ? $0 : nil }
        card.received = received
        card.expires = expires
        card.expiresEstimated = expiresIsSuggestion || expiresFromDuration
        card.location = location
        card.locationNote = locationNote.trimmingCharacters(in: .whitespaces)
        card.owner = owner.trimmingCharacters(in: .whitespaces)
        card.forGifting = forGifting
        card.photo = photo
        card.photoBack = photoBack
        card.benefit = kind.isValueBased ? "" : benefitText.trimmingCharacters(in: .whitespacesAndNewlines)
        if editing == nil { card.addedAt = .now }
        // Nur solange es beim umgewandelten Code 128 bleibt; wer die Art ändert, hat bewusst gewählt.
        if let from = convertedFrom, card.format == .code128 { card.originalSymbology = from }
        else if editing?.format != card.format { card.originalSymbology = nil }
        store.upsert(card)
        // Erinnerungen plant der Store beim Speichern. Nur wenn noch nie gefragt wurde: einmal mit Erklärung fragen.
        Task {
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            if status == .notDetermined && !askedNotify {
                askedNotify = true
                savedCard = card
                askNotify = true
            } else {
                onSaved(card)
            }
        }
    }
}

/// Textfeld mit Beschriftung, Erklärung unter dem Feld (nicht nur im Platzhalter) und gut lesbarem Platzhalter.
struct FormField: View {
    let label: String
    var note: String? = nil
    let prompt: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    /// Codes: Festbreitenschrift, keine Autokorrektur.
    var code = false

    var body: some View {
        LabeledBox(label: label) {
            VStack(alignment: .leading, spacing: 4) {
                TextField(label, text: $text, prompt: Text(prompt).foregroundStyle(Color.muted))
                    .keyboardType(keyboard)
                    .font(code ? .scaled(16, weight: .semibold, design: .monospaced) : .scaled(16, weight: .semibold))
                    .autocorrectionDisabled(code)
                    .textInputAutocapitalization(code ? .never : .sentences)
                    .frame(minHeight: Layout.tap)
                    .accessibilityHint(note ?? "")
                if let note {
                    Text(note).font(.scaled(13)).foregroundStyle(Color.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityHidden(true)
                }
            }
        }
    }
}

/// Zweitrangige Knöpfe im Formular: warme Fläche statt System-Grau, 44 pt hoch.
private struct SoftButtonStyle: ButtonStyle {
    var foreground: Color = .ink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.scaled(15, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, Layout.inset)
            .frame(minHeight: Layout.tap)
            .background(Color.fill, in: .capsule)
            .contentShape(.capsule)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}


/// Kamera für ein Foto des Gutscheins (Papier, Karte, Bildschirm).
struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

/// Foto bildschirmfüllend, zoombar, z. B. zum Vorzeigen an der Kasse.
struct PhotoViewer: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1

    var body: some View {
        Image(uiImage: image).resizable().scaledToFit()
            .accessibilityLabel("Foto des Gutscheins")
            .scaleEffect(scale)
            .gesture(MagnifyGesture().onChanged { scale = max(1, $0.magnification) }.onEnded { _ in withAnimation { scale = 1 } })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
            .overlay(alignment: .topTrailing) {
                Button("Schließen", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly).font(.system(size: 17, weight: .bold))
                    .buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.large)
                    .padding(16)
                    .accessibilityLabel("Schließen")
            }
    }
}
