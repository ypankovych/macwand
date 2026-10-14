#!/usr/bin/env bash
# Builds build/MacWand.app: the Rust engine plus the SwiftUI app as universal
# (Apple silicon + Intel) binaries for macOS 12 and later, ad-hoc signed.
# Needs only the Xcode Command Line Tools and a Rust toolchain with both
# aarch64-apple-darwin and x86_64-apple-darwin targets.
# Set VERSION (e.g. VERSION=1.2.3) to stamp the bundle version; otherwise Info.plist's is kept.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/MacWand.app"
OBJ="$ROOT/build/obj"
CARGO="$(command -v cargo || echo "$HOME/.cargo/bin/cargo")"
SDK="$(xcrun --show-sdk-path)"
export MACOSX_DEPLOYMENT_TARGET=12.0

rm -rf "$APP" "$OBJ"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$OBJ"

for arch in arm64 x86_64; do
  rust_target="$([ "$arch" = arm64 ] && echo aarch64-apple-darwin || echo x86_64-apple-darwin)"

  echo "==> Engine ($arch)"
  "$CARGO" build --release --quiet --target "$rust_target" --manifest-path "$ROOT/engine/Cargo.toml"
  cp "$ROOT/engine/target/$rust_target/release/macwand-engine" "$OBJ/macwand-engine-$arch"

  echo "==> App ($arch)"
  find "$ROOT/app/Sources" -name '*.swift' -print0 \
    | xargs -0 swiftc -O -parse-as-library -target "$arch-apple-macos$MACOSX_DEPLOYMENT_TARGET" -sdk "$SDK" \
        -o "$OBJ/MacWand-$arch"
done

lipo -create "$OBJ/MacWand-arm64" "$OBJ/MacWand-x86_64" -output "$APP/Contents/MacOS/MacWand"
lipo -create "$OBJ/macwand-engine-arm64" "$OBJ/macwand-engine-x86_64" -output "$APP/Contents/MacOS/macwand-engine"
cp "$ROOT/app/Resources/Info.plist" "$APP/Contents/"
if [ -n "${VERSION:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
fi
cp "$ROOT/app/Resources/AppIcon.icns" "$APP/Contents/Resources/"

# Ad-hoc signature: enough to run locally and keep a stable identity for privacy permissions.
codesign --force --sign - "$APP/Contents/MacOS/macwand-engine"
codesign --force --sign - "$APP"

echo "==> $APP"
