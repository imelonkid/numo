#!/bin/bash
# Builds build/Numo.app (release, ad-hoc signed). No Xcode required.
set -euo pipefail
cd "$(dirname "$0")/.."

# VERSION may carry a pre-release suffix (0.1.0-dev.12); the bundle version keeps only the numeric part.
VERSION="${VERSION:-0.1.0}"
SHORT_VERSION="${VERSION%%-*}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
APP="build/Numo.app"

# Build outside the project folder: SwiftPM's SQLite build database fails in some synced folders.
SCRATCH="${NUMO_BUILD_DIR:-$HOME/Library/Caches/numo-build}"
if [ "${UNIVERSAL:-0}" = "1" ]; then
  # Apple silicon + Intel: build each arch on its own and merge with lipo.
  # (A single multi-arch `swift build` switches to the Xcode build system, which rejects
  # the target's swiftLanguageMode setting.)
  for arch in arm64 x86_64; do
    swift build -c release --product Numo --scratch-path "$SCRATCH" --arch "$arch"
  done
  BIN="$SCRATCH/Numo-universal"
  lipo -create -output "$BIN" \
    "$SCRATCH/arm64-apple-macosx/release/Numo" \
    "$SCRATCH/x86_64-apple-macosx/release/Numo"
else
  swift build -c release --product Numo --scratch-path "$SCRATCH"
  BIN="$SCRATCH/release/Numo"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Numo"

ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
swift scripts/make-icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Numo</string>
    <key>CFBundleDisplayName</key><string>Numo</string>
    <key>CFBundleIdentifier</key><string>com.melonkid.numo</string>
    <key>CFBundleExecutable</key><string>Numo</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${SHORT_VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Numo 文稿</string>
            <key>CFBundleTypeRole</key><string>Editor</string>
            <key>LSHandlerRank</key><string>Alternate</string>
            <key>LSItemContentTypes</key><array><string>public.plain-text</string></array>
            <key>NSDocumentClass</key><string>NumoDocument</string>
        </dict>
    </array>
    <key>NSHumanReadableCopyright</key><string>© 2026 melonkid</string>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"
echo "Built $APP"
