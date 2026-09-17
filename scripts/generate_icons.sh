#!/usr/bin/env bash
# Regenerates the legacy launcher PNGs from design/app_icon.html.
#
# Only API 24-25 use these; API 26+ uses the adaptive vector icon that
# configure_android.py writes, so this is rarely needed. Run it if you change
# the mark.
set -euo pipefail
cd "$(dirname "$0")/.."

TMP=$(mktemp -d)
cp design/app_icon.html "$TMP/"
qlmanage -t -s 512 -o "$TMP" "$TMP/app_icon.html" >/dev/null 2>&1
SRC="$TMP/app_icon.html.png"
[ -f "$SRC" ] || { echo "Render failed"; exit 1; }

for pair in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  d="${pair%%:*}"; px="${pair##*:}"
  out="android/app/src/main/res/mipmap-$d/ic_launcher.png"
  mkdir -p "$(dirname "$out")"
  sips -z "$px" "$px" "$SRC" --out "$out" >/dev/null 2>&1
  echo "  $d ${px}x${px}"
done
rm -rf "$TMP"
echo "Legacy launcher icons regenerated."
