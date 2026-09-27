import SwiftUI
import RestwertKit

/// Ergebnis nach dem Scan: Wert, Code, Gültigkeit und ein Echtheits-Hinweis.
struct ScanResultView: View {
    let outcome: ScanOutcome
    var onAdd: () -> Void
    var onRescan: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var revealed = false

    private struct Check: Identifiable {
        enum Level { case ok, warning, info }
        let id = UUID()
        let level: Level
        let text: String
    }

    var body: some View {
        let draft = outcome.draft
        let code = outcome.barcode ?? draft.number
        let merchant = draft.merchantID.flatMap { Merchant.byID[$0] }
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    MerchantMark(merchantID: draft.merchantID, name: merchant?.name ?? draft.customName ?? "?")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Erkannter Gutschein").font(.scaled(13, weight: .semibold)).foregroundStyle(Color.ink2)
                        Text(merchant?.name ?? draft.customName ?? "Laden nicht erkannt").font(.scaled(20, weight: .bold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                    Spacer()
                    if outcome.usedAppleIntelligence {
                        Image(systemName: "apple.intelligence")
                            .font(.scaled(17, weight: .semibold))
                            .symbolRenderingMode(.multicolor)
                            .symbolEffect(.bounce, value: revealed)
                            .accessibilityLabel("Mit Apple Intelligence gelesen")
                    }
                }
                if let img = outcome.photo.flatMap(UIImage.init(data:)) {
                    Image(uiImage: img).resizable().scaledToFill()
                        .frame(height: 150).frame(maxWidth: .infinity)
                        .clipShape(.rect(cornerRadius: Layout.buttonRadius, style: .continuous))
                        .accessibilityLabel("Foto des Gutscheins")
                }
                // Bei sehr großer Schrift eine Spalte, damit Code und Datum nicht abgeschnitten werden.
                LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())],
                          spacing: 8) {
                    cell("Wert", draft.percent.map { "\(Int($0))\u{00A0}%" } ?? draft.value.map(\.euro) ?? "–", index: 0)
                    cell("Gültig bis", draft.expires.map(\.dayMonthYear) ?? "nicht gefunden", index: 1)
                    cell("Code", code ?? "–", index: 2)
                    cell("Format", outcome.format?.label ?? (code == nil ? "–" : "Nur Code"), index: 3)
                }
                if let code, let format = outcome.format {
                    BarcodeView(number: code, format: format, height: 70).padding(.top, 4)
                }
            }
            .padding(Layout.inset).cardSurface(radius: Layout.cardRadius)

            VStack(alignment: .leading, spacing: 10) {
                Label("Echtheits-Hinweis", systemImage: "checkmark.shield").font(.scaled(17, weight: .bold))
                ForEach(checks(draft: draft, merchant: merchant)) { check in
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

            Button("Hinzufügen", action: onAdd).buttonStyle(.primary)
            Button("Erneut scannen", action: onRescan).buttonStyle(.quiet)
        }
        .padding(.top, 8)
        .onAppear { revealed = true }
        .sensoryFeedback(.success, trigger: revealed)
    }

    private func cell(_ label: String, _ value: String, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.scaled(12, weight: .semibold)).foregroundStyle(Color.ink2)
            Text(label == "Code" ? value.grouped : value)
                .font(label == "Code" ? .scaled(15, weight: .bold, design: .monospaced) : .scaled(15, weight: .bold))
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1).minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: typeSize.isAccessibilitySize)
        }
        .padding(Layout.group).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.fill, in: .rect(cornerRadius: Layout.buttonRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .opacity(revealed || reduceMotion ? 1 : 0)
        .offset(y: revealed || reduceMotion ? 0 : 12)
        .animation(reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.3).delay(0.08 * Double(index)), value: revealed)
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

    private func checks(draft: CardDraft, merchant: Merchant?) -> [Check] {
        var out: [Check] = []
        if let code = outcome.barcode, let format = outcome.format {
            switch BarcodeEncoder.hasValidChecksum(code, format: format) {
            case true?: out.append(Check(level: .ok, text: "Prüfziffer des \(format.label)-Barcodes stimmt."))
            case false?: out.append(Check(level: .warning, text: "Prüfziffer des Barcodes stimmt nicht. Code bitte mit dem Original vergleichen."))
            case nil: out.append(Check(level: .ok, text: "\(format.label)-Barcode sauber gelesen (\(code.count) Zeichen)."))
            }
        } else if draft.number != nil {
            out.append(Check(level: .info, text: "Kein Barcode gefunden, Code nur aus dem Text gelesen. Bitte mit dem Original vergleichen."))
        } else {
            out.append(Check(level: .warning, text: "Kein Code gefunden. Bitte manuell eintragen."))
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
            out.append(expires >= Calendar.current.startOfDay(for: .now)
                       ? Check(level: .ok, text: "Gültig bis \(expires.dayMonthYear).")
                       : Check(level: .warning, text: "Das Ablaufdatum \(expires.dayMonthYear) liegt in der Vergangenheit."))
        } else {
            let legal = GiftCard.legalExpiry(from: .now).dayMonthYear
            out.append(Check(level: .warning, text: "Kein Ablaufdatum gefunden. Vorausgefüllt wird die gesetzliche Frist (\(legal)) – bitte mit dem Gutschein vergleichen."))
        }
        if let value = draft.value, value > 500 {
            out.append(Check(level: .warning, text: "Ungewöhnlich hoher Wert (\(value.euro)). Bitte prüfen."))
        }
        out.append(Check(level: .info, text: "Echte Läden verlangen nie Gutscheincodes per Telefon, Chat oder E-Mail. Wer danach fragt, will betrügen."))
        return out
    }
}
