#!/bin/bash
#
#  build-app.sh
#  Network Scanner
#
#  Copyright © 2026 Advandz Technologies, LLC.
#

# Builds "Network Scanner.app" as a universal (Apple Silicon + Intel) binary, and the disk image
# a GitHub release carries for the app's updater.
#   ./build-app.sh            → "build/Network Scanner.app" and build/Network-Scanner-<version>.dmg
#   ./build-app.sh --open     → build and launch
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Network Scanner.app"

echo "▸ Compiling universal release binary (arm64 + x86_64)…"
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/NetScanner"

if [ ! -f Resources/AppIcon.icns ]; then
    echo "▸ Rendering fallback app icon…"
    Scripts/make-icon.sh
fi

echo "▸ Assembling $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NetScanner"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/oui.txt "$APP/Contents/Resources/oui.txt"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf "APPL????" > "$APP/Contents/PkgInfo"

# App icon. Resources/AppIcon.icon is an Icon Composer document (Liquid Glass, with Default, Dark,
# Clear and Tinted appearances). Xcode's actool compiles it into Assets.car; without Xcode the
# static AppIcon.icns rendered from it (Scripts/make-icon.sh) is used.
if xcrun --find actool >/dev/null 2>&1; then
    echo "▸ Compiling Liquid Glass icon…"
    ICON_OBJ="$(mktemp -d)"
    # Absolute paths: actool hands off to a long-lived helper (ibtoold) that resolves relative paths
    # against its own working directory, so a relative path fails whenever that helper started elsewhere.
    if xcrun actool "$PWD/Resources/AppIcon.icon" \
        --compile "$PWD/$APP/Contents/Resources" \
        --platform macosx --target-device mac \
        --minimum-deployment-target "$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" Resources/Info.plist)" \
        --app-icon AppIcon --include-all-app-icons \
        --output-partial-info-plist "$ICON_OBJ/AppIcon-partial.plist" \
        --errors --warnings >/dev/null; then
        /usr/libexec/PlistBuddy -c "Add :CFBundleIconName string AppIcon" "$APP/Contents/Info.plist"
    else
        echo "  actool failed; using the static AppIcon.icns" >&2
        cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
    fi
    rm -rf "$ICON_OBJ"
else
    echo "▸ Using the static icon (install Xcode 26 to compile the Liquid Glass AppIcon.icon)"
fi

echo "▸ Compiling localizations…"
xcrun xcstringstool compile Resources/Localizable.xcstrings --output-directory "$APP/Contents/Resources"
xcrun xcstringstool compile Resources/InfoPlist.xcstrings --output-directory "$APP/Contents/Resources"
# Declare every compiled language so macOS (and the standard menus) offer it.
PLIST="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleLocalizations array" "$PLIST"
for dir in "$APP"/Contents/Resources/*.lproj; do
    /usr/libexec/PlistBuddy -c "Add :CFBundleLocalizations: string $(basename "$dir" .lproj)" "$PLIST"
done
echo "  $(/usr/libexec/PlistBuddy -c "Print :CFBundleLocalizations" "$PLIST" | sed -n 's/^ *//p' | grep -v '[{}]' | tr '\n' ' ')"

echo "▸ Signing (ad-hoc, hardened runtime)…"
# The hardened runtime stops other code being injected into the app (DYLD_INSERT_LIBRARIES, unsigned
# libraries). Under it, Location access needs its entitlement: the Wi-Fi tab uses it for BSSIDs.
codesign --force --sign - --timestamp=none --options runtime --entitlements Resources/NetScanner.entitlements "$APP"
# The updater checks the downloaded app's signature the same way.
codesign --verify --strict "$APP"

echo "▸ Architectures: $(lipo -archs "$APP/Contents/MacOS/NetScanner")"
echo "✓ Built $APP"

# Disk image: the app plus a shortcut to /Applications to drag it onto.
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)"
DMG="build/Network-Scanner-$VERSION.dmg"
echo "▸ Packing $DMG…"
STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE:?}"' EXIT
ditto "$APP" "$STAGE/Network Scanner.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG" "$DMG.sig"
hdiutil create -volname "Network Scanner $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null
echo "✓ Packed $DMG"

# The updater installs a disk image only with a valid "<image>.sig" made with the release key, which
# lives outside the repository (Scripts/update-key.swift). Macs without the key still build, unsigned.
if [ -f "${NETWORK_SCANNER_SIGNING_KEY:-$HOME/.com.advandz.networkscanner/update-signing.key}" ]; then
    echo "▸ Signing $DMG for the updater…"
    swift Scripts/update-key.swift sign "$DMG"
else
    echo "  No update-signing key: $DMG isn't signed, so the updater won't install it." >&2
fi

if [[ "${1:-}" == "--open" ]]; then
    open "$APP"
fi
