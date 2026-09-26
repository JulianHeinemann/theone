#!/usr/bin/env bash
# Baut Restwert für den Simulator, startet ihn und macht Screenshots aller Bildschirme plus ein kurzes Video.
# Aufruf aus ios/:  scripts/simulator-shots.sh   (Ergebnis in build/shots/)
set -euo pipefail

BUNDLE_ID="de.restwert.app"
OUT="build/shots"
mkdir -p "$OUT"

# Neuestes iPhone-Pro-Gerät der neuesten iOS-Laufzeit wählen
UDID="$(xcrun simctl list devices available -j | python3 -c '
import json, sys, re
data = json.load(sys.stdin)["devices"]
def ver(k):
    m = re.search(r"iOS-(\d+)-(\d+)", k)
    return (int(m.group(1)), int(m.group(2))) if m else (0, 0)
for runtime in sorted((k for k in data if "iOS" in k), key=ver, reverse=True):
    phones = [d for d in data[runtime] if d["name"].startswith("iPhone")]
    pro = [d for d in phones if "Pro" in d["name"] and "Max" not in d["name"]]
    pick = (pro or phones)
    if pick:
        print(pick[-1]["udid"]); break
')"
echo "Simulator: $(xcrun simctl list devices | grep "$UDID")"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b

set -o pipefail
xcodebuild -project Restwert.xcodeproj -scheme Restwert -configuration Debug \
  -destination "id=$UDID" -derivedDataPath build/sim \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | tee build/sim-build.log | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true
grep -q "BUILD SUCCEEDED" build/sim-build.log

APP="$(find build/sim/Build/Products -maxdepth 2 -name 'Restwert.app' -type d | head -1)"
xcrun simctl install "$UDID" "$APP"
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularBars 4 --wifiBars 3 --dataNetwork wifi || true
xcrun simctl ui "$UDID" appearance light || true

shot() {
  local name="$1"; shift
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$BUNDLE_ID" "$@" >/dev/null
  sleep "${WAIT:-5}"
  xcrun simctl io "$UDID" screenshot "$OUT/$name.png" >/dev/null
  echo "📸 $name"
}

MAIN=(-onboarded YES -authDecided YES)

WAIT=4 shot 01-onboarding -onboarded NO
WAIT=4 shot 02-login -onboarded YES -authDecided NO
shot 03-start "${MAIN[@]}"
shot 04-detail "${MAIN[@]}" -demoScreen detail
shot 05-radar "${MAIN[@]}" -demoScreen radar
shot 06-kasse "${MAIN[@]}" -demoScreen checkout
shot 07-betrag "${MAIN[@]}" -demoScreen keypad
shot 08-scannen "${MAIN[@]}" -demoScreen scan
shot 09-formular "${MAIN[@]}" -demoScreen form
shot 10-verlauf "${MAIN[@]}" -demoScreen history
shot 11-kassentest "${MAIN[@]}" -demoScreen tests
shot 12-haendler "${MAIN[@]}" -demoScreen merchants
shot 13-einstellungen "${MAIN[@]}" -demoScreen settings

# Kurzes Video vom Start-Bildschirm (Mesh-Verlauf) und vom Radar (Radarstrahl, Punkte)
record() {
  local name="$1"; shift
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl io "$UDID" recordVideo --codec h264 --force "$OUT/$name.mp4" &
  local rec=$!
  sleep 1
  xcrun simctl launch "$UDID" "$BUNDLE_ID" "$@" >/dev/null
  sleep 7
  kill -INT "$rec"
  wait "$rec" || true
  echo "🎬 $name"
}
record video-start "${MAIN[@]}"
record video-radar "${MAIN[@]}" -demoScreen radar

# Die gebaute App zum Selbst-Installieren im eigenen Simulator
(cd "$(dirname "$APP")" && zip -qry "$OLDPWD/$OUT/Restwert-Simulator.zip" Restwert.app)
ls -la "$OUT"
