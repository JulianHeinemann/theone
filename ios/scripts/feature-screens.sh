#!/usr/bin/env bash
# Screenshots der neuen Funktionen (Speichern mit einem Tipp, Mindestbestellwert, Musterwarnung, Dublette,
# eigene Gutscheine ausgeben und einlösen) auf dem iPhone-Simulator und die Hauptscreens auf dem iPad-Simulator.
# Aufruf aus ios/:  scripts/feature-screens.sh <iPhone-UDID> <iPad-UDID> [Ausgabeordner]
set -euo pipefail
U="$1"; P="$2"; O="${3:-build/beta-shots}"; B=de.restwert.app
APP="$(find build/sim/Build/Products -maxdepth 2 -name 'Restwert.app' -type d | head -1)"
SRC="$(cd "$(dirname "$0")/../../docs/evaluation/testgutscheine" && pwd)"
mkdir -p "$O"
xcrun simctl uninstall "$U" $B 2>/dev/null || true; xcrun simctl install "$U" "$APP"
DATA="$(xcrun simctl get_app_container "$U" $B data)"; mkdir -p "$DATA/Documents/scan-tests"; cp "$SRC"/v0[13569]* "$DATA/Documents/scan-tests/"
BASE=(-onboarded YES -appLock NO -codeLock NO -askedNotifyAfterSave YES)
run() { local n="$1" w="$2"; shift 2; xcrun simctl terminate "$U" $B 2>/dev/null || true
        xcrun simctl launch "$U" $B "${BASE[@]}" "$@" >/dev/null; sleep "$w"; xcrun simctl io "$U" screenshot "$O/$n.png" >/dev/null 2>&1; echo "📸 $n"; }
imp() { echo "$DATA/Documents/scan-tests/$1"; }
run ein-tipp-speichern 16 -demoImport "$(imp v01-douglas-ean13.jpg)"
run mindestbestellwert 16 -demoImport "$(imp v05-zalando-rabatt-mbw.jpg)"
# Speichern mit einem Tipp: Douglas speichern, danach bleibt man im Hinzufügen-Tab
run gespeichert-im-tab 16 -demoOpenForm YES -demoAutoSave YES -demoImport "$(imp v01-douglas-ean13.jpg)"
# Dublette: denselben Gutschein noch einmal scannen
# Mehrere Fotos auf einmal (wie Mehrfachauswahl in „Aus Fotos“): erstes Ergebnis mit „Foto 1 von 3“
run mehrere-fotos 16 -demoImportBatch "$(imp v05-zalando-rabatt-mbw.jpg)|$(imp v06-mediamarkt-falsche-pruefziffer.jpg)|$(imp v09-amazon-online.jpg)"
run dublette 16 -demoImport "$(imp v01-douglas-ean13.jpg)"
xcrun simctl ui "$U" content_size accessibility-extra-large
run gross-dublette 20 -demoImport "$(imp v01-douglas-ean13.jpg)"
xcrun simctl ui "$U" content_size large
# Musterwarnung: erst Amazon (1.250 €) speichern, dann IKEA (100 €) scannen
run amazon-gespeichert 16 -demoOpenForm YES -demoAutoSave YES -demoImport "$(imp v09-amazon-online.jpg)"
cp "$SRC"/v03* "$DATA/Documents/scan-tests/"
run musterwarnung 16 -demoImport "$(imp v03-ikea-qr-rotated.jpg)"
# Eigenen Gutschein ausgeben, dann seinen QR-Code scannen (Einlösen aus Laden-Sicht)
run ausgeben-teilen 7 -demoScreen issue -demoIssueAuto YES
xcrun simctl ui "$U" content_size accessibility-extra-large
run gross-ausgeben 7 -demoScreen issue -demoIssueAuto YES
xcrun simctl ui "$U" content_size large
CODE=$(python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print([c['number'] for c in d['cards'] if c.get('issuedByMe')][-1])" "$DATA/Library/Application Support/restwert.json")
"$(dirname "$0")/qr-image.sh" "$CODE" "$DATA/Documents/scan-tests/eigener-qr.png"
run eigener-gutschein-einloesen 9 -demoImport "$DATA/Documents/scan-tests/eigener-qr.png"
xcrun simctl ui "$U" content_size accessibility-extra-large
run gross-eigener-gutschein-einloesen 9 -demoImport "$DATA/Documents/scan-tests/eigener-qr.png"
xcrun simctl ui "$U" content_size large
run liste-ausgegeben 5
run liste-ausgegeben-filter 5 -demoFilter issued
xcrun simctl terminate "$U" $B 2>/dev/null || true
# iPad
xcrun simctl install "$P" "$APP"
for spec in "start:" "kasse:checkout" "einstellungen:settings" "hinzufuegen:scan" "detail:detail"; do
  n="${spec%%:*}"; s="${spec#*:}"; ARGS=("${BASE[@]}"); [ -n "$s" ] && ARGS+=(-demoScreen "$s")
  xcrun simctl terminate "$P" $B 2>/dev/null || true; xcrun simctl launch "$P" $B "${ARGS[@]}" >/dev/null; sleep 6
  xcrun simctl io "$P" screenshot "$O/ipad-$n.png" >/dev/null 2>&1; echo "📸 ipad-$n"
done
xcrun simctl terminate "$P" $B 2>/dev/null || true
