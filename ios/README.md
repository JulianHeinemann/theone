# Restwert – iOS-App

SwiftUI-App (iOS 17+) für Gutscheine: scannen, Restwert führen, einlösen, Ablauf-Radar, Bon.

## Aufs iPhone bringen

Du brauchst einen Mac mit **Xcode 16 oder neuer** und ein iPhone mit **iOS 17 oder neuer**. Ein kostenloser Apple-Account reicht.

1. Ordner `ios/` auf den Mac holen (Git oder ZIP) und **`Restwert.xcodeproj`** doppelklicken.
2. Links das Projekt **Restwert** wählen → Target **Restwert** → Tab **Signing & Capabilities**:
   - **Team**: deine Apple-ID wählen (unter Xcode → Settings → Accounts hinzufügen, falls leer).
   - **Bundle Identifier**: auf etwas Eigenes ändern, z. B. `de.deinname.restwert`.
3. iPhone per Kabel anschließen, entsperren, „Diesem Computer vertrauen“.
4. Auf dem iPhone **Entwicklermodus** einschalten: Einstellungen → Datenschutz & Sicherheit → Entwicklermodus → an, Neustart.
5. Oben in Xcode dein iPhone als Ziel wählen und **▶ Run** (⌘R) drücken.
6. Beim ersten Start auf dem iPhone: Einstellungen → Allgemein → VPN & Geräteverwaltung → deinem Entwickler-Zertifikat vertrauen.

Mit kostenlosem Account läuft die App 7 Tage, danach einfach erneut aus Xcode starten.

## Funktionen

- **Scannen**: Live-Kamera (Barcode + Text inkl. Handschrift, Apple Vision), Foto/Screenshot, PDF/Datei, E-Mail-Text einfügen, manuell.
  Aus Mail: Anhang teilen → Restwert. Danach Ergebnis mit Echtheits-Hinweis → Hinzufügen oder erneut scannen.
- **Arten**: Geschenkkarte, Wertgutschein, Rabattcode, eigener Gutschein, Coupon.
- **Detail**: Restwert groß, Status (Gültig, Läuft bald ab, Eingelöst, Abgelaufen), Gültig bis, Resttage, ursprünglicher Wert, Anzahl Einlösungen,
  Aufbewahrungsort mit Notiz (Sheet), Barcode im Originalformat + Code kopieren, Teileinlösung per Schieberegler/Schnellwahl mit Abriss-Animation,
  Rabattcodes „Als eingelöst markieren“ mit Stempel, Einlöse-Verlauf, Gutschein entfernen, PIN hinter Face ID.
- **An der Kasse**: großer Barcode, Helligkeit automatisch auf Maximum, Kassentest (geklappt/abgelehnt).
- **Ablauf-Radar**: Punkte auf Ringen (30 T, 90 T, 6 M, 1 J), Größe = Restwert, darunter Zeitstrahl nach Monaten.
- **Bon**: alle Einlösungen über alle Gutscheine mit Summe, antippbar.
- **Einstellungen**: Sortierung (Ablaufdatum, Wert, Shop), Warnfrist in Tagen, Erinnerungen 30/7 Tage vorher, Export.

Daten liegen nur auf dem Gerät (`Application Support/restwert.json`, Dateischutz `completeFileProtection`).

## Projekt

- Xcode-16-Projekt mit synchronisiertem Ordner: neue Dateien in `Restwert/` erscheinen automatisch.
- `Restwert-Info.plist` enthält nur die Dokumenttypen (PDF, Bild, Text) für „Teilen → Restwert“; alles andere wird generiert.
- Alternativ mit [XcodeGen](https://github.com/yonaskolb/XcodeGen): `xcodegen generate` im Ordner `ios/` erzeugt das Projekt aus `project.yml`.
