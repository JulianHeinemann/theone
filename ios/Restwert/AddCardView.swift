import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Scannen → Ergebnis prüfen → Formular. Beim Bearbeiten direkt das Formular.
struct AddCardView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    var importURL: URL?
    var editing: GiftCard?
    var onSaved: (GiftCard) -> Void

    enum Step { case source, result, form }
    @State private var step: Step = .source
    @State private var outcome: ScanOutcome?
    @State private var busy = false
    @State private var showScanner = false
    @State private var showFiles = false
    @State private var photoItem: PhotosPickerItem?
    @State private var emailText = ""
    @State private var showEmail = false

    // Formular
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch step {
                    case .source: sourceStep
                    case .result: resultStep
                    case .form: formStep
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.page.ignoresSafeArea())
            .navigationTitle(editing != nil ? "Bearbeiten" : (step == .form ? "Gutschein hinzufügen" : "Scannen"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            }
            .overlay { if busy { ProgressView("Wird gelesen …").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20)) } }
        }
        .fullScreenCover(isPresented: $showScanner) {
            LiveScannerView { result in handle(result) }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.pdf, .image, .plainText, .text]) { result in
            if case .success(let url) = result { Task { await analyzeURL(url) } }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                busy = true
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    let result = await Importer.analyze(image: img)
                    busy = false
                    handle(result)
                } else { busy = false }
                photoItem = nil
            }
        }
        .sheet(isPresented: $showEmail) { emailSheet }
        .task {
            if let editing { load(editing); step = .form }
            else if let importURL { await analyzeURL(importURL) }
        }
    }

    // MARK: Schritt 1: Quelle

    private var sourceStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button { showScanner = true } label: { ViewfinderTeaser() }.buttonStyle(.plain)
            Text("Oder auf anderem Weg").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.muted).padding(.top, 4)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    sourceTile("photo", "Foto", "Auch Screenshots und Handschrift", Pastel.all[0])
                }
                .buttonStyle(.plain)
                Button { showEmail = true } label: { sourceTile("envelope", "E-Mail", "Text einfügen", Pastel.all[1]) }.buttonStyle(.plain)
                Button { showFiles = true } label: { sourceTile("doc.richtext", "PDF / Datei", "Aus Mail-Anhang oder Dateien", Pastel.all[2]) }.buttonStyle(.plain)
                Button { step = .form } label: { sourceTile("keyboard", "Manuell", "Alles selbst eintippen", Pastel.all[4]) }.buttonStyle(.plain)
            }
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "square.and.arrow.up")
                Text("Tipp: In Mail einen Gutschein-Anhang lange drücken, „Teilen“ und dann Restwert wählen.")
            }
            .font(.system(size: 13.5)).foregroundStyle(Color.ink2)
            .padding(14).background(Color.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(.top, 8)
    }

    private func sourceTile(_ icon: String, _ title: String, _ sub: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon).font(.system(size: 19, weight: .semibold)).foregroundStyle(Color.ink)
                .frame(width: 44, height: 44).background(color, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(Color.ink)
            Text(sub).font(.system(size: 12.5)).foregroundStyle(Color.muted).lineLimit(2, reservesSpace: true)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: 22)
    }

    private var emailSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Kopier in Mail den Text der Gutschein-E-Mail und füg ihn hier ein. Restwert sucht Shop, Wert, Code, PIN und Ablaufdatum heraus.")
                    .font(.system(size: 14)).foregroundStyle(Color.ink2)
                PasteButton(payloadType: String.self) { strings in
                    Task { @MainActor in emailText = strings.joined(separator: "\n") }
                }
                .labelStyle(.titleAndIcon)
                TextEditor(text: $emailText)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(Color.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                Button("Auswerten") {
                    showEmail = false
                    handle(ScanOutcome(text: emailText))
                }
                .buttonStyle(FilledButtonStyle())
                .disabled(emailText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(16)
            .navigationTitle("Aus E-Mail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { showEmail = false } } }
        }
        .presentationDetents([.large])
    }

    // MARK: Schritt 2: Ergebnis

    private var draft: CardDraft { TextParser.parse(outcome?.text ?? "") }

    private var resultStep: some View {
        let d = draft
        let o = outcome ?? ScanOutcome()
        let code = o.barcode ?? d.number
        let checks = authenticityChecks(outcome: o, draft: d)
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    LetterTile(text: d.merchantID.flatMap { Merchant.byID[$0]?.name } ?? "?", color: Pastel.color(for: d.merchantID ?? "x"))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Erkannter Gutschein").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.muted)
                        Text(d.merchantID.flatMap { Merchant.byID[$0]?.name } ?? "Shop nicht erkannt").font(.system(size: 19, weight: .bold))
                    }
                    Spacer()
                }
                if let img = o.photo.flatMap(UIImage.init(data:)) {
                    Image(uiImage: img).resizable().scaledToFill().frame(height: 150).frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    resultCell("Wert", d.value.map(\.euro) ?? "–")
                    resultCell("Gültig bis", d.expires.map(\.dayMonthYear) ?? "–")
                    resultCell("Code", code ?? "–")
                    resultCell("Format", o.format?.label ?? (code == nil ? "–" : "Nur Code"))
                }
                if let code, let f = o.format {
                    BarcodeView(number: code, format: f, height: 70).padding(.top, 4)
                }
            }
            .padding(18).cardSurface(radius: 28)

            VStack(alignment: .leading, spacing: 10) {
                Text("Echtheits-Hinweis").font(.system(size: 17, weight: .bold))
                ForEach(checks, id: \.text) { c in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: c.ok == true ? "checkmark.circle.fill" : (c.ok == false ? "exclamationmark.triangle.fill" : "info.circle.fill"))
                            .foregroundStyle(c.ok == true ? Color.good : (c.ok == false ? Color.warn : Color.muted))
                        Text(c.text).font(.system(size: 14)).foregroundStyle(Color.ink2)
                    }
                }
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading).cardSurface(radius: 24)

            Button("Hinzufügen") { applyOutcome(); step = .form }
                .buttonStyle(FilledButtonStyle())
            Button("Erneut scannen") { outcome = nil; step = .source; showScanner = true }
                .buttonStyle(FilledButtonStyle(background: .surface, foreground: .ink))
        }
        .padding(.top, 8)
    }

    private func resultCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 12)).foregroundStyle(Color.muted)
            Text(value).font(.system(size: 15, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private struct Check { let ok: Bool?; let text: String }

    private func authenticityChecks(outcome o: ScanOutcome, draft d: CardDraft) -> [Check] {
        var out: [Check] = []
        if let code = o.barcode, let f = o.format {
            if [.ean13, .ean8, .upca].contains(f) {
                let valid: Bool
                if case .bars? = BarcodeRenderer.render(code, format: f) { valid = true } else { valid = false }
                out.append(Check(ok: valid, text: valid ? "Prüfziffer des \(f.label)-Barcodes stimmt." : "Prüfziffer des Barcodes stimmt nicht. Code bitte prüfen."))
            } else {
                out.append(Check(ok: true, text: "\(f.label)-Barcode sauber gelesen (\(code.count) Zeichen)."))
            }
        } else if d.number != nil {
            out.append(Check(ok: nil, text: "Kein Barcode gefunden, Code nur aus dem Text gelesen. Bitte mit dem Original vergleichen."))
        } else {
            out.append(Check(ok: false, text: "Kein Code gefunden. Bitte manuell eintragen."))
        }
        if let m = d.merchantID.flatMap({ Merchant.byID[$0] }) {
            out.append(Check(ok: true, text: "Shop erkannt: \(m.name). \(m.category.long)."))
        } else {
            out.append(Check(ok: nil, text: "Shop nicht erkannt. Du wählst ihn im nächsten Schritt aus."))
        }
        if let e = d.expires {
            out.append(e >= Calendar.current.startOfDay(for: .now)
                       ? Check(ok: true, text: "Gültig bis \(e.dayMonthYear).")
                       : Check(ok: false, text: "Das Ablaufdatum \(e.dayMonthYear) liegt in der Vergangenheit."))
        }
        out.append(Check(ok: nil, text: "Echte Händler verlangen nie Gutscheincodes per Telefon, Chat oder E-Mail. Wer danach fragt, will betrügen."))
        return out
    }

    // MARK: Schritt 3: Formular

    private var formStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Art").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.muted).padding(.top, 8)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(VoucherKind.allCases) { k in
                        Button { withAnimation(.snappy) { kind = k; if !k.isValueBased && !formatLocked { format = .text } } } label: {
                            Label(k.label, systemImage: k.symbol).font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.ink)
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .background(kind == k ? Color.brandYellow : Color.surface, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)

            VStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Shop").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.muted)
                    Picker("Shop", selection: $merchantID) {
                        Text("Shop wählen").tag("")
                        ForEach(MerchantCategory.allCases) { cat in
                            Section(cat.label) { ForEach(Merchant.sorted(in: cat)) { m in Text(m.name).tag(m.id) } }
                        }
                        Text("Anderer Shop …").tag("other")
                    }
                    .labelsHidden().tint(.ink)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                if merchantID == "other" { field("Name des Shops", "z. B. Buchhandlung am Markt", $customName) }
                if let m = Merchant.byID[merchantID], merchantID != "other" {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle")
                        Text(m.category.long + ". " + m.tip)
                    }
                    .font(.system(size: 13)).foregroundStyle(Color.ink2).padding(.horizontal, 4)
                }

                if kind.isValueBased {
                    HStack(spacing: 8) {
                        field("Wert in €", "50,00", $valueText, keyboard: .decimalPad)
                        field("Restwert", "wie Wert", $balanceText, keyboard: .decimalPad)
                    }
                } else {
                    HStack(spacing: 8) {
                        field("Rabatt in %", "z. B. 15", $percentText, keyboard: .decimalPad)
                        field("oder Wert in €", "optional", $valueText, keyboard: .decimalPad)
                    }
                }
                field(kind == .discountCode ? "Rabattcode" : "Code bzw. Kartennummer", "wird beim Scannen ausgefüllt", $number)
                HStack(spacing: 8) {
                    if kind == .giftCard { field("PIN", "optional", $pin, keyboard: .numberPad) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Barcode").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.muted)
                        Picker("Barcode", selection: $format) {
                            ForEach(CodeFormat.allCases) { Text($0.label).tag($0) }
                        }
                        .labelsHidden().tint(.ink)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                HStack(spacing: 8) {
                    dateBox("Erhalten am", $received)
                    dateBox("Gültig bis", $expires)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Aufbewahrungsort").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.muted)
                    Picker("Aufbewahrungsort", selection: $location) {
                        ForEach(StorageLocation.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                    }
                    .labelsHidden().tint(.ink)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                field("Notiz zum Ort", "optional, z. B. rotes Portemonnaie", $locationNote)
            }
            .padding(12)
            .cardSurface(radius: 24)
            .onChange(of: received) { _, new in if editing == nil { expires = GiftCard.legalExpiry(from: new) } }
            .onChange(of: merchantID) { _, id in if !formatLocked, let m = Merchant.byID[id] { format = m.format } }

            Text("Steht kein Datum auf dem Gutschein, gilt meist die gesetzliche Frist: drei Jahre ab Ende des Jahres, in dem er gekauft wurde (§ 195 BGB).")
                .font(.system(size: 12.5)).foregroundStyle(Color.muted).padding(.horizontal, 4)

            if !errors.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(errors, id: \.self) { Label($0, systemImage: "exclamationmark.circle.fill") }
                }
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.bad)
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.badSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            Button(editing != nil ? "Änderungen speichern" : "Speichern") { save() }
                .buttonStyle(FilledButtonStyle())
        }
    }

    private func dateBox(_ label: String, _ date: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.muted)
            DatePicker(label, selection: date, displayedComponents: .date).labelsHidden()
                .environment(\.locale, Locale(identifier: "de_DE"))
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Logik

    private func handle(_ result: ScanOutcome) {
        outcome = result
        step = .result
    }

    private func analyzeURL(_ url: URL) async {
        busy = true
        let result = await Importer.analyze(url: url)
        busy = false
        handle(result)
    }

    private func applyOutcome() {
        let o = outcome ?? ScanOutcome()
        let d = TextParser.parse(o.text)
        if let id = d.merchantID { merchantID = id; format = Merchant.byID[id]?.format ?? format }
        if let code = o.barcode { number = code; format = o.format ?? format; formatLocked = true } else if let n = d.number { number = n }
        if let p = d.pin { pin = p }
        if let v = d.value { valueText = v.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "de_DE"))) }
        if let e = d.expires { expires = e }
        if let m = Merchant.byID[merchantID], m.category == .codeOnly, o.barcode == nil { format = .text }
        photo = o.photo
        let lower = o.text.lowercased()
        if lower.contains("rabatt") || lower.contains("% auf") || lower.contains("prozent") { kind = .discountCode }
    }

    private func load(_ c: GiftCard) {
        kind = c.kind; merchantID = c.merchantID; customName = c.customName; number = c.number; format = c.format
        pin = c.pin; received = c.received; expires = c.expires; location = c.location; locationNote = c.locationNote
        photo = c.photo; formatLocked = true
        let fmt: (Double) -> String = { $0.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "de_DE"))) }
        valueText = c.value > 0 ? fmt(c.value) : ""
        balanceText = c.kind.isValueBased ? fmt(c.balance) : ""
        percentText = c.percent.map { $0.formatted() } ?? ""
    }

    private func save() {
        var e: [String] = []
        if merchantID.isEmpty { e.append("Wähl einen Shop aus.") }
        if merchantID == "other" && customName.trimmingCharacters(in: .whitespaces).isEmpty { e.append("Gib den Namen des Shops ein.") }
        let code = number.trimmingCharacters(in: .whitespacesAndNewlines)
        if code.isEmpty { e.append("Der Code fehlt. Scann den Gutschein oder tipp den Code ein.") }
        let value = parseMoney(valueText)
        var balance = parseMoney(balanceText)
        let percent = parseMoney(percentText)
        if kind.isValueBased {
            if value == nil || (value ?? 0) <= 0 { e.append("Gib den Wert in Euro ein, z. B. 50,00.") }
            if !balanceText.isEmpty && balance == nil { e.append("Der Restwert ist keine gültige Zahl.") }
            if let v = value, let b = balance, b > v { e.append("Der Restwert ist größer als der Wert.") }
        } else {
            if percent == nil && value == nil { e.append("Gib einen Rabatt in % oder einen Wert in € ein.") }
            if let p = percent, p <= 0 || p > 100 { e.append("Der Rabatt muss zwischen 1 und 100 % liegen.") }
        }
        if expires < received { e.append("„Gültig bis“ liegt vor dem Erhalt-Datum.") }
        withAnimation(.snappy) { errors = e }
        guard e.isEmpty else { return }

        if balance == nil { balance = kind.isValueBased ? value : 0 }
        var card = editing ?? GiftCard(merchantID: merchantID, number: code, format: format, value: 0, balance: 0,
                                        received: received, expires: expires)
        card.kind = kind
        card.merchantID = merchantID
        card.customName = merchantID == "other" ? customName.trimmingCharacters(in: .whitespaces) : ""
        card.number = code
        card.format = format
        card.pin = kind == .giftCard ? pin.trimmingCharacters(in: .whitespaces) : ""
        card.value = value ?? 0
        card.balance = kind.isValueBased ? (balance ?? 0) : (value ?? 0)
        card.percent = kind.isValueBased ? nil : percent
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

/// Kamera-Sucher-Vorschau mit laufender Scanlinie; öffnet den echten Scanner.
struct ViewfinderTeaser: View {
    @State private var move = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color(hex: 0xE9ECF2))
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.ink, style: StrokeStyle(lineWidth: 2.5, dash: [26, 200]))
                .padding(28)
            GeometryReader { g in
                Rectangle()
                    .fill(LinearGradient(colors: [Color.brandYellow.opacity(0), Color.brandYellow], startPoint: .top, endPoint: .bottom))
                    .frame(height: 40)
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.brandYellow).frame(height: 3) }
                    .offset(y: move ? g.size.height - 70 : 30)
                    .padding(.horizontal, 30)
            }
            VStack(spacing: 10) {
                Image(systemName: "camera.viewfinder").font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Color.ink).frame(width: 58, height: 58).background(Color.brandYellow, in: Circle())
                Text("Gutschein scannen").font(.system(size: 18, weight: .bold)).foregroundStyle(Color.ink)
                Text("Barcode, gedruckter Text und Handschrift").font(.system(size: 13)).foregroundStyle(Color.muted)
            }
        }
        .aspectRatio(1.45, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onAppear { withAnimation(.easeInOut(duration: 1.6).repeatForever()) { move = true } }
    }
}
