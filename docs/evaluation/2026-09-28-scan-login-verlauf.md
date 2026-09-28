# Scan, Barcodes, Login und neue Funktionen: Verlauf über 14 Testrunden (27./28.09.2026)

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
- **Unit-Tests:** 137/137 grün (Dateischutz der Fotos gilt auf iPhone/iPad; auf dem Mac ohne, damit die Tests nicht vom gesperrten Bildschirm abhängen).
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
