#!/bin/bash
# Packages NabBar for download: build/release/NabBar.dmg (the app and
# an Applications shortcut), the Touch Portal plugin, and their SHA-256 sums.
#
#   scripts/make-dmg.sh
#
# The app is signed ad hoc: a personal certificate would put its owner's name
# in a public download. It is not notarized, so macOS asks once before the
# first launch (see README, "Install").
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
OUT="$ROOT/build/release"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Sources/App/Info.plist)
DMG="$OUT/NabBar.dmg"   # a stable name, so releases/latest/download/NabBar.dmg always works

NABBAR_SIGN_IDENTITY=- scripts/build-local.sh

echo "==> Making $DMG"
rm -rf "$OUT" && mkdir -p "$OUT/stage"
ditto build/local/NabBar.app "$OUT/stage/NabBar.app"
ln -s /Applications "$OUT/stage/Applications"
hdiutil create -quiet -volname "NabBar $VERSION" -srcfolder "$OUT/stage" -fs HFS+ -format UDZO -ov "$DMG"
rm -rf "$OUT/stage"
cp build/local/NabBar.tpp "$OUT/NabBar-TouchPortal.tpp"

hdiutil verify -quiet "$DMG"
(cd "$OUT" && shasum -a 256 NabBar.dmg NabBar-TouchPortal.tpp > SHA256SUMS.txt)
echo "==> Done"
ls -lh "$OUT"
