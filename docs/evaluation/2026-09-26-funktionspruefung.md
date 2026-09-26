# Funktionsprüfung: 21 Funktionen, QA und Personas – 26.09.2026

> **Methode:** Je Funktion prüft ein QA-Agent den Code Szenario für Szenario (Datei und Zeile). 5 passende Personas aus dem 500er-Pool (Runde 4) spielen die Funktion aus ihrem Alltag durch. Jeder gemeldete Fehler wird von einem weiteren Agenten gegengeprüft, der ihn zu widerlegen versucht. **Simulierte Personas, keine echten Menschen; kein echtes Gerät.**

**Ergebnis:** 144 Fehler bestätigt, 6 widerlegt.

## Matrix

| Funktion | Status | Personas | Nutzen | Wichtigstes Problem |
|---|---|---|---|---|
| Onboarding und erster Start | funktioniert mit Mängeln | 5 von 5 geschafft, alle 5 bei den Beispielkarten mit Mühe | 5.8 | Ist die Datendatei nicht lesbar (z. B. Start im Hintergrund bei gesperrtem Gerät), gilt das als erster Start. Dann ersetzen Beispielkarten die eigenen Gutscheine. Außerdem kann man das Onboarding nicht scrollen: Text und bei großer Schrift auch der Button werden abgeschnitten. |
| Start: Summe, Liste, Filter, Suche | kaputt | 3 von 5 geschafft (alle mit Mühe), 2 gescheitert (kein Android; Langdruck-Menü nicht gefunden) | 5.2 | Blocker: Ist die Datendatei nicht lesbar, werden Beispielkarten angelegt, und die nächste Speicherung überschreibt die echten Gutscheine. Außerdem bleibt ein Filter aktiv, auch wenn sein Chip verschwindet. Dann ist die Liste leer und man kommt nicht mehr heraus. |
| Hinzufügen: Live-Scan und Fallback | funktioniert mit Mängeln | 5 von 5 geschafft, 4 davon mit Mühe | 6.2 | Bei jedem alphanumerischen Barcode, QR-, PDF417- und Aztec-Code erscheint fälschlich „Prüfziffer stimmt nicht“. Der Live-Scan setzt die Textzeilen in zufälliger Reihenfolge zusammen. |
| Import aus Foto, Mail-Text, PDF/Datei, Teilen | funktioniert mit Mängeln | 4 von 5 geschafft (alle mit Mühe), 1 gescheitert (Android) | 5.8 | Der Text-Parser liest falsch: „Wert“ ohne Wortgrenze, 19 % MwSt wird zum Rabattcode, Kundennummer wird zum Code, „gültig vom X bis Y“ ergibt das Anfangsdatum. Beim Import über Teilen bricht die App ihren eigenen Task ab. |
| Schnellerfassung (neues Formular) | funktioniert mit Mängeln | 5 von 5 geschafft, 4 davon mit Mühe | 7 | „Gültig bis“ = heute wird als „vor dem Erhalt-Datum“ abgelehnt. „Erhalten am“ überschreibt ein gescanntes Ablaufdatum. Beim Bearbeiten lässt sich das Foto nicht entfernen. |
| Bearbeiten und PIN-Schutz im Formular | funktioniert mit Mängeln | 5 von 5 geschafft, alle 5 mit Mühe | 6 | Beim Bearbeiten kann man keine neue PIN eintippen, weil das Feld nach der ersten Ziffer sperrt. „Foto entfernen“ wird beim Speichern ignoriert. |
| Gutschein-Detail | kaputt | 5 von 5 geschafft, alle mit Mühe (Erinnerung und Aufbewahrungsort schwer zu finden) | 7.6 | Blocker: Die App stürzt ab, wenn man eine eigene Erinnerung für einen Gutschein setzt, der heute abläuft. Das Status-Badge ist im Dunkelmodus kaum lesbar. |
| An der Kasse | funktioniert mit Mängeln | 4 von 5 geschafft (3 mit Mühe), 1 gescheitert (Nummer verdecken nicht gefunden); 1 Persona braucht die Kasse nicht (nur online) | 6.6 | Die PIN erscheint an der Kasse ohne Face ID. Im Vollbild-Barcode gehen Helligkeit und Displaysperre zurück. „Bezahlt“ mit leerem Betrag speichert ohne Rückmeldung. |
| Tastenfeld: Einkauf abziehen / Neuer Stand | funktioniert mit Mängeln | 5 von 5 geschafft, alle 5 mit Mühe | 6.4 | Einen neuen Stand von 0,00 € kann man nicht eintragen. Die Nachfrage „Betrag offen“ wird nicht gelöscht. Bei großer Schrift wird der Bestätigungsbutton abgeschnitten. |
| Rabattcodes und Coupons einlösen | funktioniert mit Mängeln | 4 von 5 geschafft (alle mit Mühe), 1 gescheitert (kein Feld für Besitzer/Herkunft) | 5.2 | Ein Doppeltipp auf „Als eingelöst markieren“ löst den Code zweimal ein, und man kann das Einlösen nicht zurücknehmen. |
| Erinnerungen und Mitteilungen | kaputt | 4 von 5 geschafft (alle mit Mühe bei der Uhrzeit), 1 gescheitert („Morgen erinnern“ nicht gefunden) | 7.8 | Blocker: Absturz bei einer eigenen Erinnerung am Ablauftag. Ist kein Vorlauf gewählt, bekommt trotzdem jeder Gutschein eine Mitteilung. Vertagte Erinnerungen kommen auch nach dem Ausschalten und für archivierte oder gelöschte Karten. |
| Ablauftermine | funktioniert | 3 von 5 geschafft (alle mit Mühe bei der Monatssumme), 2 gescheitert (Android; Gutscheine nach Besitzer trennen) | 5.4 | Die Monatssumme hat keine Beschriftung, ist klein und grau, und es wird nicht erklärt, dass Rabattcodes und Verschenk-Gutscheine fehlen (confirmed minor). |
| Verlauf (Bon) und Kassentests | funktioniert mit Mängeln | 5 von 5 geschafft, alle 5 mit Mühe (Summe, Teilen) | 5.4 | SUMME verrechnet Aufladungen und Korrekturen und kann negativ werden. Die Summe hat kein Vorzeichen und keine Beschriftung, und am Bon selbst gibt es keinen Teilen-Knopf. |
| Händlerliste | funktioniert | 5 von 5 geschafft, 4 davon mit Mühe | 5.6 | Die Link-Etiketten passen teils nicht zum Prüfweg (IKEA: „online prüfen“, braucht aber Login). Die Suche findet keine Umlautvarianten und nichts bei Leerzeichen am Ende. Lokale und Sammelgutscheine fehlen. |
| Archiv, Entfernen, Wiederherstellen, Rückgängig | funktioniert mit Mängeln | Kernablauf 5 von 5 geschafft, aber alle 5 scheitern am fehlenden Rückgängig nach Archivieren/Entfernen | 5.6 | Das Einspielen einer Sicherung bringt entfernte Gutscheine nie zurück, meldet aber Erfolg. Der Timer eines alten Toasts schließt den neuen. Nach Archivieren oder Entfernen gibt es kein Rückgängig. |
| Einstellungen: Anzeige und Sicherheit | kaputt | 4 von 5 geschafft (3 mit Mühe), 1 gescheitert (Nummer verdecken mit Lupe/VoiceOver) | 5 | Blocker: Die PIN erscheint an der Kasse ohne Face ID, obwohl „PIN mit Face ID schützen“ an ist. Die App-Sperre liegt unter Sheets. Die Wiederherstellung nach „Alles löschen“ übernimmt nichts. |
| Sicherung, CSV, Wiederherstellen | funktioniert mit Mängeln | 5 von 5 geschafft, 4 davon mit Mühe (Bereich nur nach Scrollen sichtbar) | 4.6 | Die Wiederherstellung nach „Alles löschen“ stellt nichts wieder her, meldet aber Erfolg. In Excel werden lange Kartennummern zerstört. Die Sicherungsdatei enthält die PINs unverschlüsselt. |
| iCloud-Sync mit eigener Verschlüsselung | kaputt | 4 von 5 geschafft (alle mit Mühe), 1 gescheitert (Teilen mit der Partnerin nicht möglich) | 4.8 | Blocker: Nach „Daten aus iCloud löschen“ funktioniert der Sync nie wieder. Geänderte oder gelöschte PINs werden zurückgeschrieben. Die Kopfzeile „Nichts verlässt dein iPhone“ widerspricht dem eingeschalteten Schalter. |
| Widget und Deep Link | funktioniert mit Mängeln | 4 von 5 geschafft (alle mit Mühe), 1 gescheitert (Widget ohne Hilfe nicht einrichtbar) | 6.8 | Das Widget zählt die Tage nicht herunter und zeigt abgelaufene Gutscheine weiter an. Die Summe enthält Beispielkarten. |
| Barrierefreiheit: Dunkelmodus, große Schrift, VoiceOver | funktioniert mit Mängeln | 4 von 5 geschafft (alle mit Mühe), 1 gescheitert (Zloty-Gutscheine nicht abbildbar) | 6.8 | Eine geänderte Textgröße löscht alle Eingaben. Das Status-Etikett ist im Dunkelmodus unlesbar. Die Tab-Leiste wächst nicht mit und verdeckt die letzte Karte. VoiceOver sagt „Betrag offen“ nicht an. |
| Datenschutz: Manifest, Texte, Erklärseite | funktioniert mit Mängeln | 4 von 5 geschafft (3 mit Mühe), 1 gescheitert (Face-ID-Texte auf einem Touch-ID-Gerät) | 6 | Die Aussage „PINs nur im Schlüsselbund“ ist falsch: Die PINs liegen im Klartext-JSON und kommen über den Sync zurück. Der Satz „auch wir nicht / Apple auch nicht“ ignoriert das iCloud-Backup. |

## Zusammenfassung

Die 21 Funktionen von Restwert decken das Konzept gut ab. Am meisten Nutzen sahen die Personas bei den Erinnerungen (7,8/10), im Gutschein-Detail (7,6) und in der Schnellerfassung (7,0). Am wenigsten nützlich fanden sie Sicherung und CSV (4,6), den iCloud-Sync (4,8) und die Sicherheitseinstellungen (5,0).

Wegen bestätigter Blocker gelten 5 Funktionen als kaputt:
- Start/Laden: Ist die Datendatei nicht lesbar, überschreiben Beispielkarten die echten Gutscheine.
- Detail und Erinnerungen: Die App stürzt bei einer eigenen Erinnerung am Ablauftag ab.
- Sicherheit: Die PIN erscheint an der Kasse ohne Face ID.
- iCloud-Sync: Nach „Daten aus iCloud löschen“ funktioniert er dauerhaft nicht mehr.

14 Funktionen laufen mit Mängeln, nur Ablauftermine und Händlerliste haben ausschließlich kleine Fehler. Datenschutz und Sicherheit haben dabei mehr Probleme als die Texte versprechen: PINs liegen im Klartext-JSON, gelöschte PINs kommen per Sync zurück, und nach „Alles löschen“ meldet die Wiederherstellung Erfolg, stellt aber nichts wieder her.

Die Personas schafften die Kernabläufe meist, aber oft mit Mühe. Das sind die häufigsten Stolpersteine:
- Schwebende Tab-Leiste und fehlende Skalierung bei großer Schrift
- Graue Kleinschrift mit zu wenig Kontrast
- Beispielkarten, die wie echtes Geld wirken
- Kein Rückgängig nach Archivieren und Entfernen
- Aktionen, die nur per Langdruck erreichbar sind
- Die widersprüchliche iCloud-Kopfzeile

Gescheitert sind Personas vor allem an:
- fehlendem Android
- fehlender Lokalisierung
- Touch ID gegen Face-ID-Texte
- fehlendem Teilen mit Partner oder Familie

Empfohlene Reihenfolge:
1. Die Blocker beheben: Laden, DatePicker-Absturz, PIN an der Kasse, Sync-Zone.
2. Die übrigen Datenschutz-Fehler (major) beheben.
3. Die UX-Befunde mit P1 umsetzen: Tab-Leiste und Kontrast, Beispiel-Banner, Rückgängig überall, sichtbare Aktionen, ehrliche iCloud-Anzeige, Widget-Tage.
4. Formularklarheit und Lokalisierung angehen.

## Bestätigte Fehler

Status: ⏳ in Arbeit (7 Reparaturpakete)

| Schwere | Funktion | Ort | Fehler |
|---|---|---|---|
| blocker | f02 Start: Summe, Liste, Filter, Suche | `Store.swift:38` | Bei nicht lesbarer Datendatei werden Beispielkarten angelegt, die nächste Speicherung überschreibt die echten Gutscheine |
| blocker | f07 Gutschein-Detail | `CardDetailView.swift:205` | Absturz bei eigener Erinnerung für Gutschein, der heute abläuft |
| blocker | f11 Erinnerungen und Mitteilungen | `CardDetailView.swift:205` | Absturz: Eigene Erinnerung am Ablauftag (ungültiger DatePicker-Bereich) |
| blocker | f16 Einstellungen: Anzeige und Sicherheit | `CheckoutView.swift:163` | PIN an der Kasse wird ohne Face ID angezeigt, obwohl „PIN mit Face ID schützen“ an ist |
| blocker | f18 iCloud-Sync mit eigener Verschlüsselung | `CloudSync.swift:121` | Nach 'Daten aus iCloud löschen' funktioniert der Sync nie wieder (Zone wird nicht neu angelegt) |
| major | f01 Onboarding und erster Start | `OnboardingView.swift:17` | Onboarding nicht scrollbar: Text wird abgeschnitten, bei großer Schrift auch der Button |
| major | f01 Onboarding und erster Start | `Store.swift:38` | Datei nicht lesbar wird als erster Start behandelt: Beispielkarten ersetzen die eigenen Gutscheine (Widget, Anzeige, Überschreiben) |
| major | f02 Start: Summe, Liste, Filter, Suche | `HomeView.swift:48` | Gewählter Filter bleibt aktiv, wenn sein Chip oder die ganze Filterleiste verschwindet: Liste leer ohne Ausweg |
| major | f03 Hinzufügen: Live-Scan und Fallback | `BarcodeEncoder.swift:20` | Falsche Warnung 'Prüfziffer stimmt nicht' bei jedem nicht rein numerischen Barcode (Code 128 alphanumerisch, QR, PDF417, Aztec) |
| major | f03 Hinzufügen: Live-Scan und Fallback | `LiveScannerView.swift:121` | Live-Scan setzt die Textzeilen in zufälliger Reihenfolge zusammen |
| major | f04 Import aus Foto, Mail-Text, PDF/Datei, Teilen | `ScanView.swift:91` | Import über Teilen/Öffnen-in bricht seinen eigenen Task ab |
| major | f04 Import aus Foto, Mail-Text, PDF/Datei, Teilen | `ScanView.swift:92` | Geteiltes PDF bleibt unsichtbar, wenn das Formular offen ist |
| major | f04 Import aus Foto, Mail-Text, PDF/Datei, Teilen | `Importer.swift:152` | Hochformat-Fotos werden mit 3-facher Auflösung neu gerendert (Speicherspitze, Absturzgefahr) |
| major | f04 Import aus Foto, Mail-Text, PDF/Datei, Teilen | `TextParser.swift:78` | „Wert“ ohne Wortgrenze: Mindestbestellwert oder Datum wird zum Gutscheinwert |
| major | f04 Import aus Foto, Mail-Text, PDF/Datei, Teilen | `TextParser.swift:65` | Beliebige Prozentangabe (z. B. 19 % MwSt) macht aus einem Wertgutschein einen Rabattcode |
| major | f04 Import aus Foto, Mail-Text, PDF/Datei, Teilen | `TextParser.swift:100` | Kunden- oder Bestellnummer wird als Gutscheincode übernommen |
| major | f04 Import aus Foto, Mail-Text, PDF/Datei, Teilen | `TextParser.swift:92` | „gültig vom X bis Y“ ergibt das Anfangsdatum als Ablauf |
| major | f05 Schnellerfassung (neues Formular) | `CardFormView.swift:431` | Foto lässt sich beim Bearbeiten nicht entfernen |
| major | f05 Schnellerfassung (neues Formular) | `CardFormView.swift:105` | „Erhalten am“ überschreibt ein schon gesetztes oder gescanntes „Gültig bis“ |
| major | f05 Schnellerfassung (neues Formular) | `CardFormView.swift:399` | „Gültig bis“ = heute wird als „vor dem Erhalt-Datum“ abgelehnt |
| major | f05 Schnellerfassung (neues Formular) | `CardFormView.swift:141` | Barcode-Typ bleibt nach Artwechsel Code → Karte auf „Text“ |
| major | f06 Bearbeiten und PIN-Schutz im Formular | `CardFormView.swift:299` | Neue PIN lässt sich beim Bearbeiten nicht eintippen: Feld sperrt sich nach der ersten Ziffer |
| major | f06 Bearbeiten und PIN-Schutz im Formular | `CardFormView.swift:431` | Foto entfernen wird beim Speichern ignoriert |
| major | f07 Gutschein-Detail | `CardDetailView.swift:160` | „Nicht bezahlt“ / „Jetzt eintragen“ löschen die geplante Nachfrage-Mitteilung nicht |
| major | f07 Gutschein-Detail | `CheckoutView.swift:341` | Neuen Stand 0 € kann nicht eingetragen werden |
| major | f07 Gutschein-Detail | `MerchantMark.swift:118` | Status-Badge auf der Karte im Dunkelmodus kaum lesbar |
| major | f07 Gutschein-Detail | `CardDetailView.swift:197` | Eigene Erinnerung ohne Mitteilungs-Berechtigung wirkungslos und ohne Hinweis |
| major | f08 An der Kasse | `CheckoutView.swift:94` | Vollbild-Barcode setzt Helligkeit und Displaysperre zurück |
| major | f08 An der Kasse | `CheckoutView.swift:163` | PIN an der Kasse ohne Face ID sichtbar |
| major | f08 An der Kasse | `CheckoutView.swift:198` | 'Bezahlt' mit leerem, 0- oder ungültigem Betrag speichert stumm und lässt 'Betrag offen' stehen |
| major | f08 An der Kasse | `Store.swift:181` | Rabattcode/Coupon wird nach 'Bezahlt' nicht eingelöst |
| major | f09 Tastenfeld: Einkauf abziehen / Neuer Stand | `CheckoutView.swift:341` | Neuer Stand 0,00 € (Bon zeigt leer) kann nicht eingetragen werden |
| major | f09 Tastenfeld: Einkauf abziehen / Neuer Stand | `Store.swift:124` | Nachfrage-Mitteilung 'Betrag offen' wird nach dem Eintragen nicht gelöscht |
| major | f09 Tastenfeld: Einkauf abziehen / Neuer Stand | `CheckoutView.swift:266` | Tastenfeld-Ansicht nicht scrollbar – Bestätigungsbutton bei großer Schrift abgeschnitten |
| major | f10 Rabattcodes und Coupons einlösen | `CardDetailView.swift:335` | Doppeltipp auf 'Als eingelöst markieren' löst den Code zweimal ein |
| major | f11 Erinnerungen und Mitteilungen | `Store.swift:320` | Ohne gewählte Vorlaufzeit bekommt jeder Gutschein eine 'läuft bald ab'-Mitteilung |
| major | f11 Erinnerungen und Mitteilungen | `Store.swift:302` | Ausschalten der Erinnerungen lässt vertagte ('-snooze') Erinnerungen stehen |
| major | f11 Erinnerungen und Mitteilungen | `Store.swift:302` | Vertagte Erinnerung kommt auch für archivierte, gelöschte oder eingelöste Gutscheine |
| major | f11 Erinnerungen und Mitteilungen | `Store.swift:142` | „Betrag offen“-Nachfrage kommt, obwohl der Betrag schon eingetragen ist |
| major | f11 Erinnerungen und Mitteilungen | `RestwertApp.swift:331` | Tippen auf Mitteilung beim Kaltstart öffnet den Gutschein nicht |
| major | f13 Verlauf (Bon) und Kassentests | `BonView.swift:32` | SUMME rechnet Aufladungen und Korrekturen gegen und kann negativ werden |
| major | f15 Archiv, Entfernen, Wiederherstellen, Rückgängig | `RestwertApp.swift:274` | Abgebrochener Timer des alten Toasts schließt sofort den neuen Toast |
| major | f15 Archiv, Entfernen, Wiederherstellen, Rückgängig | `Store.swift:237` | Sicherung einspielen bringt entfernte Gutscheine nie zurück, meldet sie aber als übernommen |
| major | f15 Archiv, Entfernen, Wiederherstellen, Rückgängig | `Store.swift:150` | Rückgängig nach Aufladung setzt den Startwert nicht zurück |
| major | f16 Einstellungen: Anzeige und Sicherheit | `Store.swift:197` | Wiederherstellen nach „Alles löschen“ übernimmt keinen Gutschein, meldet aber Erfolg |
| major | f16 Einstellungen: Anzeige und Sicherheit | `RestwertApp.swift:117` | App-Sperre liegt unter geöffneten Sheets und Vollbildansichten |
| major | f16 Einstellungen: Anzeige und Sicherheit | `CheckoutView.swift:145` | „Nummer verdecken“ wirkt nicht bei Textcodes und nicht im Vollbild |
| major | f16 Einstellungen: Anzeige und Sicherheit | `SettingsView.swift:40` | PIN-Schutz und App-Sperre lassen sich ohne Face ID ausschalten |
| major | f17 Sicherung, CSV, Wiederherstellen | `Store.swift:237` | Wiederherstellen nach "Alles löschen" stellt nichts wieder her, meldet aber Erfolg |
| major | f17 Sicherung, CSV, Wiederherstellen | `Store.swift:223` | CSV: lange Kartennummern werden in Excel zerstört (Exponentialschreibweise, führende Nullen) |
| major | f18 iCloud-Sync mit eigener Verschlüsselung | `Sync.swift:42` | Geänderte PIN kommt auf anderen Geräten nie an und wird zurückgeschrieben |
| major | f18 iCloud-Sync mit eigener Verschlüsselung | `Store.swift:53` | Gelöschte PIN taucht nach dem nächsten Sync wieder auf |
| major | f18 iCloud-Sync mit eigener Verschlüsselung | `CloudSync.swift:108` | 'Daten aus iCloud löschen' lässt PINs und Schlüssel im iCloud-Schlüsselbund |
| major | f18 iCloud-Sync mit eigener Verschlüsselung | `Store.swift:196` | Kassentests kommen nach 'Alles löschen' per Sync zurück |
| major | f18 iCloud-Sync mit eigener Verschlüsselung | `Store.swift:237` | Sicherung einspielen nach 'Alles löschen' übernimmt nichts, meldet aber N Gutscheine |
| major | f19 Widget und Deep Link | `RestwertWidget.swift:49` | Widget zählt Tage nicht herunter und zeigt abgelaufene Gutscheine weiter an |
| major | f19 Widget und Deep Link | `WidgetBridge.swift:25` | Widget-Summe enthält Beispielkarten, obwohl eigene Gutscheine vorhanden sind |
| major | f20 Barrierefreiheit: Dunkelmodus, große Schrift, VoiceOver | `MerchantMark.swift:120` | Status-Etikett auf der Markenkarte ist im Dunkelmodus kaum lesbar |
| major | f20 Barrierefreiheit: Dunkelmodus, große Schrift, VoiceOver | `RestwertApp.swift:112` | Geänderte Textgröße löscht alle Eingaben und Navigationszustände |
| major | f20 Barrierefreiheit: Dunkelmodus, große Schrift, VoiceOver | `CardRow.swift:46` | VoiceOver sagt 'Betrag offen' in der Kartenzeile nicht an |
| major | f21 Datenschutz: Manifest, Texte, Erklärseite | `CheckoutView.swift:163` | Kasse zeigt PIN ohne Face ID, obwohl 'PIN mit Face ID schützen' aktiv ist |
| major | f21 Datenschutz: Manifest, Texte, Erklärseite | `Store.swift:56` | Aussage 'PINs nur im Schlüsselbund, nie in einer Datenbank' ist falsch: PINs liegen im Klartext-JSON |
| major | f21 Datenschutz: Manifest, Texte, Erklärseite | `Store.swift:72` | Gelöschte PIN wird bei aktivem iCloud-Sync wiederhergestellt |
| major | f21 Datenschutz: Manifest, Texte, Erklärseite | `CloudSync.swift:121` | Nach 'Daten aus iCloud löschen' schlägt erneutes Einschalten des Syncs dauerhaft fehl |
| minor | f01 Onboarding und erster Start | `OnboardingView.swift:11` | Beispielkarte „Café am Markt“ in der Vorschau schon bei Standardschrift abgeschnitten |
| minor | f01 Onboarding und erster Start | `RestwertApp.swift:108` | Nach „Einführung ansehen“ führt „Los geht's“ zurück in die Einstellungen statt zu Start |
| minor | f01 Onboarding und erster Start | `Store.swift:270` | Beispielkarten mit Empfangsdatum in der Zukunft beim ersten Start in der ersten Jahreshälfte |
| minor | f02 Start: Summe, Liste, Filter, Suche | `HomeView.swift:47` | „X laufen bald ab“ im Summenkopf ändert sich mit Filter und Suche, Summe und Kartenzahl nicht |
| minor | f02 Start: Summe, Liste, Filter, Suche | `HomeView.swift:52` | Suche ohne Treffer zeigt keinen Hinweis |
| minor | f02 Start: Summe, Liste, Filter, Suche | `HomeView.swift:133` | VoiceOver sagt nicht an, welcher Filter-Chip aktiv ist |
| minor | f02 Start: Summe, Liste, Filter, Suche | `HomeView.swift:246` | Bei großer Schrift fehlt im Summenkopf der Hinweis auf Rabattcodes |
| minor | f03 Hinzufügen: Live-Scan und Fallback | `LiveScannerView.swift:174` | UPC-E wird als UPC-A übernommen: falsche Prüfziffer-Warnung und kein Barcode |
| minor | f03 Hinzufügen: Live-Scan und Fallback | `LiveScannerView.swift:75` | Fallback meldet 'Kamera nicht freigegeben', obwohl die Freigabe erteilt ist |
| minor | f03 Hinzufügen: Live-Scan und Fallback | `LiveScannerView.swift:51` | Foto-Fallback im Live-Scanner: Ladefehler ohne Hinweis, gleiches Foto nicht erneut wählbar |
| minor | f03 Hinzufügen: Live-Scan und Fallback | `LiveScannerView.swift:71` | Erklärtext im Kamera-Fallback wird bei großer Schrift abgeschnitten |
| minor | f04 Import aus Foto, Mail-Text, PDF/Datei, Teilen | `Models.swift:487` | Tausenderpunkt ohne Nachkommastellen: „1.000 €“ wird zu 1,00 € |
| minor | f04 Import aus Foto, Mail-Text, PDF/Datei, Teilen | `CardFormView.swift:352` | Format „Nur Text“ für Rabattcode wird durch onChange(merchantID) wieder überschrieben |
| minor | f04 Import aus Foto, Mail-Text, PDF/Datei, Teilen | `SmartExtractor.swift:46` | Von der KI erkannter unbekannter Shopname geht verloren |
| minor | f04 Import aus Foto, Mail-Text, PDF/Datei, Teilen | `ScanView.swift:72` | Import-Fehler werden verschluckt, ohne Hinweis |
| minor | f04 Import aus Foto, Mail-Text, PDF/Datei, Teilen | `RestwertApp.swift:113` | Textgröße ändern verwirft das angezeigte Ergebnis und laufende Importe |
| minor | f05 Schnellerfassung (neues Formular) | `CardFormView.swift:107` | Manuell gewählter Barcode-Typ wird bei einer Ladenänderung überschrieben |
| minor | f05 Schnellerfassung (neues Formular) | `CardFormView.swift:423` | „Guthaben jetzt“ beim Bearbeiten ändert das Guthaben ohne Verlaufseintrag |
| minor | f05 Schnellerfassung (neues Formular) | `CardFormView.swift:394` | Negatives „Guthaben jetzt“ wird angenommen |
| minor | f05 Schnellerfassung (neues Formular) | `CardFormView.swift:397` | Rabatt unter 1 % wird entgegen der Fehlermeldung akzeptiert |
| minor | f06 Bearbeiten und PIN-Schutz im Formular | `CardFormView.swift:374` | Betrag korrigieren lässt das alte Guthaben stehen: Karte wirkt teilweise benutzt |
| minor | f06 Bearbeiten und PIN-Schutz im Formular | `CardFormView.swift:399` | 'Gültig bis' = Erhalt-Tag wird als Fehler abgelehnt (Uhrzeitvergleich) |
| minor | f06 Bearbeiten und PIN-Schutz im Formular | `CardFormView.swift:141` | Art wechseln Karte -> Code -> Karte verliert den Barcode-Typ |
| minor | f06 Bearbeiten und PIN-Schutz im Formular | `CardFormView.swift:372` | Code nachträglich ergänzen: Barcode-Typ bleibt 'Text' |
| minor | f07 Gutschein-Detail | `CardDetailView.swift:196` | Standard-Erinnerungszeit ist 00:00 Uhr nachts |
| minor | f07 Gutschein-Detail | `MerchantMark.swift:116` | „noch 1 Tage“ / „noch 0 Tage“ im Karten-Badge |
| minor | f07 Gutschein-Detail | `MerchantMark.swift:113` | BalanceCard ignoriert große Schrift (Dynamic Type) |
| minor | f07 Gutschein-Detail | `CardDetailView.swift:132` | PIN bleibt nach App-Wechsel ohne erneute Face-ID-Abfrage sichtbar |
| minor | f07 Gutschein-Detail | `Store.swift:112` | Entfernen lässt die PIN im iCloud-Schlüsselbund zurück |
| minor | f07 Gutschein-Detail | `CardDetailView.swift:140` | „Guthaben prüfen“ bei Händlern, die nur eine Info-Seite haben |
| minor | f07 Gutschein-Detail | `CardDetailView.swift:102` | „Einlösungen“ zählt Aufladungen und Korrekturen mit |
| minor | f07 Gutschein-Detail | `CardFormView.swift:485` | VoiceOver liest Schließen-Knopf im Foto-Vollbild als „Foto des Gutscheins“ |
| minor | f08 An der Kasse | `Store.swift:142` | 'Später eintragen'-Erinnerung wird nie gelöscht |
| minor | f08 An der Kasse | `CheckoutView.swift:202` | Rückgängig nach 'Bezahlt' lässt den Kassentest stehen |
| minor | f08 An der Kasse | `CheckoutView.swift:193` | Toast verspricht Erinnerung auch ohne Mitteilungs-Erlaubnis |
| minor | f08 An der Kasse | `BarcodeView.swift:81` | Vollbild für Text-Codes im Dunkelmodus weiß auf weiß |
| minor | f09 Tastenfeld: Einkauf abziehen / Neuer Stand | `Store.swift:150` | Rückgängig nach Aufladung lässt erhöhten Ursprungswert stehen |
| minor | f09 Tastenfeld: Einkauf abziehen / Neuer Stand | `Store.swift:147` | Rückgängig stellt 'Betrag offen' nicht wieder her |
| minor | f10 Rabattcodes und Coupons einlösen | `BonView.swift:125` | Eingelöster Rabattcode steht im Verlauf mit 'Rest 0,00 €' |
| minor | f10 Rabattcodes und Coupons einlösen | `CardRow.swift:98` | Rabattcode mit Eurowert zeigt auf dem Etikett nur 'Rabattcode' |
| minor | f10 Rabattcodes und Coupons einlösen | `HomeView.swift:246` | Hinweis 'nicht in der Summe' fehlt bei großer Schrift |
| minor | f10 Rabattcodes und Coupons einlösen | `CardDetailView.swift:340` | Versehentliches 'Als eingelöst markieren' lässt sich nicht zurücknehmen |
| minor | f11 Erinnerungen und Mitteilungen | `Store.swift:320` | Ersatzerinnerung wird nach dem Auslösen immer wieder neu geplant |
| minor | f11 Erinnerungen und Mitteilungen | `RestwertApp.swift:325` | 'Morgen erinnern' übernimmt veralteten Titel und feuert auch nach Ablauf |
| minor | f11 Erinnerungen und Mitteilungen | `CardDetailView.swift:58` | Eigene Erinnerung lässt sich für Verschenk-Gutscheine und Beispiele setzen, wird aber nie geplant |
| minor | f11 Erinnerungen und Mitteilungen | `SettingsView.swift:30` | Keine Rückmeldung, wenn Mitteilungen nicht erlaubt sind |
| minor | f12 Ablauftermine | `RadarView.swift:30` | Monatssumme ignoriert 'Zum Verschenken'-Gutscheine, die in derselben Monatsgruppe angezeigt werden |
| minor | f12 Ablauftermine | `RadarView.swift:37` | Zoom-Übergang zum Detail hat in der Ablauftermin-Liste keine Quelle |
| minor | f13 Verlauf (Bon) und Kassentests | `BonView.swift:123` | Filialname wird je nach Schreibweise doch doppelt angezeigt |
| minor | f13 Verlauf (Bon) und Kassentests | `BonView.swift:167` | Leerer Filter zeigt „Noch keine Tests“, obwohl Tests vorhanden sind |
| minor | f13 Verlauf (Bon) und Kassentests | `BonView.swift:154` | Ohne Tests steht groß „0 von 0 Mal“ |
| minor | f13 Verlauf (Bon) und Kassentests | `BonView.swift:197` | Export ignoriert den Filter und gibt Beispiel-Tests als echte aus |
| minor | f14 Händlerliste | `Models.swift:111` | IKEA: Link heißt „Guthaben online prüfen“, der Tipp sagt „nur mit Login“ |
| minor | f14 Händlerliste | `Models.swift:116` | Hilfe- und FAQ-Seiten als Formular (.form) oder Kundenkonto (.account) eingestuft |
| minor | f14 Händlerliste | `MerchantsView.swift:13` | Suche findet nichts bei Leerzeichen am Ende (Autokorrektur) |
| minor | f14 Händlerliste | `MerchantsView.swift:13` | Suche beachtet Umlaute und Sonderzeichen: „Muller“, „mueller“, „hm“, „ca“ finden nichts |
| minor | f14 Händlerliste | `MerchantsView.swift:69` | Aktiver Kategorie-Filter wird VoiceOver nicht angesagt |
| minor | f14 Händlerliste | `MerchantsView.swift:82` | Kassentest-Bilanz 50 % wird grün (als gut) angezeigt |
| minor | f15 Archiv, Entfernen, Wiederherstellen, Rückgängig | `Store.swift:112` | Entfernte Gutscheine behalten ihre PIN im iCloud-Schlüsselbund |
| minor | f15 Archiv, Entfernen, Wiederherstellen, Rückgängig | `Store.swift:302` | Entfernen/Archivieren lässt die 'Betrag offen'-Nachfrage stehen |
| minor | f15 Archiv, Entfernen, Wiederherstellen, Rückgängig | `Store.swift:147` | Rückgängig stellt den Zustand 'Betrag offen' nicht wieder her |
| minor | f16 Einstellungen: Anzeige und Sicherheit | `RestwertApp.swift:123` | App-Übersicht zeigt Inhalt trotz App-Sperre |
| minor | f16 Einstellungen: Anzeige und Sicherheit | `RestwertApp.swift:294` | Face ID startet beim Zurückkehren nicht von selbst |
| minor | f16 Einstellungen: Anzeige und Sicherheit | `Store.swift:196` | „Alles löschen“ lässt Nachfragen und PINs im iCloud-Schlüsselbund zurück |
| minor | f17 Sicherung, CSV, Wiederherstellen | `Store.swift:221` | CSV-Beträge hängen von der Gerätesprache ab statt deutsch formatiert zu sein |
| minor | f17 Sicherung, CSV, Wiederherstellen | `Store.swift:225` | CSV-Felder werden nicht maskiert (Anführungszeichen, Zeilenumbrüche) |
| minor | f17 Sicherung, CSV, Wiederherstellen | `Store.swift:239` | Erfolgsmeldung nennt die Zahl der Karten in der Datei, nicht die der übernommenen |
| minor | f18 iCloud-Sync mit eigener Verschlüsselung | `Sync.swift:60` | Zeitstempel verliert Sekundenbruchteile: jede Karte wird bei jedem Sync neu hochgeladen, Konflikte innerhalb einer Sekunde kippen |
| minor | f18 iCloud-Sync mit eigener Verschlüsselung | `CloudSync.swift:73` | Änderung während eines laufenden Syncs wird nicht hochgeladen |
| minor | f18 iCloud-Sync mit eigener Verschlüsselung | `CloudSync.swift:186` | Fehler bei einzelnen Datensätzen werden ignoriert: 'Abgeglichen' trotz gescheitertem Upload |
| minor | f18 iCloud-Sync mit eigener Verschlüsselung | `SettingsView.swift:172` | Kopfzeile zeigt 'Sicher in deinem iCloud' vor jeder Prüfung bzw. widerspricht dem Schalter |
| minor | f19 Widget und Deep Link | `RestwertWidget.swift:78` | Leerzustand auf dem Sperrbildschirm mit festem Schwarz kaum sichtbar |
| minor | f20 Barrierefreiheit: Dunkelmodus, große Schrift, VoiceOver | `CardRow.swift:15` | Archivierte Karte wird von VoiceOver wie eine gültige Karte vorgelesen |
| minor | f20 Barrierefreiheit: Dunkelmodus, große Schrift, VoiceOver | `HomeView.swift:133` | Filter-Chips geben ihren Auswahlzustand nicht an VoiceOver weiter |
| minor | f20 Barrierefreiheit: Dunkelmodus, große Schrift, VoiceOver | `MerchantMark.swift:116` | Markenkarte zeigt 'noch 0 Tage' am Ablauftag und 'noch 1 Tage' am Vortag |
| minor | f20 Barrierefreiheit: Dunkelmodus, große Schrift, VoiceOver | `HomeView.swift:177` | Entfernen-Knöpfe im Bereich Erledigt nennen die Karte nicht |
| minor | f20 Barrierefreiheit: Dunkelmodus, große Schrift, VoiceOver | `HomeView.swift:246` | Kompakte Summenkarte bei großer Schrift verliert Beschriftung und Rabattcode-Hinweis |
| minor | f20 Barrierefreiheit: Dunkelmodus, große Schrift, VoiceOver | `CheckoutView.swift:411` | Tastenfeld: gedrückte Taste im Dunkelmodus hell auf Gelb |
| minor | f21 Datenschutz: Manifest, Texte, Erklärseite | `SettingsView.swift:142` | 'Daten aus iCloud löschen' lässt PINs und Schlüssel im iCloud-Schlüsselbund |
| minor | f21 Datenschutz: Manifest, Texte, Erklärseite | `OnboardingView.swift:54` | Onboarding verspricht 'Niemand außer dir … auch wir nicht', obwohl das iCloud-Backup für Apple lesbar ist |

## UX-Befunde der Personas

| Prio | Funktion | Nennungen | Befund | Empfehlung |
|---|---|---|---|---|
| P1 | f02, f14, f16, f20 | 19 | Die schwebende Tab-Leiste verdeckt die letzte Karte oder Zeile, ihre Beschriftung wächst bei großer Schrift nicht mit, und die Filter-Chips werden rechts abgeschnitten (nicht erkennbar, dass man wischen kann). | Unter der Liste einen Innenabstand in Höhe der Tab-Leiste einplanen. Die Tab-Beschriftung an Dynamic Type anpassen. Die Chips bei großer Schrift umbrechen oder mit einem Fade-Hinweis zeigen, dass man scrollen kann. |
| P1 | f03, f04, f05, f09, f11, f12, f16, f20, f21 | 16 | Graue Nebentexte (Hinweise, Monatssummen, Unterzeilen, Datenschutzhinweise) sind zu klein und kontrastarm, besonders im Dunkelmodus und für ältere oder sehbehinderte Nutzer. | Die muted-Farbe auf mindestens 4,5:1 Kontrast anheben. Wichtige Werte wie Summen und Erklärungen zu Aktionen nicht in muted setzen und über .scaled mitwachsen lassen. |
| P1 | f10, f15 | 10 | Nach Archivieren, Entfernen und „Als eingelöst markieren“ gibt es kein Rückgängig, obwohl es nach einem Einkauf eines gibt. Nutzer erwarten dasselbe Sicherheitsnetz. | Den bestehenden Undo-Toast auch für Archivieren, Entfernen und Einlösen verwenden. Vorher den Toast-Timer-Bug beheben. |
| P1 | f01, f02, f14 | 9 | Die Beispielkarten sehen aus wie echtes Guthaben (136,25 € oben). Es gibt kein Beispiel-Etikett, „Beispielkarten entfernen“ steht grau ganz unten, und das Onboarding zeigt andere Beispiele als der Start. | Einen Banner „Das sind Beispiele“ mit „Entfernen“ direkt über der Summe einblenden, Beispielkarten sichtbar kennzeichnen und die Onboarding-Beispiele an die Startdaten angleichen. |
| P1 | f02, f15 | 9 | Kasse, Bearbeiten, Archivieren und Entfernen sind nur über langes Drücken erreichbar. Eine noch aktive Karte lässt sich in der Detailansicht nicht archivieren. | „Archivieren“ in die Detailansicht aufnehmen (Menü unter dem Stift), Swipe-Aktionen in der Liste ergänzen und beim ersten Mal einen einmaligen Hinweis auf das Langdruck-Menü zeigen. |
| P1 | f18, f21 | 9 | „Nur auf diesem iPhone – Nichts verlässt dein iPhone“ steht direkt über einem eingeschalteten iCloud-Schalter. Der Schalter bleibt ohne iCloud-Konto grün, „Jetzt abgleichen“ und „Löschen“ lassen sich trotzdem antippen. | Die Kopfzeile erst nach der Kontoprüfung setzen. Ohne Konto den Schalter deaktivieren oder zurücksetzen und die Aktionen ausgrauen. Den Statuswechsel für VoiceOver ansagen. |
| P1 | f19 | 4 | Das Widget zeigt veraltete Resttage („in 5 Tagen“ noch Tage später) und eine Summe mit Beispielkarten, dadurch geht das Vertrauen in die Zahl verloren. | Das Ablaufdatum statt daysLeft in widget.json speichern und die Tage im Widget je Timeline-Eintrag berechnen. Die Summe mit demselben Filter wie die Liste bilden. |
| P2 | f04, f05, f06 | 12 | Die Arten Karte/Gutschein/Code/Andere sind unklar („Code“ ist doppelt belegt). Die Artwahl steckt unter „Mehr“, obwohl sie bestimmt, welche Felder erscheinen. | Die Artwahl nach oben ziehen, die Optionen mit kurzen Beispielen beschriften (z. B. „Guthabenkarte“, „Papiergutschein“, „Rabattcode %“) und das Feld „Code oder Kartennummer“ umbenennen. |
| P2 | f12, f13 | 11 | Summen sind nicht beschriftet: Die Monatssumme erklärt nicht, dass Rabattcodes fehlen, und SUMME im Bon hat kein Vorzeichen, obwohl die Posten eines haben. | Beschriftungen wie „Guthaben, das verfällt“ und „Eingelöst gesamt“ verwenden und „+ 1 Rabattcode“ bei der Monatssumme anzeigen. |
| P2 | f08, f16 | 9 | „Nummer verdecken“ gibt es nur in den Einstellungen. An der Kasse fehlt ein Schalter, VoiceOver kann die Nummer nicht aufdecken, und der Zweck ist unklar. | Den Schalter zusätzlich an der Kasse anbieten, die maskierte Nummer als Button mit Hinweis umsetzen und in der Einstellung erklären, wozu sie dient (Schutz vor Blicken in der Schlange). |
| P2 | f04, f05, f06 | 8 | Der Aufklapper „Mehr/Weniger“ versteckt oft gebrauchte Felder wie „Guthaben jetzt“ und PIN. Die Beschriftung „Weniger“ sagt nichts aus. | „Guthaben jetzt“ und PIN immer anzeigen. Den Aufklapper „Weitere Angaben (Für wen, Ort, Barcode-Typ …)“ nennen. |
| P2 | f04, f07, f09, f10, f11, f19, f20 | 8 | Die App gibt es nur auf Deutsch. Nutzer mit englischer, arabischer, türkischer, russischer, ukrainischer oder polnischer Systemsprache kommen nur mit Mühe zurecht. | Die Strings in einen String Catalog auslagern und zuerst Englisch lokalisieren. Danach Türkisch, Arabisch, Russisch und Ukrainisch prüfen. |
| P2 | f02, f04, f07, f10, f12, f18 | 8 | Es fehlt eine geteilte Liste für Partner, Familie oder Assistenz sowie ein Feld „gehört wem / von wem“. | Als Roadmap-Thema prüfen: CloudKit-Sharing einer Zone und ein Besitzerfeld, das sich vom Feld „Für wen“ unterscheidet. |
| P2 | f08, f11 | 7 | Erinnerungen gibt es nur zu einer festen, vollen Stunde, die Nachfrage kommt fest um 9 Uhr. Das passt nicht zu Schichtarbeit, und an der Kasse sieht man nicht, wann nachgefragt wird. | Minutengenaue Uhrzeit und eigene Ruhezeiten erlauben. Den Hinweis „Wir fragen um HH:MM nach“ direkt bei „Später eintragen“ zeigen. |
| P2 | f06 | 5 | Im Formular gibt es nur unten einen Speichern-Knopf, und das X verwirft Änderungen ohne Rückfrage. | Einen „Sichern“-Knopf in die Toolbar setzen und bei geänderten Feldern vor dem Verwerfen nachfragen (interactiveDismissDisabled plus Dialog). |
| P2 | f05 | 5 | Beim Neuanlegen heißt das Formular „Bearbeiten“. | Beim Neuanlegen den Titel „Neuer Gutschein“ verwenden. |
| P2 | f09 | 5 | Der Unterschied zwischen „Einkauf abziehen“ und „Neuen Stand eintragen“ ist unklar. Der graue Knopf „Erst Betrag wählen“ wirkt kaputt, beim Überbetrag fehlt „Rest bar zahlen“, und das Rückgängig verschwindet zu schnell. | Unter jedem Reiter einen Satz zur Erklärung zeigen. Den Knopftext „Betrag eintippen“ verwenden, beim Überbetrag „Rest zahlst du anders“ ergänzen und den Toast auf 12 bis 15 Sekunden verlängern oder Vorlesezeit bemessen. |
| P2 | f17 | 5 | Die Sicherung steht weit unten. iCloud-Backup, iCloud-Sync und Sicherungsdatei sind drei unklar abgegrenzte Wege. Die JSON-Datei enthält die PINs im Klartext und kann per Messenger geteilt werden. | Die Sicherung zusammen mit iCloud in einen Abschnitt „Daten sichern“ oben legen, die drei Wege in einer Übersicht erklären und die Sicherungsdatei optional mit Passwort verschlüsseln. |
| P2 | f16, f21, f06 | 4 | Überall steht „Face ID“, auch auf Geräten mit Touch ID (iPhone 8/SE) und iPad. Nutzer wissen dann nicht, ob der Schutz bei ihnen greift. | Den Text aus LAContext.biometryType ableiten (Face ID / Touch ID / Gerätecode). |
| P2 | f02, f20 | 3 | Bei großer Schrift verliert der kompakte Summenkopf die Überschrift und den Hinweis auf Rabattcodes. Nutzer wissen dann nicht, was die Zahl umfasst. | Beschriftung und Rabatt-Hinweis auch in der kompakten Variante zeigen (umbrechen statt weglassen). |
| P3 | f13, f14 | 8 | Einen Teilen-Knopf gibt es nur bei den Kassentests, nicht am Bon. Die Kassentests liegen im Verlauf statt beim Händler, und „Code 128“ ist Fachjargon. | Einen ShareLink am Bon sichtbar machen, die Kassentest-Bilanz auf der Händlerkarte zeigen und das Barcode-Format ausblenden oder übersetzen. |
| P3 | f04 | 6 | „Karte scannen“, „Aus Fotos“ und „Aus einer Datei“ sind schwer zu unterscheiden. Die PDF-Anleitung sieht antippbar aus, ist es aber nicht, und mehrere Fotos lassen sich nicht auf einmal wählen. | Die Einstiege mit Anwendungsbeispielen beschriften, den Anleitungskasten optisch als Hinweis gestalten und im PhotosPicker Mehrfachauswahl mit Stapelimport erlauben. |
| P3 | f07, f08 | 6 | „Nicht bezahlt“ im Banner ist doppeldeutig, und unklar bleibt, ob die Kasse ein Foto des Papiergutscheins annimmt. | „Doch nicht benutzt“ statt „Nicht bezahlt“ schreiben. Beim Foto-Ticket einen Hinweis wie „Viele Läden wollen das Original – nimm es sicherheitshalber mit“ zeigen, ergänzt um die Kassentest-Bilanz des Händlers. |
| P3 | f11 | 5 | „Morgen erinnern“ erreicht man nur durch langes Drücken auf die Mitteilung. | In der App einmal auf die Aktion hinweisen und alternativ in der Detailansicht „Später erinnern“ anbieten. |
| P3 | f03 | 5 | Das Wort „Simulator“ im Kamera-Fallback ist für Laien unverständlich, und der Knopf zu den Einstellungen ist kleiner als der Foto-Knopf. | Den Text ohne Entwicklerbegriffe formulieren und den Grund nennen. Bei verweigerter Erlaubnis den Einstellungen-Knopf zur Hauptaktion machen. |
| P3 | f07 | 4 | Eigene Erinnerung und Aufbewahrungsort stehen in der Detailansicht weit unten und werden übersehen. | Beide als kompakte Zeilen direkt unter die Guthabenkarte setzen. |
| P3 | f02 | 4 | Die Filter „Zum Verschenken“ und „Für X“ erscheinen erst, wenn es passende Daten gibt. Deshalb weiß niemand, dass es sie gibt. | Im Formular oder im leeren Zustand auf „Für wen“ und „Zum Verschenken“ hinweisen und optional eine eigene Summe „zum Verteilen“ anzeigen. |
| P3 | f02, f04, f12 | 3 | Es gibt keine Android-Version, daher bleibt ein Teil der Zielgruppe ganz ausgeschlossen. | Als strategische Entscheidung festhalten. Bis dahin im Store- und Web-Auftritt klar „nur iPhone“ angeben. |

## Widerlegte Meldungen

- f04: Ergebnisseite zeigt die erkannte PIN nicht – Die Beobachtung selbst stimmt: Das Raster in ScanResultView.swift:44-49 hat nur die Felder Wert, Gültig bis, Code und Format, und auch die Liste der Echtheits-Hinweise (checks, Zeilen 103-131) erwähnt draft.pin nie. Das ist aber kein Funktionsfehler. Der Text im Sheet (ScanView.swift:200) sagt nur, dass Restwert Shop, Wert, Code, PIN und Ablaufdatum „heraussucht“. Er verspricht nicht, dass die Ergebnisseite alle diese Felder anzeigt. Die PIN wird erkannt (TextParser.pin) und in den Entwurf übernommen. Laut Meldung erscheint sie im Formular, das auf „Hinzufügen“ folgt, und dort lässt sie sich vor dem Speichern prüfen und korrigieren. Es geht also keine Information verloren, und die Funktion ist nicht kaputt. Dass die PIN schon auf der Ergebnisseite zu sehen sein soll, ist ein UX-Wunsch und kein eindeutiger Fehler, deshalb real=false.
- f09: Schnellbetrag gleich Guthaben wird ausgeblendet – Der Code verhält sich wie beschrieben, das ist aber kein Fehler. In CheckoutView.swift:302 steht `[5.0, 10, 20].filter { $0 < card.balance }`, und direkt daneben steht immer der Chip „Alles“. Er setzt die Eingabe auf das volle Guthaben, hier also „10,00“. Bei genau 10,00 € Guthaben wäre ein Chip „10 €“ nur eine Kopie von „Alles“ mit demselben Betrag. Das strikte `<` verhindert diese Doppelung offenbar absichtlich. Man kann weiterhin genau 10 € mit einem Tipp abziehen. Es fällt keine Funktion weg und es entsteht kein falscher Betrag oder Zustand. Dass ein zusätzlicher „10 €“-Chip erwartet wird, ist eine Geschmacksfrage und kein nachweisbarer Defekt.
- f13: Nach dem Löschen einer Karte fehlen ihre Einlösungen im Verlauf – Der beschriebene Ablauf stimmt zwar: Die Einlösungen stecken in GiftCard.history, Store.delete (Store.swift:112) entfernt die ganze Karte, und Store.bonLines (Store.swift:88) baut CardQueries.bonLines(cards) nur aus den vorhandenen Karten. Nach dem Löschen fehlen ihre Posten also im Bon. Ein Fehler ist das aber nicht eindeutig, sondern eher gewolltes Verhalten. Beide Löschdialoge fragen ausdrücklich „Gutschein endgültig entfernen?“ (CardDetailView.swift:81, HomeView.swift:79). Für aufgebrauchte Gutscheine, deren Verlauf bleiben soll, bietet die App das Archivieren an (Store.setArchived, Archiv-Banner in CardDetailView). Archivierte Karten bleiben in cards, ihre Posten stehen also weiter im Bon. Der Kommentar in BonView Zeile 4 („jede Einlösung über alle Gutscheine“) passt zu „alle vorhandenen Gutscheine“. Das .disabled(store.card(line.cardID) == nil) in Zeile 96 ist nur eine Absicherung und belegt nicht, dass Posten gelöschter Karten aufbewahrt werden sollen. Dafür gibt es weder ein Datenmodell noch eine Speicherung, auch der Sync kennt nur deletedIDs. Dass Kassentests bleiben, liegt daran, dass sie getrennt gespeichert werden. Ein Widerspruch zu einer festgelegten Anforderung ergibt sich daraus nicht. Da nicht eindeutig: real=false.
- f14: „Deine Händler“ zählt Beispielkarten mit, Kassentests schließen Beispiele aus – This is not a clear bug. It is a deliberate difference in meaning. Line 24 in MerchantsView.swift does count example cards, but the rest of the app does the same. seedExamples (Store.swift:258ff) fills store.cards with IKEA, Thalia, Douglas, Amazon, Zalando and Stadtgutschein, all with isExample=true. activeCards, total and the wallet on HomeView show these cards as normal cards until the user taps "Beispielkarten entfernen". So "Deine Händler" matches the demo wallet the user sees. The demo is meant to show what the app looks like when it has content. Line 80 filters !isExample on purpose, because the label reads "Selbst getestet": a demo test was not run by the user, so leaving it out of that count is consistent, not a mistake. After clearExamples() the cards and tests disappear together (Store.swift:191-192), so nothing is left behind in an inconsistent state. The most this could be is a product decision about whether demo merchants should be grouped in a list, not a malfunction that clearly occurs in the code.
- f16: Aufdecken der verdeckten Nummer mit VoiceOver nicht möglich – Die Aussage „Aufdecken mit VoiceOver nicht möglich / volle Nummer nicht erreichbar“ stimmt so nicht.
1) Der Button direkt über dem Text (CheckoutView.swift:139-143, VoiceOver-Label „Barcode groß anzeigen“) öffnet FullBarcode. Dort steht in Zeile 428 ungekürzt `Text(card.number.grouped)`, unabhängig von maskNumber. VoiceOver-Nutzer kommen also mit einem Doppeltipp an die volle Nummer.
2) SwiftUI gibt die VoiceOver-Aktivierung (Doppeltipp) auf einem Element mit .onTapGesture normalerweise an die Tap-Geste weiter. Das Fokussieren und Doppeltippen auf den maskierten Text löst also sehr wahrscheinlich `numberShown = true` aus. Es fehlt nur das Button-Merkmal, VoiceOver sagt also nicht an, dass man hier aufdecken kann.
Übrig bleibt höchstens ein kleiner Mangel beim Bedienhinweis, aber nicht die gemeldete Unerreichbarkeit. Im Zweifel also nicht echt.
- f21: Widget-Datei ohne vollständigen Dateischutz, entgegen der Aussage auf der Erklärseite – Ich halte den Fehler für widerlegt. Der Satz auf der Erklärseite in SettingsView.swift:259 („Gutscheine, Fotos und Verlauf liegen in einer Datei, die iOS verschlüsselt, solange das iPhone gesperrt ist“) meint die eigentliche Datenbank-Datei. Die wird in Store.swift:57 mit [.atomic, .completeFileProtection] geschrieben, die Aussage stimmt also so, wie sie dasteht.

widget.json ist keine Gutschein-Datei, sondern eine kleine Zusammenfassung für das Widget. Laut Kommentar in WidgetBridge.swift enthält sie nur Namen, Überschrift, Resttage und Summe, keine Codes, PINs oder Fotos. Ohne vollen Dateischutz geschrieben ist sie mit Absicht: Das Widget für den Sperrbildschirm (Commit e9b00b9) muss sie lesen, während das Gerät gesperrt ist. Mit completeFileProtection könnte das Widget in RestwertWidget.swift:22 sie bei gesperrtem iPhone nicht mehr laden. Die vorgeschlagene Korrektur würde also das Widget kaputt machen.

Die CSV aus Store.swift (Zeilen 216–229) entsteht nur, wenn man selbst eine Liste zum Teilen exportiert. Die Erklärseite sagt nichts über Exporte, einen Widerspruch gibt es dort also nicht.
