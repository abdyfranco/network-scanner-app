#!/bin/bash
#
#  update-strings.sh
#  Network Scanner
#
#  Copyright © 2026 Advandz Technologies, LLC.
#

# Refreshes Resources/Localizable.xcstrings from the source code.
# The compiler lists every localizable string (Text("…"), String(localized: "…"), LocalizedStringKey
# parameters…), then xcstringstool adds new keys to the catalog and marks removed ones stale.
# Translate new keys in Xcode (open the .xcstrings file) or any editor; build-app.sh compiles the catalog.
set -euo pipefail
cd "$(dirname "$0")/.."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "▸ Extracting localizable strings…"
swift build -c release --scratch-path "$WORK/build" \
    -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$WORK/strings" >/dev/null

echo "▸ Syncing Resources/Localizable.xcstrings…"
xcrun xcstringstool sync Resources/Localizable.xcstrings --stringsdata "$WORK"/strings/*.stringsdata
echo "✓ $(xcrun xcstringstool print Resources/Localizable.xcstrings | wc -l | tr -d ' ') keys in the catalog"

# Lists any new keys that still need translating.
Scripts/check-strings.py || true
