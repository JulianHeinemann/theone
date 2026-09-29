# Restwert – iOS-App

SwiftUI-App für iOS 26 für Gutscheine: scannen, Restwert führen, einlösen, Ablauf-Radar, Bon.
Gebaut mit Swift 6, Liquid Glass und Apple Intelligence (wo verfügbar).

## Aufs iPhone bringen

Du brauchst einen Mac mit **Xcode 26 oder neuer** und ein iPhone mit **iOS 26 oder neuer**. Ein kostenloser Apple-Account reicht.

1. Ordner `ios/` auf den Mac holen (Git oder ZIP) und **`Restwert.xcodeproj`** doppelklicken. Xcode lädt das lokale Paket `RestwertKit` automatisch.
2. Links das Projekt **Restwert** wählen → Target **Restwert** → Tab **Signing & Capabilities**:
   - **Team**: deine Apple-ID wählen (unter Xcode → Settings → Accounts hinzufügen, falls leer).
   - **Bundle Identifier**: auf etwas Eigenes ändern, z. B. `de.deinname.restwert`.
3. iPhone per Kabel anschließen, entsperren, „Diesem Computer vertrauen“.
4. Auf dem iPhone **Entwicklermodus** einschalten: Einstellungen → Datenschutz & Sicherheit → Entwicklermodus → an, Neustart.
5. Oben in Xcode dein iPhone als Ziel wählen und **▶ Run** (⌘R) drücken.
6. Beim ersten Start auf dem iPhone: Einstellungen → Allgemein → VPN & Geräteverwaltung → deinem Entwickler-Zertifikat vertrauen.

Mit kostenlosem Account läuft die App 7 Tage, danach einfach erneut aus Xcode starten.

## Funktionen

- **Scannen** (eigener Tab): Live-Kamera (Barcode + Text inkl. Handschrift), Foto/Screenshot, PDF/Datei, E-Mail-Text, manuell.
  Aus Mail: Anhang teilen → Restwert. Danach Ergebnis mit Echtheits-Hinweis → Hinzufügen oder erneut scannen.
  Auf Geräten mit Apple Intelligence liest das On-Device-Modell Shop, Wert, Code, PIN und Ablaufdatum zusätzlich zum Regel-Parser.
- **Arten**: Geschenkkarte, Wertgutschein, Rabattcode, eigener Gutschein, Coupon.
- **Detail**: Restwert groß, Status (Gültig, Läuft bald ab, Eingelöst, Abgelaufen), Gültig bis, Resttage, ursprünglicher Wert, Anzahl Einlösungen,
  Aufbewahrungsort mit Notiz (Sheet), Barcode im Originalformat + Code kopieren, Teileinlösung per Schieberegler/Schnellwahl mit Abriss-Animation,
  Rabattcodes „Als eingelöst markieren“ mit Stempel, Einlöse-Verlauf, Gutschein entfernen, PIN hinter Face ID.
- **An der Kasse**: großer Barcode, Helligkeit automatisch auf Maximum, Kassentest (geklappt/abgelehnt).
- **Ablauf-Radar**: Punkte auf Ringen (30 T, 90 T, 6 M, 1 J), Größe = Restwert, darunter Zeitstrahl nach Monaten.
- **Verlauf (Bon)**: alle Einlösungen über alle Gutscheine mit Summe, antippbar.
- **Einstellungen**: optional „Mit Apple anmelden“ (nur lokal), iCloud-Sync, Sortierung (Ablaufdatum, Wert, Shop), Warnfrist in Tagen, Erinnerungen 30/7 Tage vorher, Export.

Daten liegen auf dem Gerät (`Application Support/restwert.json`, Dateischutz `completeFileProtection`).
Mit iCloud-Sync gehen sie Ende-zu-Ende verschlüsselt in die private CloudKit-Datenbank des Nutzers, ohne Fotos; PINs nur in den iCloud-Schlüsselbund. Kein eigener Server.

## Projekt

```
ios/
├── Restwert/                 App (synchronisierter Ordner, neue Dateien erscheinen automatisch)
│   ├── App/                  Einstieg, Navigation, Store, Apple-Anmeldung + iCloud-Sync
│   ├── Design/               Farben, Bausteine, Ordnerkarte
│   ├── Services/             Vision-Import, Apple Intelligence, Barcode-Darstellung
│   └── Features/             Home, Radar, Detail, Kasse, Verlauf, Händler, Einstellungen, Scan, Formular, Onboarding
└── Packages/RestwertKit/     Modelle, Textparser, Barcode-Kodierung, Sync-Logik – mit Swift-Testing-Tests
```

- Swift 6 mit `MainActor` als Standard-Isolation; Analyse läuft mit `@concurrent` im Hintergrund.
- Tests für die Logik: `cd Packages/RestwertKit && swift test`.
- UI-Tests (XCUITest, Simulator): `xcodebuild test -project Restwert.xcodeproj -scheme RestwertUITests -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` – Einstieg mit Anmeldeseite, Vorder- und Rückseite scannen, Barrierefreiheits-Audit (Apple) für Start, Einstellungen und Kasse; bewusst hingenommene Audit-Befunde stehen mit Begründung in `RestwertUITests/RestwertUITests.swift`.
- Barcodes an der Kasse Ende-zu-Ende: `scripts/barcode-kasse-test.sh <Simulator-UDID>`, Screenshots danach mit Vision zurücklesen.
- Alternativ mit [XcodeGen](https://github.com/yonaskolb/XcodeGen): `xcodegen generate` im Ordner `ios/` erzeugt das Projekt aus `project.yml`.
