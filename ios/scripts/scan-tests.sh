#!/usr/bin/env bash
# Liest alle Testgutscheine aus docs/evaluation/testgutscheine im Simulator ein und macht vom Ergebnis je einen Screenshot.
# Aufruf aus ios/ (App vorher bauen und installieren):  scripts/scan-tests.sh <Simulator-UDID> [Ausgabeordner]
set -euo pipefail
UDID="$1"; OUT="${2:-build/scan-shots}"; BUNDLE_ID="de.restwert.app"
SRC="$(cd "$(dirname "$0")/../../docs/evaluation/testgutscheine" && pwd)"
mkdir -p "$OUT"
for f in "$SRC"/v*.{jpg,pdf,txt}; do
  [ -e "$f" ] || continue
  name="$(basename "$f")"; id="${name%%-*}"
  # iOS leert tmp gelegentlich: vor jedem Lauf frisch in den App-Container kopieren.
  DATA="$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)"
  mkdir -p "$DATA/Documents/scan-tests"; cp "$f" "$DATA/Documents/scan-tests/"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$BUNDLE_ID" -onboarded YES -appLock NO -demoImport "$DATA/Documents/scan-tests/$name" >/dev/null
  sleep "${WAIT:-16}"
  xcrun simctl io "$UDID" screenshot "$OUT/scan-$id.png" >/dev/null 2>&1
  echo "📸 $id"
done
