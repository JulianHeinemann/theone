# Kontrollrunde 2 „Das Ticket“ (10 simulierte Design-Personas, intensiv)

Stand: Commit 6b8b5d0 (nach Umbau, 4-seitiger Einstieg, Verfallsradar, geschätztes Ablaufdatum, Speichern im Hintergrund).
Dieselben 10 simulierten Personas wie in Runde 1. 45 Screenshots aus dem Simulator „Restwert Frisch“ (hell, dunkel, XL, 4 Einstiegsseiten, 4 Scroll-Positionen), Pixelmessungen. Animation/Performance nur aus dem Code.

## Noten (Ø, Runde 1 → Runde 2)

| Kategorie | R1 | R2 | Δ |
|---|---|---|---|
| Gesamt | 6.9 | 7.0 | +0.1 |
| **Markencharakter** | 6.0 | **7.6** | **+1.6** |
| Konsistenz | 5.8 | 6.4 | +0.6 |
| Farbe | 7.4 | 7.5 | +0.1 |
| Typografie | 7.1 | 7.2 | +0.1 |
| Dunkelmodus | 6.9 | 7.0 | +0.1 |
| Abstände/Raster | 6.8 | 6.9 | +0.1 |
| Komponenten | 6.6 | 6.9 | +0.3 |
| Premium-Gefühl | 6.5 | 6.8 | +0.3 |
| Ikonografie | 6.7 | 6.7 | 0 |
| **Hierarchie** | 8.0 | **7.2** | **−0.8** |
| **Barrierefreiheit** | 6.5 | **6.2** | **−0.3** |

10/10 erkennen eine eigene Marke (R1: 9/10). 132 Befunde, 15 „hoch“ (R1: 24).
Die Marke hat den großen Sprung gemacht. Die neuen Teile (Radar, Einstieg) bringen aber alte Fehlerklassen zurück (XL, Tippziele) und der Radar drückt „Läuft bald ab“ nach unten (Hierarchie −0.8).

## Übereinstimmende Befunde

1. **Radar bei XL: Jahreszahlen überlappen („20292030“)** – 8 von 10. Feste 64-pt-Labelbox ohne Kollisionsprüfung; auf Start XL liegt die Achse unter der Tab-Leiste.
2. **Radar-Tippziele überlappen ~50 %** (Spurabstand 22 pt bei 44-pt-Knöpfen); VoiceOver ohne Betrag/Datum; ohne Beträge eher Deko; Hülle ohne Ticket-Form (Fremdkörper).
3. **Einstieg XL: Fließtext läuft unter die Seitenpunkte** und wird abgeschnitten – 5 von 10. Seite 4: Punkte/Knopf springen ~48 pt nach oben.
4. **Kasse: doppelter Tipp auf „Bezahlt“ legt zwei Ziffernblöcke** auf den Stapel; abgerissene Hälfte springt zurück (im Code bestätigt).
5. **Schatten ohne `.compositingGroup()`** auf Einstieg-Ticket und Detailkarte → im Dunkeln Textschatten, Gelb wird Senf, Teal fleckig. Schatten generell ohne System (Start-Summe flach, Einstieg/Detail mit Schatten).
6. **Ladenfarben-Kontrast:** 8 Läden < 4,5:1 (Netflix, Lieferando, Primark, Zalando …) → Schriftfarbe automatisch Tinte/Weiß wählen. Amazon/Schiefer im Dunkeln kaum sichtbar; Douglas = Stadtgutschein gleiches Grau.
7. **Ziffernblock:** Inhalt zentriert statt linksbündig (x 44 statt 16); Tasten ohne Ruhefläche (im Dunkeln unsichtbar), wachsen nicht mit Schrift; „Alles“ oben außer Daumenreichweite; Betrag ohne Preisschild-Form; VoiceOver sagt Summe nicht nach jeder Taste.
8. **Hierarchie Start:** Summe + Radar vor „Läuft bald ab“ – nur 1,5 dringende Zeilen sichtbar.
9. **„…“-Menü fehlt in Ablauftermine**; Monatsköpfe ohne Überschrift-Trait.
10. **Zwei Logos:** Einstieg-Mitteilung zeigt Fantasie-Icon statt App-Icon; App-Icon bei 29–40 px unleserlich, Balken wirkt wie Schieberegler.
11. **„Geschätzt“** nur in Formular und Detail, nicht in Liste/Radar/Ablaufterminen/Erinnerungen.
12. **Kleineres:** kalte Systemgraus (Schalter aus, Segment, muted dunkel), Barcode-Platte ohne Radius, Formular-Platzhalter 1,72:1, gelbe Aktionskachel „Karte scannen“ im Einstieg bricht die Gelb-Regel, Wortmarke auf Start 4–5 pt versetzt, Läden-Titel 56 pt höher als andere Tabs, Einstieg baut CardRow nach, gerade Apostrophe, 4 Begriffe für Ablauf, Einstieg zeigt die Kasse nicht, Einstieg-Haptik doppelt / Reduce Motion nur teilweise, Barcode/Foto werden bei jedem Neuzeichnen auf dem Main-Thread erzeugt, Widget-Update/Schlüsselbund noch synchron.

## Nachweislich behoben (aus R1)
Stempel/Schatten/Schalter im Dunkeln, echte Ticket-Hälften an der Kasse, eine Strichelung, Komma auf Grundlinie + Cent bündig, 9 Textstufen, 48/55 Radien über Tokens, ein FilterChip, 16-pt-Rand überall, Detail 12/24-Takt, Kasse einhändig (Knöpfe unten), XL-Kassenknöpfe gestapelt, Reduce Motion bei Stempel/Kasse, Suche fest oben, Speichern im Hintergrund.
