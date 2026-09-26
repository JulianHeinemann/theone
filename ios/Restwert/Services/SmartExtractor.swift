import Foundation
import FoundationModels
import RestwertKit

/// Strukturierte Felder, die das On-Device-Sprachmodell aus Gutschein-Text liest.
@Generable
nonisolated struct VoucherFields {
    @Guide(description: "Name des Shops oder Händlers, z. B. Thalia, IKEA, Zalando. Leer, wenn unbekannt.")
    var shop: String?
    @Guide(description: "Gutscheinwert in Euro als Zahl, z. B. 25.0. Leer bei Rabattcodes ohne Eurobetrag.")
    var valueEuro: Double?
    @Guide(description: "Rabatt in Prozent, nur bei Rabattcodes, z. B. 15.")
    var percent: Double?
    @Guide(description: "Gutscheincode oder Kartennummer genau wie im Text, ohne Leerzeichen.")
    var code: String?
    @Guide(description: "PIN, falls angegeben.")
    var pin: String?
    @Guide(description: "Ablaufdatum im Format TT.MM.JJJJ, falls angegeben.")
    var expiry: String?
}

/// Nutzt Apple Intelligence (Foundation Models), wenn das Gerät es unterstützt. Sonst bleibt es beim Regel-Parser.
nonisolated enum SmartExtractor {
    static var isAvailable: Bool { SystemLanguageModel.default.isAvailable }

    @concurrent
    static func extract(from text: String) async -> CardDraft? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, SystemLanguageModel.default.isAvailable else { return nil }
        let session = LanguageModelSession(instructions: """
            Du liest Texte von Gutscheinen, Geschenkkarten und Gutschein-E-Mails, auch fehlerhafte Texterkennung \
            von Fotos und Handschrift. Übernimm nur Angaben, die wirklich im Text stehen. Erfinde nichts.
            """)
        do {
            let response = try await session.respond(
                to: "Lies die Gutschein-Angaben aus diesem Text:\n\n\(trimmed.prefix(4000))",
                generating: VoucherFields.self)
            return draft(from: response.content)
        } catch {
            return nil
        }
    }

    private static func draft(from f: VoucherFields) -> CardDraft {
        var d = CardDraft()
        if let shop = f.shop, !shop.isEmpty { d.merchantID = TextParser.merchant(in: shop) }
        d.value = f.valueEuro.flatMap { $0 > 0 && $0 <= 5000 ? $0 : nil }
        d.percent = f.percent.flatMap { $0 > 0 && $0 <= 90 ? $0 : nil }
        d.number = f.code?.replacingOccurrences(of: " ", with: "").nilIfEmpty
        d.pin = f.pin?.nilIfEmpty
        if let e = f.expiry { d.expires = TextParser.expiry(in: "gültig bis \(e)") }
        return d
    }
}

nonisolated private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
