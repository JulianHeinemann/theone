# Datenhaltung: keine Gutscheindaten bei uns

Stand 26.09.2026. Ziel: Restwert betreibt **keine Datenbank mit Gutschein-, PIN- oder Zahlungsdaten**. Ein Einbruch bei uns kann keine Gutscheine offenlegen, weil dort keine liegen.

## iOS (umgesetzt)

| Was | Wo | Wer kann es lesen |
|---|---|---|
| Gutscheine, Verlauf, Kassentests | Lokal: `Application Support/restwert.json` mit `completeFileProtection` | Nur das entsperrte iPhone |
| Fotos der Karten | Nur lokal | Nur das iPhone |
| Sync zwischen Apple-Geräten (optional) | CloudKit, **private Datenbank des Nutzers**, Zone „Restwert“ | Niemand außer den Geräten des Nutzers – jeder Datensatz ist vorher mit AES-GCM-256 verschlüsselt (`CloudPayload`) |
| Sync-Schlüssel | iCloud-Schlüsselbund (`kSecAttrSynchronizable`) | Ende-zu-Ende verschlüsselt von Apple, auch ohne „Erweiterten Datenschutz“ |
| PINs | Einzeln im iCloud-Schlüsselbund (`PinVault`), nie in CloudKit | Wie oben |
| Sicherung | iPhone-Backup (iCloud/Finder) enthält die lokale Datei; zusätzlich Sicherungsdatei zum Selbst-Aufbewahren | Nutzer |
| Zahlungen (falls eingeführt) | StoreKit / In-App-Kauf | Apple; wir speichern nichts |

Record-Typen in CloudKit: `Card` (Feld `blob`: verschlüsselt, `modified`: Datum), `Test` (`blob`), `Tombstone` (`del-<UUID>`, markiert Löschungen). Der Server sieht nur Zufallsbytes und Zeitstempel.

Ablauf beim Abgleich (`CloudSync.syncNow`): iCloud-Status prüfen → Zone anlegen → alle Datensätze lesen → entschlüsseln → mit lokalem Stand zusammenführen (`SyncMerge`, neuere Änderung gewinnt) → Neues/Neueres hochladen (`CloudPlan`). Liegen in iCloud schon Daten, aber der Schlüssel ist auf dem neuen Gerät noch nicht angekommen, wartet die App („Warte auf den Schlüssel…“) statt einen zweiten Schlüssel zu erzeugen.

**Was ihr noch tun müsst:** Im Apple Developer Account die App-ID `de.restwert.app` mit iCloud/CloudKit aktivieren und den Container `iCloud.de.restwert.app` anlegen (automatische Signierung mit `-allowProvisioningUpdates` kann das beim ersten Archivieren erledigen). Danach im CloudKit-Dashboard das Schema nach Production deployen.

**Railway-Server:** Die App schickt keine Gutscheine mehr dorthin; er liefert nur noch Datenschutz- und Impressumsseite. Bestehende Konten und die Tabelle mit Gutscheinen können gelöscht werden.

## Android (Konzept)

Gleiches Prinzip, andere Bausteine:

| iOS | Android-Gegenstück |
|---|---|
| Lokale Datei mit Dateischutz | Room-Datenbank, verschlüsselt mit SQLCipher; Schlüssel im **Android Keystore** |
| CloudKit private DB | **Google Drive `appDataFolder`**: versteckter App-Ordner im Drive des Nutzers, nur für die App sichtbar. Eine Datei pro Gutschein oder eine verschlüsselte Gesamtdatei, vorher AES-GCM verschlüsselt (gleiches Format wie `CloudPayload`) |
| iCloud-Schlüsselbund für Sync-Schlüssel und PINs | **Google Block Store**: kleiner, Ende-zu-Ende verschlüsselter Speicher, der mit der Displaysperre gesichert in die Google-Cloud-Sicherung geht und auf ein neues Gerät wiederhergestellt wird |
| iPhone-Backup | **Android Auto Backup** (ab Android 9 Ende-zu-Ende verschlüsselt, wenn eine Displaysperre gesetzt ist) |
| StoreKit | **Google Play Billing** |
| Apple Wallet (PKPass) | **Google Wallet** Generic Pass – die JWT-Signatur braucht ein Dienstkonto; das geht zustandslos (signieren, nichts speichern) |
| Vision / VisionKit | ML Kit (Barcode Scanning, Text Recognition v2, on-device) |

Das gemeinsame Kernmodell (Gutschein, Parser, Barcode-Logik, Verschlüsselungsformat) sollte plattformneutral beschrieben und getestet sein, damit beide Apps dieselben Daten lesen können: AES-GCM mit 96-Bit-Nonce, Format `nonce ‖ ciphertext ‖ tag` (entspricht `AES.GCM.SealedBox.combined`), JSON mit ISO-8601-Datumsangaben.

## iPhone ↔ Android gemeinsam

Ohne eigenen Server gibt es keinen gemeinsamen Speicher zwischen iCloud und Google. Drei Wege, von einfach nach aufwendig:

1. **Übertragen statt synchronisieren:** Sicherungsdatei exportieren und auf dem anderen Gerät importieren (heute schon auf iOS vorhanden). Kein Server, deckt den Gerätewechsel ab.
2. **Nutzer-eigener Speicher:** Beide Apps schreiben die verschlüsselte Datei in einen Ordner, den der Nutzer wählt (iCloud Drive, Google Drive, Dropbox über den System-Dateiauswahldialog). Schlüssel einmalig per QR-Code von Gerät zu Gerät übertragen.
3. **Zero-Knowledge-Relay:** Ein kleiner Server speichert nur verschlüsselte Blöcke, deren Schlüssel er nie sieht (Schlüssel per QR-Code). Ein Einbruch dort legt keine Gutscheine offen, es ist aber wieder ein Server im Betrieb.

Empfehlung: Mit 1 starten, 2 nachziehen, 3 nur bei echtem Bedarf.
