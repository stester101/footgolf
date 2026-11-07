#!/usr/bin/env bash
# Structural verification of an exported APK. Usage: tools/scripts/verify_apk.sh <apk> [apksigner]
set -euo pipefail
APK="${1:?apk path}"
APKSIGNER="${2:-apksigner}"
[ -f "$APK" ] || { echo "APK missing: $APK"; exit 1; }
SIZE=$(stat -c %s "$APK")
[ "$SIZE" -gt 1000000 ] || { echo "APK suspiciously small: $SIZE bytes"; exit 1; }
unzip -tq "$APK" > /dev/null || { echo "APK is not a valid ZIP"; exit 1; }
LISTING=$(unzip -l "$APK")
for needed in "AndroidManifest.xml" "classes.dex" "lib/arm64-v8a/libgodot_android.so" "assets/project.binary" \
              "assets/data/footballers_seed.json" "assets/data/courses.json" "assets/data/holes/hole_01.json" "assets/data/holes/hole_09.json"; do
  echo "$LISTING" | grep -q " $needed\$" || { echo "Missing entry in APK: $needed"; exit 1; }
done
if echo "$LISTING" | grep -q "assets/tests/"; then echo "Test scripts leaked into APK"; exit 1; fi
"$APKSIGNER" verify --verbose "$APK" | grep -E "Verifies|Verified using v2"
echo "APK OK: $APK ($SIZE bytes) sha256=$(sha256sum "$APK" | cut -d' ' -f1)"
