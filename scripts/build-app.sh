#!/usr/bin/env bash
# Builds Afterglow.app from the Swift package.
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
APP="$ROOT/build/Afterglow.app"

cd "$ROOT"
ARCH_FLAGS=()
for arch in $ARCHS; do ARCH_FLAGS+=(--arch "$arch"); done

swift build -c "$CONFIG" "${ARCH_FLAGS[@]}"
BIN_DIR="$(swift build -c "$CONFIG" "${ARCH_FLAGS[@]}" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Afterglow" "$APP/Contents/MacOS/Afterglow"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

codesign --force --options runtime --timestamp=none \
    --entitlements "$ROOT/Resources/Afterglow.entitlements" \
    --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"

echo "Built $APP"
