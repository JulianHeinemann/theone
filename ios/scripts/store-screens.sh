#!/usr/bin/env bash
# App-Store-Screenshots (6,9", 1320 × 2868) mit Überschrift – nur erfundene Läden, keine echten Marken.
# Aufruf aus ios/:  scripts/store-screens.sh [Simulator-UDID eines iPhone Pro Max]
# Ergebnis: ../docs/appstore/screenshots/ (gerahmt) und …/raw/ (unbearbeitet).
set -euo pipefail
U="${1:-$(xcrun simctl list devices available | grep -m1 'iPhone 17 Pro Max' | grep -oE '[0-9A-F-]{36}')}"
B=de.restwert.app
OUT="../docs/appstore/screenshots"; RAW="$OUT/raw"; mkdir -p "$RAW"
TEST="$(cd ../docs/evaluation/testgutscheine && pwd)"
xcrun simctl boot "$U" 2>/dev/null || true; xcrun simctl bootstatus "$U" -b >/dev/null
xcodebuild -project Restwert.xcodeproj -scheme Restwert -destination "id=$U" -derivedDataPath build/sim build 2>&1 | grep -E "error:|BUILD" 
APP="$(find build/sim/Build/Products -maxdepth 2 -name 'Restwert.app' -type d | head -1)"
xcrun simctl uninstall "$U" $B 2>/dev/null || true; xcrun simctl install "$U" "$APP"
xcrun simctl status_bar "$U" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 --dataNetwork wifi
xcrun simctl ui "$U" content_size large
BASE=(-onboarded YES -appLock NO -codeLock NO -askedNotifyAfterSave YES -storeShots YES)
shot() { local n="$1" w="$2"; shift 2; xcrun simctl terminate "$U" $B 2>/dev/null || true
         xcrun simctl launch "$U" $B "${BASE[@]}" "$@" >/dev/null; sleep "$w"
         xcrun simctl io "$U" screenshot "$RAW/$n.png" >/dev/null 2>&1; echo "📸 $n"; }
xcrun simctl ui "$U" appearance light
shot 01_start 6
shot 02_checkout 6 -demoScreen checkout
shot 03_scan 25 -demoImport "$TEST/v15-coupon-gratis-kaffee.jpg"
shot 04_detail 6 -demoScreen detail
shot 05_radar 6 -demoScreen radar
shot 06_keypad 6 -demoScreen keypad -demoKeypad 7,80
xcrun simctl ui "$U" appearance dark
shot 07_start_dunkel 6
xcrun simctl ui "$U" appearance light
F="scripts/store-frame.py"
python3 $F "$RAW/01_start.png" "$OUT/01_start.png" "Kein Gutschein\nverfällt mehr." "Guthaben, Fristen und Codes an einem Ort."
python3 $F "$RAW/02_checkout.png" "$OUT/02_checkout.png" "An der Kasse:\nCode zeigen, fertig." "Groß, hell und scanbar. Danach den Rest abziehen."
python3 $F "$RAW/03_scan.png" "$OUT/03_scan.png" "Scannen statt\nabtippen." "Gutscheine, Coupons, Vorder- und Rückseite."
python3 $F "$RAW/04_detail.png" "$OUT/04_detail.png" "Jeder Euro\nnachvollziehbar." "Verlauf, PIN hinter Face ID, Ablauf im Blick."
python3 $F "$RAW/05_radar.png" "$OUT/05_radar.png" "Was bald\nabläuft, zuerst." "Das Verfallsradar zeigt, was wann fällig wird."
python3 $F "$RAW/06_keypad.png" "$OUT/06_keypad.png" "Einkauf abziehen,\nRest stimmt." "Ein Betrag, ein Tipp – das Guthaben ist aktuell."
python3 $F "$RAW/07_start_dunkel.png" "$OUT/07_start_dunkel.png" "Auch im\nDunkeln schön." "Hell, dunkel und große Schrift – alles passt." dark
echo "Fertig: $OUT"
