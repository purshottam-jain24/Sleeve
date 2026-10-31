#!/usr/bin/env bash
# Builds a distributable Sleeve-<version>.dmg in dist/.
#
#   scripts/make-dmg.sh
#       Universal (Apple Silicon + Intel), ad-hoc signed. Downloaders approve it once in
#       System Settings › Privacy & Security ("Open Anyway"); see the DMG's read-me.
#
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" NOTARY_PROFILE=sleeve scripts/make-dmg.sh
#       Signed with Developer ID, notarized by Apple and stapled: opens with no warning.
#       Create the profile once with:
#       xcrun notarytool store-credentials sleeve --apple-id you@example.com --team-id TEAMID
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
IDENTITY="${SIGN_IDENTITY:--}"
APP="$ROOT/build/Sleeve.app"
DIST="$ROOT/dist"
DMG="$DIST/Sleeve-$VERSION.dmg"

if [[ -n "${NOTARY_PROFILE:-}" && "$IDENTITY" != Developer\ ID* ]]; then
    echo "Notarization needs a 'Developer ID Application' SIGN_IDENTITY." >&2
    exit 1
fi

echo "==> Building Sleeve $VERSION (universal)"
CONFIG=release ARCHS="arm64 x86_64" SIGN_IDENTITY="$IDENTITY" scripts/build-app.sh
lipo -info "$APP/Contents/MacOS/Sleeve"

echo "==> Assembling disk image"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/Sleeve.app"
ln -s /Applications "$STAGE/Applications"
if [[ "$IDENTITY" == "-" ]]; then
    cp "$ROOT/scripts/dmg-readme.txt" "$STAGE/Read Me First.txt"
fi

mkdir -p "$DIST"
rm -f "$DMG"
hdiutil create -volname "Sleeve $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" >/dev/null

if [[ "$IDENTITY" != "-" ]]; then
    codesign --force --timestamp --sign "$IDENTITY" "$DMG"
fi

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    echo "==> Notarizing (this can take a few minutes)"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature -v "$DMG"
fi

(cd "$DIST" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
echo "==> $DMG ($(du -h "$DMG" | cut -f1))"
cat "$DMG.sha256"
