#!/usr/bin/env bash
# Packages build/MacWand.app into release downloads:
#   build/MacWand-<version>.dmg  (drag-to-Applications disk image)
#   build/MacWand-<version>.zip
# each with a .sha256 checksum file. Run scripts/build.sh first.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/MacWand.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
STAGE="$ROOT/build/dmg"

rm -rf "$STAGE" "$ROOT/build/MacWand-$VERSION".*
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "MacWand" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov \
  "$ROOT/build/MacWand-$VERSION.dmg" >/dev/null
ditto -c -k --keepParent "$APP" "$ROOT/build/MacWand-$VERSION.zip"
rm -rf "$STAGE"

for file in "$ROOT/build/MacWand-$VERSION.dmg" "$ROOT/build/MacWand-$VERSION.zip"; do
  (cd "$ROOT/build" && shasum -a 256 "$(basename "$file")") > "$file.sha256"
done

ls -lh "$ROOT/build/MacWand-$VERSION".*
