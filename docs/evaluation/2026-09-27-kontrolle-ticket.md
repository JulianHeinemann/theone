# Kontrollrunde „Das Ticket“ (10 simulierte Design-Personas, intensiv)

Stand: Commit fea8d85 (Ticket-Marke mit SF Rounded, neues App-Icon). Simulierte Personas, keine echten Menschen.
Material: 41 Screenshots aus dem Simulator „Restwert Test“ – alle Screens hell, dunkel, Barrierefreiheit XL,
dazu 4 echte Scroll-Positionen. Die Personas haben Abstände, Farben und Kontraste per Pixelanalyse gemessen.
Animation und Haptik wurden nur aus dem Code beurteilt.

## Noten (Ø von 10, in Klammern Vorrunde mit 200 Reviews)

| Kategorie | Ø | Vorrunde |
|---|---|---|
| Gesamt | 6.9 | 7.0 |
| Hierarchie | 8.0 | 8.0 |
| Farbe | 7.4 | – |
| Typografie | 7.1 | – |
| Dunkelmodus | 6.9 | – |
| Abstände/Raster | 6.8 | 6.91 |
| Ikonografie | 6.7 | – |
| Komponenten | 6.6 | – |
| Barrierefreiheit | 6.5 | – |
| Premium-Gefühl | 6.5 | – |
| **Markencharakter** | **6.0** | **5.03** |
| **Konsistenz** | **5.8** | – |

9 von 10 erkennen eine eigene Marke. 118 Befunde, davon 24 „hoch“.
Die Marke ist gestiegen (+1,0), die Wirkung wird aber durch Inkonsistenz gebremst: Die Signatur steht nur auf 3 von 15 Screens.

## Übereinstimmende Befunde (von mehreren Personas unabhängig gemessen)

1. **Stempel „Aufgebraucht“ im Dunkeln unlesbar** – `Color.ink` ist dunkel hell → ca. 1,2:1 auf Gelb (Theme.swift, UsedUpStamp). Fix: `onBrand`. (Farbe, Dunkel)
2. **Schatten mit `ink` gefärbt** → im Dunkeln graue Halos (5 Stellen). Fix: eigenes Schatten-Token (dunkel: Schwarz 40 % oder keiner).
3. **Schalter im Dunkeln AN/AUS nicht unterscheidbar** (`.tint(Color.ink)`, 1,14:1). (4 Personas)
4. **Onboarding ohne Marke**: „Restwert“ 17 pt ohne Punkt, kein Ticket, 20 statt 16 pt Rand. (6 Personas)
5. **Zwei Ticket-Systeme**: Kasse nutzt alte `Perforation` mit aufgemalten 28-pt-Kreisen statt `TicketShape`; drei verschiedene Strichelungen.
6. **Betragsschrift**: Komma wird mit hochgestellt („136’25“), Lücke hinter „1“ (monospacedDigit, 11–13 pt), Cent 2,6 pt zu tief.
7. **Kasse**: „Bezahlt“ öffnet ein Textfeld mit System-Tastatur statt des eigenen Ziffernblocks; Hauptknöpfe in der oberen Hälfte; bei XL laufen „Nicht angenommen/Später eintragen“ aus dem Bild; Button ohne vertikales Padding.
8. **Unterer Leerraum**: `contentMargins(.bottom, 120)` doppelt zur Safe Area → 144 pt (Start) bzw. 186 pt (Detail) tote Fläche.
9. **Tokens kaum genutzt**: 13 Radien statt 3, 5 Karten-Innenabstände (12–20), 25 Schriftgrößen inkl. Halbstufen; 19 von 46 Stellen nutzen Layout-Tokens.
10. **Kontraste**: Text auf Ladenfarben mit 85 % Deckkraft (10 Läden < 4,5:1); fast schwarze Ladenkacheln #2C2C2E verstoßen gegen „nie Schwarz“ und verschwinden im Dunkeln; Platzhalter „leer = für mich“ 1,72:1; Fremdfarben (Orange FF9F0A, System-Rot, kalte Systemgraus).
11. **Barrierefreiheit**: Tap-Ziele < 44 pt („…“ 36, Chips 35–37, „Alles“ 40, PIN-Pille 30); keine VoiceOver-Überschriften; Ziffernblock sagt Betrag nicht an; Stempel „EINGELÖST“ ignoriert Reduce Motion.
12. **Kleineres**: Scroll-Kante hart auf Start/Detail (leere Nav-Leiste), Wortmarke 3,7 pt eingerückt, Punkt skaliert nicht, Detail-Kachelraster mit halber Kachel, ungenutzte Komponenten (ActionRow, SectionHeader, SecondaryPill), Bon im Verlauf 11 pt Rand, „Rest-/wert“-Silbentrennung im Scan, App-Icon nur 65 % Füllung ohne Dark/Tinted-Variante.

## Nicht ändern (Lob)
Gelbes Summen-Ticket, Regel „Ladenfarbe = Kartenfarbe“, ruhige Kasse, Kerben auf der Abrisslinie auch bei XL,
warme Dunkelflächen, kalibrierte Status-Tokens (muted/warn ≥ 4,8:1), Texte in den Kernmomenten, CardRow-VoiceOver-Satz.

## Umsetzung (nach der Runde)

| Befund | Umgesetzt |
|---|---|
| Stempel im Dunkeln unlesbar | `UsedUpStamp` nutzt `onBrand` (immer Tinte auf Gelb) |
| Schatten mit `ink` | neues Token `shade` (hell 8 % Tinte, dunkel 45 % Schwarz) an allen 5 Stellen |
| Schalter im Dunkeln | Token `toggleOn` (Grün) für alle Toggles |
| Onboarding ohne Marke | gemeinsame `Wordmark`, gelbes Summen-Ticket, Rand 16 pt, Claim „Kein Restwert bleibt liegen.“ |
| Zwei Ticket-Systeme | `Perforation` entfernt; Kasse nutzt `TicketHalf` (echte halbe Kerben), eine Strichelung `DashLine` für Ticket und Bon, beginnt und endet mit vollem Strich |
| Abreißen | unterer Abschnitt samt Papier kippt nach unten weg (Drehung +9°, 160 pt) |
| Betragsschrift | Komma auf der Grundlinie, proportionale Ziffern (`Font.display`), Cent oben bündig |
| Kasse | „Bezahlt“ → eigener Ziffernblock (Route `.pay`, zählt als Kassentest); Knöpfe im Daumenbereich; bei XL untereinander |
| Detail | „An der Kasse zeigen“ unten fixiert; Gruppen 12/24 pt; übrige Kachel volle Breite |
| Unterer Leerraum | `contentMargins` 120 → 24 pt; weiche Scroll-Kante überall |
| Tokens | `Layout.inset` 16 / `ticketInset` 20 / `tap` 44; Radien auf 3 Tokens; Schriftgrößen von 25 auf 9 Stufen |
| Chips/Auswahl | ein `FilterChip` (44 pt) für Start, Läden, Verlauf (statt Glas-Chips und Segment-Picker) |
| Ladenfarben | keine fast schwarzen Kacheln mehr (#52525B); Text auf Karte voll deckend; Aktions-Icons im Dunkeln neutral |
| Barrierefreiheit | Tippziele ≥ 44 pt („…“, Chips, „Alles“, Sortierung), Überschriften für VoiceOver, Ziffernblock sagt Betrag an und meldet Ablehnung, Stempel „Eingelöst“ beachtet Reduce Motion, Formular-Hinweis im Label statt im Platzhalter |
| Farben außerhalb | Orange → `soon`, Löschen → `bad`, Scan-Kachel in Tinte als Ticket |
| Sonstiges | Listenzeilen gleich hoch, Läden-Beschreibung 2 Zeilen, Kartennummer überall Mono und einzeilig, Wortmarke im Bon, App-Icon größer mit Dark- und Tinted-Variante, ungenutzte Bausteine entfernt |

Offen: „…“-Menü in „Alle Ablauftermine“, Such-Platzhalter (Systemfarbe).
