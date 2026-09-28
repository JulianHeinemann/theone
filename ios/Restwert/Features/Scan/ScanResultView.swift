import SwiftUI
import RestwertKit

/// Ergebnis nach dem Scan: Wert, Code, Gültigkeit und ein Echtheits-Hinweis.
struct ScanResultView: View {
    let outcome: ScanOutcome
    /// „Wann gekauft/erhalten?“ geändert: Fristen neu rechnen.
    var onReceived: (Date) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var revealed = false
    /// Nach ein paar Scans ist der Betrugshinweis bekannt: dann nur noch einzeilig.
    @AppStorage("fraudHintScans") private var fraudHintScans = 0

    fileprivate struct Check: Identifiable {
        enum Level { case ok, warning, info }
        let id = UUID()
        let level: Level
        let text: String
    }

    var body: some View {
        Group {
            if outcome.looksLikeVoucher { voucher } else { notVoucher }
        }
        .padding(.top, 8)
        .onAppear {
            revealed = true
            fraudHintScans += 1
        }
        .task {
            // Kurz warten, bis VoiceOver den Seitenwechsel angesagt hat; Warnungen mit hoher Priorität.
            try? await Task.sleep(for: .milliseconds(700))
            var text = AttributedString(announcement)
            if announcement.contains("Achtung") { text.accessibilitySpeechAnnouncementPriority = .high }
            AccessibilityNotification.Announcement(text).post()
        }
        .sensoryFeedback(outcome.looksLikeVoucher ? .success : .warning, trigger: revealed)
    }

    /// Kurze Ansage nach dem Lesen, damit auch ohne Blick aufs Display klar ist, was erkannt wurde.
    private var announcement: String {
        guard outcome.looksLikeVoucher else { return "Kein Gutschein erkannt." }
        let d = outcome.draft
        let name = d.merchantID.flatMap { Merchant.byID[$0]?.name } ?? d.customName ?? "Laden nicht erkannt"
        let amount = d.percent.map { "\(Int($0)) Prozent" } ?? d.value.map(\.euro) ?? "ohne Betrag"
        let until = d.expires.map { ", gültig bis \($0.dayMonthYear)" } ?? ""
        let warnings = checks(draft: d, merchant: d.merchantID.flatMap { Merchant.byID[$0] }).filter { $0.level == .warning }
        let warn = warnings.isEmpty ? "" : " Achtung: " + warnings.map(\.text).joined(separator: " ")
        return "Gutschein erkannt: \(name), \(amount)\(until).\(warn)"
    }

    private var notVoucher: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Kein Gutschein erkannt", systemImage: "questionmark.text.page")
                .font(.scaled(20, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            Text("Das sieht nicht nach einem Gutschein aus: kein Laden, kein Betrag, kein Code oder Barcode. Ist es doch einer, fotografier die Seite mit Betrag und Code, oder trag ihn von Hand ein.")
                .font(.scaled(15)).foregroundStyle(Color.ink2)
                .fixedSize(horizontal: false, vertical: true)
            photoView
        }
        .padding(Layout.inset).frame(maxWidth: .infinity, alignment: .leading).cardSurface(radius: Layout.cardRadius)
    }

    private var voucher: some View {
        let draft = outcome.draft
        let merchant = draft.merchantID.flatMap { Merchant.byID[$0] }
        let code = outcome.displayCode
        let allChecks = checks(draft: draft, merchant: merchant)
        let warnings = allChecks.filter { $0.level == .warning }
        return VStack(alignment: .leading, spacing: 16) {
            // Warnungen (abgelaufen, hoher Wert, Prüfziffer) ganz oben, nicht unter den angehefteten Knöpfen.
            if !warnings.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(warnings) { w in
                        Label(w.text, systemImage: "exclamationmark.triangle.fill")
                            .font(.scaled(15, weight: .semibold)).foregroundStyle(Color.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .symbolRenderingMode(.multicolor)
                .padding(Layout.group).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.warn.opacity(0.14), in: .rect(cornerRadius: Layout.buttonRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Layout.buttonRadius, style: .continuous).strokeBorder(Color.warn, lineWidth: 1))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Achtung: " + warnings.map(\.text).joined(separator: " "))
            }
            // Bei hohem Wert gleich oben, sonst unter dem Ergebnis (das Ergebnis zuerst).
            // Bei sehr großer Schrift immer nach dem Ergebnis, sonst sähe man keine einzige Angabe.
            if (draft.value ?? 0) >= 100 && !typeSize.isAccessibilitySize { fraudBox(draft) }
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    MerchantMark(merchantID: draft.merchantID, name: merchant?.name ?? draft.customName ?? "?")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Gelesen – bitte prüfen").font(.scaled(15, weight: .semibold)).foregroundStyle(Color.ink2)
                        Text((outcome.displayMerchantName ?? "Laden nicht erkannt") + (outcome.aiFilled.contains("Laden") ? " ✦" : ""))
                            .font(.scaled(20, weight: .bold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                    Spacer()
                    if !outcome.aiFilled.isEmpty {
                        Image(systemName: "apple.intelligence")
                            .font(.scaled(17, weight: .semibold))
                            .symbolRenderingMode(.multicolor)
                            .symbolEffect(.bounce, value: reduceMotion ? false : revealed)
                            .accessibilityLabel("Mit Apple Intelligence gelesen")
                    }
                }
                // Bei sehr großer Schrift eine Spalte, damit Code und Datum nicht abgeschnitten werden.
                LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())],
                          spacing: 8) {
                    if let p = draft.percent {
                        cell("Rabatt", "\(Int(p))\u{00A0}%", index: 0)
                    } else {
                        cell("Wert", draft.value.map(\.euro) ?? "nicht gefunden", index: 0)
                    }
                    if let expires = draft.expires, expires < Calendar.current.startOfDay(for: .now) {
                        // Abgelaufen direkt an der Kachel, nicht nur im Warnkasten.
                        cell("Abgelaufen", "\(expires.dayMonthYear) · frag im Laden, oft noch einlösbar", index: 1, alert: true)
                    } else {
                        cell(draft.expiresIsEstimate ? "Gültig bis · berechnet" : "Gültig bis",
                             draft.expires.map(\.dayMonthYear) ?? "nicht gefunden", index: 1)
                    }
                    if let code {
                        cell("Code", code, index: 2)
                        cell("Barcode an der Kasse", formatText, index: 3)
                        if let pin = draft.pin { cell("PIN", String(repeating: "•", count: pin.count), index: 4) }
                    } else {
                        // Papiergutschein ohne Code: keine leeren „–“-Kacheln, sondern sagen, was an der Kasse passiert.
                        cell("An der Kasse", outcome.photo != nil ? "Foto zeigen" : "Code eintragen", index: 2)
                    }
                }
                // Foto nach den Angaben: bei großer Schrift stehen Wert und Datum sonst erst nach dem Scrollen.
                photoView
                if !outcome.aiFilled.isEmpty {
                    Label("✦ = Apple Intelligence hat diese Angabe im Text gefunden und zugeordnet. Bitte besonders prüfen.", systemImage: "apple.intelligence")
                        .font(.scaled(12)).foregroundStyle(Color.ink2)
                }
                receivedRow(draft)
                // Falsche Prüfziffer: keinen Barcode zeichnen, der an der Kasse garantiert scheitert.
                // Nur gelesene oder an der Nummer erkannte Barcodes zeichnen, nie geratene.
                if let code, let resolved = outcome.resolvedFormat, resolved.format != .text, resolved.origin != .merchant,
                   ScanDraft.retailCheck(code)?.valid != false {
                    BarcodeView(number: code, format: resolved.format, height: 70).padding(.top, 4)
                }
            }
            .padding(Layout.inset).cardSurface(radius: Layout.cardRadius)

            if (draft.value ?? 0) < 100 || typeSize.isAccessibilitySize { fraudBox(draft) }

            VStack(alignment: .leading, spacing: 10) {
                // Kein „Echtheits“-Versprechen: geprüft werden nur Form und Plausibilität.
                Label("Was wir geprüft haben", systemImage: "checklist").font(.scaled(17, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                ForEach(allChecks.filter { $0.level != .warning }) { check in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: icon(check.level)).foregroundStyle(tint(check.level))
                            .accessibilityLabel(levelLabel(check.level))
                        Text(check.text).font(.scaled(15)).foregroundStyle(Color.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(Layout.inset).frame(maxWidth: .infinity, alignment: .leading).cardSurface(radius: Layout.cardRadius)
        }
    }

    /// Betrugshinweis: bei hohem Wert ausführlich mit nächstem Schritt, sonst nach drei Scans kurz.
    @ViewBuilder
    private func fraudBox(_ draft: CardDraft) -> some View {
    // Bei hohem Wert immer ausführlich, sonst nach drei Scans kurz.
    let highValue = (draft.value ?? 0) >= 100
    Label(highValue ? "Hat dich jemand gebeten, diesen Gutschein zu kaufen und den Code durchzugeben? Dann ist es Betrug. Gib den Code nicht weiter, ruf den Laden an und erstatte Anzeige bei der Polizei."
          : fraudHintScans < 3 ? "Kein Laden, keine Behörde und keine Firma lässt sich mit Gutscheincodes bezahlen. Wer am Telefon oder per Nachricht nach dem Code fragt, will betrügen."
          : "Gib Gutscheincodes nie am Telefon oder per Nachricht weiter.",
          systemImage: "exclamationmark.shield")
        .font(.scaled(14, weight: .medium)).foregroundStyle(Color.ink)
        .fixedSize(horizontal: false, vertical: true)
        .padding(Layout.group).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.fill, in: .rect(cornerRadius: Layout.buttonRadius, style: .continuous))
    }

    /// Ganzes Foto zeigen (nicht beschneiden), damit Ladenname und Logo sichtbar bleiben.
    @ViewBuilder private var photoView: some View {
        if let img = outcome.photo.flatMap(UIImage.init(data:)) {
            Image(uiImage: img).resizable().scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 160)
                .background(Color.fill, in: .rect(cornerRadius: Layout.buttonRadius, style: .continuous))
                .clipShape(.rect(cornerRadius: Layout.buttonRadius, style: .continuous))
                .accessibilityLabel("Foto des Gutscheins")
        }
    }

    /// Dasselbe Format, das das Formular gleich vorschlägt, mit Herkunft.
    private var formatText: String {
        guard let resolved = outcome.resolvedFormat else { return "nicht gefunden" }
        if resolved.format == .text { return "Nur Code" }
        switch resolved.origin {
        case .scanned: return Self.friendly(resolved.format)
        case .number: return "\(Self.friendly(resolved.format)) · am Code erkannt"
        // Nicht gelesen: keine Art behaupten.
        case .merchant: return "nicht gelesen – im nächsten Schritt wählen"
        }
    }

    private func cell(_ label: String, _ value: String, index: Int, alert: Bool = false) -> some View {
        let ai = outcome.aiFilled.contains(label) || (label.hasPrefix("Gültig") && outcome.aiFilled.contains("Gültig bis"))
        return VStack(alignment: .leading, spacing: 2) {
            Label {
                Text(label + (ai ? " ✦" : ""))
            } icon: {
                if alert { Image(systemName: "exclamationmark.triangle.fill") }
            }
            .font(.scaled(12, weight: .semibold)).foregroundStyle(alert ? Color.warn : Color.ink2)
            // Codes nur an Gruppengrenzen umbrechen: in Gruppen feste Leerzeichen/Bindestriche.
            Text(label == "Code" ? Self.unbreakableGroups(value.grouped) : value)
                .font(label == "Code" ? .scaled(15, weight: .bold, design: .monospaced) : .scaled(15, weight: .bold))
                .foregroundStyle(alert ? Color.warn : Color.ink)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 3).minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Layout.group).frame(maxWidth: .infinity, alignment: .leading)
        .background(alert ? Color.warn.opacity(0.12) : Color.fill, in: .rect(cornerRadius: Layout.buttonRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)\(ai ? ", von Apple Intelligence ergänzt" : "")")
        .accessibilityElement(children: .combine)
        .opacity(revealed || reduceMotion ? 1 : 0)
        .offset(y: revealed || reduceMotion ? 0 : 12)
        .animation(reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.3).delay(0.08 * Double(index)), value: revealed)
    }

    /// Barcode-Art in Alltagssprache, Fachname in Klammern.
    static func friendly(_ f: CodeFormat) -> String {
        switch f {
        case .qr: "QR-Code"
        case .pdf417: "breiter 2D-Code (PDF417)"
        case .aztec: "Quadrat-Code (Aztec)"
        case .dataMatrix: "Quadrat-Code (Data Matrix)"
        case .text: "Nur Code"
        default: "Strichcode (\(f.label))"
        }
    }

    /// Bindestriche in Codes nicht umbrechen (IK‑9934‑2281‑4410), Leerzeichen zwischen Gruppen schon.
    static func unbreakableGroups(_ s: String) -> String {
        // Nach jedem Bindestrich eine unsichtbare Umbruchstelle: Umbruch nur zwischen Gruppen (IK-9934-/2281-4410).
        s.replacingOccurrences(of: "-", with: "\u{2011}\u{200B}")
    }

    /// „Wann gekauft oder bekommen?“: davon hängen gesetzliche Frist und „3 Jahre gültig“ ab.
    @ViewBuilder
    private func receivedRow(_ draft: CardDraft) -> some View {
        if draft.expires == nil || draft.expiresIsEstimate {
            DatePicker(selection: Binding(get: { outcome.received ?? .now }, set: { onReceived($0) }),
                       in: ...Date.now, displayedComponents: .date) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wann gekauft oder bekommen?").font(.scaled(15, weight: .semibold))
                    Text("Davon hängt „Gültig bis“ ab.").font(.scaled(12)).foregroundStyle(Color.ink2)
                }
            }
            .environment(\.locale, Locale(identifier: "de_DE"))
            .padding(.top, 4)
        }
    }

    private func icon(_ level: Check.Level) -> String {
        switch level {
        case .ok: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        }
    }

    private func levelLabel(_ level: Check.Level) -> String {
        switch level {
        case .ok: "In Ordnung"
        case .warning: "Achtung"
        case .info: "Hinweis"
        }
    }

    private func tint(_ level: Check.Level) -> Color {
        switch level {
        case .ok: .good
        case .warning: .warn
        case .info: .ink2
        }
    }

    fileprivate func checks(draft: CardDraft, merchant: Merchant?) -> [Check] {
        var out: [Check] = []
        if outcome.barcode != nil, outcome.resolvedFormat?.format == .text, draft.percent == nil {
            out.append(Check(level: .info, text: "Online-Code: Du gibst ihn im Shop ein. Der Barcode auf dem Gutschein wird deshalb nicht angezeigt."))
        }
        if let original = outcome.convertedSymbology {
            out.append(Check(level: .info, text: "Der Barcode ist ein \(original). Restwert zeigt ihn an der Kasse als Code 128 mit demselben Inhalt; die meisten Kassen lesen das. Nimm beim ersten Mal das Original mit."))
        }
        if let code = outcome.barcode, let format = outcome.format {
            switch BarcodeEncoder.hasValidChecksum(code, format: format) {
            case true?: out.append(Check(level: .ok, text: "Prüfziffer des \(format.label)-Barcodes stimmt."))
            case false?: out.append(Check(level: .warning, text: "Prüfziffer des Barcodes stimmt nicht. Code bitte mit dem Original vergleichen."))
            case nil: out.append(Check(level: .ok, text: "\(format.label)-Barcode sauber gelesen (\(code.count) Zeichen)."))
            }
        } else if let number = draft.number {
            let online = draft.percent != nil || merchant?.category == .codeOnly
            if online {
                // Online-Codes haben keinen Barcode: kein Hinweis auf die Barcode-Suche.
            } else if outcome.barcodeUnavailable {
                out.append(Check(level: .info, text: "Die Barcode-Suche lief auf diesem Gerät nicht. Code aus dem Text gelesen, bitte mit dem Original vergleichen."))
            } else if outcome.source != .text {
                out.append(Check(level: .info, text: "Kein Barcode gefunden, Code aus dem Text gelesen. Bitte mit dem Original vergleichen."))
            }
            if let retail = ScanDraft.retailCheck(number) {
                out.append(retail.valid
                    ? Check(level: .ok, text: "Der Code hat eine gültige EAN-13-Prüfziffer.")
                    : Check(level: .warning, text: "Eine Ziffer des Codes ist wahrscheinlich falsch gelesen. Bitte vergleiche jede Ziffer mit dem Gutschein."))
            }
            if outcome.resolvedFormat?.origin == .merchant, outcome.resolvedFormat?.format != .text {
                out.append(Check(level: .info, text: "Der Barcode wurde nicht gelesen. Wähl im nächsten Schritt die Barcode-Art, die auf dem Gutschein zu sehen ist."))
            }
        } else {
            out.append(Check(level: .info, text: "Kein Code gefunden. Bei Papiergutscheinen reicht das Foto an der Kasse, sonst trag ihn im nächsten Schritt ein."))
        }
        if let merchant {
            out.append(Check(level: .ok, text: "Laden erkannt: \(merchant.name). \(merchant.category.long)."))
            if let howTo = merchant.redeemHowTo { out.append(Check(level: .info, text: howTo)) }
        } else if let name = draft.customName {
            out.append(Check(level: .info, text: "„\(name)“ steht nicht in der Liste der Läden. Prüf den Namen im nächsten Schritt."))
        } else {
            out.append(Check(level: .info, text: "Laden nicht erkannt. Du trägst ihn im nächsten Schritt ein."))
        }
        if let expires = draft.expires {
            if expires < Calendar.current.startOfDay(for: .now) {
                out.append(Check(level: .warning, text: "Laut Gutschein abgelaufen am \(expires.dayMonthYear)."))
                if draft.percent == nil {
                    out.append(Check(level: .info, text: "Oft trotzdem nicht verloren: Für gekaufte Gutscheine gelten meist 3 Jahre ab Ende des Kaufjahres, kürzere Fristen sind oft unwirksam. Frag beim Laden nach Einlösung oder Erstattung."))
                }
            } else if draft.expiresIsEstimate {
                out.append(Check(level: .info, text: "Gültig bis \(expires.dayMonthYear) ist aus der Laufzeit auf dem Gutschein berechnet, ab dem Kaufdatum oben. Stell es dort richtig ein."))
            } else {
                out.append(Check(level: .ok, text: "Gültig bis \(expires.dayMonthYear)."))
            }
        } else {
            let legal = GiftCard.legalExpiry(from: outcome.received ?? .now).dayMonthYear
            // Kein Alarm: fehlt ein Datum, gilt meist die gesetzliche Frist. Sie beginnt mit dem Kauf, nicht mit dem Scan.
            out.append(Check(level: .info, text: "Kein Ablaufdatum gefunden. Vorausgefüllt wird die gesetzliche Frist (\(legal)), gerechnet ab dem Kaufdatum oben."))
        }
        if let value = draft.value, value > 500 {
            out.append(Check(level: .warning, text: "Ungewöhnlich hoher Wert (\(value.euro)). Bitte prüfen."))
        }
        return out
    }
}

extension ScanOutcome {
    /// Rote Warnungen (abgelaufen, hoher Wert, Prüfziffer); „Hinzufügen“ fragt dann einmal nach und nennt sie.
    var warningTexts: [String] {
        let d = draft
        return ScanResultView(outcome: self).checks(draft: d, merchant: d.merchantID.flatMap { Merchant.byID[$0] })
            .filter { $0.level == .warning }.map(\.text)
    }

    var hasWarnings: Bool { !warningTexts.isEmpty }
}
