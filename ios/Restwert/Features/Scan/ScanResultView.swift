import SwiftUI
import RestwertKit

/// Ergebnis nach dem Scan: Wert, Code, Gültigkeit und ein Echtheits-Hinweis.
struct ScanResultView: View {
    let outcome: ScanOutcome
    var onAdd: () -> Void
    var onRescan: () -> Void
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
                        Text("Erkannter Gutschein").font(.scaled(13, weight: .semibold)).foregroundStyle(Color.muted)
                        Text(merchant?.name ?? draft.customName ?? "Shop nicht erkannt").font(.scaled(20, weight: .bold))
                    }
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
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    cell("Wert", draft.percent.map { "\(Int($0)) %" } ?? draft.value.map(\.euro) ?? "–", index: 0)
                    cell("Gültig bis", draft.expires.map(\.dayMonthYear) ?? "–", index: 1)
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
                        Text(check.text).font(.scaled(15)).foregroundStyle(Color.ink2)
                    }
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
            Text(label).font(.scaled(12)).foregroundStyle(Color.muted)
            Text(value).font(.scaled(15, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(Layout.group).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.fill, in: .rect(cornerRadius: Layout.buttonRadius, style: .continuous))
        .opacity(revealed ? 1 : 0)
        .offset(y: revealed ? 0 : 12)
        .animation(.spring(duration: 0.5, bounce: 0.3).delay(0.08 * Double(index)), value: revealed)
    }

    private func icon(_ level: Check.Level) -> String {
        switch level {
        case .ok: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        }
    }

    private func tint(_ level: Check.Level) -> Color {
        switch level {
        case .ok: .good
        case .warning: .warn
        case .info: .muted
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
            out.append(Check(level: .ok, text: "Shop erkannt: \(merchant.name). \(merchant.category.long)."))
        } else if let name = draft.customName {
            out.append(Check(level: .info, text: "„\(name)“ steht nicht in der Liste der Läden. Prüf den Namen im nächsten Schritt."))
        } else {
            out.append(Check(level: .info, text: "Shop nicht erkannt. Du wählst ihn im nächsten Schritt aus."))
        }
        if let expires = draft.expires {
            out.append(expires >= Calendar.current.startOfDay(for: .now)
                       ? Check(level: .ok, text: "Gültig bis \(expires.dayMonthYear).")
                       : Check(level: .warning, text: "Das Ablaufdatum \(expires.dayMonthYear) liegt in der Vergangenheit."))
        }
        if let value = draft.value, value > 500 {
            out.append(Check(level: .warning, text: "Ungewöhnlich hoher Wert (\(value.euro)). Bitte prüfen."))
        }
        out.append(Check(level: .info, text: "Echte Läden verlangen nie Gutscheincodes per Telefon, Chat oder E-Mail. Wer danach fragt, will betrügen."))
        return out
    }
}
