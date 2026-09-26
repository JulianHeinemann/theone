# Nutzertest mit 50 Personas – 26.09.2026

> **Methode:** 50 simulierte Testpersonen (KI-Agenten mit je eigener Identität: Alter, Beruf, Technikaffinität, Situation, Bedürfnisse wie Sehschwäche oder Deutsch als Zweitsprache). Jede Persona hat 15 echte Simulator-Screenshots der App angesehen und 3 Alltagsaufgaben durchgespielt. Ein Auswertungs-Agent hat das Feedback zu Themen geclustert und gegen die Screenshots geprüft. **Keine echten Menschen** – die Ergebnisse ersetzen keinen Test mit echten Kundinnen und Kunden, zeigen aber verlässlich offensichtliche Hürden.

**Durchschnittsnote:** 6.4 / 10 · **würden die App nutzen:** 80 %

Rohdaten aller 50 Personas: [2026-09-26-persona-test-raw.json](2026-09-26-persona-test-raw.json)

## Aufgaben

| Aufgabe | gescheitert | mit Mühe |
|---|---|---|
| Einen neuen Gutschein erfassen (Karte in der Hand) | 0 | 13 |
| Gesamtes offenes Guthaben prüfen | 0 | 2 |
| App zum ersten Mal öffnen und verstehen | 0 | 0 |
| Nächsten verfallenden Gutschein finden | 0 | 0 |
| Douglas-Restguthaben online prüfen | 0 | 15 |
| Erinnerungen vor dem Ablauf einstellen | 0 | 9 |
| Thalia-Barcode zeigen und 12,60 € eintragen | 1 | 14 |
| Herausfinden, ob REWE Handy-Gutscheine annimmt | 0 | 15 |
| PIN einer Geschenkkarte ansehen | 0 | 1 |
| Abgelaufenen/aufgebrauchten Gutschein loswerden | 0 | 15 |

## Markiertes Feedback

Legende: ✅ umgesetzt · 🟡 teilweise umgesetzt · ⏳ offen · ✗ verworfen

| Status | Prio | Nennungen | Schwere | Thema | Umsetzung |
|---|---|---|---|---|---|
| ✅ | P1 | 27/50 | minor | Kalender-Symbol oben rechts auf Start ist nicht beschriftet und nicht als 'Ablauftermine' erkennbar | Toolbar-Icon entfernt; großer Button „Alle Ablauftermine“ unter der Liste. |
| ✅ | P1 | 21/50 | major | Kein erkennbarer Hinzufügen-Knopf: der Scan-Button unten rechts wirkt wie 'Barcode an der Kasse zeigen' | Tab heißt „Hinzufügen“ mit Plus-Symbol; zusätzlich „+“ oben rechts auf Start. |
| ✅ | P1 | 18/50 | major | Einlösen: Slider in 0,50-€-Schritten, Vorbelegung 10 € und 'Betrag genau eintippen' als blasser grauer Link | Slider und 10-€-Vorbelegung entfernt; Schnellbeträge als Auswahl, „Genauen Betrag eintippen“ als Button, Knopf zeigt „12,60 € abziehen“. |
| ✅ | P1 | 18/50 | minor | Unklar, ob der 15-%-Rabattcode in der Gesamtsumme steckt ('6 Gutscheine' vs. Eurosumme) | Unterzeile „5 Karten · 2 laufen bald ab“ plus „+ 1 Rabattcode, nicht in der Summe“. |
| ✅ | P1 | 14/50 | major | Barcode an der Kasse schwer zu erreichen: 'An der Kasse zeigen' steht unter dem Einlösen-Block, kein Schnellzugriff aus der Liste | „An der Kasse zeigen“ als schwarzer Hauptknopf direkt unter der Karte; langes Drücken auf eine Zeile in der Liste bietet es ebenfalls an. |
| 🟡 | P1 | 17/50 | major | Aufgebrauchte oder abgelaufene Gutscheine lassen sich nur ganz unten im Detail entfernen; kein Swipe, kein Archiv, keine Rubrik | Kontextmenü (Kasse, Bearbeiten, Entfernen) auf jeder Zeile; eingeklappte Sektion „Aufgebraucht & abgelaufen“ mit Papierkorb. Ein echtes Archiv (ausblenden statt löschen) fehlt noch. |
| ✅ | P1 | 8/50 | major | Betrag höher als das Restguthaben wird nur blockiert, ohne Lösung (Rest bar zahlen) | Keine Sperre mehr: Hinweis „Nur 12,40 € auf der Karte. 0,20 € zahlst du an der Kasse anders.“ und Knopf „Alles abziehen (12,40 €)“. |
| 🟡 | P1 | 16/50 | major | Hellgraue Kleinschrift (Ablaufdatum, 'Danach übrig', Feldlabels, Hinweise) ist für sehschwache Nutzer kaum lesbar | Grau (#696C74) und Orange (#B35F00) abgedunkelt, Sekundärtexte teils größer. Dynamic Type ist noch nicht durchgängig umgesetzt. |
| ✅ | P1 | 14/50 | major | 'Guthaben online prüfen' ist nur ein kleiner Textlink unter dem Barcode und wird leicht übersehen | Vollbreiter Button unter „An der Kasse zeigen“; Beschriftung je nach Händler (Formular / Kundenkonto / Info). |
| 🟡 | P1 | 17/50 | major | Erinnerungszeitpunkte (30/7 Tage, 10 Uhr) sind fest; nicht pro Gutschein änderbar | Neue Seite „Wann erinnern?“: 60/30/14/7/1 Tage und Uhrzeit wählbar. Eine eigene Erinnerung pro Gutschein fehlt noch. |
| ✅ | P1 | 6/50 | minor | Onboarding: Beispielkarten wirken wie echte Daten und widersprechen dem Start-Screen (IKEA 9 vs. 24 Tage) | Vorschau als „Beispiel“ gekennzeichnet, Datenschutz-Satz und PDF/Mail-Import ergänzt. |
| ✅ | P2 | 17/50 | minor | Kassen-Screen: nicht erkennbar, dass nach 'Geklappt' die Betragseingabe folgt; Folgen von 'Abgelehnt' unklar | „Geklappt – Betrag eintragen“ / „Abgelehnt – nur notieren“ plus Hinweis, dass Abgelehnt das Guthaben nicht ändert. |
| 🟡 | P2 | 16/50 | minor | Fach- und Doppelbegriffe schwer verständlich (Restwert/Restguthaben, 'Bald fällig' vs. 'Läuft bald ab', Code 128, § 195 BGB, eGift, Schere-Icon) | „Code 128“ entfernt, „Bald fällig“ zu „Läuft bald ab“ vereinheitlicht, Schere-Icon entfernt. BGB-Hinweis und Händlertexte noch offen. |
| ✅ | P2 | 12/50 | minor | Großer schwarzer 'Anmelden oder Konto erstellen'-Button dominiert die Einstellungen und weckt Datensammel-Verdacht | Schwarzer Button ersetzt durch „Deine Daten bleiben auf diesem iPhone“ und dezenten Link „Optional: Konto für mehrere Geräte“. |
| ⏳ | P2 | 14/50 | minor | Erfassungsformular lang; Rabattcode-Typ ('%') ist abgeschnitten und nicht als wischbar erkennbar | Offen. |
| 🟡 | P2 | 14/50 | minor | Händler (z. B. REWE) schwer auffindbar; Händler-Info nicht mit eigener Karte verknüpft | Sektion „Deine Händler“ oben in der Händlerliste; Händler-Hinweis erscheint jetzt im Kassen-Screen. Section-Index fehlt. |
| 🟡 | P3 | 11/50 | minor | Dringlichkeit und Status vor allem über Farbe (Orange, Grün, Rot) – schwach bei Rot-Grün-Schwäche | Uhr-/Warnsymbol vor „noch X Tage“ und „abgelaufen“, Papierkorb-Icon beim Entfernen. |
| ✅ | P3 | 5/50 | minor | Fortschrittsbalken in der Liste ohne Bezugswert ('von 40,00 €' fehlt) | „von 40,00 €“ steht wieder unter dem Betrag, Balken darunter. |
| 🟡 | P3 | 6/50 | minor | Wichtige Aktionen oben (Zurück, Stift, Suche, Kalender) einhändig schwer erreichbar | Ablauftermine und Kasse jetzt im unteren/mittleren Bereich; Zurück/Stift bleiben oben (System). |
| ⏳ | P3 | 11/50 | idee | Wünsche: Apple-Wallet-Export/Import, Mehrfach-Scan, Familienzuordnung | Backlog. |
| ✗ | – | 36/50 | minor | Schwebende Tab-Leiste verdeckt letzten Listeneintrag / Inhalte im Screenshot | Das ist Standardverhalten der iOS-26-Liquid-Glass-Tab-Leiste: Inhalt scrollt darunter durch. Die Screenshots sind statische Momentaufnahmen, gescrollt ist alles erreichbar (belegt durch 03_detail_b, wo 'Gutschein entfernen' frei über der Leiste steht). Der berechtigte Teil (kleiner Online-Prüflink) ist im Thema 'online-pruefen-link' erfasst. |
| ✗ | – | 15/50 | minor | Angst, 'Gutschein entfernen' versehentlich anzutippen | Unbegründet: CardDetailView.swift:64 zeigt vor dem Löschen einen confirmationDialog 'Gutschein endgültig entfernen?'. Die Personas konnten das auf den Screenshots nicht sehen. |
| ✗ | – | 4/50 | major | 'Guthaben online prüfen' fehlt im Kartendetail, nur im Händler-Tab | Faktisch falsch: 03_detail.png zeigt 'Guthaben online prüfen' unter dem Barcode (CardDetailView.swift:170, balanceURL). Die Personas haben den kleinen Link nur übersehen, das bestätigt aber das Sichtbarkeitsproblem. |
| ✗ | – | 7/50 | major | Kein Weg für PDF-Gutscheine aus E-Mail | 03_scan.png zeigt eindeutig 'Aus einer E-Mail' und 'Aus einer Datei – PDF oder Bild, z. B. aus einem Mail-Anhang' sowie den Share-Tipp. Die Funktion existiert, die berechtigten Teilpunkte sind in anderen Themen abgedeckt. |
| ✗ | – | 5/50 | minor | Filter-Chips in der Händlerliste rechts abgeschnitten | Das Anschneiden ist das beabsichtigte Scroll-Signal (Peek) für horizontal wischbare Chips und iOS-üblich. Die Hauptfilter 'Alle' und 'Am Handy vorzeigbar' sind voll sichtbar. Beim Formular-Typwechsel ist es anders, weil dort ein Pflichttyp versteckt ist (eigenes Thema). |
| ✗ | – | 4/50 | idee | Für 1–2 Gutscheine im Jahr zu viel App (Tabs, Kassentest, Verlauf) | Das ist eine Frage der Zielgruppenpassung, kein Usability-Fehler. Das Produkt richtet sich an Nutzer mit mehreren Karten, und Gelegenheitsnutzer profitieren bereits von den P1-Vereinfachungen. |
| ✗ | – | 1/50 | minor | Ablauftermine-Seite zeigt 'Start' als aktiven Tab | Korrektes Verhalten: Die Ablauftermine sind eine Push-Navigation innerhalb des Start-Stacks (NavigationLink Route.radar in HomeView), also bleibt 'Start' aktiv. |

## Details je Thema

### ✅ Kalender-Symbol oben rechts auf Start ist nicht beschriftet und nicht als 'Ablauftermine' erkennbar

*P1 jetzt umsetzen · 27 Nennungen · Screens: 02_start.png, 03_radar.png*

> Renate: 'Ich habe gedacht, es ist ein Kalender-Export.'

> Nina: 'Ich dachte, dort sind die Erinnerungen.'

> Dimitri: 'Einhändig komme ich da nicht hin, und ohne Beschriftung weiß ich auch nicht, was es tut.'

**Empfehlung:** Das Icon durch eine beschriftete Pille 'Ablauf' ersetzen oder unter 'Bald fällig' einen Link 'Alle Ablauftermine' setzen. Der liegt im Daumenbereich und macht das Toolbar-Icon überflüssig.

**Begründung:** Die Hälfte aller Personas nennt das, und der Aufwand ist minimal (ein Label bzw. ein zusätzlicher NavigationLink). Im Screenshot bestätigt: nur ein Icon ohne Text.

### ✅ Kein erkennbarer Hinzufügen-Knopf: der Scan-Button unten rechts wirkt wie 'Barcode an der Kasse zeigen'

*P1 jetzt umsetzen · 21 Nennungen · Screens: 02_start.png*

> Anna: 'Das Symbol sieht eher nach Barcode an der Kasse zeigen aus als nach neue Karte anlegen.'

> Lea: 'Ich hätte fast aufgegeben.'

> Tobias: 'Alle vier Tabs haben eine Beschriftung, nur der wichtigste Knopf ... ohne Text.'

**Empfehlung:** Beim abgesetzten Tab ein Plus-Symbol (z. B. 'plus.viewfinder') verwenden und ihn 'Hinzufügen' nennen, auch als accessibilityLabel. Zusätzlich auf Start ein '+'-Toolbar-Button und bei leerer oder Beispiel-Liste ein großer CTA 'Ersten Gutschein hinzufügen'.

**Begründung:** 13 von 15 Personas hatten beim Kern-Task 'Erfassen' Mühe. Das Problem ist im Screenshot klar zu sehen (barcode.viewfinder ohne Label) und kostet wenig Aufwand bei großer Wirkung.

### ✅ Einlösen: Slider in 0,50-€-Schritten, Vorbelegung 10 € und 'Betrag genau eintippen' als blasser grauer Link

*P1 jetzt umsetzen · 18 Nennungen · Screens: 03_detail_b.png, 03_detail_c.png*

> Hannah: 'beim Einlösen hätte ich aus Versehen 10 Euro statt 12,60 abgezogen.'

> Petra: 'Ich dachte, das ist nur ein Hinweis, kein Knopf.'

> Jan: 'Kassenbeträge sind fast nie glatt.'

**Empfehlung:** Den Einlösen-Block umbauen: Der Primärknopf 'Betrag eingeben' öffnet das Keypad (03_keypad), die Schnellbeträge bleiben als Chips. Den Slider entfernen oder ohne Vorbelegung (0 €) anzeigen. 'Einlösen' bleibt deaktiviert, bis ein Betrag gewählt ist.

**Begründung:** Hohe Häufigkeit und ein echtes Fehlbuchungsrisiko. Im Code bestätigt (Slider step 0.5, Label in Color.muted). Der Aufwand ist gering, weil das Keypad schon existiert.

### ✅ Unklar, ob der 15-%-Rabattcode in der Gesamtsumme steckt ('6 Gutscheine' vs. Eurosumme)

*P1 jetzt umsetzen · 18 Nennungen · Screens: 02_start.png*

> Tobias: 'Nachgerechnet: 20+23,85+12,40+50+30 = 136,25, der Code zählt also nicht mit. Das steht aber nirgends.'

> Ben: 'Ich traue der Summe nicht.'

> Finn: 'solange ich nicht weiß, was mit dem 15-%-Code passiert, rechne ich lieber selbst nach.'

**Empfehlung:** Die Unterzeile so formulieren: '5 Guthaben · 1 Rabattcode · 2 bald fällig'. Optional die Summe antippbar machen, dann erscheint eine Aufschlüsselung.

**Begründung:** Das Vertrauen in die Kernzahl leidet, und die Lösung ist eine reine Textänderung. Die Rechnung bestätigt: Die Summe schließt den Code aus.

### ✅ Barcode an der Kasse schwer zu erreichen: 'An der Kasse zeigen' steht unter dem Einlösen-Block, kein Schnellzugriff aus der Liste

*P1 jetzt umsetzen · 14 Nennungen · Screens: 03_detail.png, 03_detail_b.png, 03_detail_c.png, 02_start.png*

> Karl-Heinz: 'Wenn die Schlange wartet, drücke ich schnell mal das Falsche und buche Geld ab.'

> Marie: 'Wallet macht das mit einem Tap.'

> Sophie: 'Welchen soll ich an der Kasse nehmen?'

**Empfehlung:** 'An der Kasse zeigen' als Primärknopf direkt unter die Guthabenkarte setzen, oder als Toolbar-Button neben dem Stift. Der Einlösen-Block wandert darunter. In der Start-Liste ein contextMenu bzw. Swipe 'An der Kasse zeigen' und ab ca. 6 Karten eine Suche (.searchable) anbieten.

**Begründung:** Das ist der zentrale Nutzungsmoment an der Kasse. Die Reihenfolge ist in 03_detail_b bestätigt (gelber Einlösen-Knopf vor 'An der Kasse zeigen'). Der Umbau beschränkt sich auf eine Umsortierung.

### 🟡 Aufgebrauchte oder abgelaufene Gutscheine lassen sich nur ganz unten im Detail entfernen; kein Swipe, kein Archiv, keine Rubrik

*P1 jetzt umsetzen · 17 Nennungen · Screens: 03_detail_c.png, 02_start.png*

> Emre: 'zum Löschen muss ich bis ans Ende der Welt scrollen.'

> Aylin: 'Außerdem fehlt ein Archivieren statt Löschen, damit der Verlauf erhalten bleibt.'

> Karl-Heinz: 'Ich sehe keine Ecke, in der ich den Müll auf einen Blick finde.'

**Empfehlung:** In der Start-Liste .swipeActions und ein contextMenu mit 'Entfernen' und 'Archivieren' anbieten. Bei Guthaben 0 oder abgelaufenem Datum im Detail oben ein Banner 'Aufgebraucht – archivieren?'. Auf Start eine eingeklappte Sektion 'Aufgebraucht & abgelaufen'. Den Menüpunkt 'Entfernen' auch ins Stift-Menü.

**Begründung:** 15 von 15 Personas hatten beim Task Mühe. Im Code bestätigt: kein swipeActions in HomeView. Swipe bzw. Kontextmenü sind billig, das Archiv ist etwas mehr Aufwand.

### ✅ Betrag höher als das Restguthaben wird nur blockiert, ohne Lösung (Rest bar zahlen)

*P1 jetzt umsetzen · 8 Nennungen · Screens: 03_keypad.png*

> Nina: 'lässt mich die App einfach nicht weiter, und das passiert an der Kasse jeden Tag.'

> Olga: 'Ein Hinweis wie Nur 12,40 € möglich, Rest zahlst du an der Kasse fehlt.'

> Fatma: 'Der Button Abziehen ist blassgelb mit grauer Schrift, ich sehe kaum, ob er aktiv ist.'

**Empfehlung:** Bei Überbetrag statt der Sperre einen Hinweis zeigen: 'Nur 12,40 € auf der Karte – 0,20 € zahlst du anders' und einen Button '12,40 € abziehen (alles)'. Den deaktivierten Abziehen-Zustand kontrastreicher gestalten.

**Begründung:** Nina ist der einzige gescheiterte Task. Im Code bestätigt: Die Meldung 'Mehr als das Restguthaben' blockiert. Das ist ein Alltagsfall an der Kasse und schnell gelöst.

### 🟡 Hellgraue Kleinschrift (Ablaufdatum, 'Danach übrig', Feldlabels, Hinweise) ist für sehschwache Nutzer kaum lesbar

*P1 jetzt umsetzen · 16 Nennungen · Screens: 02_start.png, 03_detail_b.png, 03_detail_c.png, 03_form.png, 03_checkout.png, 03_merchants.png, 03_radar.png*

> Ingrid: 'Das Wichtigste, nämlich wann der Gutschein abläuft, steht in winziger grauer Schrift.'

> Svetlana: 'alles, was ich danach noch tun muss, ist klein und grau versteckt.'

> Fatma: 'alles Grüne und Graue drumherum muss ich mit der Lupe lesen'

**Empfehlung:** Den Color.muted-Token im Theme auf mindestens 4.5:1 Kontrast abdunkeln. Sekundärtexte ab 13 auf 15 pt anheben und mit Dynamic Type skalieren. Grünen Statustext ('Am Handy vorzeigbar') und Hinweiszeilen abdunkeln. Mit Accessibility-XXL-Schrift testen.

**Begründung:** Die Personas mit Sehschwäche nennen das fast durchgängig als 'major'. Die Screenshots bestätigen blasses Grau. Eine zentrale Token-Änderung wirkt auf alle Screens.

### ✅ 'Guthaben online prüfen' ist nur ein kleiner Textlink unter dem Barcode und wird leicht übersehen

*P1 jetzt umsetzen · 14 Nennungen · Screens: 03_detail.png, 03_merchants.png*

> Renate: 'Dabei ist genau das meine Hauptfrage bei 8 Karten aus der Schublade'

> Jürgen: 'Mit meinen Augen und Fingern treffe ich den nicht.'

> Jonas: 'das sollte ein richtiger Button sein.'

**Empfehlung:** Den Link aus dem Barcode-Ticket nehmen und als eigenen, vollbreiten Sekundärbutton ('Guthaben beim Händler prüfen') direkt unter der Guthabenkarte bzw. neben 'PIN anzeigen' platzieren. In der Händlerliste die Aktion als Button mit ausreichendem Tap-Target darstellen.

**Begründung:** 15 von 15 Personas hatten bei diesem Task Mühe. Der Link existiert zwar, ist in 03_detail aber klein und sitzt am Rand über der Tab-Leiste. Er muss nur verschoben und größer werden.

### 🟡 Erinnerungszeitpunkte (30/7 Tage, 10 Uhr) sind fest; nicht pro Gutschein änderbar

*P1 jetzt umsetzen · 17 Nennungen · Screens: 03_settings.png*

> Renate: 'um 10 Uhr schlafe ich nach der Nachtschicht'

> Kemal: 'wann die App mich erinnert, will ich selbst bestimmen, nicht um 10 Uhr, wenn ich im Transporter sitze.'

> Mehmet: 'warum darf ich nicht selbst festlegen, wann die App mich erinnert?'

**Empfehlung:** Die Einstellungszeile 'Ablauf-Erinnerungen' öffnet eine Unterseite mit Uhrzeit-Picker und Mehrfachauswahl der Vorlaufzeiten (60/30/7/1 Tag). Im Detail optional eine eigene Erinnerung pro Gutschein. Zudem erklären, wie sich die Vorlaufzeiten zur 'Läuft bald ab'-Grenze verhalten.

**Begründung:** Häufigster Feature-Wunsch, und er betrifft den Kern-Nutzen (Verfall verhindern). Der Aufwand ist mittel (Notification-Scheduling mit Parametern), der Nutzen hoch. Schichtarbeiter können die feste Zeit praktisch nicht nutzen.

### ✅ Onboarding: Beispielkarten wirken wie echte Daten und widersprechen dem Start-Screen (IKEA 9 vs. 24 Tage)

*P1 jetzt umsetzen · 6 Nennungen · Screens: 01_onboarding.png, 02_start.png*

> Anna: 'bei einer App, die mir Fristen erklären soll, sinkt da mein Vertrauen sofort.'

> Rainer: 'Ich dachte, die App hätte meine Karten irgendwoher.'

> Jürgen: 'Da sollte Beispiel dranstehen.'

**Empfehlung:** Die Onboarding-Vorschau aus denselben Beispieldaten wie den Store generieren, statt den String 'noch 9 Tage' hart zu codieren (OnboardingView.swift:9). Die Vorschau mit 'Beispiel' kennzeichnen. Einen Satz zum Datenschutz ergänzen ('Bleibt nur auf deinem iPhone') und PDF/Mail als Importweg nennen.

**Begründung:** Der Widerspruch ist im Code und in den Screenshots belegt. Die Korrektur ist trivial und stärkt das Vertrauen beim ersten Eindruck.

### ✅ Kassen-Screen: nicht erkennbar, dass nach 'Geklappt' die Betragseingabe folgt; Folgen von 'Abgelehnt' unklar

*P2 bald · 17 Nennungen · Screens: 03_checkout.png*

> Sophie: 'Barcode zeigen geht fix, aber danach 12,60 € eintragen dauert ewig – das muss direkt nach Geklappt kommen.'

> Olga: 'Wenn ich Abgelehnt drücke, weiß ich nicht, ob der Gutschein gelöscht oder nur markiert wird.'

> Ali: 'Welcher Weg ist der richtige?'

**Empfehlung:** Die Buttons eindeutig benennen: 'Geklappt – Betrag eintragen' und 'Abgelehnt – nur notieren'. Nach 'Geklappt' das Betragsfeld fokussieren und die Keypad-Schnellbeträge wiederverwenden. Einen Einzeiler ergänzen: 'Abgelehnt ändert dein Guthaben nicht'. Den Einlösen-Weg im Detail und im Kassen-Screen zu einem Flow zusammenführen.

**Begründung:** Teilweise ein Missverständnis: Laut CheckoutView.swift erscheint nach 'Geklappt' ein Feld 'Bezahlter Betrag, wird abgezogen'. Die Personas sahen nur den statischen Screenshot. Das eigentliche Problem ist die fehlende Vorankündigung und der doppelte Weg, beides mit Text leicht zu beheben. Deshalb 'minor' statt 'major'.

### 🟡 Fach- und Doppelbegriffe schwer verständlich (Restwert/Restguthaben, 'Bald fällig' vs. 'Läuft bald ab', Code 128, § 195 BGB, eGift, Schere-Icon)

*P2 bald · 16 Nennungen · Screens: 03_checkout.png, 03_form.png, 03_settings.png, 03_detail_c.png, 03_merchants.png*

> Sabine: '„Fällig“ kenne ich von Rechnungen, nicht von Gutscheinen.'

> Hannah: 'Code 128 verstehe ich nicht.'

> Leyla: 'Für mich einfacher: Guthaben überall gleich.'

**Empfehlung:** Einheitlich 'Guthaben' und 'Läuft bald ab' verwenden. Die Zeile 'Code 128' im Kassen-Screen entfernen (nur 'Helligkeit auf Maximum'). Den BGB-Hinweis vereinfachen: 'Meist 3 Jahre gültig' plus Info-Popover. Händlertexte kürzen und das Schere-Icon beim Einlösen durch ein neutrales Symbol ersetzen.

**Begründung:** Betrifft vor allem Zweitsprachler und ältere Personas. Das ist reine Copy-Arbeit mit geringem Aufwand, aber keine Blockade.

### ✅ Großer schwarzer 'Anmelden oder Konto erstellen'-Button dominiert die Einstellungen und weckt Datensammel-Verdacht

*P2 bald · 12 Nennungen · Screens: 03_settings.png, 02_start.png, 01_onboarding.png*

> Helga: 'als Erstes will die App, dass ich ein Konto mache. Da bin ich raus.'

> Karl-Heinz: 'bevor ich da meine PINs reinschreibe, will ich schwarz auf weiß sehen, wo die landen.'

> Renate: 'sollte aber wichtiger sein als die Werbung für ein Konto.'

**Empfehlung:** Den Konto-Button zu einem sekundären Link ('Optional: Konto für Sync') herabstufen. Die Zeile 'Alles liegt nur auf diesem iPhone' prominent machen, auch im Onboarding. Beim Link 'Guthaben online prüfen' darauf hinweisen, dass nur die Händlerseite geöffnet wird.

**Begründung:** Die datenskeptische Zielgruppe reagiert stark darauf, und drei Personas sagen deshalb ab. Der Hinweis 'Alles liegt nur auf diesem iPhone' ist zwar vorhanden, aber visuell untergeordnet. Die Änderung ist klein.

### ⏳ Erfassungsformular lang; Rabattcode-Typ ('%') ist abgeschnitten und nicht als wischbar erkennbar

*P2 bald · 14 Nennungen · Screens: 03_form.png*

> Doris: 'Genau den brauche ich für meine Rabattcodes, und ich wusste nicht, dass man seitlich wischen kann.'

> Anna: 'Ich will nur Shop, Betrag, Code.'

> Tobias: 'Wahlfelder sollten eingeklappt sein.'

**Empfehlung:** Die Typ-Auswahl als Segmented Control mit drei gleich breiten Segmenten gestalten (Karte / Gutschein / Rabattcode), damit nichts abgeschnitten wird. Optionale Felder (Barcode-Typ, Erhalten am, Ort, Notiz) unter 'Mehr Details' einklappen. 'Restwert' beim Neuanlegen automatisch aus 'Wert' übernehmen und kennzeichnen.

**Begründung:** Real im Screenshot, aber nicht blockierend. Der 'abgeschnittene Speichern-Button' ist dagegen normales Scroll-Verhalten des Sheets und wird nicht adressiert.

### 🟡 Händler (z. B. REWE) schwer auffindbar; Händler-Info nicht mit eigener Karte verknüpft

*P2 bald · 14 Nennungen · Screens: 03_merchants.png*

> Dimitri: 'Wichtige Hinweise wie bei REWE ... gehören als Warnung direkt auf den Kassen-Screen'

> Ali: 'Besser wäre ein Hinweis vorzeigbar direkt auf meiner Karte im Detail.'

> Moritz: 'Hier wäre eine Suche unten (wie in iOS-Safari) oder ein Alphabet-Index gut.'

**Empfehlung:** Oben in der Händlerliste eine Sektion 'Deine Händler' (Händler mit gespeicherten Karten) zeigen, darunter alphabetisch mit Section-Index. Den Händler-Status samt Hinweis ('nur Strich-Barcode zeigen') im Kartendetail und im Kassen-Screen anzeigen. Kompaktere Zeilen verwenden.

**Begründung:** Alle 15 Personas mit diesem Task hatten Mühe, aber die Suche existiert und funktioniert. Der Mehrwert liegt vor allem in der Verknüpfung mit der eigenen Karte. Mittlerer Aufwand.

### 🟡 Dringlichkeit und Status vor allem über Farbe (Orange, Grün, Rot) – schwach bei Rot-Grün-Schwäche

*P3 später · 11 Nennungen · Screens: 02_start.png, 03_merchants.png, 03_checkout.png, 03_settings.png*

> Tobias: 'Ein Symbol (Uhr oder Ausrufezeichen) wäre trotzdem robuster.'

> Nico: 'Ein klares Ja/Nein oder ein Haken wäre besser.'

> Ben: 'Ein Mülleimer-Symbol oder ein Button-Rahmen würde helfen.'

**Empfehlung:** Bei 'noch X Tage' ein Uhr- bzw. Ausrufezeichen-Icon und fette Schrift ergänzen. Für jeden Händlerstatus ein eigenes Symbol verwenden. Beim Entfernen-Button ein Papierkorb-Icon zeigen. Die Toggles bleiben System-Standard (iOS 'Ein/Aus-Beschriftungen' greift automatisch).

**Begründung:** Die Personas bestätigen selbst, dass der Text die Information schon trägt. Das ist eine Robustheitsverbesserung ohne akuten Fehler, günstig beim nächsten Design-Pass.

### ✅ Fortschrittsbalken in der Liste ohne Bezugswert ('von 40,00 €' fehlt)

*P3 später · 5 Nennungen · Screens: 02_start.png*

> Tobias: 'Ohne Zahl ist der Balken für mich nur Deko.'

> Jonas: 'Was der bedeutet (verbrauchter Anteil?), ist nicht beschriftet.'

> Luca: 'Es wird nicht erklärt, dass der Balken den verbrauchten Anteil zeigt.'

**Empfehlung:** Unter dem Betrag 'von 40,00 €' anzeigen, wie im Onboarding, und den Balken darunter behalten oder ersetzen.

**Begründung:** Geringe Häufigkeit, kleine Textänderung, nur ein Verständnisproblem.

### 🟡 Wichtige Aktionen oben (Zurück, Stift, Suche, Kalender) einhändig schwer erreichbar

*P3 später · 6 Nennungen · Screens: 02_start.png, 03_detail.png, 03_merchants.png, 03_form.png*

> Emre: 'Einhändig auf dem 17 Pro komme ich da nicht hin.'

> Rainer: 'die kleinen Knöpfe oben ... treffe ich mit einer Hand im Auto nicht.'

> Paul: 'Das Schließen-X liegt oben links, also weit weg vom Daumen.'

**Empfehlung:** Die Hauptaktionen in den unteren Bereich verlegen (siehe Kasse- und Kalender-Themen). In iOS 26 die Suche in die Tab-Leiste integrieren (Tab(role: .search)).

**Begründung:** Zurück-Swipe und Standard-Navigation bleiben verfügbar, das ist iOS-Konvention. Das Thema löst sich größtenteils mit P1 'Kasse' und 'Kalender'.

### ⏳ Wünsche: Apple-Wallet-Export/Import, Mehrfach-Scan, Familienzuordnung

*P3 später · 11 Nennungen · Screens: 02_start.png, 03_scan.png, 03_detail.png*

> Moritz: 'für zwei Gutscheine im Jahr bleibe ich bei Wallet, solange ich die Karten nicht dorthin schieben kann.'

> Anna: 'Ein Nächste Karte scannen wäre für mich das wichtigste Feature.'

> Mehmet: 'Eine Möglichkeit, Gutscheine einer Person zuzuordnen, fehlt.'

**Empfehlung:** Ins Backlog: (1) Nach dem Speichern 'Nächste Karte scannen' anbieten (günstig). (2) Feld 'Für/Gehört' mit Filter. (3) Wallet-Pass-Export (erfordert PassKit-Signierung und Server).

**Begründung:** Idee-Level. Wallet ist teuer und nur für eine Teilgruppe (Power-User mit 1–2 Gutscheinen) relevant. Der Mehrfach-Scan ist ein Quick Win für Nutzer mit Schublade voller Karten.

### ✗ Schwebende Tab-Leiste verdeckt letzten Listeneintrag / Inhalte im Screenshot

*verwerfen · 36 Nennungen · Screens: 02_start.png, 03_detail.png, 03_merchants.png, 03_settings.png*

> Karl-Heinz: 'Die letzte Karte in der Liste verschwindet hinter der schwebenden Tabbar'

> Olga: 'Unten verdeckt die schwebende Tab-Leiste den Douglas-Text und H&M.'

> Kemal: 'So funktioniert Restwert ... scheinen durch die Tab-Leiste hindurch'

**Empfehlung:** Keine Änderung nötig. Optional prüfen, dass alle ScrollViews genügend Bottom-Inset haben (03_detail_b zeigt, dass das Ende sauber über die Leiste scrollt).

**Begründung:** Das ist Standardverhalten der iOS-26-Liquid-Glass-Tab-Leiste: Inhalt scrollt darunter durch. Die Screenshots sind statische Momentaufnahmen, gescrollt ist alles erreichbar (belegt durch 03_detail_b, wo 'Gutschein entfernen' frei über der Leiste steht). Der berechtigte Teil (kleiner Online-Prüflink) ist im Thema 'online-pruefen-link' erfasst.

### ✗ Angst, 'Gutschein entfernen' versehentlich anzutippen

*verwerfen · 15 Nennungen · Screens: 03_detail_b.png, 03_detail_c.png*

> Lukas: 'Ich hoffe, dass danach noch eine Bestätigung kommt.'

> Ingrid: 'Ich habe Angst, ihn aus Versehen anzutippen.'

> Jürgen: 'Wird vor dem Löschen nachgefragt?'

**Empfehlung:** Keine Änderung. Optional das Papierkorb-Icon ergänzen (siehe Farbe-Thema).

**Begründung:** Unbegründet: CardDetailView.swift:64 zeigt vor dem Löschen einen confirmationDialog 'Gutschein endgültig entfernen?'. Die Personas konnten das auf den Screenshots nicht sehen.

### ✗ 'Guthaben online prüfen' fehlt im Kartendetail, nur im Händler-Tab

*verwerfen · 4 Nennungen · Screens: 03_detail_b.png, 03_detail_c.png*

> Gisela: 'Stattdessen muss ich in einen anderen Tab (Händler) wechseln.'

> Brigitte: 'Den gibt es aber nur im Tab Händler.'

> Irina: 'Im Gutschein selbst hätte ich einen Knopf erwartet.'

**Empfehlung:** Keine eigene Änderung; die Sichtbarkeit wird im Thema 'online-pruefen-link' behoben.

**Begründung:** Faktisch falsch: 03_detail.png zeigt 'Guthaben online prüfen' unter dem Barcode (CardDetailView.swift:170, balanceURL). Die Personas haben den kleinen Link nur übersehen, das bestätigt aber das Sichtbarkeitsproblem.

### ✗ Kein Weg für PDF-Gutscheine aus E-Mail

*verwerfen · 7 Nennungen · Screens: 01_onboarding.png, 02_start.png, 03_scan.png*

> Ingrid: 'meine PDFs aus der E-Mail bekomme ich hier gar nicht rein.'

> Samuel: 'Ob ich das PDF direkt übernehmen kann ... ist für mich nicht erkennbar.'

> Clara: 'Mein Hauptfall (PDF aus Mail) steht als dritte Zeile'

**Empfehlung:** Keine Funktionsänderung. PDF/Mail im Onboarding-Text nennen (siehe Onboarding-Thema) und den Teilen-Tipp auf dem Scan-Screen kontrastreicher machen (siehe Kontrast-Thema).

**Begründung:** 03_scan.png zeigt eindeutig 'Aus einer E-Mail' und 'Aus einer Datei – PDF oder Bild, z. B. aus einem Mail-Anhang' sowie den Share-Tipp. Die Funktion existiert, die berechtigten Teilpunkte sind in anderen Themen abgedeckt.

### ✗ Filter-Chips in der Händlerliste rechts abgeschnitten

*verwerfen · 5 Nennungen · Screens: 03_merchants.png*

> Olga: 'Man merkt kaum, dass man seitlich wischen kann.'

> Clara: 'ich weiß nicht, was da noch kommt.'

> Elias: 'Der dritte Chip rechts ist angeschnitten'

**Empfehlung:** Keine Änderung.

**Begründung:** Das Anschneiden ist das beabsichtigte Scroll-Signal (Peek) für horizontal wischbare Chips und iOS-üblich. Die Hauptfilter 'Alle' und 'Am Handy vorzeigbar' sind voll sichtbar. Beim Formular-Typwechsel ist es anders, weil dort ein Pflichttyp versteckt ist (eigenes Thema).

### ✗ Für 1–2 Gutscheine im Jahr zu viel App (Tabs, Kassentest, Verlauf)

*verwerfen · 4 Nennungen · Screens: 02_start.png, 03_detail_c.png*

> Nina: 'Wahrscheinlich lösche ich die App wieder nach dem Einlösen.'

> Helga: 'Für meine ein, zwei Gutscheine im Jahr ist mir das viel zu viel.'

> Jürgen: 'zu viel Gedöns'

**Empfehlung:** Keine Funktionsreduktion. Stattdessen die Hauptpfade vereinfachen (siehe P1-Themen).

**Begründung:** Das ist eine Frage der Zielgruppenpassung, kein Usability-Fehler. Das Produkt richtet sich an Nutzer mit mehreren Karten, und Gelegenheitsnutzer profitieren bereits von den P1-Vereinfachungen.

### ✗ Ablauftermine-Seite zeigt 'Start' als aktiven Tab

*verwerfen · 1 Nennungen · Screens: 03_radar.png*

> Dimitri: 'In der Tab-Leiste ist Start markiert, obwohl ich auf der Ablauftermine-Seite bin.'

**Empfehlung:** Keine Änderung.

**Begründung:** Korrektes Verhalten: Die Ablauftermine sind eine Push-Navigation innerhalb des Start-Stacks (NavigationLink Route.radar in HomeView), also bleibt 'Start' aktiv.

## Was gut ankam

- Große gelbe Gesamtsumme ist sofort lesbar (fast alle 50 Personas)
- 'Bald fällig' mit orangem 'noch X Tage' ganz oben verhindert Verfall
- Barcode an der Kasse groß, mit lesbarer Nummer und automatisch maximaler Helligkeit
- Einlöse-Verlauf im Kassenbon-Stil ist sofort verständlich
- Viele Erfassungswege: Kamera, Fotos, E-Mail, PDF, von Hand
- Kein Konto nötig, Daten bleiben lokal, PIN per Face ID geschützt
- Händlerliste mit Filter 'Am Handy vorzeigbar' beantwortet eine echte Kassenfrage
- Ablauftermine nach Monat gruppiert mit Summen
- Onboarding erklärt den Zweck in einem Satz
- Schnellbeträge 5/10/20/Alles und 'Danach übrig' geben Sicherheit
