import SwiftUI
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
    @State private var photo: Data?
    @State private var errors: [String] = []
    @State private var formatLocked = false
    @State private var loaded = false
    @State private var shake = 0

    init(outcome: ScanOutcome? = nil, editing: GiftCard? = nil, onSaved: @escaping (GiftCard) -> Void) {
        self.outcome = outcome
        self.editing = editing
        self.onSaved = onSaved
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                kindPicker
                fields
                Text("Steht kein Datum auf dem Gutschein, gilt meist die gesetzliche Frist: drei Jahre ab Ende des Jahres, in dem er gekauft wurde (§ 195 BGB).")
                    .font(.system(size: 12.5)).foregroundStyle(Color.muted).padding(.horizontal, 4)
                if !errors.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(errors, id: \.self) { Label($0, systemImage: "exclamationmark.circle.fill") }
                    }
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.bad)
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
            if let editing { load(editing) } else if let outcome { apply(outcome) }
        }
        .onChange(of: received) { _, new in if editing == nil { expires = GiftCard.legalExpiry(from: new) } }
        .onChange(of: merchantID) { _, id in
            if !formatLocked, let m = Merchant.byID[id] { format = m.format }
        }
    }

    // MARK: Felder

    private var kindPicker: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(VoucherKind.allCases) { k in
                        Button {
                            withAnimation(.snappy) {
                                kind = k
                                if !k.isValueBased && !formatLocked { format = .text }
                            }
                        } label: {
                            Label(k.label, systemImage: k.symbol).font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.ink)
                                .padding(.horizontal, 14).padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(kind == k ? .regular.tint(Color.brandYellow).interactive() : .regular.interactive(), in: .capsule)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .scrollIndicators(.hidden)
        .padding(.top, 8)
        .sensoryFeedback(.selection, trigger: kind)
    }

    private var fields: some View {
        VStack(spacing: 8) {
            LabeledBox(label: "Shop") {
                Picker("Shop", selection: $merchantID) {
                    Text("Shop wählen").tag("")
                    ForEach(MerchantCategory.allCases) { cat in
                        Section(cat.label) {
                            ForEach(Merchant.sorted(in: cat)) { m in Text(m.name).tag(m.id) }
                        }
                    }
                    Text("Anderer Shop …").tag("other")
                }
                .labelsHidden().tint(Color.ink)
            }
            if merchantID == "other" {
                LabeledField(label: "Name des Shops", placeholder: "z. B. Buchhandlung am Markt", text: $customName)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if let m = Merchant.byID[merchantID], merchantID != "other" {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                    Text(m.category.long + ". " + m.tip)
                }
                .font(.system(size: 13)).foregroundStyle(Color.ink2).padding(.horizontal, 4)
                .transition(.opacity)
            }

            if kind.isValueBased {
                HStack(spacing: 8) {
                    LabeledField(label: "Wert in €", placeholder: "50,00", text: $valueText, keyboard: .decimalPad)
                    LabeledField(label: "Restwert", placeholder: "wie Wert", text: $balanceText, keyboard: .decimalPad)
                }
            } else {
                HStack(spacing: 8) {
                    LabeledField(label: "Rabatt in %", placeholder: "z. B. 15", text: $percentText, keyboard: .decimalPad)
                    LabeledField(label: "oder Wert in €", placeholder: "optional", text: $valueText, keyboard: .decimalPad)
                }
            }
            LabeledField(label: kind == .discountCode ? "Rabattcode" : "Code bzw. Kartennummer",
                         placeholder: "wird beim Scannen ausgefüllt", text: $number)
            HStack(spacing: 8) {
                if kind == .giftCard {
                    LabeledField(label: "PIN", placeholder: "optional", text: $pin, keyboard: .numberPad)
                }
                LabeledBox(label: "Barcode") {
                    Picker("Barcode", selection: $format) {
                        ForEach(CodeFormat.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden().tint(Color.ink)
                }
            }
            HStack(spacing: 8) {
                dateBox("Erhalten am", $received)
                dateBox("Gültig bis", $expires)
            }
            LabeledBox(label: "Aufbewahrungsort") {
                Picker("Aufbewahrungsort", selection: $location) {
                    ForEach(StorageLocation.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                }
                .labelsHidden().tint(Color.ink)
            }
            LabeledField(label: "Notiz zum Ort", placeholder: "optional, z. B. rotes Portemonnaie", text: $locationNote)
        }
        .padding(12)
        .cardSurface(radius: 24)
        .animation(.snappy, value: kind)
        .animation(.snappy, value: merchantID)
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
        if let id = d.merchantID {
            merchantID = id
            format = Merchant.byID[id]?.format ?? format
        }
        if let code = o.barcode {
            number = code
            format = o.format ?? format
            formatLocked = true
        } else if let n = d.number {
            number = n
        }
        if let p = d.pin { pin = p }
        if let v = d.value { valueText = Self.money(v) }
        if let e = d.expires { expires = e }
        if let p = d.percent {
            kind = .discountCode
            percentText = p.formatted()
            if o.barcode == nil { format = .text }
        }
        if let m = Merchant.byID[merchantID], m.category == .codeOnly, o.barcode == nil { format = .text }
        photo = o.photo
    }

    private func load(_ c: GiftCard) {
        kind = c.kind
        merchantID = c.merchantID
        customName = c.customName
        number = c.number
        format = c.format
        pin = c.pin
        received = c.received
        expires = c.expires
        location = c.location
        locationNote = c.locationNote
        photo = c.photo
        formatLocked = true
        valueText = c.value > 0 ? Self.money(c.value) : ""
        balanceText = c.kind.isValueBased ? Self.money(c.balance) : ""
        percentText = c.percent.map { $0.formatted() } ?? ""
    }

    private static func money(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(2)).grouping(.never).locale(Locale(identifier: "de_DE")))
    }

    private func validate() -> [String] {
        var e: [String] = []
        if merchantID.isEmpty { e.append("Wähl einen Shop aus.") }
        if merchantID == "other" && customName.trimmingCharacters(in: .whitespaces).isEmpty { e.append("Gib den Namen des Shops ein.") }
        if number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            e.append("Der Code fehlt. Scann den Gutschein oder tipp den Code ein.")
        }
        let value = parseMoney(valueText)
        let balance = parseMoney(balanceText)
        let percent = parseMoney(percentText)
        if kind.isValueBased {
            if (value ?? 0) <= 0 { e.append("Gib den Wert in Euro ein, z. B. 50,00.") }
            if !balanceText.isEmpty && balance == nil { e.append("Der Restwert ist keine gültige Zahl.") }
            if let v = value, let b = balance, b > v { e.append("Der Restwert ist größer als der Wert.") }
        } else {
            if percent == nil && value == nil { e.append("Gib einen Rabatt in % oder einen Wert in € ein.") }
            if let p = percent, p <= 0 || p > 100 { e.append("Der Rabatt muss zwischen 1 und 100 % liegen.") }
        }
        if expires < received { e.append("„Gültig bis“ liegt vor dem Erhalt-Datum.") }
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
        let balance = parseMoney(balanceText) ?? value
        let code = number.trimmingCharacters(in: .whitespacesAndNewlines)

        var card = editing ?? GiftCard(merchantID: merchantID, number: code, format: format, value: 0, balance: 0,
                                       received: received, expires: expires)
        card.kind = kind
        card.merchantID = merchantID
        card.customName = merchantID == "other" ? customName.trimmingCharacters(in: .whitespaces) : ""
        card.number = code
        card.format = format
        card.pin = kind == .giftCard ? pin.trimmingCharacters(in: .whitespaces) : ""
        card.value = value
        card.balance = kind.isValueBased ? balance : value
        card.percent = kind.isValueBased ? nil : parseMoney(percentText)
        card.received = received
        card.expires = expires
        card.location = location
        card.locationNote = locationNote.trimmingCharacters(in: .whitespaces)
        card.photo = photo ?? card.photo
        store.upsert(card)
        Task { await store.requestNotifications() }
        onSaved(card)
    }
}
