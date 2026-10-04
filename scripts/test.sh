#!/bin/bash
# Runs the NumoCore tests. With only Command Line Tools installed (no Xcode),
# swift-testing lives outside the default search paths, so we point at it explicitly.
set -euo pipefail
cd "$(dirname "$0")/.."

DEV="$(xcode-select -p)"
FW="$DEV/Library/Developer/Frameworks"
LIB="$DEV/Library/Developer/usr/lib"
# Build outside the project folder: SwiftPM's SQLite build database fails in some synced folders.
SCRATCH="${NUMO_BUILD_DIR:-$HOME/Library/Caches/numo-build}"

if [ -d "$FW/Testing.framework" ]; then
  exec swift test --scratch-path "$SCRATCH" \
    -Xswiftc -F -Xswiftc "$FW" \
    -Xlinker -F -Xlinker "$FW" \
    -Xlinker -rpath -Xlinker "$FW" \
    -Xlinker -rpath -Xlinker "$LIB" \
    "$@"
else
  exec swift test --scratch-path "$SCRATCH" "$@"
fi
