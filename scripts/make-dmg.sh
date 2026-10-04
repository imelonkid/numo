#!/bin/bash
# Packages build/Numo.app into build/Numo-<VERSION>.dmg (drag-to-Applications layout).
# Builds the app first unless SKIP_BUILD=1.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.1.0}"
export VERSION
[ "${SKIP_BUILD:-0}" = "1" ] || scripts/build-app.sh

APP="build/Numo.app"
STAGE="build/dmg"
DMG="build/Numo-${VERSION}.dmg"

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "Numo" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
echo "Built $DMG"
