import SwiftUI
import PhotosUI
import LocalAuthentication
import RestwertKit

/// Formular zum Hinzufügen oder Bearbeiten eines Gutscheins, vorbefüllt aus einem Scan.
struct CardFormView: View {
    var outcome: ScanOutcome?
    var editing: GiftCard?
    var onSaved: (GiftCard) -> Void

    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var kind: VoucherKind = .giftCard
    @State private var merchantID = ""
    @State private var customName = ""
    @State private var number = ""
    @State private var format: CodeFormat = .code128
    @State private var pin = ""
    @State private var valueText = ""
    @State private var balanceText = ""
    @State private var percentText = ""
    @State private var received = Date.now
    @State private var expires = GiftCard.legalExpiry(from: .now)
    @State private var location: StorageLocation = .drawer
    @State private var locationNote = ""
    @State private var owner = ""
    @State private var forGifting = false
    @State private var photo: Data?
    @State private var errors: [String] = []
    /// Format kommt aus Scan, Nutzerwahl oder gespeicherter Karte und wird nicht mehr automatisch gesetzt.
    @State private var formatLocked = false
    /// „Gültig bis“ ist nur der gesetzliche Vorschlag und darf „Erhalten am“ folgen.
    @State private var expiresIsSuggestion = true
    /// Beim Bearbeiten war schon eine PIN gespeichert: nur die bleibt verdeckt.
    @State private var hadStoredPin = false
    @State private var loaded = false
    @State private var shake = 0
    @State private var showMore = false
    @State private var pinRevealed = false
    @State private var shopText = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showPhoto = false
    @AppStorage("pinLock") private var pinLock = true

    init(outcome: ScanOutcome? = nil, editing: GiftCard? = nil, onSaved: @escaping (GiftCard) -> Void) {
        self.outcome = outcome
        self.editing = editing
        self.onSaved = onSaved
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                photoSlot
                fields
                Text("Kein Datum auf dem Gutschein? Dann gilt er meist drei Jahre, gerechnet ab Ende des Kaufjahres. Das Datum ist schon so vorausgefüllt.")
                    .font(.scaled(13)).foregroundStyle(Color.ink2).padding(.horizontal, 4)
                if !errors.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(errors, id: \.self) { Label($0, systemImage: "exclamationmark.circle.fill") }
                    }
                    .font(.scaled(14, weight: .semibold)).foregroundStyle(Color.bad)
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.badSoft, in: .rect(cornerRadius: 16, style: .continuous))
                    .modifier(Shake(animatableData: CGFloat(shake)))
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                Button(editing != nil ? "Änderungen speichern" : "Speichern", action: save)
                    .buttonStyle(.primary)
            }
            .padding(.horizontal, 16).padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
        .pageBackground()
        .navigationTitle(editing != nil ? "Bearbeiten" : "Gutschein hinzufügen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if editing != nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .sensoryFeedback(.error, trigger: shake)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let editing { load(editing); showMore = true } else if let outcome { apply(outcome) }
            if shopText.isEmpty, let m = Merchant.byID[merchantID] { shopText = merchantID == "other" ? customName : m.name }
        }
        .onChange(of: shopText) { _, text in matchShop(text) }
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
            if let photo, let image = UIImage(data: photo) { PhotoViewer(image: image) }
        }
        .onChange(of: received) { _, new in if expiresIsSuggestion { expires = GiftCard.legalExpiry(from: new) } }
        .onChange(of: merchantID) { _, _ in
            if !formatLocked { format = autoFormat }
        }
    }

    /// Format ohne Scan oder Nutzerwahl: Codes und reine Online-Händler als Text, sonst das Händlerformat.
    private var autoFormat: CodeFormat {
        guard kind.isValueBased else { return .text }
        guard let m = Merchant.byID[merchantID] else { return .code128 }
        return m.category == .codeOnly ? .text : m.format
    }

    // MARK: Felder

    /// Vier gleich breite Segmente; „Andere“ zeigt darunter die seltenen Arten.
    private var kindPicker: some View {
        let others: [VoucherKind] = [.coupon, .custom]
        return VStack(alignment: .leading, spacing: 8) {
            Picker("Art", selection: Binding(
                get: { others.contains(kind) ? .coupon : kind },
                set: { setKind($0 == .coupon && others.contains(kind) ? kind : $0) })) {
                Text("Karte").tag(VoucherKind.giftCard)
                Text("Gutschein").tag(VoucherKind.valueVoucher)
                Text("Code").tag(VoucherKind.discountCode)
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
        withAnimation(.snappy) {
            kind = k
            if !formatLocked { format = autoFormat }
        }
    }

    /// Foto zuerst: reicht auch allein, z. B. für Papiergutscheine ohne Barcode.
    private var photoSlot: some View {
        HStack(spacing: 14) {
            if let photo, let image = UIImage(data: photo) {
                Button { showPhoto = true } label: {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: 84, height: 84).clipShape(.rect(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Foto ansehen")
                VStack(alignment: .leading, spacing: 8) {
                    Text("Foto gespeichert").font(.scaled(16, weight: .semibold))
                    HStack(spacing: 16) {
                        PhotosPicker("Ersetzen", selection: $photoItem, matching: .images)
                        Button("Entfernen", role: .destructive) { self.photo = nil }
                    }
                    .font(.scaled(14, weight: .medium))
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Foto vom Gutschein").font(.scaled(16, weight: .semibold))
                    Text("Reicht auch allein, z. B. für Papierzettel ohne Barcode. An der Kasse zeigst du dann das Foto.")
                        .font(.scaled(13)).foregroundStyle(Color.ink2)
                    HStack(spacing: 8) {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button { showCamera = true } label: { Label("Foto machen", systemImage: "camera") }
                                .buttonStyle(.bordered)
                        }
                        PhotosPicker(selection: $photoItem, matching: .images) { Label("Aus Fotos", systemImage: "photo") }
                            .buttonStyle(.bordered)
                    }
                    .font(.scaled(14, weight: .semibold)).tint(Color.ink)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.surface, in: .rect(cornerRadius: 16, style: .continuous))
        .padding(.top, 8)
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

    private var fields: some View {
        VStack(spacing: 2) {
            LabeledField(label: "Laden", placeholder: "z. B. dm, Café am Markt, Google Play", text: $shopText)
            if !shopSuggestions.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(shopSuggestions) { m in
                            Button { shopText = m.name } label: {
                                HStack(spacing: 6) {
                                    MerchantMark(merchantID: m.id, name: m.name, size: 22)
                                    Text(m.name).font(.scaled(14, weight: .medium))
                                }
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Color.fill, in: .capsule)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .scrollIndicators(.hidden)
            }
            if let m = Merchant.byID[merchantID], merchantID != "other" {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                    Text(m.category.long + ". " + m.tip)
                }
                .font(.scaled(13)).foregroundStyle(Color.muted).padding(.horizontal, 4).padding(.vertical, 6)
                .transition(.opacity)
            }
            if kind.isValueBased {
                LabeledField(label: "Betrag in €", placeholder: "z. B. 25,00", text: $valueText, keyboard: .decimalPad)
            } else {
                HStack(spacing: 16) {
                    LabeledField(label: "Rabatt in %", placeholder: "z. B. 15", text: $percentText, keyboard: .decimalPad)
                    LabeledField(label: "oder Wert in €", placeholder: "optional", text: $valueText, keyboard: .decimalPad)
                }
            }
            dateBox("Gültig bis", Binding(get: { expires }, set: { expires = $0; expiresIsSuggestion = false }))
            LabeledField(label: kind == .discountCode ? "Rabattcode" : "Code oder Kartennummer (falls vorhanden)",
                         placeholder: "wird beim Scannen ausgefüllt", text: $number)
            Button {
                withAnimation(.snappy) { showMore.toggle() }
            } label: {
                HStack {
                    Text(showMore ? "Weniger" : "Mehr (Art, PIN, schon benutzt, für wen, Ort)")
                    Spacer()
                    Image(systemName: "chevron.down").rotationEffect(.degrees(showMore ? 180 : 0))
                }
                .font(.scaled(14, weight: .medium)).foregroundStyle(Color.ink2)
                .padding(.horizontal, 4).padding(.vertical, 10).contentShape(.rect)
            }
            .buttonStyle(.plain)
            if showMore {
                kindPicker.padding(.bottom, 6)
                if kind.isValueBased {
                    LabeledField(label: "Guthaben jetzt, falls schon benutzt", placeholder: "wie Betrag", text: $balanceText, keyboard: .decimalPad)
                }
                if kind == .giftCard { pinField }
                LabeledField(label: "Für wen?", placeholder: "leer = für mich, z. B. Mia oder Oma", text: $owner)
                Toggle(isOn: $forGifting) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Zum Verschenken").font(.scaled(16, weight: .semibold))
                        Text("Zählt nicht zu deinem Guthaben").font(.scaled(13)).foregroundStyle(Color.muted)
                    }
                }
                .tint(Color.ink)
                .padding(.horizontal, 4).padding(.vertical, 10)
                LabeledBox(label: "Barcode-Typ (wird meist automatisch erkannt)") {
                    Picker("Barcode-Typ", selection: Binding(get: { format }, set: { format = $0; formatLocked = true })) {
                        ForEach(CodeFormat.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden().tint(Color.ink)
                }
                dateBox("Erhalten am", $received)
                LabeledBox(label: "Aufbewahrungsort") {
                    Picker("Aufbewahrungsort", selection: $location) {
                        ForEach(StorageLocation.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                    }
                    .labelsHidden().tint(Color.ink)
                }
                LabeledField(label: "Notiz zum Ort", placeholder: "optional, z. B. rotes Portemonnaie", text: $locationNote)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
        .background(Color.surface, in: .rect(cornerRadius: 16, style: .continuous))
        .animation(.snappy, value: kind)
        .animation(.snappy, value: merchantID)
    }

    /// Gespeicherte PIN verdeckt, wie im Detail: Aufdecken nur nach Face ID, wenn die Einstellung an ist.
    /// Eine neue PIN lässt sich immer eintippen, auch ins verdeckte Feld (ersetzt die alte).
    private var pinField: some View {
        LabeledBox(label: "PIN") {
            HStack {
                if pinRevealed || !hadStoredPin {
                    TextField("optional", text: $pin).keyboardType(.numberPad)
                } else {
                    SecureField("optional", text: $pin).keyboardType(.numberPad)
                }
                if hadStoredPin {
                    Button(pinRevealed ? "PIN verbergen" : "PIN zeigen", systemImage: pinRevealed ? "eye.slash" : "eye") {
                        Task { await revealPin() }
                    }
                    .labelStyle(.iconOnly).foregroundStyle(Color.ink2)
                }
            }
        }
    }

    private func revealPin() async {
        if pinRevealed { pinRevealed = false; return }
        guard pinLock else { pinRevealed = true; return }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { pinRevealed = true; return }
        pinRevealed = (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "PIN anzeigen")) ?? false
    }

    private func dateBox(_ label: String, _ date: Binding<Date>) -> some View {
        LabeledBox(label: label) {
            DatePicker(label, selection: date, displayedComponents: .date)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "de_DE"))
        }
    }

    // MARK: Logik

    private func apply(_ o: ScanOutcome) {
        let d = o.draft
        if let id = d.merchantID { merchantID = id }
        if let p = d.percent {
            kind = .discountCode
            percentText = p.formatted()
        }
        if let code = o.barcode {
            number = code
            format = o.format ?? Merchant.byID[merchantID]?.format ?? format
            formatLocked = true
        } else {
            if let n = d.number { number = n }
            // Ohne Barcode automatisch; onChange(merchantID) rechnet später mit derselben Regel (Rabattcode bleibt Text)
            format = autoFormat
        }
        if let p = d.pin { pin = p }
        if let v = d.value { valueText = Self.money(v) }
        if let e = d.expires { expires = e; expiresIsSuggestion = false }
        photo = o.photo
    }

    private func load(_ c: GiftCard) {
        kind = c.kind
        merchantID = c.merchantID
        customName = c.customName
        number = c.number
        format = c.format
        pin = c.pin
        hadStoredPin = !c.pin.isEmpty
        received = c.received
        expires = c.expires
        expiresIsSuggestion = false
        location = c.location
        locationNote = c.locationNote
        owner = c.owner
        forGifting = c.forGifting
        photo = c.photo
        // Ohne Code war .text keine echte Wahl: beim Ergänzen eines Codes gilt wieder das automatische Format
        formatLocked = !c.number.isEmpty
        valueText = c.value > 0 ? Self.money(c.value) : ""
        balanceText = c.kind.isValueBased ? Self.money(c.balance) : ""
        percentText = c.percent.map { $0.formatted() } ?? ""
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
        if number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && photo == nil {
            e.append("Fotografier den Gutschein oder tipp den Code ab.")
        }
        let value = parseMoney(valueText)
        let balance = parseMoney(balanceText)
        let percent = parseMoney(percentText)
        if kind.isValueBased {
            if (value ?? 0) <= 0 { e.append("Gib den Betrag in Euro ein, z. B. 25,00.") }
            if !balanceText.isEmpty && balance == nil { e.append("„Guthaben jetzt“ ist keine gültige Zahl.") }
            if let b = balance, b < 0 { e.append("„Guthaben jetzt“ darf nicht negativ sein.") }
            if !balanceFollowsValue, let v = value, let b = balance, b > v { e.append("„Guthaben jetzt“ ist größer als der Betrag.") }
        } else {
            if percent == nil && value == nil { e.append("Gib einen Rabatt in % oder einen Wert in € ein.") }
            if let p = percent, p < 1 || p > 100 { e.append("Der Rabatt muss zwischen 1 und 100 % liegen.") }
            if let v = value, v < 0 { e.append("Der Wert darf nicht negativ sein.") }
        }
        // Tagesgenau: gleicher Tag ist gültig, Uhrzeiten spielen keine Rolle
        let cal = Calendar.current
        if cal.startOfDay(for: expires) < cal.startOfDay(for: received) { e.append("„Gültig bis“ liegt vor dem Erhalt-Datum.") }
        return e
    }

    private func save() {
        let problems = validate()
        withAnimation(.snappy) { errors = problems }
        guard problems.isEmpty else {
            withAnimation(.linear(duration: 0.4)) { shake += 1 }
            return
        }
        let value = parseMoney(valueText) ?? 0
        let balance = balanceFollowsValue ? value : (parseMoney(balanceText) ?? value)
        let code = number.trimmingCharacters(in: .whitespacesAndNewlines)

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
        card.received = received
        card.expires = expires
        card.location = location
        card.locationNote = locationNote.trimmingCharacters(in: .whitespaces)
        card.owner = owner.trimmingCharacters(in: .whitespaces)
        card.forGifting = forGifting
        card.photo = photo
        store.upsert(card)
        Task { await store.requestNotifications() }
        onSaved(card)
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
