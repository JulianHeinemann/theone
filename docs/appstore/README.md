# Restwert im App Store – alles zum Einreichen

Alles zum Kopieren in App Store Connect. Längen sind geprüft (Apple-Grenzen in Klammern).
Offene Punkte, die nur du erledigen kannst, stehen ganz unten.

## App-Informationen

| Feld | Inhalt |
|---|---|
| Name (30) | Restwert – Gutscheine |
| Untertitel (30) | Gutscheine nie mehr verfallen |
| Bundle-ID | `de.restwert.app` (Widget: `de.restwert.app.widget`) |
| SKU | `restwert-ios` |
| Primäre Sprache | Deutsch |
| Kategorie | Finanzen (Zweitkategorie: Dienstprogramme) |
| Altersfreigabe | 4+ (alle Fragen mit „Nein“ beantworten) |
| Copyright | 2026 Julian Heinrich |
| Preis | Vorschlag: kostenlos mit einmaligem „Plus“-Kauf, oder 2,99–4,99 € einmalig. Die simulierten Tests ergaben fast einhellig 2–5 € einmalig, kein Abo. |

## URLs

Nach dem Einschalten von GitHub Pages (siehe unten):

| Feld | URL |
|---|---|
| Datenschutz (Pflicht) | https://julianheinemann.github.io/theone/datenschutz.html |
| Support (Pflicht) | https://julianheinemann.github.io/theone/support.html |
| Marketing (optional) | https://julianheinemann.github.io/theone/ |

Die Seiten liegen in `site/` und werden vom Workflow „Webseite“ veröffentlicht.

## Werbetext (170)

Kein Gutschein verfällt mehr: Restwert zeigt, was noch drauf ist, erinnert vor dem Ablauf und zeigt den Code an der Kasse groß. Kein Konto nötig, keine Tracker.

## Beschreibung (4000)

Geschenkkarten in der Schublade, Rabattcodes in alten Mails, der Stadtgutschein vom Arbeitgeber – und irgendwann ist er abgelaufen. Restwert sammelt alles an einem Ort und sagt dir rechtzeitig Bescheid.

NOCH DRAUF – AUF EINEN BLICK
Das gelbe Ticket zeigt dein ganzes Guthaben. Darunter steht, was bald abläuft, und der Verfallsradar zeigt die nächsten Monate auf einer Zeitachse.

IN SEKUNDEN ANGELEGT
• Karte scannen: Barcode und Text werden automatisch gelesen – auf Wunsch Vorder- und Rückseite (Kartennummer und PIN stehen oft hinten)
• Coupons direkt erkennen: „Gratis Kaffee“, „2 für 1“, „-15 % auf alles“, „10 € Rabatt ab 50 €“
• Foto, Screenshot oder PDF wählen
• Text einer Gutschein-Mail einfügen
• Oder alles von Hand eintragen
Steht kein Ablaufdatum drauf, setzt Restwert die gesetzliche Frist von drei Jahren und markiert sie als „geschätzt“.

AN DER KASSE
„An der Kasse zeigen“ macht den Code groß und den Bildschirm hell. Nach dem Bezahlen tippst du den Betrag ein – der neue Stand steht sofort da. Online-Codes kopierst du mit einem Tipp.

RECHTZEITIG ERINNERT
Vor dem Ablauf bekommst du eine Mitteilung. Wann, stellst du selbst ein. Ohne Spam, versprochen.

DEINE DATEN BLEIBEN BEI DIR
• Kein Konto nötig – optional „Mit Apple anmelden“, nur auf deinem Gerät; keine Werbung, keine Tracker
• Kein Server von uns: Wir sehen deine Gutscheine nie
• Texterkennung läuft auf dem iPhone
• Optionaler iCloud-Sync, vorher auf dem iPhone verschlüsselt
• PINs nur nach Face ID

AUSSERDEM
• Widget für den Home-Bildschirm
• Siri und Kurzbefehle: „Wie viel Guthaben habe ich?“
• Dunkelmodus, große Schrift und VoiceOver
• Sicherung und Export als Tabelle

## Stichwörter (100)

`geschenkkarte,guthaben,rabattcode,restguthaben,ablauf,erinnerung,stadtgutschein,coupon,barcode,rückseite`

## Neu in dieser Version

Erste Version im App Store.

## Screenshots

`screenshots/` enthält 7 Bilder in 1320 × 2868 (6,9", Pflichtgröße; Apple skaliert sie für kleinere iPhones). Nur iPhone – keine iPad-Bilder nötig.
In dieser Reihenfolge hochladen: 01_start, 02_checkout, 03_scan, 04_detail, 05_radar, 06_keypad, 07_start_dunkel.
`screenshots/raw/` sind die unbearbeiteten Simulator-Aufnahmen. Neu erzeugen: `cd ios && scripts/store-screens.sh`.

Alle Läden in Bildern, Beispielen und Einstieg sind erfunden (Modehaus Kranz, Wohnwerk, Buchhandlung Seitenweise, Parfümerie Blüte, Kaufhaus Lindner, Café Krone) – keine echten Marken (Richtlinie 5.2.1).

## App-Datenschutz („Nutrition Label“)

Frage „Erheben Sie oder Ihre Drittanbieter Daten von dieser App?“ → **Nein, wir erheben keine Daten.**

Begründung (für dich, nicht für Apple): Alles liegt auf dem Gerät. Der iCloud-Sync speichert in der privaten Datenbank des Nutzers, Ende-zu-Ende verschlüsselt; wir haben keinen Zugriff. Keine Analyse, keine Werbung, keine Tracker.
Absturzberichte über Apple zählen nicht als Erhebung durch uns.

## Exportkontrolle

In `Restwert-Info.plist` steht `ITSAppUsesNonExemptEncryption = NO`. Die App nutzt Verschlüsselung (CryptoKit, AES-GCM) nur zum Schutz der eigenen Daten des Nutzers – das fällt unter die Ausnahme. App Store Connect fragt deshalb nicht bei jedem Build nach.

## Hinweise für die Prüfung (App Review Information)

- Anmeldung: nicht nötig. „Mit Apple anmelden“ ist optional (Einstieg Seite 4 mit „Später“ überspringbar, Einstellungen → Konto), legt kein Server-Konto an und fragt nur den Namen ab (gespeichert wird nur der Vorname, keine E-Mail); Kennung (Schlüsselbund) und Vorname bleiben auf dem Gerät. „Abmelden“ beendet die Anmeldung (der Vorname bleibt für eine erneute Anmeldung gemerkt), „Alles löschen“ entfernt alles – es gibt kein Konto auf einem Server, daher keine Kontolöschung nach 5.1.1(v) nötig. Alle Funktionen gehen ohne Anmeldung.
- Beim ersten Start zeigt die App Beispiel-Gutscheine. Damit lassen sich alle Funktionen ohne eigene Daten ausprobieren (Detail, „An der Kasse zeigen“, Einkauf abziehen, Verfallsradar).
- Scannen braucht eine Kamera. Alternativ „Hinzufügen → Aus dem Text einer E-Mail“ mit z. B. „Buchhandlung Seitenweise Gutschein 25,00 € Code 6300981274561234 gültig bis 31.12.2027“.
- iCloud-Sync ist optional und in den Einstellungen abschaltbar.
- Kontakt: Julian Heinrich, info@maitr.de, +49 176 3211307

## Vor dem Einreichen – nur du

1. **Apple-Konto:** App-ID `de.restwert.app` mit iCloud (Container `iCloud.de.restwert.app`), App Groups (`group.de.restwert.app`) und „Sign in with Apple“; Widget-ID `de.restwert.app.widget` und Teilen-Erweiterung `de.restwert.app.share` mit derselben App-Gruppe. CloudKit-Schema in die Produktion übernehmen. Am einfachsten in Xcode unter „Signing & Capabilities“ das Team wählen und die Häkchen setzen.
2. **CloudKit-Schema:** Einmal eine Debug-Version mit eingeschaltetem Sync laufen lassen, dann im CloudKit-Dashboard (icloud.developer.apple.com) das Schema von „Development“ nach **„Production“ deployen**. Ohne diesen Schritt funktioniert der Sync in der Store-Version nicht.
3. **Impressum und Kontakt:** eingetragen (Julian Heinrich, Münster) – in `site/`, `server/public/` und in der App (`LegalView.swift`).
4. **Händlerstatus (DSA):** In App Store Connect angeben. Wer die App verkauft oder als Unternehmer anbietet, gilt als „Trader“; Anschrift, Telefon und E-Mail werden dann im Store angezeigt.
5. **GitHub Pages einschalten:** Repository → Settings → Pages → Source „GitHub Actions“. Danach veröffentlicht der Workflow „Webseite“ die Seiten.
6. **Alter Server:** `api-production-9130.up.railway.app` wird von der App nicht mehr genutzt. Alte Endpunkte (`/api/auth`, `/api/sync`) abschalten oder den Dienst beenden.
7. **Hochladen:** siehe `ios/TESTFLIGHT.md`.
