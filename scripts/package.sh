#!/usr/bin/env bash
# Packages build/MacWand.app into release downloads:
#   build/MacWand-<version>.dmg  (drag-to-Applications disk image)
#   build/MacWand-<version>.zip
# Run scripts/build.sh first.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/MacWand.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
STAGE="$ROOT/build/dmg"

rm -rf "$STAGE" "$ROOT/build/MacWand-$VERSION.dmg" "$ROOT/build/MacWand-$VERSION.zip"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "MacWand" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov \
  "$ROOT/build/MacWand-$VERSION.dmg" >/dev/null
ditto -c -k --keepParent "$APP" "$ROOT/build/MacWand-$VERSION.zip"
rm -rf "$STAGE"

ls -lh "$ROOT/build/MacWand-$VERSION".*
