#!/usr/bin/env bash
# Frische Installation und kompletter Screenshot-Satz für Beta-Tests (Scan, Kasse, Sperre, große Schrift, Kontrast, Dunkel).
# Aufruf aus ios/ (App vorher bauen):  scripts/beta-screens.sh <Simulator-UDID> [Ausgabeordner]
set -euo pipefail
U="$1"; O="${2:-build/beta-shots}"; B=de.restwert.app
APP="$(find build/sim/Build/Products -maxdepth 2 -name 'Restwert.app' -type d | head -1)"
rm -rf "$O"; mkdir -p "$O"
xcrun simctl ui "$U" appearance light; xcrun simctl ui "$U" increase_contrast disabled; xcrun simctl ui "$U" content_size large
xcrun simctl uninstall "$U" $B 2>/dev/null || true; xcrun simctl install "$U" "$APP"
shot() { local n="$1"; shift; xcrun simctl terminate "$U" $B 2>/dev/null || true; xcrun simctl launch "$U" $B "$@" >/dev/null; sleep "${WAIT:-5}"; xcrun simctl io "$U" screenshot "$O/$n.png" >/dev/null 2>&1; echo "📸 $n"; }
M=(-onboarded YES -appLock NO -codeLock NO)
shot einstieg -onboarded NO
shot start "${M[@]}"
shot hinzufuegen "${M[@]}" -demoScreen scan
shot detail "${M[@]}" -demoScreen detail
shot kasse "${M[@]}" -demoScreen checkout
shot einstellungen-schutz -onboarded YES -appLock NO -codeLock YES -lockDelay 60 -demoScreen settings
shot detail-code-geschuetzt -onboarded YES -appLock NO -codeLock YES -demoScreen detail
shot kasse-code-geschuetzt -onboarded YES -appLock NO -codeLock YES -demoScreen checkout
shot login-ohne-code -onboarded YES -appLock YES -simulateNoPasscode YES -codeLock NO
shot login-faceid -onboarded YES -appLock YES -simulateNoPasscode NO -codeLock NO
xcrun simctl spawn "$U" notifyutil -p com.apple.BiometricKit_Sim.pearl.match; sleep 3; xcrun simctl io "$U" screenshot "$O/login-entsperrt.png" >/dev/null 2>&1
# Schutz für geteilte Geräte ganz an: grüne Bestätigung in den Einstellungen (nach Face ID)
shot geteiltes-geraet-an -onboarded YES -appLock YES -codeLock YES -pinLock YES -simulateNoPasscode NO -demoScreen settings
xcrun simctl spawn "$U" notifyutil -p com.apple.BiometricKit_Sim.pearl.match; sleep 3; xcrun simctl io "$U" screenshot "$O/geteiltes-geraet-an.png" >/dev/null 2>&1
# Große Schrift, Kontrast erhöhen, Dunkelmodus
xcrun simctl ui "$U" content_size accessibility-extra-large
shot gross-start "${M[@]}"; shot gross-kasse "${M[@]}" -demoScreen checkout; shot gross-einstellungen "${M[@]}" -demoScreen settings
xcrun simctl ui "$U" content_size large; xcrun simctl ui "$U" increase_contrast enabled
shot kontrast-start "${M[@]}"; shot kontrast-einstellungen "${M[@]}" -demoScreen settings
xcrun simctl ui "$U" increase_contrast disabled; xcrun simctl ui "$U" appearance dark
shot dunkel-start "${M[@]}"; shot dunkel-kasse "${M[@]}" -demoScreen checkout
xcrun simctl ui "$U" appearance light
# Scan-Ergebnisse (danach, sie legen nichts an) und Lesefortschritt
DATA="$(xcrun simctl get_app_container "$U" $B data)"; mkdir -p "$DATA/Documents/scan-tests"; cp ../docs/evaluation/testgutscheine/v02* "$DATA/Documents/scan-tests/"
xcrun simctl terminate "$U" $B 2>/dev/null || true
xcrun simctl launch "$U" $B "${M[@]}" -demoImport "$DATA/Documents/scan-tests/v02-thalia-code128-pin.jpg" >/dev/null; sleep 2
xcrun simctl io "$U" screenshot "$O/lesen-fortschritt.png" >/dev/null 2>&1
scripts/scan-tests.sh "$U" "$O" >/dev/null
xcrun simctl ui "$U" content_size accessibility-extra-large
WAIT=16 scripts/scan-tests.sh "$U" "$O/gross" >/dev/null || true
xcrun simctl ui "$U" content_size large
# Zuletzt: diese Aufnahmen legen Testkarten an (ersetzen die Beispiele)
shot kasse-online "${M[@]}" -demoBarcode "text:AQ7K-2ZPM4H-R8TX@amazon"
shot kasse-code93 "${M[@]}" -demoBarcode "code128:C93-4471-2208" -demoOriginal "Code 93"
shot kasse-online-mindestbestellwert "${M[@]}" -demoBarcode "text:ZAL-SOMMER15-K4@zalando" -demoMinOrder 50
shot papier-foto-geschuetzt -onboarded YES -appLock NO -codeLock YES -demoScreen paper
scripts/barcode-kasse-test.sh "$U" "$O/barcodes" >/dev/null
xcrun simctl terminate "$U" $B 2>/dev/null || true
echo "fertig: $(ls "$O" | wc -l) Dateien"
