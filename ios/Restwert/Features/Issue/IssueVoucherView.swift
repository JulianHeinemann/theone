import SwiftUI
import RestwertKit

/// Eigene Gutscheine ausgeben (z. B. als Café): Betrag und Empfänger eintragen, Restwert erzeugt einen eindeutigen Code
/// mit QR-Code und ein Gutscheinbild zum Teilen oder Drucken. Beim Einlösen scannt man den QR-Code mit Restwert.
struct IssueVoucherView: View {
    var onIssued: (GiftCard) -> Void
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("issuerName") private var issuerName = ""
    @State private var valueText = ""
    @State private var recipient = ""
    @State private var message = ""
    @State private var expires = GiftCard.legalExpiry(from: .now)
    @State private var issued: GiftCard?
    @State private var errors: [String] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Layout.section) {
                if let issued {
                    IssuedVoucherShare(card: issued, message: message)
                } else {
                    form
                }
            }
            .padding(.horizontal, Layout.page).padding(.vertical, Layout.group)
        }
        .pageBackground()
        .readableWidth()
        #if DEBUG
        .onAppear {
            // Nur für Tests: `-demoIssueAuto YES` füllt aus und erstellt den Gutschein.
            guard UserDefaults.standard.bool(forKey: "demoIssueAuto"), issued == nil else { return }
            issuerName = "Café am Markt"; valueText = "25"; recipient = "Familie Weber"; message = "Alles Gute zum Geburtstag!"
            issue()
        }
        #endif
        .navigationTitle(issued == nil ? "Gutschein ausgeben" : "Gutschein teilen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(issued == nil ? "Abbrechen" : "Fertig") {
                    if let issued { onIssued(issued) }
                    dismiss()
                }
            }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: Layout.group) {
            Text("Für Läden, Cafés und Vereine: Du gibst einen Gutschein aus, den Kunden bei dir einlösen. Restwert erzeugt einen eindeutigen Code mit QR-Code. Zum Einlösen scannst du ihn einfach mit Restwert.")
                .font(.scaled(15)).foregroundStyle(Color.ink2)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                FormField(label: "Dein Laden", prompt: "z.\u{00A0}B. Café am Markt", text: $issuerName)
                Divider()
                FormField(label: "Guthaben in €", prompt: "z.\u{00A0}B. 25,00", text: $valueText, keyboard: .decimalPad)
                Divider()
                FormField(label: "Für wen? (optional)", prompt: "z.\u{00A0}B. Familie Weber", text: $recipient)
                Divider()
                FormField(label: "Gruß auf dem Gutschein (optional)", prompt: "z.\u{00A0}B. Alles Gute zum Geburtstag!", text: $message)
                Divider()
                LabeledBox(label: "Gültig bis (gesetzlich mindestens 3 Jahre ab Jahresende)") {
                    DatePicker("Gültig bis", selection: $expires, in: Date.now..., displayedComponents: .date)
                        .labelsHidden()
                        .environment(\.locale, Locale(identifier: "de_DE"))
                        .frame(minHeight: Layout.tap, alignment: .leading)
                }
            }
            .padding(.horizontal, Layout.inset)
            .background(Color.surface, in: .rect(cornerRadius: Layout.cardRadius, style: .continuous)).modifier(ContrastEdge())
            if !errors.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(errors, id: \.self) { Label($0, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Color.warn) }
                }
                .font(.scaled(14, weight: .medium))
            }
            Button("Gutschein erstellen", action: issue).buttonStyle(.primary)
            Text("Ausgegebene Gutscheine zählen nicht zu deinem Guthaben. Du findest sie in der Liste mit „ausgegeben“.")
                .font(.scaled(13)).foregroundStyle(Color.muted)
        }
    }

    private func issue() {
        var e: [String] = []
        let name = issuerName.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { e.append("Gib den Namen deines Ladens ein.") }
        guard let value = parseMoney(valueText), value > 0 else {
            e.append("Gib das Guthaben in Euro ein, z.\u{00A0}B. 25,00.")
            errors = e
            return
        }
        guard e.isEmpty else { errors = e; return }
        let existing = Set(store.cards.filter(\.issuedByMe).map(\.number))
        var card = GiftCard(kind: .valueVoucher, merchantID: Merchant.other.id, customName: name,
                            number: IssuedVoucher.makeCode(for: name, existing: existing), format: .qr,
                            value: value, balance: value, received: .now, expires: expires, location: .phone)
        card.issuedTo = recipient.trimmingCharacters(in: .whitespaces)
        // Gruß mit ablegen, damit er beim erneuten Teilen wieder auf dem Bild steht.
        card.greeting = message.trimmingCharacters(in: .whitespaces)
        card.issuedByMe = true
        store.upsert(card)
        withAnimation(.snappy) { issued = card }
        AccessibilityNotification.Announcement("Gutschein über \(value.euro) erstellt").post()
    }
}

/// Fertiger Gutschein: Vorschau und Teilen als Bild (Nachricht, Mail, Drucken).
struct IssuedVoucherShare: View {
    let card: GiftCard
    var message = ""
    @State private var image: Image?

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.group) {
            IssuedVoucherCard(card: card, message: message)
            if let image {
                ShareLink(item: image, preview: SharePreview("Gutschein \(card.name)", image: image)) {
                    Label("Gutschein teilen oder drucken", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.primary)
            }
            Label("Zum Einlösen: Tipp unten auf „+“ und dann auf „Gutschein scannen“ und scanne den QR-Code. Restwert erkennt den eigenen Gutschein und öffnet gleich „Gutschein einlösen“.",
                  systemImage: "qrcode.viewfinder")
                .font(.scaled(14)).foregroundStyle(Color.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task {
            let renderer = ImageRenderer(content: IssuedVoucherCard(card: card, message: message).frame(width: 360).padding(12)
                .background(Color.white).environment(\.colorScheme, .light))
            renderer.scale = 3
            if let ui = renderer.uiImage { image = Image(uiImage: ui) }
        }
    }
}

/// Das Gutscheinbild selbst: Laden, Betrag, Empfänger, Gruß, QR-Code und Code zum Abtippen.
struct IssuedVoucherCard: View {
    let card: GiftCard
    var message = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("GUTSCHEIN").font(.system(size: 13, weight: .heavy)).kerning(2).foregroundStyle(Color(hex: 0x5C5953))
            Text(card.name).font(.system(size: 24, weight: .bold)).foregroundStyle(Color(hex: 0x111111))
            Text(card.value.euro).font(.system(size: 40, weight: .heavy, design: .rounded)).foregroundStyle(Color(hex: 0x111111))
            if !card.issuedTo.isEmpty { Text("für \(card.issuedTo)").font(.system(size: 17)).foregroundStyle(Color(hex: 0x3A3833)) }
            if !message.isEmpty { Text(message).font(.system(size: 16).italic()).foregroundStyle(Color(hex: 0x3A3833)) }
            HStack(alignment: .bottom, spacing: 14) {
                BarcodeView(number: card.number, format: .qr, height: 60)
                    .frame(width: 130, height: 130)
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.number).font(.system(size: 15, weight: .bold, design: .monospaced)).foregroundStyle(Color(hex: 0x111111))
                    Text("gültig bis \(card.expires.dayMonthYear)").font(.system(size: 13)).foregroundStyle(Color(hex: 0x3A3833))
                    Text("Einlösbar bei \(card.name)").font(.system(size: 13)).foregroundStyle(Color(hex: 0x3A3833))
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0xFFD84D), in: TicketShape(radius: 20, notchRadius: 10, notchY: 0.62))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Gutschein \(card.name), \(card.value.euro)\(card.issuedTo.isEmpty ? "" : ", für \(card.issuedTo)"), Code \(card.number)")
    }
}
