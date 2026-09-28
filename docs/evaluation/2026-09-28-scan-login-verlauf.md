# Scan, Barcodes und Login: Verlauf über 9 Testrunden (27./28.09.2026)

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

Ziel (> 9/10, > 80 % Weiterempfehlung) ist **nicht erreicht**. Seit Beta 2 steigen die Werte nur noch in kleinen Schritten.
Was die Tester für eine 9–10 nennen, ist inzwischen überwiegend neue Funktion (iPad-Version, Aussteller-Funktion für Cafés,
Speichern mit einem Tipp, Feld für Mindestbestellwert) oder außerhalb der App (echtes iPhone an echter Kasse, Server/Impressum).

## Nachweise
- **Barcodes an der Kasse:** Die App zeichnet alle 11 Arten (EAN-13, EAN-8, UPC-A, ITF, Code 39, Code 128, QR, PDF417, Aztec, Data Matrix);
  Apples Barcode-Erkennung liest die Kassen-Screenshots 12/12 exakt zurück (`ios/scripts/barcode-kasse-test.sh`).
  Rücklesetests (Vision) sind dauerhaft in den Unit-Tests (`BarcodeRoundTripTests`).
- **Einscannen:** Im Simulator liest die App EAN-13, Code 128, QR, PDF417 und Aztec direkt von den Testgutscheinen
  (Vision Revision 1 als Ausweg ohne Neural Engine, CoreImage für QR). Auf dem Mac liest dieselbe Vision-API wie auf dem iPhone alle 8 Barcodes.
- **Texterkennung:** Golden-Set mit echter Vision-Texterkennung aller 12 Bildgutscheine, Regel-Parser ohne KI: 12/12.
- **Unit-Tests:** 116 (113 grün, solange der Mac gesperrt ist: drei Foto-Datei-Tests brauchen `.completeFileProtection`, das macOS bei gesperrtem Bildschirm verweigert; entsperrt 116/116).

## Wichtigste gefundene und behobene Fehler
- KI erfand Gutscheine („Milch“ aus einer Einkaufsliste); Angaben der KI werden nur noch übernommen, wenn sie wortgenau im Text stehen.
- App-Sperre öffnete ohne Gerätecode ohne Prüfung; Code-Schutz ließ sich über Foto, Bearbeiten, Export, Suche, Kontextmenü und Kopieren umgehen.
- Data Matrix wurde nicht als Barcode gezeichnet (eigener ECC-200-Encoder); Leerzeichen wurden aus Code 39/128 entfernt; ITF wurde still mit 0 aufgefüllt.
- Laufzeiten „ab Ende des Jahres“ falsch berechnet; Kassenbons, Ausweise, Kontoauszüge galten als Gutscheine; MwSt als Rabatt; Laufzeit als Betrag.
- Server nahm weiter Konten und Gutschein-Kopien an (Registrierung/Upload jetzt 410; nicht deployt).

## Offen (Betreiber / echtes Gerät / neue Funktionen)
- Barcode-Test an einer echten Kasse und mit echtem iPhone-Scanner; VoiceOver/Face ID auf echtem Gerät.
- Impressum, Verantwortlicher, Hosting, Löschdatum für Altkonten; Server-Deploy; DB-Tests (Docker).
- iPad-Version, Speichern mit einem Tipp, Mindestbestellwert, Funktionen für Aussteller, PINs im Schlüsselbund mit Zugriffskontrolle.
