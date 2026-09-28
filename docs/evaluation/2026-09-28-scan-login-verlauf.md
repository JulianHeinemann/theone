# Scan, Barcodes, Login und neue Funktionen: Verlauf über 15 Testrunden (27./28.09.2026)

Alle Personas sind simuliert (keine echten Menschen). Rohdaten je Runde in `2026-09-2*-scan-login-*-raw.json` und `2026-09-28-beta-runde*-raw.json`.
Runde 1 im Detail: `2026-09-27-scan-login-20.md`.

## Bewertung

| Runde | Wer | Ø Gesamt | aktive Weiterempfehlung (9–10) |
|---|---|---|---|
| Personas 1 | 9 Alltag + 11 Fachleute, App + echtes Gerät + Server | 5,55 | 0/20 |
| Personas 2 | dieselben | 6,65 | 0/20 |
| Personas 3 | dieselben | 7,30 | 0/20 |
| Personas 4 | dieselben | 7,50 | 2/20 |
| Personas 5 | dieselben | 7,50 | 2/20 |
| Beta 1 | 20 neue Beta-Tester, nur Simulator-Build | 7,55 | 0/20 |
| Beta 2 | dieselben | 7,90 | 2/20 |
| Beta 3 | dieselben | 7,95 | 2/20 |
| Beta 4 | dieselben | 8,05 | 3/20 |
| Beta 5 | dieselben + 5 neue Funktionen | 8,10 | 4/20 |
| Beta 6 | dieselben | 8,50 | 9/20 |
| Beta 7 | dieselben | 8,85 | 13/20 |
| Beta 8 | dieselben | 9,15 | 16/20 |
| Beta 9 | dieselben | 9,25 | 18/20 |
| Beta 10 | dieselben, Schwerpunkt Einstieg, Performance und Codequalität | 8,80 | 15/20 |

**Beta-Runde 10 (Einstieg, Performance, Codequalität):** Ø 8,80 und 15/20 – die Runde bewertete den Stand *vor* den Korrekturen
und fand zwei neue ernste Punkte: „Alles löschen“ und „Aus iCloud löschen“ verlangten anders als die Schutz-Schalter keine Face ID
(Sandra, geteiltes iPad, 10 → 7), und bei selbst ausgegebenen Gutscheinen zeigten Liste und Detail den Empfänger nicht, weil sie
`owner` statt `issuedTo` lasen (Meltem, 9 → 8). Beides ist mit dieser Runde behoben (`allowedToDelete`, `GiftCard.forWhom`).
Anlass der Runde war die ruckelnde Einstiegs-Animation. Ursachen und Korrekturen:
- Schatten lagen als `compositingGroup().shadow` auf Gruppen, deren Inhalt sich in jedem Bild ändert (Zähler im Ticket, gleitende
  Zeilen): jedes Bild wurde neu gerastert und weichgezeichnet. Schatten liegen jetzt auf der deckenden Grundfläche (`cardSurface`,
  auch im Scan-Ergebnis); `ticketShadow` bleibt für Flächen ohne einfache Grundform (Bon, Kassen-Abriss, Stempel).
- Inaktive Seiten wurden per `.opacity(0.4)` auf der ganzen Seite gedimmt (Gruppen-Deckkraft, Zwischenebene pro Bild beim Wischen);
  jetzt ein Papier-Schleier obenauf, visuell identisch.
- „Weiter“/„Überspringen“ setzten die alte Seite sofort zurück, während sie noch 0,5 s hinausglitt (Ticket verschwand schlagartig);
  der Reset wartet jetzt 600 ms, und eine fertige Seite spielt beim schnellen Zurück nicht neu. Erinnern-Seite startet wie die
  anderen nach 150 ms; `Locale("de_DE")` im Zähler wird nicht mehr je Bild angelegt.
- Scan-Ergebnis: `ScanOutcome.draft` (kompletter Regel-Parser über den OCR-Text) lief bis zu ~30-mal je Aufbau und wird jetzt
  einmal je Änderung von Text, KI-Ergebnis oder Kaufdatum berechnet; `checks` ist eine reine Funktion ohne Wegwerf-View.
- Foto-Ausrichtung und PDF-Seiten (bis 3 × 2600 px) werden im Hintergrund gezeichnet statt auf dem Main Thread; Widget wird beim
  Aktivwerden nur noch einmal geschrieben (toter Parameter `total` entfernt).
- Codequalität: Betrugsmuster (ab 100 € in 7 Tagen) und Dubletten-Vergleich lagen zweimal wortgleich in Scan und Formular, jetzt
  `CardQueries.recentHighValueCount`/`duplicate(of:in:)` im Kit mit Tests (139/139); das Formular fragt nach einem Scan ohne Betrag
  auch selbst; totes `Store.csvFile()`, `cell()` und `LAContext` entfernt; `flatSurface()` statt sechsfach kopierter Fläche;
  ein Wortlaut für „Nicht angenommen“/„Hat nicht geklappt“ inkl. Bestätigung; `aiFilled` markiert auch den Laden.
- Texte: Einstieg Seite 3 in einem Satz, Seite 4 „Von Hand eingeben – Laden, Guthaben und Ablaufdatum eintippen“, „Barcode“ statt
  „Strichcode“, „Kassen-Tests“, „deiner iCloud“, kürzerer Fristen-Hinweis, geschützte Leerzeichen; Datenschutz-Website nennt für die
  Zwischenablage jetzt wie die App zehn Minuten; die `.broken`-Kopie der Datei bekommt ausdrücklich `complete`-Dateischutz.
Weiter offen (bekannte Grenzen oder größer): Tab-Leiste über der Radar-Unterkante, iPad-Start-Layout, Teilen-Erweiterung für
Mail-Text, Wallet-Pass, XCUITest-Target, Accessibility-Audit; Speichern-Hinweis über „Von Hand eingeben“; Widget/Siri öffnen das
Detail statt direkt die Kasse; Codes mit Leerzeichen ohne Hinweis; „Wiederherstellen“ im Einstieg ohne Rückmeldung zum Sync.

**Ziel erreicht in Beta-Runde 9:** Ø 9,25/10 und 18/20 (90 %) aktive Weiterempfehlung (NPS 9–10).
Weiterempfehlung hier streng als NPS 9–10 gezählt; nach Gesamtnote 9–10 sind es ebenfalls 18/20. Alle Personen sind simuliert.
Zwischen Beta 4 und 5 kamen die gewünschten Funktionen dazu: Speichern mit einem Tipp, Mindestbestellwert, iPad-Version,
eigene Gutscheine ausgeben (Cafés) und Warnung bei Betrugsmuster; danach Mehrfach-Fotoauswahl, Dubletten-Erkennung,
Bilanz für Fotoreihen, Kontrast-Ränder und ein einheitliches Wort „Guthaben“.

## Nachweise
- **Barcodes an der Kasse:** Die App zeichnet alle 11 Arten (EAN-13, EAN-8, UPC-A, ITF, Code 39, Code 128, QR, PDF417, Aztec, Data Matrix);
  Apples Barcode-Erkennung liest die Kassen-Screenshots 12/12 exakt zurück (`ios/scripts/barcode-kasse-test.sh`).
  Rücklesetests (Vision) sind dauerhaft in den Unit-Tests (`BarcodeRoundTripTests`).
- **Einscannen:** Im Simulator liest die App EAN-13, Code 128, QR, PDF417 und Aztec direkt von den Testgutscheinen
  (Vision Revision 1 als Ausweg ohne Neural Engine, CoreImage für QR). Auf dem Mac liest dieselbe Vision-API wie auf dem iPhone alle 8 Barcodes.
- **Texterkennung:** Golden-Set mit echter Vision-Texterkennung aller 12 Bildgutscheine, Regel-Parser ohne KI: 12/12.
- **Unit-Tests:** 139/139 grün (Dateischutz der Fotos gilt auf iPhone/iPad; auf dem Mac ohne, damit die Tests nicht vom gesperrten Bildschirm abhängen).
- **Kassen-Rücklesung:** Code 128 und alle Strichcodes werden auf ganze Bildschirmpixel gerastert gezeichnet; 12/12 weiter exakt gelesen.

## Wichtigste gefundene und behobene Fehler
- KI erfand Gutscheine („Milch“ aus einer Einkaufsliste); Angaben der KI werden nur noch übernommen, wenn sie wortgenau im Text stehen.
- App-Sperre öffnete ohne Gerätecode ohne Prüfung; Code-Schutz ließ sich über Foto, Bearbeiten, Export, Suche, Kontextmenü und Kopieren umgehen.
- Data Matrix wurde nicht als Barcode gezeichnet (eigener ECC-200-Encoder); Leerzeichen wurden aus Code 39/128 entfernt; ITF wurde still mit 0 aufgefüllt.
- Laufzeiten „ab Ende des Jahres“ falsch berechnet; Kassenbons, Ausweise, Kontoauszüge galten als Gutscheine; MwSt als Rabatt; Laufzeit als Betrag.
- Server nahm weiter Konten und Gutschein-Kopien an (Registrierung/Upload jetzt 410; nicht deployt).

## Offen (Betreiber / echtes Gerät)
- Barcode-Test an einer echten Kasse und mit echtem iPhone-Scanner; VoiceOver/Face ID auf echtem Gerät.
- Impressum, Verantwortlicher, Hosting, Löschdatum für Altkonten; Server-Deploy; DB-Tests (Docker).
- Wünsche für später: Teilen-Erweiterung für markierten Mail-Text, Wallet-Pass, XCUITest-Target und dokumentierter Accessibility-Audit.
