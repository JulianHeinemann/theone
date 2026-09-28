import SwiftUI

// Datenschutzerklärung und Impressum direkt in der App – ohne Server, ohne Netz.
// Platzhalter in eckigen Klammern sind absichtlich sichtbar markiert und müssen vor der Veröffentlichung ersetzt werden.

/// Ein Abschnitt einer Rechtsseite: Überschrift und Absätze. Absätze mit „[…]“ werden als Platzhalter hervorgehoben.
private struct LegalSection: Identifiable {
    let title: String
    let paragraphs: [String]
    var id: String { title }
}

/// Anbieterangaben – bewusst Platzhalter, nichts erfunden.
private enum Provider {
    static let name = "[Name]"
    static let address = "[Anschrift]"
    static let email = "[E-Mail]"
}

struct PrivacyPolicyView: View {
    private let sections: [LegalSection] = [
        LegalSection(title: "Verantwortlich", paragraphs: [
            Provider.name, Provider.address, Provider.email,
        ]),
        LegalSection(title: "Kurz gesagt", paragraphs: [
            "Restwert hat kein Konto und keinen eigenen Server. Die App enthält keine Tracker, keine Analyse- und keine Werbe-Software. Wir erfahren nicht, welche Gutscheine du hast.",
        ]),
        LegalSection(title: "Auf deinem iPhone", paragraphs: [
            "Gutscheine, Fotos, PINs, Einlösungen und Testergebnisse liegen in einer Datei im Bereich der App. iOS verschlüsselt sie, solange das iPhone gesperrt ist.",
            "Für das Widget legt die App eine kurze Übersicht (Name, Betrag, Ablaufdatum – keine Codes, keine PINs) in einem gemeinsamen Ordner von App und Widget auf demselben Gerät ab.",
        ]),
        LegalSection(title: "Scannen und Texterkennung", paragraphs: [
            "Kamera, Fotos und PDFs werden auf dem iPhone ausgewertet (Barcode-, Text- und Handschrifterkennung von Apple). Wo Apple Intelligence verfügbar ist, läuft auch sie auf dem Gerät. Bilder und Texte werden dafür nirgendwohin geschickt.",
        ]),
        LegalSection(title: "Mitteilungen", paragraphs: [
            "Erinnerungen plant die App lokal auf dem iPhone. Es gibt keinen Push-Server. Ob Mitteilungen auf dem Sperrbildschirm Inhalte zeigen, stellst du in den iOS-Einstellungen ein.",
        ]),
        LegalSection(title: "iCloud-Sync (freiwillig)", paragraphs: [
            "Der Sync ist anfangs aus. Schaltest du ihn ein, speichert die App deine Gutscheine in der privaten iCloud-Datenbank deines eigenen Apple Accounts (CloudKit).",
            "Jeder Gutschein wird vorher auf dem iPhone mit AES-GCM (256 Bit) verschlüsselt. Der Schlüssel liegt in deinem iCloud-Schlüsselbund, den Apple Ende-zu-Ende verschlüsselt. Den Inhalt können weder wir noch Apple lesen.",
            "PINs gehen nie in die iCloud-Datenbank, sondern einzeln in deinen iCloud-Schlüsselbund. Fotos werden nicht synchronisiert und bleiben auf dem Gerät.",
            "Für Apple sichtbar bleiben technische Angaben wie Anzahl, zufällige Kennungen, Größe und Änderungszeit der Einträge. Für iCloud gelten Apples Datenschutzbestimmungen.",
            "In den Einstellungen löscht „Daten aus iCloud löschen“ alles aus deinem iCloud und aus dem iCloud-Schlüsselbund.",
        ]),
        LegalSection(title: "iCloud-Backup des iPhones", paragraphs: [
            "Unabhängig vom Sync sichert iOS die Daten von Apps im iCloud-Backup, wenn es eingeschaltet ist – auch Gutscheine, Fotos und PINs aus Restwert.",
            "Ohne „Erweiterten Datenschutz für iCloud“ hält Apple die Schlüssel zu diesem Backup und kann darauf zugreifen. Mit „Erweitertem Datenschutz“ ist das Backup Ende-zu-Ende verschlüsselt. In den iCloud-Einstellungen kannst du Restwert auch vom Backup ausnehmen.",
        ]),
        LegalSection(title: "Sicherung und Export", paragraphs: [
            "Eine Sicherungsdatei oder Tabelle (CSV) entsteht nur, wenn du sie anforderst. Wohin sie geht, wählst du selbst. Die Zwischendatei auf dem iPhone wird danach gelöscht.",
            "Die Sicherung enthält PINs und Fotos und ist nicht zusätzlich verschlüsselt. Die Tabelle enthält keine PINs.",
        ]),
        LegalSection(title: "Zwischenablage", paragraphs: [
            "Kopierst du in der Gutschein-Ansicht einen Code, bleibt er nur auf diesem Gerät (nicht auf anderen Apple-Geräten) und verschwindet nach zwei Minuten. Kopierst du ihn an der Kasse zum Online-Einlösen, bleibt er ebenfalls nur auf diesem Gerät und verschwindet nach zehn Minuten.",
        ]),
        LegalSection(title: "Links zu Läden", paragraphs: [
            "Links zum Guthaben-Check öffnen die Website des Ladens. Restwert gibt dabei keine Gutscheindaten weiter. Auf der Website gelten die Datenschutzregeln des Ladens.",
        ]),
        LegalSection(title: "App Store und Absturzberichte", paragraphs: [
            "Restwert kommt über den App Store oder TestFlight von Apple; dabei gelten Apples Bedingungen. Absturz- und Nutzungsdaten sehen wir nur, wenn du in iOS erlaubst, sie mit App-Entwicklern zu teilen. Apple gibt sie dann ohne deinen Namen weiter. Bei TestFlight sehen wir außerdem Feedback, das du selbst sendest.",
        ]),
        LegalSection(title: "Kontakt", paragraphs: [
            "Schreibst du uns eine E-Mail, nutzen wir deine Adresse und Nachricht nur, um zu antworten (Art. 6 Abs. 1 lit. b und f DSGVO), und löschen sie, wenn sie dafür nicht mehr nötig sind.",
        ]),
        LegalSection(title: "Deine Rechte", paragraphs: [
            "Du hast das Recht auf Auskunft, Berichtigung, Löschung, Einschränkung der Verarbeitung, Datenübertragbarkeit und Widerspruch sowie auf Beschwerde bei einer Datenschutz-Aufsichtsbehörde.",
            "Da deine Gutscheine nur bei dir liegen, löschst du sie selbst: in den Einstellungen mit „Alles löschen“ oder indem du die App entfernst. iCloud-Daten löschst du wie oben beschrieben.",
        ]),
    ]

    var body: some View {
        LegalPage(title: "Datenschutz", intro: "Stand: September 2026", sections: sections)
    }
}

struct ImprintView: View {
    private let sections: [LegalSection] = [
        LegalSection(title: "Angaben gemäß § 5 DDG", paragraphs: [
            Provider.name, Provider.address,
        ]),
        LegalSection(title: "Kontakt", paragraphs: [
            Provider.email,
        ]),
        LegalSection(title: "Verantwortlich für den Inhalt", paragraphs: [
            Provider.name, Provider.address,
        ]),
    ]

    var body: some View {
        LegalPage(title: "Impressum", intro: nil, sections: sections)
    }
}

/// Gemeinsames Gerüst: Liste mit Abschnittsköpfen, Text wächst mit der Schriftgröße und bricht immer um.
private struct LegalPage: View {
    let title: String
    let intro: String?
    let sections: [LegalSection]

    var body: some View {
        List {
            if let intro {
                Text(intro).font(.scaled(13)).foregroundStyle(Color.muted)
                    .listRowBackground(Color.clear)
            }
            ForEach(sections) { section in
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(section.paragraphs, id: \.self) { paragraph in
                            if paragraph.hasPrefix("[") && paragraph.hasSuffix("]") {
                                placeholder(paragraph)
                            } else {
                                Text(paragraph).font(.scaled(15)).foregroundStyle(Color.ink2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text(section.title)
                        .accessibilityAddTraits(.isHeader)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .pageBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Platzhalter deutlich markiert, damit er vor der Veröffentlichung nicht übersehen wird.
    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.scaled(15, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.warnSoft, in: .rect(cornerRadius: 6))
            .accessibilityLabel("Platzhalter: \(text.trimmingCharacters(in: CharacterSet(charactersIn: "[]")))")
    }
}

#Preview("Datenschutz") { NavigationStack { PrivacyPolicyView() } }
#Preview("Impressum") { NavigationStack { ImprintView() } }
