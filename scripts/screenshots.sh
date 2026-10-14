#!/usr/bin/env bash
# Regenerates docs/screenshots/*.png from the real UI with demo scan results.
# Nothing is scanned and nothing is shown on screen.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/screenshots"
mkdir -p "$OUT"

SOURCES=()
while IFS= read -r -d '' file; do
  [ "$(basename "$file")" = "MacWandApp.swift" ] || SOURCES+=("$file")
done < <(find "$ROOT/app/Sources" -name '*.swift' -print0)

swiftc -O -sdk "$(xcrun --show-sdk-path)" -o "$OUT/screenshots" \
  "${SOURCES[@]}" "$ROOT/scripts/screenshots/main.swift"
"$OUT/screenshots" "$ROOT/docs/screenshots"
