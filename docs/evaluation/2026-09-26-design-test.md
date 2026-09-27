# Design-Test mit 50 Personas (20–30 Jahre) – 26.09.2026

*Zweite Runde nach Umsetzung von Runde 1 ([Auswertung Runde 1](2026-09-26-persona-test.md)). Stand der Markierungen: nach dem Commit dieser Datei.*

> **Methode:** 50 simulierte Testpersonen zwischen 20 und 30 (KI-Agenten mit eigener Identität, u. a. Designer:innen, Studierende, Content Creator, Fintech-PMs) bewerten 13 aktuelle Simulator-Screenshots mit Fokus auf Design. **Keine echten Menschen.**

## Noten (1–10)

| Bereich | Ø |
|---|---|
| Gesamteindruck | 7.0 |
| Typografie | 7.0 |
| Farbe | 6.3 |
| Hierarchie | 7.2 |
| Abstaende layout | 6.0 |
| Konsistenz | 6.1 |
| Eigenstaendigkeit | 6.3 |
| Modernitaet | 7.3 |

**Wirkt wie KI-Template:** 4 % · **würden die App laden:** 98 %

## Vergleich mit Runde 1

Runde 1 hatte den Fokus auf Bedienbarkeit (Ø 6,4, 80 % würden nutzen). Diese Runde hat den Fokus auf Design (Ø 7,0, 98 % würden laden, nur 2 von 50 finden die App KI-typisch). Die großen Hürden aus Runde 1 tauchen nicht mehr auf: das unbeschriftete Kalender-Icon, der fehlende Hinzufügen-Knopf, der Slider beim Einlösen und der versteckte Kassen-Button. Einige Lösungen aus Runde 1 haben aber neue Designprobleme erzeugt. Das zusätzliche „+“ oben rechts ist jetzt die meistgenannte Kritik (46/50). Das Stapeln bei großer Schrift funktioniert, sieht aber kaputt aus. Das gekürzte Formular hat ein herausgefallenes „Andere“-Segment. Der größte Punkt ist geblieben, nur schärfer: Die schwebende Tab-Bar überdeckt Inhalte und steht auch in Kassen- und Eingabe-Flows. Die Gelb-Orange-Reibung ist neu, weil die Frist-Farbe #B35F00 für die Lesbarkeit abgedunkelt wurde und jetzt direkt am Hero-Gelb und am Zalando-Orange sitzt.

## Markiertes Feedback

Legende: ✅ umgesetzt · 🟡 teilweise · ⏳ offen · ✗ verworfen

| Status | Prio | Nennungen | Thema | Umsetzung |
|---|---|---|---|---|
| ✅ | P1 | 46/50 | Doppelter Plus-Button (oben rechts und neben der Tab-Bar) | Plus oben rechts entfernt; nur noch „Hinzufügen“ neben der Tab-Leiste. |
| ✅ | P1 | 44/50 | Schwebende Tab-Bar überdeckt das Listenende und die Abzieh-Karte (fehlender Bottom-Inset) | Harte Scroll-Kante oben und unten: Inhalt läuft nicht mehr lesbar unter die Tab-Leiste. |
| ✅ | P1 | 45/50 | Warme Töne reiben sich: Hero-Gelb, Zalando-Orange und Frist-Braunorange direkt übereinander | Frist-Farbe auf klares Rot (#B42318) als Badge mit hellem Grund; Hero-Gelb unverändert; 4 pt mehr Abstand. |
| ✅ | P1 | 40/50 | Detail: drei Vollbreit-Buttons in drei Stilen ohne Rangfolge | Nur „An der Kasse zeigen“ vollbreit; PIN und „Guthaben prüfen“ als zwei gleiche kleine Knöpfe nebeneinander. |
| ✅ | P1 | 27/50 | Große Schrift: Betrag rutscht links unter den Namen, Trenner beginnt mitten in der Zeile | Gestapelt: Betrag an der Textkante (58 pt) und in Namensgröße; Hero-Zeile auf „+ 1 Rabattcode extra“ gekürzt. |
| ✅ | P1 | 26/50 | Tab-Bar steht in Push- und Eingabe-Flows (Kasse, Keypad, Detail), dort ist „Start“ aktiv | Tab-Leiste in Detail, Kasse, Einkauf abziehen und Ablauftermine ausgeblendet. |
| ✅ | P1 | 29/50 | Formular: „Andere“ fällt aus dem Segmented Control, drei Feldstile, Karten in Karten mit wenig Kontrast | Vier gleich breite Segmente (Karte · Gutschein · Code · Andere); Felder als flache Zeilen mit Haarlinie in einer weißen Gruppe. |
| ✅ | P1 | 28/50 | „PIN anzeigen“ an der Kasse in Monospace und als kleine Pill, im Detail dagegen in SF mit Face-ID-Icon | PIN an der Kasse in SF mit Face-ID-Symbol wie im Detail; Händler-Hinweis als Fußnote ohne Box. |
| ✅ | P1 | 22/50 | Keypad: Chip „Alles“ läuft rechts aus dem Raster, deaktivierter CTA in Blassgelb wirkt kaputt | Chips gleich breit, 50 € entfernt; deaktivierter Knopf neutral grau „Betrag abziehen“; Cursor schwarz 2 pt. |
| ✅ | P2 | 25/50 | Ausgegrauter 20-€-Chip ohne Erklärung wirkt wie Lade- oder Renderfehler | Nur Beträge unter dem Restwert; „Alles (12,40 €)“ nennt den Rest. |
| ✅ | P2 | 24/50 | Einstellungen: Stepper-Zeile „„Läuft bald ab“ ab 30 Tagen“ bricht um, Hilfetext abgeschnitten | Stepper ersetzt durch Auswahl „Als ‚bald‘ markieren: 30 Tage vorher“, Erklärung als Fußzeile. |
| ✅ | P2 | 20/50 | Verlauf: Stat-Kacheln doppeln die Bon-Summe, Bon-Unterzeilen klein und grau, Douglas-Zeile bricht um | Stat-Kacheln entfernt, „NOCH OFFEN“ im Bonkopf; Unterzeilen 13 pt dunkler, Händlername nicht doppelt. |
| 🟡 | P2 | 17/50 | Farbsystem: Gelb in zu vielen Rollen, Grün (Toggles, „Am Handy vorzeigbar“) als Fremdfarbe, Outline-Icons in Einstellungen | Toggles und aktiver Filter-Chip jetzt Schwarz, Grün abgedunkelt; Gelb bleibt Marke + Primäraktion (Einlösen/Code kopieren). |
| 🟡 | P2 | 16/50 | Händlerkarten textlastig, Filterleiste mit abweichendem Hintergrundstreifen | Händlertexte auf 2 Zeilen begrenzt, aktiver Filter schwarz. Fade am Rand offen. |
| ✅ | P2 | 10/50 | Formular-Label „Schon benutzt? Rest“ holprig | Label „Restguthaben“, Platzhalter „wie Wert“. |
| ⏳ | P3 | 8/50 | Fortschrittsbalken nur bei teilweise genutzten Karten, sehr dünn und dicht am Text | Offen. |
| ⏳ | P3 | 7/50 | Onboarding ohne Markenmoment, Leerraum vor dem CTA | Offen. |
| ⏳ | P3 | 7/50 | Zu wenig Persönlichkeit / Belohnungsmoment beim Abziehen | Offen. |
| ⏳ | P3 | 6/50 | Monogramm-Kacheln (D, T, €) wirken wie Platzhalter, Douglas und Stadtgutschein beide schwarz | Offen. |
| ⏳ | P3 | 3/50 | Detail-Markenkarte flach und leer (kein Logo, keine Textur) | Offen. |
| ⏳ | P3 | 5/50 | Kasse: „Geklappt/Abgelehnt“-Karten ungleich hoch, Leerraum bis zur Tab-Bar | Offen. |
| ✗ | – | 12/50 | REWE nicht in „Deine Händler“ auffindbar | Das ist ein Missverständnis: „Deine Händler“ zeigt korrekt nur Händler, von denen man Karten besitzt, und REWE gehört nicht dazu. Die Aufgabe stammte aus Runde 1 und war nicht Teil dieses Design-Tests. Der offene Section-Index ist bereits als 🟡 in Runde 1 vermerkt. |
| ✗ | – | 1/50 | Dark Mode nicht in den Screenshots | Das ist kein Befund zur App, sondern eine Lücke im Testmaterial. Als Hinweis für die nächste Runde notieren. |

## Details je Thema

### ✅ Doppelter Plus-Button (oben rechts und neben der Tab-Bar)

*P1 jetzt umsetzen · 46 Nennungen · 02_start, 04_start_grosse_schrift*

> Lena: „Oben rechts gibt es ein rundes + und unten rechts neben der Tabbar noch eins … das obere schwebt ohne Bezug über dem Titel.“

> Noah: „Doppelte Primäraktion wirkt unentschlossen, der obere schwebt über leerem Raum.“

> Oskar: „zwei Plus-Buttons und das verrutschte 'Andere' zeigen, dass noch keiner Pixel gezählt hat.“

**Empfehlung:** Toolbar-„+“ auf Start entfernen, nur das Plus neben der Tab-Bar behalten. Den Titel „Restwert“ dann bis ca. 8 pt unter die Statusleiste hochziehen, damit die freigewordene Höhe (~60 pt) dem Hero zugutekommt. Optional das Tab-Bar-Plus als einzige Primäraktion in Schwarz (#111) mit weißem Symbol füllen.

**Begründung:** Im Screenshot bestätigt (02_start: + bei y≈85 und y≈845). Fast alle nennen es, der Aufwand ist minimal. Es ist ein Nebeneffekt aus Runde 1: Das zweite Plus war dort als Hilfe gedacht und ist durch den Hinzufügen-Tab überflüssig geworden.

### ✅ Schwebende Tab-Bar überdeckt das Listenende und die Abzieh-Karte (fehlender Bottom-Inset)

*P1 jetzt umsetzen · 44 Nennungen · 02_start, 03_detail, 03_merchants, 03_settings, 04_start_grosse_schrift*

> Paula: „Die Karte ‚Eingekauft? Betrag abziehen‘ läuft unter die schwebende Tab-Bar. Hinter der Bar schimmert ein gelber Button durch.“

> Mara: „Wirkt eher wie ein Fehler als wie echtes Liquid Glass.“

> Can: „Der gelbe Schimmer hinter der Tabbar sieht nach einem Render-Fehler aus.“

**Empfehlung:** Allen Scroll-Inhalten unter der Floating-Tab-Bar einen unteren Inhaltsabstand geben: Höhe der Tab-Bar + 24 pt (≈ 110 pt, per .safeAreaInset(edge: .bottom) oder .contentMargins(.bottom, 110, for: .scrollContent)). Zusätzlich einen 40 pt hohen Verlauf von der Hintergrundfarbe (#F2F2F4, 0 % → 100 %) hinter der Bar legen, damit durchscheinende Texte nicht als „Brei“ lesbar sind. Den gelben Abziehen-Button im Detail so positionieren, dass er beim ersten Scrollstand ganz sichtbar ist oder ganz verdeckt bleibt.

**Begründung:** Auf 4 Screens bestätigt: Thalia/Amazon auf Start, der gelbe Button im Detail, Stadtgutschein in Händler, der Stepper-Hilfetext in den Einstellungen. Das ist der stärkste Grund für das „Beta“-Gefühl, und die Korrektur ist eine globale Einstellung.

### ✅ Warme Töne reiben sich: Hero-Gelb, Zalando-Orange und Frist-Braunorange direkt übereinander

*P1 jetzt umsetzen · 45 Nennungen · 02_start, 03_radar, 04_start_grosse_schrift*

> Lena: „Drei warme Töne streiten sich. Die Dringlichkeitsfarbe sollte sich klarer vom Markengelb absetzen.“

> Tom: „Die Warnfarbe wirkt so eher schmutzig als dringend.“

> Ida: „das Orange für 'noch 12 Tage' kann ich kaum lesen.“

**Empfehlung:** Die Frist-Farbe von #B35F00 (Braunorange) auf ein klares Rot-Orange ändern, z. B. #C8341B (auf Weiß ≈ 5,4:1, erfüllt AA). Bei ≤ 14 Tagen als Pill-Badge setzen: Hintergrund #FDECE8, Text #B42318, 13 pt semibold, 4/8 pt Padding, Uhr-Icon in derselben Farbe und als Outline wie die übrigen Icons. Das Hero-Gelb (#FFE04B-Bereich) nicht ändern, es wird als Markenzeichen gelobt. Zwischen Hero und der Sektion „Läuft bald ab“ 8 pt mehr Abstand (von ~24 auf 32 pt).

**Begründung:** Im Screenshot bestätigt, die Töne liegen nah beieinander. Das ist ein Folgeeffekt der Abdunklung aus Runde 1. Es genügt, einen Farbtoken zu ändern. Die Wirkung ist hoch, weil es den ersten Screen betrifft.

### ✅ Detail: drei Vollbreit-Buttons in drei Stilen ohne Rangfolge

*P1 jetzt umsetzen · 40 Nennungen · 03_detail*

> Lena: „So braucht der Screen viel Höhe, und das eigentliche Abziehen des Betrags landet unter dem Falz.“

> Paula: „‚PIN anzeigen‘ ist linksbündig, die anderen beiden sind zentriert. Das sieht nach einer Liste aus, nicht nach einer Hierarchie.“

> Bastian: „im Detail-Screen stapeln sich Buttons wie im Formular-Baukasten.“

**Empfehlung:** „An der Kasse zeigen“ bleibt als einziger Vollbreit-Button (schwarz, 56 pt hoch). „PIN anzeigen“ und „Guthaben online prüfen“ kommen in eine zweispaltige Zeile mit sekundären Buttons: je 44 pt hoch, weißer Grund, 15 pt medium, beide zentriert, Icon vor dem Text, 8 pt Abstand dazwischen. Alternativ „PIN“ als Metadaten-Zeile neben „Gültig bis / Einlösungen“ einbauen („PIN •••• anzeigen“). Das spart ca. 70 pt, dadurch rückt die Abzieh-Karte über den Falz.

**Begründung:** Im Screenshot bestätigt: PIN ist linksbündig, die anderen sind zentriert, drei Pillen gleicher Breite. Der Aufwand ist mittel. Die Korrektur verstärkt T02, weil die Abzieh-Karte dann sichtbar wird.

### ✅ Große Schrift: Betrag rutscht links unter den Namen, Trenner beginnt mitten in der Zeile

*P1 jetzt umsetzen · 27 Nennungen · 04_start_grosse_schrift*

> Jule: „Die Zeile wird doppelt so hoch, die Beträge verlieren ihre feste Spalte … Der Trenner beginnt bei x≈90 und schneidet mitten in die Zeile.“

> Noah: „Wirkt kaputt statt adaptiv.“

> Mila: „Besser wäre ein bewusster Stack-Wechsel.“

**Empfehlung:** Im gestapelten Layout (ab .accessibility1 oder per ViewThatFits) den Betragsblock auf die Textkante einrücken (leading = Logo 44 pt + 12 pt Abstand = 56 pt) und nicht an die Zellkante setzen. Den Trenner ebenfalls ab 56 pt beginnen lassen, dann passt er zur Einrückung. Den Betrag mit derselben Schriftgröße wie den Namen setzen, nicht größer. Im Hero „+ 1 Rabattcode, nicht in der Summe“ auf „+ 1 Rabattcode extra“ kürzen, damit die Zeile nicht umbricht. Alternativ bis .xxxLarge das zweispaltige Layout behalten und nur den Namen umbrechen lassen.

**Begründung:** Im Screenshot bestätigt: „15 %“ steht bei x≈35 unter dem Logo, der Trenner beginnt bei x≈90. Das Stapeln aus Runde 1 hat den richtigen Ansatz, nur die Ausrichtung fehlt. Der Aufwand ist gering.

### ✅ Tab-Bar steht in Push- und Eingabe-Flows (Kasse, Keypad, Detail), dort ist „Start“ aktiv

*P1 jetzt umsetzen · 26 Nennungen · 03_keypad, 03_checkout, 03_detail, 03_radar*

> Malik: „Schade, dass die Tab-Bar überall reinlatscht, auch da, wo ich gerade bezahle.“

> Deniz: „Der gelbe Button 'Betrag eingeben' stößt fast an die Tab-Bar. In einem modalen Eingabe-Flow gehört die Tab-Bar gar nicht hin.“

> Mila: „sonst tippt man an der Kasse leicht daneben.“

**Empfehlung:** .toolbar(.hidden, for: .tabBar) auf „An der Kasse“, „Einkauf abziehen“ und „Ablauftermine“ setzen, im Detail ebenfalls oder mindestens dort, wo T02 den Abstand herstellt. Im Keypad sitzt der CTA dann 16 pt über der Home-Indicator-Safe-Area. Alternativ „Einkauf abziehen“ als .sheet mit .presentationDetents([.large]) statt als Push präsentieren.

**Begründung:** Bestätigt: Im Keypad klebt der CTA auf der Tab-Bar (y≈785 vs. 845), im Checkout sind ~100 pt Leerraum plus Tab-Bar. Es ist eine Zeile Code pro Screen, und die Wirkung an der Kasse ist hoch.

### ✅ Formular: „Andere“ fällt aus dem Segmented Control, drei Feldstile, Karten in Karten mit wenig Kontrast

*P1 jetzt umsetzen · 29 Nennungen · 03_form*

> Can: „'Andere' steht außerhalb der grauen Pille, als wäre es rausgerutscht.“

> Merve: „das Formular fühlt sich an wie Karten in Karten in Karten. Da fehlt mir der Mut zur flachen Liste.“

> Tarek: „das Formular sieht aus, als hätte jemand anderes es gebaut.“

**Empfehlung:** „Andere“ ins Segment holen, sodass es vier gleich breite Segmente gibt (Kurzlabels „Karte · Gutschein · Code · Andere“, 13 pt), oder „Andere“ als Menü-Chevron im vierten Segment anbieten. Die Feldkacheln sollen entfallen: eine weiße Gruppe (Radius 16) mit Zeilen und 0,5-pt-Trennern (#E3E3E8) auf Hintergrund #F2F2F4. Ein einheitlicher Wertstil für alle Felder: Label 13 pt #696C74, Wert 17 pt semibold #111, bündig auf 16 pt. Datum ohne graue Pill als Text mit Kalender-Icon rechts, Picker (Shop, Barcode-Typ, Ort) ebenfalls bündig mit Chevron rechts statt Einrückung. Der Wallet-Hinweis wird zur Fußnote unter der Gruppe (13 pt).

**Begründung:** Im Screenshot bestätigt: „Andere“ steht bei x≈360 außerhalb der Pille, Datums-Pills, eingerückte Picker, weiße Kacheln auf fast weißem Sheet. Es wird oft genannt, und das Formular ist der erste Arbeits-Screen nach dem Anlegen. Der Aufwand ist mittel.

### ✅ „PIN anzeigen“ an der Kasse in Monospace und als kleine Pill, im Detail dagegen in SF mit Face-ID-Icon

*P1 jetzt umsetzen · 28 Nennungen · 03_checkout*

> Jule: „Das wirkt wie ein Debug-Label.“

> Samir: „Das wirkt wie ein Überbleibsel vom Bon-Stil. Außerdem fehlt ihm das Face-ID-Icon, das er im Detail hat.“

> Luisa: „‚PIN anzeigen‘ ist in Mono gesetzt, auf dem Detail-Screen dagegen in SF.“

**Empfehlung:** Button in SF Pro 15 pt semibold mit Face-ID-Symbol (faceid) setzen, identisch zum Detail. Monospace nur für die Kartennummer und den Bon verwenden. Die graue Wallet-Infobox im Ticket als einzeilige Fußnote unter die Nummer setzen (13 pt #696C74, ohne Box), damit der Barcode allein steht.

**Begründung:** Im Screenshot bestätigt. Der Fix ist trivial und stellt die Konsistenz über die ganze App her.

### ✅ Keypad: Chip „Alles“ läuft rechts aus dem Raster, deaktivierter CTA in Blassgelb wirkt kaputt

*P1 jetzt umsetzen · 22 Nennungen · 03_keypad*

> Kaan: „Der Chip 'Alles' stößt rechts an den Bildschirmrand, links gibt es dagegen 16 px Rand.“

> Esra: „ein blasser gelber Button, der aussieht, als wär er kaputt.“

> Bastian: „der Button-Text ist identisch mit dem Label ‚Betrag eingeben‘ darüber.“

**Empfehlung:** Chips als HStack mit gleicher Breite (maxWidth: .infinity, Spacing 8 pt, horizontales Padding 16 pt beidseitig) statt fester Breiten, alternativ „50 €“ streichen (bei 12,40 € Rest ohnehin sinnlos). Deaktivierter CTA neutral: Hintergrund #E6E6EA, Text #8A8D94, Label „Betrag abziehen“. Aktiv: Gelb mit Text „12,60 € abziehen“. Den Cursor neben der 0 auf 2 pt Breite in #111 setzen statt Gelb.

**Begründung:** Im Screenshot bestätigt: „Alles“ endet bei x≈407 von 414. Der blasse Button hat bei beigem Text auf Hellgelb auch einen Kontrastmangel. Der Aufwand ist klein.

### ✅ Ausgegrauter 20-€-Chip ohne Erklärung wirkt wie Lade- oder Renderfehler

*P2 bald · 25 Nennungen · 03_detail*

> Lena: „Man liest das als Ladefehler. Besser ausblenden oder durch einen Hinweis ersetzen.“

> Vincent: „Entweder ganz ausblenden oder erklären, warum er gesperrt ist.“

**Empfehlung:** Nur Schnellbeträge anzeigen, die ≤ Restwert sind. Freie Plätze werden nicht aufgefüllt, „Alles (12,40 €)“ bekommt den Platz. Wenn der Chip stehen bleibt: durchgestrichen oder mit Mikrotext „mehr als Rest“ (11 pt) darunter.

**Begründung:** Bestätigt (20 € grau). Das passt zur Logik aus Runde 1 (kein Blockieren). Klein und schnell umsetzbar, aber weniger sichtbar als die P1-Themen.

### ✅ Einstellungen: Stepper-Zeile „„Läuft bald ab“ ab 30 Tagen“ bricht um, Hilfetext abgeschnitten

*P2 bald · 24 Nennungen · 03_settings*

> Tom: „das Anführungszeichen steht vorne verloren … Eine kürzere Formulierung wie 'Warnen ab' …“

> Noah: „Wert lieber als eigene Zeile/Picker.“

**Empfehlung:** Label kürzen auf „Als ‚bald‘ markieren“ und den Wert rechts als Menü-Picker „30 Tage ⌃⌄“ (7/14/30/60) statt Stepper anzeigen. Den Hilfetext als Section-Footer unter die Gruppe setzen. Der untere Inset aus T02 behebt das Abschneiden.

**Begründung:** Im Screenshot bestätigt (zweizeiliger Titel, der Hilfetext wird unter der Tab-Bar abgeschnitten). Ein seltener Screen, aber ein schneller Fix.

### ✅ Verlauf: Stat-Kacheln doppeln die Bon-Summe, Bon-Unterzeilen klein und grau, Douglas-Zeile bricht um

*P2 bald · 20 Nennungen · 03_history*

> Lena: „'28,75 € Eingelöst' steht in der Kachel und noch mal als SUMME im Bon.“

> Malik: „Die zwei Stat-Karten darüber sind aber Standard-Dashboard-Look.“

> Greta: „graue kleine Monospace auf Creme hat wenig Kontrast.“

**Empfehlung:** Stat-Kacheln entfernen. „Noch offen 136,25 €“ als eine Zeile in den Bonkopf unter das Datum schreiben (Mono 13 pt). Die Unterzeilen auf „Beispielstadt · Rest 12,40 €“ kürzen (Händlername steht schon darüber), Mono 13 pt statt ~11 pt, Farbe #5A5D63 statt Hellgrau (≥ 4,5:1 auf Creme #FAF7EF). Über jeder Datumszeile 12 pt Abstand.

**Begründung:** Bestätigt: Doppelung, Umbruch bei Douglas, kleine graue Zeilen. Der Bon ist das meistgelobte Element, deshalb lohnt der Feinschliff.

### 🟡 Farbsystem: Gelb in zu vielen Rollen, Grün (Toggles, „Am Handy vorzeigbar“) als Fremdfarbe, Outline-Icons in Einstellungen

*P2 bald · 17 Nennungen · 03_settings, 03_merchants, 03_tests, 03_keypad*

> Mila: „Gelb sollte für eine Bedeutung reserviert sein.“

> Arda: „Die grünen System-Toggles und dünnen SF-Symbole wirken wie Settings.app.“

> Julian: „Drei Akzentfarben ohne klares System.“

**Empfehlung:** Rollen festlegen: Gelb ausschließlich für Guthaben/Marke (Hero, Tests-Quote flach ohne Verlauf). Aktiver Filter-Chip und Toggles bekommen Schwarz (#111) als .tint. Status „Am Handy vorzeigbar“ in #1F7A4D nur als Icon plus Text 13 pt, oder neutral (#111) mit Icon. Settings-Icons einheitlich auf SF Symbols .regular in 28-pt-Kacheln mit #F2F2F4-Hintergrund, wie die Datenschutz-Karte.

**Begründung:** Teilweise bestätigt: grüne Toggles, gelber Chip, Tests-Karte mit Verlauf. Das ist eher Systempflege als ein Fehler, deshalb nach den P1-Themen.

### 🟡 Händlerkarten textlastig, Filterleiste mit abweichendem Hintergrundstreifen

*P2 bald · 16 Nennungen · 03_merchants*

> Samir: „Das wirkt wie ein Beipackzettel … Status und Link reichen, die Beschreibung gehört ins Detail.“

> Selin: „hinter den Chips ist ein leicht dunklerer Hintergrundstreifen sichtbar.“

**Empfehlung:** Beschreibung pro Karte auf maximal 1 Zeile kürzen (lineLimit(1), Rest im Händler-Detail). Aufbau: Name 17 pt semibold, Status 13 pt mit Icon, Link als eigene 44-pt-Zeile mit Chevron. Den Hintergrund der Filter-Chip-Leiste transparent machen, rechts einen 24 pt breiten Fade als Scroll-Hinweis ergänzen.

**Begründung:** Bestätigt: 3–4 Textzeilen pro Karte, ein leicht abgesetzter Streifen hinter den Chips. „Nur online“ ist im Screenshot nicht abgeschnitten (endet bei x≈372), dieser Teil entfällt.

### ✅ Formular-Label „Schon benutzt? Rest“ holprig

*P2 bald · 10 Nennungen · 03_form*

> Hanna: „Das Label klingt wie zwei Labels auf einmal. Besser ‚Restguthaben‘.“

> Carla: „Das Label klingt nach einer Frage und nach einem Wert zugleich.“

**Empfehlung:** Label „Restguthaben“, Platzhalter „wie Wert“ (leer = voller Wert).

**Begründung:** Textänderung ohne Aufwand. Passt in denselben Durchgang wie T07.

### ⏳ Fortschrittsbalken nur bei teilweise genutzten Karten, sehr dünn und dicht am Text

*P3 später · 8 Nennungen · 02_start, 03_radar*

> Tom: „Er ist zu dünn und klebt fast am Text darüber.“

> Ronja: „Dadurch werden die Zeilen unterschiedlich hoch und der Rhythmus der Liste leidet.“

**Empfehlung:** Balken nur bei teilweiser Nutzung beibehalten, aber Platz immer reservieren (feste Zeilenhöhe), 4 pt hoch statt ~3 pt, 6 pt Abstand zu „von X €“, Spur #E6E6EA, Füllung #111. Alternativ Balken entfernen, weil „von 40,00 €“ genügt.

**Begründung:** Bestätigt (Douglas/Thalia). Das ist inhaltlich sinnvoll und hat wenig Wirkung.

### ⏳ Onboarding ohne Markenmoment, Leerraum vor dem CTA

*P3 später · 7 Nennungen · 01_onboarding*

> Lena: „Für den ersten Eindruck fehlt ein eigenes Markenzeichen, zum Beispiel ein gelbes Karten-Icon.“

> Levin: „Zeig die gelbe Summenkarte schon hier.“

**Empfehlung:** Die Beispielliste in eine Mini-Hero-Karte im Markengelb (Radius 20, „Beispiel: 84,50 €“) einbetten, die Wortmarke „Restwert“ auf 22 pt heavy setzen und einen gelben Kartenbildpunkt davorstellen. Den Leerraum mit Spacer(minLength: 24) begrenzen.

**Begründung:** Wird selten genannt, das Onboarding ist ein Einmal-Screen. Es wird aber gleichzeitig als ruhig gelobt, deshalb ist keine Eile nötig.

### ⏳ Zu wenig Persönlichkeit / Belohnungsmoment beim Abziehen

*P3 später · 7 Nennungen · Gesamt, 03_detail*

> Luis: „Die gelbe Karte oben ist cool, danach fühlt es sich an wie die iPhone-Einstellungen.“

> Henry: „Nach dem Abziehen ein kleines Konfetti/Haptik-Moment oder animiertes Bon-Ausdrucken.“

**Empfehlung:** Nach „Betrag abziehen“ einen Bon-Streifen einblenden, der 0,4 s von oben „ausgedruckt“ wird (Mono, „−12,60 € · Rest 0,00 €“), dazu .sensoryFeedback(.success). Das nutzt das stärkste Signature-Element statt Konfetti.

**Begründung:** Nur Personas mit Vorliebe für verspielte Apps nennen es (2 davon sehen die App als KI-typisch). Die Idee greift den gelobten Bon auf, hat aber geringe Priorität.

### ⏳ Monogramm-Kacheln (D, T, €) wirken wie Platzhalter, Douglas und Stadtgutschein beide schwarz

*P3 später · 6 Nennungen · 02_start, 03_merchants*

> Tom: „Die Kacheln mit weißem Buchstaben ('D', 'T', 'Z') sehen nach Platzhaltern aus.“

> Deniz: „Douglas und Stadtgutschein haben beide Schwarz. Dadurch sehen sie in der Liste gleich aus.“

**Empfehlung:** Stadtgutschein und generische Karten bekommen eine eigene Kachelfarbe (z. B. #3C4A5C) plus Symbol statt „€“. Monogramme in 20 pt heavy mit leichtem Innenverlauf (oben +6 % Helligkeit).

**Begründung:** Bestätigt, aber ohne echte Händlerlogos (rechtlich/Assets) begrenzt lösbar.

### ⏳ Detail-Markenkarte flach und leer (kein Logo, keine Textur)

*P3 später · 3 Nennungen · 03_detail*

> Mara: „Auf der grünen Thalia-Karte steht nur der Name als Text. Oben rechts ist viel leere Fläche.“

**Empfehlung:** Monogramm-Kachel oben rechts (32 pt, 20 % weiß) und subtiler Diagonalverlauf (+8 % Helligkeit oben links).

**Begründung:** Wenige Nennungen. Die Karte wird von vielen ausdrücklich als hochwertig gelobt.

### ⏳ Kasse: „Geklappt/Abgelehnt“-Karten ungleich hoch, Leerraum bis zur Tab-Bar

*P3 später · 5 Nennungen · 03_checkout*

> Frieda: „Bei ‚Geklappt‘ steht der Untertitel auf zwei Zeilen, bei ‚Abgelehnt‘ auf einer.“

> Milan: „unter 'Geklappt/Abgelehnt' ist ein großes Loch bis zur Tab-Bar.“

**Empfehlung:** Beide Karten mit .frame(maxHeight: .infinity) auf gleiche Höhe bringen, Untertitel mit lineLimit(1) und minimumScaleFactor(0.9). Die Überschrift „Hat es geklappt?“ von ~26 pt bold auf 20 pt semibold setzen. Wenn die Tab-Bar ausgeblendet ist (T06), den Barcode um 20 % höher machen und so den Leerraum nutzen.

**Begründung:** Bestätigt (Geklappt zweizeilig). Das erledigt sich teilweise mit T06.

### ✗ REWE nicht in „Deine Händler“ auffindbar

*verwerfen · 12 Nennungen · 03_merchants*

> Can: „Auf dem Screenshot sehe ich kein REWE … Bewerten konnte ich es also nicht.“

**Empfehlung:** Keine Designänderung. Optional einen Section-Index oder die Überschrift „Alle Händler A–Z“ unter „Deine Händler“ sichtbar anreißen.

**Begründung:** Das ist ein Missverständnis: „Deine Händler“ zeigt korrekt nur Händler, von denen man Karten besitzt, und REWE gehört nicht dazu. Die Aufgabe stammte aus Runde 1 und war nicht Teil dieses Design-Tests. Der offene Section-Index ist bereits als 🟡 in Runde 1 vermerkt.

### ✗ Dark Mode nicht in den Screenshots

*verwerfen · 1 Nennungen · Alle*

> Jule: „Wie die gelbe Hero-Karte und der cremefarbene Bon im Dark Mode aussehen, kann ich nicht prüfen.“

**Empfehlung:** Für die nächste Runde Dark-Mode-Screenshots von Start, Verlauf und Kasse ergänzen.

**Begründung:** Das ist kein Befund zur App, sondern eine Lücke im Testmaterial. Als Hinweis für die nächste Runde notieren.

## Was gut ankam

- Die gelbe Hero-Karte mit großer Summe ist in 1–3 Sekunden verstanden und wird als eigenständiges Markenzeichen gesehen, „endlich kein Lila-Gradient“ (fast alle 50).
- Der Kassenbon im Verlauf (Zackenrand, Monospace, SUMME) ist das meistgelobte Signature-Element, „den würde ich screenshotten“.
- Die Detailkarte in Markenfarbe (Thalia-Grün) mit Fortschrittsbalken wirkt hochwertig wie Apple Wallet.
- Der Kassen-Screen im Ticket-Look mit Stanzkerben, großem Barcode und klarer Frage „Hat es geklappt?“.
- Markenfarbige Logo-Kacheln machen die Listen schnell scanbar, die Typo mit fetten, rechtsbündigen Beträgen ist sauber.
- Das ruhige Onboarding mit Beispielliste und die Datenschutz-Karte oben in den Einstellungen schaffen Vertrauen.
