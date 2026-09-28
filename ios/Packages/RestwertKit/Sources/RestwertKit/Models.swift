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
        case .official: "Am Handy vorzeigbar"
        case .codeOnly: "Nur online"
        case .merchantApp: "Über die App des Ladens"
        case .untested: "Noch unklar"
        }
    }

    public var long: String {
        switch self {
        case .official: "Digitale Karte am Handy offiziell möglich"
        case .codeOnly: "Keine Plastikkarte nötig, Code online einlösen"
        case .merchantApp: "Nur über die App des Ladens"
        case .untested: "Offiziell unklar, hier hilft der Kassentest"
        }
    }
}

/// Wie man beim Händler an das Restguthaben kommt.
public enum BalanceCheck: String, Codable, Sendable {
    /// Direktes Formular: Nummer (und PIN) eingeben, Guthaben wird angezeigt.
    case form
    /// Guthaben erst nach Anmeldung im Kundenkonto sichtbar.
    case account
    /// Keine Online-Abfrage, der Link führt zur Info-Seite (z. B. „nur an der Kasse“).
    case info
    /// Weder Abfrage noch sinnvolle Info-Seite.
    case none

    public var linkLabel: String? {
        switch self {
        case .form: "Guthaben online prüfen"
        case .account: "Guthaben im Kundenkonto ansehen"
        case .info: "Infos zum Guthaben im Laden"
        case .none: nil
        }
    }
}

public struct Merchant: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let category: MerchantCategory
    public let format: CodeFormat
    public let balanceURL: URL?
    public let balanceCheck: BalanceCheck
    public let tip: String

    public init(_ id: String, _ name: String, _ category: MerchantCategory, _ format: CodeFormat = .code128, _ url: String? = nil,
                check: BalanceCheck = .form, _ tip: String) {
        self.id = id
        self.name = name
        self.category = category
        self.format = format
        self.balanceURL = url.flatMap(URL.init(string:))
        self.balanceCheck = url == nil ? .none : check
        self.tip = tip
    }

    public static let other = Merchant("other", "Anderer Laden", .untested, .code128, nil, "Noch keine Infos. Genau dafür ist der Kassentest da.")

    public static let all: [Merchant] = [
        Merchant("amazon", "Amazon", .codeOnly, .text, "https://www.amazon.de/gc/balance", check: .account, "Code im Amazon-Konto einlösen. Keine Filialen."),
        Merchant("zalando", "Zalando", .codeOnly, .text, "https://www.zalando.de/myaccount/", check: .account, "Nur online einlösbar, nicht in Outlets."),
        Merchant("otto", "Otto", .codeOnly, .text, "https://www.otto.de/shoppages/informationen_geschenkgutscheine_rabatte", check: .info, "Code im Warenkorb eingeben."),
        Merchant("apple", "Apple Gift Card", .codeOnly, .text, "https://secure.store.apple.com/de/shop/giftcard/balance", check: .account, "Auf den Apple Account laden."),
        Merchant("googleplay", "Google Play", .codeOnly, .text, "https://play.google.com/store/paymentmethods", check: .account, "Unter play.google.com/redeem einlösen."),
        Merchant("spotify", "Spotify", .codeOnly, .text, "https://www.spotify.com/de/account/overview/", check: .account, "PIN auf spotify.com/redeem eingeben."),
        Merchant("netflix", "Netflix", .codeOnly, .text, "https://www.netflix.com/redeem", check: .account, "Unter netflix.com/redeem einlösen."),
        Merchant("db", "Deutsche Bahn", .codeOnly, .text, "https://www.bahn.de/faq/pk/service/gutschein/geschenkkarte", check: .info, "Nur auf bahn.de oder im DB Navigator, nicht im Reisezentrum."),
        Merchant("lieferando", "Lieferando", .codeOnly, .text, "https://www.lieferando.de/geschenkkarten/saldocheck", check: .form, "Code und PIN online eingeben."),
        Merchant("wunschgutschein", "Wunschgutschein", .codeOnly, .text, "https://app.wunschgutschein.de/", check: .form, "Online in einen Partner-Gutschein umtauschen."),
        Merchant("eventim", "Eventim", .codeOnly, .text, "https://www.eventim.de/helpcenter/?faq=2288", check: .info, "Online mit dem 16-stelligen Code."),
        Merchant("ticketmaster", "Ticketmaster", .codeOnly, .text, "https://sites.prepaytec.com/chopinweb/balanceCheck.do?customerCode=2013119751813114&loc=de&showCvc=1&showExpiryDate=1&brandingCode=bal_enq_tmgermany", check: .form, "Code plus 3-stelliger Sicherheitscode."),
        Merchant("ikea", "IKEA", .official, .code128, "https://www.ikea.com/de/de/gift-cards/", check: .account, "Die Kasse scannt den Barcode auf dem Bildschirm. Guthaben online nur mit Login."),
        Merchant("thalia", "Thalia", .official, .code128, "https://www.thalia.de/geschenkkarte/", check: .form, "Die Kasse scannt den Barcode auf dem Bildschirm. Für online brauchst du Code und PIN."),
        Merchant("zara", "Zara", .official, .code128, "https://www.zara.com/de/de/z-zara-card/balance", check: .form, "E-Karte gilt in Filialen."),
        Merchant("tkmaxx", "TK Maxx", .official, .code128, "https://wbiprod.storedvalue.com/wbir/clients/tkmaxx-de", check: .form, "Digitalen Gutschein an der Kasse vorzeigen."),
        Merchant("decathlon", "Decathlon", .official, .code128, "https://www.decathlon.de/services/giftcard/balance", check: .form, "Offiziell auch digital auf dem Smartphone."),
        Merchant("douglas", "Douglas", .official, .code128, "https://www.douglas.de/de/cp/helpv2wherecanicheckthebalanceofmygiftcard/help-where-can-i-check-the-balance-of-my-gift-card", check: .info, "eGift digital oder ausgedruckt. Online mit Code und PIN."),
        Merchant("hm", "H&M", .official, .code128, "https://www2.hm.com/de_de/customer-service/geschenkkarten.html", check: .info, "E-Geschenkkarte am Handy zeigen."),
        Merchant("rossmann", "Rossmann", .official, .code128, "https://www.rossmann.de/de/service-und-hilfe/geschenkgutscheine", check: .info, "Digitaler Gutschein am Handy möglich. Guthaben nur an der Kasse."),
        Merchant("lidl", "Lidl", .official, .code128, "https://www.lidl.de/c/lidl-geschenkkarten/s10007775", check: .form, "PDF-Geschenkkarte am Handy zeigen. Guthaben mit Code und PIN."),
        Merchant("kaufland", "Kaufland", .official, .code128, "https://giftcard.kaufland.com/de_de/faq", check: .info, "Digitale Karte, Barcode am Handy. Nicht im Onlineshop."),
        Merchant("aldi", "Aldi", .official, .code128, "https://www.helaba.com/de/aldi/", check: .form, "Digitale Karte mit Barcode am Handy. Guthaben online oder an jeder Aldi-Kasse."),
        Merchant("mueller", "Müller", .official, .code128, "https://www.mueller.de/service/geschenkgutscheine/", check: .form, "Digitale Karte digital oder ausgedruckt."),
        Merchant("tchibo", "Tchibo", .official, .code128, "https://www.tchibo.de/c/geschenkkarte", check: .info, "Kartennummer vorzeigen reicht laut FAQ. Guthaben im Warenkorb oder in der Filiale."),
        Merchant("cinemaxx", "CinemaxX", .official, .code128, "https://www.cinemaxx.de/kontakt/faq", check: .info, "PDF am Handy an Kino- und Gastro-Kasse."),
        Merchant("nike", "Nike", .official, .code128, "https://www.nike.com/de/orders/gift-card-lookup", check: .form, "An der Kasse Code und PIN nennen."),
        Merchant("mediamarkt", "MediaMarkt", .official, .code128, "https://www.mediamarkt.de/de/service/giftCard", check: .form, "Die Kasse scannt den Barcode auf dem Bildschirm. Die Kasse fragt eventuell nach der PIN."),
        Merchant("saturn", "Saturn", .official, .code128, "https://www.saturn.de/de/service/giftCard", check: .form, "Wie MediaMarkt. Karte gilt nur bei Saturn."),
        Merchant("rewe", "REWE", .official, .code128, "https://kartenwelt.rewe.de/rewe-geschenkkarte.html#form-guthaben", check: .form, "Nur den Strich-Barcode zeigen. Einen QR-Code hat REWE laut Nutzerbericht abgelehnt."),
        Merchant("stadtgutschein", "Stadtgutschein", .official, .qr, nil, "Die Kasse scannt den QR-Code mit der Kassen-App. Systeme je Stadt verschieden."),
        Merchant("dm", "dm", .merchantApp, .code128, "https://www.dm.de/services/services-im-markt/geschenkkarten-3480686#abfrage-guthaben", check: .form, "Karte mit Code und PIN in die „Mein dm“-App laden und dort bezahlen."),
        Merchant("breuninger", "Breuninger", .merchantApp, .code128, "https://hilfe.breuninger.com/hc/de/articles/360016955480-Wo-kann-ich-das-Guthaben-meiner-Geschenkkarte-einsehen", check: .info, "Karte in der Breuninger-App speichern (scannen + PIN) und an der Kasse zeigen."),
        Merchant("ca", "C&A", .untested, .code128, "https://www.c-and-a.com/de/de/shop/geschenkkarten-gutscheine", check: .info, "Nur in Filialen. Guthaben nur an der Kasse oder per Hotline."),
        Merchant("primark", "Primark", .untested, .code128, "https://www.primark.com/de-de/geschenkkarten-guthaben", check: .form, "Quellen widersprüchlich, ob der Barcode auf dem Bildschirm reicht."),
        Merchant("deichmann", "Deichmann", .untested, .code128, "https://www.deichmann.com/de-de/faq-coupons", check: .info, "Online mit Code und PIN. Guthaben nur Filiale oder Hotline 0800 5020500."),
        Merchant("edeka", "EDEKA", .untested, .code128, "https://evci.pin-host.com/evci/#/guthabenabfrage", check: .form, "Keine offizielle digitale Karte gefunden."),
        Merchant("netto", "Netto", .untested, .code128, "https://www.netto-online.de/ueber-netto/Bezahlmoeglichkeiten.chtm#Geschenkkarten", check: .info, "Offiziell nur an der Kasse."),
        Merchant("penny", "Penny", .untested, .code128, "https://kartenwelt.penny.de/faq", check: .info, "Barcode nur über Drittanbieter-Apps belegt."),
        Merchant("galeria", "Galeria", .untested, .code128, "https://www.galeria.de/service/geschenkkarten/kartenwert-abrufen", check: .form, "PDF-Giftcard existiert, Nutzung am Handy in der Filiale nicht belegt."),
        Merchant("adidas", "Adidas", .untested, .code128, "https://wbiprod.storedvalue.com/wbir/clients/adidas?lng=de", check: .form, "Im Store wird der Barcode gescannt. Vom Handy nicht belegt."),
        Merchant("sephora", "Sephora", .untested, .code128, "https://geschenkgutschein.sephora.de/ecard/balance/consult3", check: .form, "eGift existiert. Gilt nicht in Galeria-Shops."),
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
        case .coupon: "Aktionsgutschein"
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
        case .shop: "Laden"
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
    /// Aus der Liste ausgeblendet, bleibt aber mit Verlauf erhalten.
    public var archivedAt: Date?
    /// Eigene Erinnerung nur für diesen Gutschein, zusätzlich zu den allgemeinen.
    public var reminderAt: Date?
    /// Wem der Gutschein gehört (leer = mir), z. B. „Mia“ oder „Oma“.
    public var owner: String = ""
    /// Zum Verschenken gedacht: zählt nicht zum eigenen Guthaben.
    public var forGifting: Bool = false
    /// An der Kasse benutzt, Betrag aber noch nicht eingetragen („Später eintragen“).
    public var pendingSince: Date?
    /// Ablaufdatum nicht auf dem Gutschein gefunden, sondern geschätzt (gesetzliche Frist). Zeigt „geschätzt“ an.
    public var expiresEstimated: Bool = false
    /// Mindestbestellwert in Euro („ab 50 € Einkauf“), vor allem bei Rabattcodes.
    public var minOrder: Double?
    /// Selbst ausgegebener Gutschein (z. B. vom eigenen Café): zählt nicht zum eigenen Guthaben, sondern ist offen bei Kunden.
    public var issuedByMe: Bool = false
    /// Nur bei selbst ausgegebenen Gutscheinen: für wen (Kunde) und der Gruß auf dem Gutscheinbild.
    public var issuedTo: String = ""
    public var greeting: String = ""
    /// Wann in Restwert erfasst (nicht wann gekauft): Grundlage für die Betrugsmuster-Warnung. Fehlt bei älteren Ständen.
    public var addedAt: Date?

    /// Erfasst seit – für Altbestände ohne `addedAt` das Kaufdatum.
    public var addedOrReceived: Date { addedAt ?? received }

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

    /// Zählt zur Guthaben-Summe: wertbasiert, nicht als eingelöst gestempelt (z. B. früherer Rabattcode, der zum
    /// Wertgutschein wurde), nicht abgelaufen, nicht archiviert und nicht zum Verschenken.
    public func countsTowardTotal(now: Date = .now) -> Bool {
        kind.isValueBased && redeemedAt == nil && daysLeft(now: now) >= 0 && !isArchived && !forGifting && !issuedByMe
    }
    public var isActive: Bool { isOpen && daysLeft >= 0 && archivedAt == nil }
    public var isArchived: Bool { archivedAt != nil }

    public var merchant: Merchant { Merchant.byID[merchantID] ?? .other }

    public var name: String {
        if merchantID == "other" { return customName.isEmpty ? "Anderer Laden" : customName }
        return merchant.name
    }

    public var daysLeft: Int { daysLeft(now: .now) }

    /// Ganze Kalendertage von heute (Ortszeit) bis zum Ablauftag. `expires` ist ein Kalendertag
    /// (``CalendarDay``), daher verschiebt kein Zeitzonenwechsel das Ergebnis.
    public func daysLeft(now: Date, calendar: Calendar = .current) -> Int {
        CalendarDay.days(from: now, to: expires, calendar: calendar)
    }

    public var remainingShare: Double {
        guard kind.isValueBased else { return redeemedAt == nil ? 1 : 0 }
        return value > 0 ? max(0, min(1, balance / value)) : 0
    }

    /// Gutscheine ohne Datum verjähren meist nach 3 Jahren, gerechnet ab Ende des Kaufjahres (§ 195 BGB).
    public static func legalExpiry(from received: Date) -> Date {
        let year = Calendar.current.component(.year, from: received) + 3
        return CalendarDay.utc.date(from: DateComponents(year: year, month: 12, day: 31, hour: 12)) ?? received
    }

    /// Betrag abziehen und im Verlauf festhalten. Gibt den neuen Restwert zurück.
    /// Gebucht wird höchstens das Guthaben (Überzahlung zahlt man an der Kasse drauf), damit Verlauf und
    /// „Rückgängig“ nie mehr zurückgeben, als wirklich abgezogen wurde.
    @discardableResult
    public mutating func redeem(_ amount: Double, store: String = "", note: String = "", at date: Date = .now) -> Double {
        guard amount.isFinite, amount > 0 else { return balance }
        let taken = (min(amount, max(0, balance)) * 100).rounded() / 100
        guard taken > 0 else { return balance }
        balance = max(0, ((balance - taken) * 100).rounded() / 100)
        history.append(Redemption(date: date, amount: taken, store: store, note: note, balanceAfter: balance))
        modifiedAt = date
        return balance
    }

    /// Guthaben direkt auf einen neuen Stand setzen (laut Bon oder nach Aufladung). Die Differenz steht im Verlauf.
    @discardableResult
    public mutating func setBalance(_ newBalance: Double, note: String = "", at date: Date = .now) -> Double {
        guard newBalance.isFinite else { return balance }
        let target = max(0, (newBalance * 100).rounded() / 100)
        let diff = ((balance - target) * 100).rounded() / 100
        guard diff != 0 else { return balance }
        balance = target
        if target > value { value = target }
        history.append(Redemption(date: date, amount: diff, store: "", note: note.isEmpty ? (diff < 0 ? Redemption.toppedUp : Redemption.corrected) : note, balanceAfter: balance))
        modifiedAt = date
        return balance
    }

    /// Rabattcodes und Coupons als Ganzes einlösen.
    public mutating func markRedeemed(store: String = "", at date: Date = .now) {
        guard redeemedAt == nil else { return }
        redeemedAt = date
        history.append(Redemption(date: date, amount: 0, store: store, note: "\(kind.label) eingelöst", balanceAfter: balance))
        modifiedAt = date
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, merchantID, customName, number, format, pin, value, balance, percent, received, expires
        case location, locationNote, redeemedAt, photo, isExample, history, modifiedAt, archivedAt, reminderAt, owner, forGifting, pendingSince, expiresEstimated
        case minOrder, issuedByMe, issuedTo, greeting, addedAt
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
        archivedAt = try c.decodeIfPresent(Date.self, forKey: .archivedAt)
        reminderAt = try c.decodeIfPresent(Date.self, forKey: .reminderAt)
        owner = try c.decodeIfPresent(String.self, forKey: .owner) ?? ""
        forGifting = try c.decodeIfPresent(Bool.self, forKey: .forGifting) ?? false
        pendingSince = try c.decodeIfPresent(Date.self, forKey: .pendingSince)
        expiresEstimated = try c.decodeIfPresent(Bool.self, forKey: .expiresEstimated) ?? false
        minOrder = try c.decodeIfPresent(Double.self, forKey: .minOrder)
        issuedByMe = try c.decodeIfPresent(Bool.self, forKey: .issuedByMe) ?? false
        issuedTo = try c.decodeIfPresent(String.self, forKey: .issuedTo) ?? ""
        greeting = try c.decodeIfPresent(String.self, forKey: .greeting) ?? ""
        addedAt = try c.decodeIfPresent(Date.self, forKey: .addedAt)
        // Ältere Stände legten Empfänger und Gruß in owner/locationNote ab: einmal umziehen.
        if issuedByMe && !c.contains(.issuedTo) {
            issuedTo = owner; greeting = locationNote
            owner = ""; locationNote = ""
        }
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

    /// Notizen von ``GiftCard/setBalance(_:note:at:)`` ohne eigene Notiz.
    public static let corrected = "Stand korrigiert"
    public static let toppedUp = "Aufgeladen"

    /// Stand direkt gesetzt (laut Bon oder Aufladung): `balanceAfter` ist ein absoluter Stand, kein Abzug.
    /// Erkannt an der Standard-Notiz; `setBalance` mit eigener Notiz zählt wie eine normale Buchung.
    public var isBalanceSet: Bool { store.isEmpty && (note == Self.corrected || note == Self.toppedUp) }
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

    /// Ziffern in Vierergruppen, andere Codes unverändert. Eine einzelne Restziffer hängt an der letzten Gruppe
    /// („4006 3813 33931“ statt „4006 3813 3393 1“), damit sie beim Umbruch nie allein steht.
    public var grouped: String {
        let s = replacingOccurrences(of: " ", with: "")
        guard !s.isEmpty, s.allSatisfy(\.isNumber) else { return self }
        var groups: [String] = []
        var i = s.startIndex
        while i < s.endIndex {
            let j = s.index(i, offsetBy: 4, limitedBy: s.endIndex) ?? s.endIndex
            groups.append(String(s[i..<j]))
            i = j
        }
        if groups.count > 1, groups.last?.count == 1 {
            let last = groups.removeLast()
            groups[groups.count - 1] += last
        }
        return groups.joined(separator: " ")
    }

    public var masked: String {
        let s = replacingOccurrences(of: " ", with: "")
        guard s.count > 4 else { return s }
        return "•••• " + s.suffix(4)
    }
}

/// Größter Betrag, den Restwert annimmt. Darüber ist es fast sicher ein Tippfehler oder eine Nummer.
public let maxMoney: Double = 100_000

/// „12,50 €“, „12.50“, „1.234,56“, „1.000“ → Double. Nur endliche Beträge von 0 bis ``maxMoney``;
/// „nan“, „inf“ und negative Werte ergeben nil.
public func parseMoney(_ text: String) -> Double? {
    var s = text.replacingOccurrences(of: "€", with: "").filter { !$0.isWhitespace }
    if s.contains(",") { s = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") }
    else if s.range(of: #"^\d{1,3}(\.\d{3})+$"#, options: .regularExpression) != nil { s = s.replacingOccurrences(of: ".", with: "") } // „1.000“ → 1000
    // Double("nan"), Double("inf") und Hex-Schreibweisen wären sonst gültig: nur Ziffern mit höchstens einem Punkt.
    guard s.range(of: #"^\d+(\.\d*)?$|^\.\d+$"#, options: .regularExpression) != nil,
          let v = Double(s), v.isFinite, v >= 0, v <= maxMoney else { return nil }
    return (v * 100).rounded() / 100
}
