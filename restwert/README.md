# Restwert – Testversion

Web-App zum Ausprobieren, ob Gutscheinkarten an der Kasse ohne Plastikkarte funktionieren.

- Karte fotografieren (oder Screenshot einfügen): Barcode und Typ werden erkannt (BarcodeDetector bzw. ZXing).
- Barcode im Originalformat nachbauen (JsBarcode: Code 128, EAN-13/8, ITF, Code 39, UPC; QR über ZXing).
- Restguthaben führen, Einkäufe abziehen, Ablauf nach § 195 BGB (3 Jahre ab Jahresende) vorschlagen.
- „An der Kasse zeigen“: weißer Vollbild-Barcode, danach Ergebnis „Geklappt/Abgelehnt“ speichern.
- Händlerliste mit Rechercheergebnis (Stand 25.09.2026), ob digitale Einlösung offiziell möglich ist.

Daten liegen nur im `localStorage` des Browsers und sind in dieser Testversion nicht verschlüsselt.
