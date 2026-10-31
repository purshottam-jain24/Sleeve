#!/usr/bin/env bash
# Builds Sleeve.app from the Swift package.
#
#   scripts/build-app.sh                 # release build, ad-hoc signed
#   CONFIG=debug scripts/build-app.sh
#   SIGN_IDENTITY="Apple Development: …" scripts/build-app.sh
#
# Ad-hoc signatures change on every build, so macOS asks for Automation and
# System Audio Recording permission again after each rebuild. Use a real signing
# identity (SIGN_IDENTITY) for stable permissions during development.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${CONFIG:-release}"
ARCHS="${ARCHS:-arm64}"
IDENTITY="${SIGN_IDENTITY:--}"
APP="$ROOT/build/Sleeve.app"

cd "$ROOT"
ARCH_FLAGS=()
for arch in $ARCHS; do ARCH_FLAGS+=(--arch "$arch"); done

swift build -c "$CONFIG" "${ARCH_FLAGS[@]}"
BIN_DIR="$(swift build -c "$CONFIG" "${ARCH_FLAGS[@]}" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Sleeve" "$APP/Contents/MacOS/Sleeve"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# The "Sleeve" screensaver plug-in (plays the wallpaper video), one slice per arch.
SAVER="$APP/Contents/Resources/Sleeve.saver"
SAVER_TMP="$ROOT/build/saver"
mkdir -p "$SAVER/Contents/MacOS" "$SAVER_TMP"
SLICES=()
for arch in $ARCHS; do
    OPT="-O"; [[ "$CONFIG" == debug ]] && OPT="-Onone"
    swiftc "$OPT" -parse-as-library -emit-library -module-name SleeveSaver \
        -target "$arch-apple-macos14" -framework ScreenSaver -framework AVFoundation \
        "$ROOT/Screensaver/SleeveSaverView.swift" -o "$SAVER_TMP/SleeveSaver-$arch"
    SLICES+=("$SAVER_TMP/SleeveSaver-$arch")
done
lipo -create "${SLICES[@]}" -output "$SAVER/Contents/MacOS/SleeveSaver"
rm -rf "$SAVER_TMP"
cp "$ROOT/Resources/Saver-Info.plist" "$SAVER/Contents/Info.plist"

# Developer ID signatures need a secure timestamp for notarization; ad-hoc ones can't have one.
TIMESTAMP="--timestamp=none"
if [[ "$IDENTITY" == Developer\ ID* ]]; then TIMESTAMP="--timestamp"; fi
codesign --force --options runtime "$TIMESTAMP" --sign "$IDENTITY" "$SAVER"
codesign --force --options runtime "$TIMESTAMP" \
    --entitlements "$ROOT/Resources/Sleeve.entitlements" \
    --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"

echo "Built $APP"
