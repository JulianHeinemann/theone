import Foundation

// MARK: - Barcode-Formate

public enum CodeFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case code128, ean13, ean8, upca, itf, code39, qr, pdf417, aztec, dataMatrix, text

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .code128: "Code 128"
        case .ean13: "EAN-13"
        case .ean8: "EAN-8"
        case .upca: "UPC-A"
        case .itf: "ITF"
        case .code39: "Code 39"
        case .qr: "QR-Code"
        case .pdf417: "PDF417"
        case .aztec: "Aztec"
        case .dataMatrix: "Data Matrix"
        case .text: "Nur Code"
        }
    }

    public var isTwoDimensional: Bool { self == .qr || self == .aztec || self == .dataMatrix || self == .pdf417 }
}

// MARK: - Händler (Recherche 25.09.2026)

public enum MerchantCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case official, codeOnly, merchantApp, untested

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .official: "Handy offiziell"
        case .codeOnly: "Nur Code"
        case .merchantApp: "Händler-App"
        case .untested: "Ungetestet"
        }
    }

    public var long: String {
        switch self {
        case .official: "Digitale Karte am Handy offiziell möglich"
        case .codeOnly: "Keine Plastikkarte nötig, Code online einlösen"
        case .merchantApp: "Nur über die App des Händlers"
        case .untested: "Offiziell unklar, hier hilft der Kassentest"
        }
    }
}

public struct Merchant: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let category: MerchantCategory
    public let format: CodeFormat
    public let balanceURL: URL?
    public let tip: String

    public init(_ id: String, _ name: String, _ category: MerchantCategory, _ format: CodeFormat = .code128, _ url: String? = nil, _ tip: String) {
        self.id = id
        self.name = name
        self.category = category
        self.format = format
        self.balanceURL = url.flatMap(URL.init(string:))
        self.tip = tip
    }

    public static let other = Merchant("other", "Anderer Händler", .untested, .code128, nil, "Noch keine Infos. Genau dafür ist der Kassentest da.")

    public static let all: [Merchant] = [
        Merchant("amazon", "Amazon", .codeOnly, .text, "https://www.amazon.de/gc/balance", "Code im Amazon-Konto einlösen. Keine Filialen."),
        Merchant("zalando", "Zalando", .codeOnly, .text, "https://www.zalando.de", "Nur online einlösbar, nicht in Outlets."),
        Merchant("otto", "Otto", .codeOnly, .text, "https://www.otto.de", "Code im Warenkorb eingeben."),
        Merchant("apple", "Apple Gift Card", .codeOnly, .text, "https://www.apple.com/de/shop/gift-cards", "Auf den Apple Account laden."),
        Merchant("googleplay", "Google Play", .codeOnly, .text, "https://play.google.com/redeem", "Unter play.google.com/redeem einlösen."),
        Merchant("spotify", "Spotify", .codeOnly, .text, "https://www.spotify.com/de/redeem/", "PIN auf spotify.com/redeem eingeben."),
        Merchant("netflix", "Netflix", .codeOnly, .text, "https://www.netflix.com/redeem", "Unter netflix.com/redeem einlösen."),
        Merchant("db", "Deutsche Bahn", .codeOnly, .text, "https://www.bahn.de", "Nur auf bahn.de oder im DB Navigator, nicht im Reisezentrum."),
        Merchant("lieferando", "Lieferando", .codeOnly, .text, "https://www.lieferando.de/geschenkkarten/saldocheck", "Nummer und PIN online eingeben."),
        Merchant("wunschgutschein", "Wunschgutschein", .codeOnly, .text, "https://www.wunschgutschein.de", "Online in einen Partner-Gutschein umtauschen."),
        Merchant("eventim", "Eventim", .codeOnly, .text, "https://www.eventim.de", "Online mit 16-stelliger Nummer."),
        Merchant("ticketmaster", "Ticketmaster", .codeOnly, .text, "https://help.ticketmaster.de", "Nummer plus 3-stelliger Sicherheitscode."),
        Merchant("ikea", "IKEA", .official, .code128, "https://www.ikea.com/de/de/gift-cards/", "Digitale Karte wird vom Handy gescannt. Guthaben online nur mit Login."),
        Merchant("thalia", "Thalia", .official, .code128, "https://www.thalia.de/hilfe/kaufprozess/geschenkkarte-gutscheine", "Digitale Geschenkkarte auch in Apple und Google Wallet."),
        Merchant("zara", "Zara", .official, .code128, "https://www.zara.com/de/de/z-zara-card/balance", "E-Karte gilt in Filialen."),
        Merchant("tkmaxx", "TK Maxx", .official, .code128, "https://www.tkmaxx.com/de/de/l/kunden-service/geschenkgutscheine+zahlungen", "Digitaler Gutschein im Wallet an der Kasse zeigen."),
        Merchant("decathlon", "Decathlon", .official, .code128, "https://www.decathlon.de/services/giftcard/balance", "Offiziell auch digital auf dem Smartphone."),
        Merchant("douglas", "Douglas", .official, .code128, "https://www.douglas.de", "eGift digital oder ausgedruckt. Online mit 17-stelliger Nummer und PIN."),
        Merchant("hm", "H&M", .official, .code128, "https://www2.hm.com/de_de/customer-service/geschenkkarten/saldouberprufung.html", "E-Geschenkkarte am Handy zeigen."),
        Merchant("rossmann", "Rossmann", .official, .code128, nil, "Digitaler Gutschein am Handy möglich. Guthaben nur an der Kasse."),
        Merchant("lidl", "Lidl", .official, .code128, "https://www.lidl.de/c/lidl-geschenkkarten", "PDF-Geschenkkarte am Handy zeigen. Guthaben mit Nummer und PIN."),
        Merchant("kaufland", "Kaufland", .official, .code128, "https://giftcard.kaufland.com/de_de/faq", "Digitale Karte, Barcode am Handy. Nicht im Onlineshop."),
        Merchant("aldi", "Aldi", .official, .code128, nil, "Digitale Aldi-Nord-Karte mit Barcode am Handy. Guthaben meist an der Kasse."),
        Merchant("mueller", "Müller", .official, .code128, "https://www.mueller.de/service/geschenkgutscheine", "Digitale Karte digital oder ausgedruckt."),
        Merchant("tchibo", "Tchibo", .official, .code128, "https://www.tchibo.de/giftcardhistory", "Kartennummer vorzeigen reicht laut FAQ."),
        Merchant("cinemaxx", "CinemaxX", .official, .code128, "https://www.cinemaxx.de", "PDF am Handy an Kino- und Gastro-Kasse."),
        Merchant("nike", "Nike", .official, .code128, "https://www.nike.com/de/orders/gift-card-lookup", "An der Kasse Nummer und PIN nennen."),
        Merchant("mediamarkt", "MediaMarkt", .official, .code128, "https://www.mediamarkt.de/de/service/giftCard", "Barcode vom Handy wird gescannt. Die Kasse fragt eventuell nach der PIN."),
        Merchant("saturn", "Saturn", .official, .code128, "https://www.saturn.de/de/service/giftCard", "Wie MediaMarkt. Karte gilt nur bei Saturn."),
        Merchant("rewe", "REWE", .official, .code128, "https://kartenwelt.rewe.de/faqs-rewe-geschenkkarte", "Nur den Strich-Barcode zeigen. Einen QR-Code hat REWE laut Nutzerbericht abgelehnt."),
        Merchant("stadtgutschein", "Stadtgutschein", .official, .qr, nil, "Händler scannt den QR-Code mit der Kassen-App. Systeme je Stadt verschieden."),
        Merchant("dm", "dm", .merchantApp, .code128, "https://www.dm.de/services/services-im-markt/geschenkkarten", "Karte mit Nummer und PIN in die „Mein dm“-App laden und dort bezahlen."),
        Merchant("breuninger", "Breuninger", .merchantApp, .code128, "https://hilfe.breuninger.com", "Karte in der Breuninger-App speichern (scannen + PIN) und an der Kasse zeigen."),
        Merchant("ca", "C&A", .untested, .code128, nil, "Nur in Filialen. Guthaben nur an der Kasse oder per Hotline."),
        Merchant("primark", "Primark", .untested, .code128, "https://www.primark.com/de-de/hilfe/geschenkkarten", "Quellen widersprüchlich, ob der Barcode vom Handy reicht."),
        Merchant("deichmann", "Deichmann", .untested, .code128, nil, "Online mit Nummer und PIN. Guthaben nur Filiale oder Hotline 0800 5020500."),
        Merchant("edeka", "EDEKA", .untested, .code128, "https://www.edeka.de/services/gutscheinkarte", "Keine offizielle digitale Karte gefunden."),
        Merchant("netto", "Netto", .untested, .code128, nil, "Offiziell nur an der Kasse."),
        Merchant("penny", "Penny", .untested, .code128, nil, "Barcode nur über Drittanbieter-Apps belegt."),
        Merchant("galeria", "Galeria", .untested, .code128, "https://www.galeria.de/service/geschenkkarten/kartenwert-abrufen", "PDF-Giftcard existiert, Nutzung am Handy in der Filiale nicht belegt."),
        Merchant("adidas", "Adidas", .untested, .code128, "https://www.adidas.de/hilfe", "Im Store wird der Barcode gescannt. Vom Handy nicht belegt."),
        Merchant("sephora", "Sephora", .untested, .code128, "https://www.sephora.de", "eGift existiert. Gilt nicht in Galeria-Shops."),
    ]

    public static let byID: [String: Merchant] = Dictionary((all + [other]).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

    public static func sorted(in category: MerchantCategory) -> [Merchant] {
        all.filter { $0.category == category }.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }
}

// MARK: - Art, Ort, Status, Sortierung

public enum VoucherKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case giftCard, valueVoucher, discountCode, custom, coupon

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .giftCard: "Geschenkkarte"
        case .valueVoucher: "Wertgutschein"
        case .discountCode: "Rabattcode"
        case .custom: "Eigener Gutschein"
        case .coupon: "Coupon"
        }
    }

    public var symbol: String {
        switch self {
        case .giftCard: "creditcard"
        case .valueVoucher: "banknote"
        case .discountCode: "percent"
        case .custom: "gift"
        case .coupon: "ticket"
        }
    }

    /// Wertbasiert = hat ein Guthaben in Euro, das teilweise eingelöst werden kann.
    public var isValueBased: Bool { self == .giftCard || self == .valueVoucher || self == .custom }
}

public enum StorageLocation: String, Codable, CaseIterable, Identifiable, Sendable {
    case wallet, drawer, phone, inbox, glovebox, pinboard

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .wallet: "Portemonnaie"
        case .drawer: "Schublade"
        case .phone: "Handy"
        case .inbox: "Postfach"
        case .glovebox: "Handschuhfach"
        case .pinboard: "Pinnwand"
        }
    }

    public var symbol: String {
        switch self {
        case .wallet: "wallet.pass"
        case .drawer: "archivebox"
        case .phone: "iphone"
        case .inbox: "tray"
        case .glovebox: "car"
        case .pinboard: "pin"
        }
    }
}

public enum VoucherStatus: Sendable, Equatable {
    case valid, expiringSoon, redeemed, expired

    public var label: String {
        switch self {
        case .valid: "Gültig"
        case .expiringSoon: "Läuft bald ab"
        case .redeemed: "Eingelöst"
        case .expired: "Abgelaufen"
        }
    }
}

public enum CardSortOrder: String, CaseIterable, Identifiable, Sendable {
    case expiry, value, shop

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .expiry: "Ablaufdatum"
        case .value: "Wert"
        case .shop: "Shop"
        }
    }
}

// MARK: - Gutschein

public struct GiftCard: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var kind: VoucherKind
    public var merchantID: String
    public var customName: String
    public var number: String
    public var format: CodeFormat
    public var pin: String
    public var value: Double
    public var balance: Double
    /// Rabatt in Prozent für Rabattcodes und Coupons (optional).
    public var percent: Double?
    public var received: Date
    public var expires: Date
    public var location: StorageLocation
    public var locationNote: String
    /// Rabattcodes und Coupons werden als Ganzes eingelöst.
    public var redeemedAt: Date?
    public var photo: Data?
    public var isExample: Bool
    public var history: [Redemption]
    /// Letzte Änderung, entscheidet beim Sync, welche Version gewinnt.
    public var modifiedAt: Date

    public init(id: UUID = UUID(), kind: VoucherKind = .giftCard, merchantID: String, customName: String = "", number: String,
                format: CodeFormat, pin: String = "", value: Double, balance: Double, percent: Double? = nil,
                received: Date, expires: Date, location: StorageLocation = .drawer, locationNote: String = "",
                redeemedAt: Date? = nil, photo: Data? = nil, isExample: Bool = false, history: [Redemption] = [],
                modifiedAt: Date = .now) {
        self.id = id; self.kind = kind; self.merchantID = merchantID; self.customName = customName; self.number = number
        self.format = format; self.pin = pin; self.value = value; self.balance = balance; self.percent = percent
        self.received = received; self.expires = expires; self.location = location; self.locationNote = locationNote
        self.redeemedAt = redeemedAt; self.photo = photo; self.isExample = isExample; self.history = history; self.modifiedAt = modifiedAt
    }

    public func status(warnDays: Int, now: Date = .now) -> VoucherStatus {
        if redeemedAt != nil || (kind.isValueBased && balance <= 0) { return .redeemed }
        let d = daysLeft(now: now)
        if d < 0 { return .expired }
        if d <= warnDays { return .expiringSoon }
        return .valid
    }

    /// Was auf der Karte groß steht: Euro-Restwert oder Rabatt.
    public var headline: String {
        if kind.isValueBased { return balance.euro }
        if let percent, percent > 0 { return "\(percent.formatted(.number.precision(.fractionLength(0...1)))) %" }
        if value > 0 { return value.euro }
        return kind.label
    }

    public var isOpen: Bool { redeemedAt == nil && (!kind.isValueBased || balance > 0) }
    public var isActive: Bool { isOpen && daysLeft >= 0 }

    public var merchant: Merchant { Merchant.byID[merchantID] ?? .other }

    public var name: String {
        if merchantID == "other" { return customName.isEmpty ? "Anderer Händler" : customName }
        return merchant.name
    }

    public var daysLeft: Int { daysLeft(now: .now) }

    public func daysLeft(now: Date) -> Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: expires)).day ?? 0
    }

    public var remainingShare: Double {
        guard kind.isValueBased else { return redeemedAt == nil ? 1 : 0 }
        return value > 0 ? max(0, min(1, balance / value)) : 0
    }

    /// Gutscheine ohne Datum verjähren meist nach 3 Jahren, gerechnet ab Ende des Kaufjahres (§ 195 BGB).
    public static func legalExpiry(from received: Date) -> Date {
        let cal = Calendar.current
        let year = cal.component(.year, from: received) + 3
        return cal.date(from: DateComponents(year: year, month: 12, day: 31)) ?? received
    }

    /// Betrag abziehen und im Verlauf festhalten. Gibt den neuen Restwert zurück.
    @discardableResult
    public mutating func redeem(_ amount: Double, store: String = "", note: String = "", at date: Date = .now) -> Double {
        guard amount > 0 else { return balance }
        balance = max(0, ((balance - amount) * 100).rounded() / 100)
        history.append(Redemption(date: date, amount: amount, store: store, note: note, balanceAfter: balance))
        modifiedAt = date
        return balance
    }

    /// Rabattcodes und Coupons als Ganzes einlösen.
    public mutating func markRedeemed(store: String = "", at date: Date = .now) {
        redeemedAt = date
        history.append(Redemption(date: date, amount: 0, store: store, note: "\(kind.label) eingelöst", balanceAfter: balance))
        modifiedAt = date
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, merchantID, customName, number, format, pin, value, balance, percent, received, expires
        case location, locationNote, redeemedAt, photo, isExample, history, modifiedAt
    }

    /// Tolerantes Dekodieren, damit ältere Speicherstände nach Updates lesbar bleiben.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decodeIfPresent(VoucherKind.self, forKey: .kind) ?? .giftCard
        merchantID = try c.decodeIfPresent(String.self, forKey: .merchantID) ?? "other"
        customName = try c.decodeIfPresent(String.self, forKey: .customName) ?? ""
        number = try c.decodeIfPresent(String.self, forKey: .number) ?? ""
        format = try c.decodeIfPresent(CodeFormat.self, forKey: .format) ?? .code128
        pin = try c.decodeIfPresent(String.self, forKey: .pin) ?? ""
        value = try c.decodeIfPresent(Double.self, forKey: .value) ?? 0
        balance = try c.decodeIfPresent(Double.self, forKey: .balance) ?? value
        percent = try c.decodeIfPresent(Double.self, forKey: .percent)
        received = try c.decodeIfPresent(Date.self, forKey: .received) ?? .now
        expires = try c.decodeIfPresent(Date.self, forKey: .expires) ?? GiftCard.legalExpiry(from: received)
        location = try c.decodeIfPresent(StorageLocation.self, forKey: .location) ?? .drawer
        locationNote = try c.decodeIfPresent(String.self, forKey: .locationNote) ?? ""
        redeemedAt = try c.decodeIfPresent(Date.self, forKey: .redeemedAt)
        photo = try c.decodeIfPresent(Data.self, forKey: .photo)
        isExample = try c.decodeIfPresent(Bool.self, forKey: .isExample) ?? false
        history = try c.decodeIfPresent([Redemption].self, forKey: .history) ?? []
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? received
    }
}

// MARK: - Einlösung (Bon)

public struct Redemption: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var date: Date
    public var amount: Double
    public var store: String
    public var note: String
    public var balanceAfter: Double

    public init(id: UUID = UUID(), date: Date, amount: Double, store: String = "", note: String = "", balanceAfter: Double) {
        self.id = id; self.date = date; self.amount = amount; self.store = store; self.note = note; self.balanceAfter = balanceAfter
    }
}

/// Eine Bon-Zeile mit Kartenbezug, für die Gesamtansicht.
public struct BonLine: Identifiable, Hashable, Sendable {
    public var id: UUID { redemption.id }
    public let cardID: UUID
    public let cardName: String
    public let merchantID: String
    public let redemption: Redemption

    public init(cardID: UUID, cardName: String, merchantID: String, redemption: Redemption) {
        self.cardID = cardID; self.cardName = cardName; self.merchantID = merchantID; self.redemption = redemption
    }
}

// MARK: - Kassentest

public struct TestResult: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var cardID: UUID?
    public var merchantID: String
    public var merchantName: String
    public var date: Date
    public var success: Bool
    public var store: String
    public var note: String
    public var format: CodeFormat
    public var amount: Double?
    public var isExample: Bool

    public init(id: UUID = UUID(), cardID: UUID? = nil, merchantID: String, merchantName: String, date: Date, success: Bool,
                store: String = "", note: String = "", format: CodeFormat, amount: Double? = nil, isExample: Bool = false) {
        self.id = id; self.cardID = cardID; self.merchantID = merchantID; self.merchantName = merchantName; self.date = date
        self.success = success; self.store = store; self.note = note; self.format = format; self.amount = amount; self.isExample = isExample
    }
}

// MARK: - Formatierung

extension Double {
    public var euro: String {
        formatted(.currency(code: "EUR").locale(Locale(identifier: "de_DE")))
    }
}

extension Date {
    public var dayMonthYear: String {
        formatted(.dateTime.day(.twoDigits).month(.twoDigits).year().locale(Locale(identifier: "de_DE")))
    }
}

extension String {
    public var initials: String {
        let words = split(separator: " ").filter { !$0.isEmpty }
        if words.count > 1, let a = words[0].first, let b = words[1].first { return "\(a)\(b)".uppercased() }
        return String(prefix(2)).uppercased()
    }

    /// Ziffern in Vierergruppen, andere Codes unverändert.
    public var grouped: String {
        let s = replacingOccurrences(of: " ", with: "")
        guard !s.isEmpty, s.allSatisfy(\.isNumber) else { return self }
        var out = ""
        for (i, ch) in s.enumerated() {
            if i > 0 && i % 4 == 0 { out.append(" ") }
            out.append(ch)
        }
        return out
    }

    public var masked: String {
        let s = replacingOccurrences(of: " ", with: "")
        guard s.count > 4 else { return s }
        return "•••• " + s.suffix(4)
    }
}

/// „12,50 €“, „12.50“, „1.234,56“ → Double
public func parseMoney(_ text: String) -> Double? {
    var s = text.replacingOccurrences(of: "€", with: "").replacingOccurrences(of: " ", with: "")
    if s.contains(",") { s = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") }
    guard let v = Double(s) else { return nil }
    return (v * 100).rounded() / 100
}
