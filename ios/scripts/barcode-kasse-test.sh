#!/usr/bin/env bash
# Ende-zu-Ende-Barcodetest: öffnet für jedes Format die Kasse im Simulator und macht einen Screenshot.
# Die Screenshots liest danach ein echter Barcode-Leser (Vision auf dem Mac) zurück.
# Aufruf aus ios/ (App vorher bauen und installieren):  scripts/barcode-kasse-test.sh <Simulator-UDID> [Ausgabeordner]
set -euo pipefail
UDID="$1"; OUT="${2:-build/barcode-shots}"; BUNDLE_ID="de.restwert.app"
mkdir -p "$OUT"
CASES=(
  "ean13:4006381333931" "ean8:96385074" "upca:036000291452" "itf:00012345678905" "code39:GUTSCHEIN 42"
  "code128:6280123456789012" "code128:AQ7K-2ZPM4H-R8TX" "qr:IK-9934-2281-4410" "pdf417:5021009933447781"
  "aztec:KS-2026-004711" "dataMatrix:SG-2291-7730" "dataMatrix:6280 1234 5678 9012"
)
: > "$OUT/cases.txt"
i=0
for c in "${CASES[@]}"; do
  i=$((i+1))
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$BUNDLE_ID" -onboarded YES -appLock NO -codeLock NO -maskNumber NO -demoBarcode "$c" >/dev/null
  sleep "${WAIT:-4}"
  xcrun simctl io "$UDID" screenshot "$OUT/kasse-$i.png" >/dev/null 2>&1
  echo "kasse-$i.png|$c" >> "$OUT/cases.txt"
  echo "📸 $c"
done
