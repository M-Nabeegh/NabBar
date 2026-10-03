#!/bin/bash
# Builds NabBar: ClaudeBar under its own name, bundle id and settings folder
# (~/.nabbar), showing only Codex, Claude and Command Code, with Sparkle
# updates off. Ad-hoc signed, local only. Runs beside an installed ClaudeBar.
#
#   scripts/build-local.sh            build + package into build/local/
#   scripts/build-local.sh --install  also copy to /Applications/NabBar.app
#
# Never touches /Applications/ClaudeBar.app, ~/.claudebar, credentials or the Keychain.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
OUT="$ROOT/build/local"
APP_NAME="NabBar"
BUNDLE_ID="com.nabeegh.nabbar"
HOME_DIR_NAME=".nabbar"
DEST="/Applications/$APP_NAME.app"
PLIST_BUDDY=/usr/libexec/PlistBuddy

[[ "$DEST" == "/Applications/ClaudeBar.app" ]] && { echo "refusing to touch the release app" >&2; exit 1; }

echo "==> Generating project without the AWS SDK (Bedrock is hidden here)"
export TUIST_CLAUDEBAR_WITHOUT_AWS=1
tuist install
tuist generate --no-open

echo "==> Building (Release)"
xcodebuild build \
  -workspace ClaudeBar.xcworkspace \
  -scheme ClaudeBar \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$OUT/DerivedData" \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  -quiet

BUILT="$OUT/DerivedData/Build/Products/Release/ClaudeBar.app"
APP="$OUT/$APP_NAME.app"
rm -rf "$APP"
ditto "$BUILT" "$APP"

echo "==> Rebranding Info.plist"
INFO="$APP/Contents/Info.plist"
$PLIST_BUDDY -c "Set :CFBundleIdentifier $BUNDLE_ID" "$INFO"
$PLIST_BUDDY -c "Set :CFBundleName $APP_NAME" "$INFO"
$PLIST_BUDDY -c "Delete :CFBundleDisplayName" "$INFO" 2>/dev/null || true
$PLIST_BUDDY -c "Add :CFBundleDisplayName string $APP_NAME" "$INFO"
$PLIST_BUDDY -c "Set :NSHumanReadableCopyright Copyright 2026 M. Nabeegh. Based on ClaudeBar, copyright 2025 TDDWorks (MIT)." "$INFO"
# No Sparkle feed: the updater never starts, so this copy can't update into upstream.
$PLIST_BUDDY -c "Delete :SUFeedURL" "$INFO" 2>/dev/null || true
$PLIST_BUDDY -c "Delete :SUPublicEDKey" "$INFO" 2>/dev/null || true
$PLIST_BUDDY -c "Set :SUEnableAutomaticChecks false" "$INFO" 2>/dev/null || true
# The installed ClaudeBar owns the claudebar:// scheme.
$PLIST_BUDDY -c "Delete :CFBundleURLTypes" "$INFO" 2>/dev/null || true
$PLIST_BUDDY -c "Add :ClaudeBarHomeDirectory string $HOME_DIR_NAME" "$INFO"
$PLIST_BUDDY -c "Add :ClaudeBarProviderLineup array" "$INFO"
for id in codex claude commandcode; do
  $PLIST_BUDDY -c "Add :ClaudeBarProviderLineup: string $id" "$INFO"
done

echo "==> Ad-hoc signing"
codesign --force --deep --sign - \
  --entitlements "$ROOT/Sources/App/entitlements.plist" \
  --options runtime "$APP"
codesign --verify --deep --strict "$APP"
echo "    codesign --verify --deep --strict: OK"

seed_home() {
  local home="$HOME/$HOME_DIR_NAME"
  mkdir -p "$home/themes"
  # Muted slate palette, loaded through the app's imported-theme store.
  cp "$ROOT/scripts/local/muted-slate.json" "$home/themes/muted-slate.json"
  if [[ ! -f "$home/settings.json" ]]; then
    cat > "$home/settings.json" <<'JSON'
{
  "app": {
    "themeMode": "imported-muted-slate",
    "overviewModeEnabled": true,
    "backgroundSyncEnabled": true,
    "backgroundSyncInterval": 300,
    "menuBarPercentageEnabled": true,
    "menuBarPercentageProviderId": "codex",
    "menuBarAdditionalProviderIds": ["claude", "commandcode"]
  },
  "providers": { "order": ["codex", "claude", "commandcode"] }
}
JSON
  fi
  # ChatGPT.app bundles the Codex CLI outside every PATH the app searches.
  local codex="/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
  if [[ -x "$codex" ]]; then
    /usr/bin/python3 - "$home/settings.json" "$codex" <<'PY'
import json, sys
path, codex = sys.argv[1], sys.argv[2]
settings = json.load(open(path))
settings.setdefault("providers", {}).setdefault("codex", {}).setdefault("cliPath", codex)
json.dump(settings, open(path, "w"), indent=2)
PY
  fi
}

if [[ "${1:-}" == "--install" ]]; then
  echo "==> Installing to $DEST"
  pgrep -f "$DEST/Contents/MacOS/" >/dev/null && pkill -f "$DEST/Contents/MacOS/" || true
  rm -rf "$DEST"
  ditto "$APP" "$DEST"
  seed_home
  codesign --verify --deep --strict "$DEST"
  echo "    installed: $DEST"
fi

echo "==> Packaging the Touch Portal plugin"
rm -f "$OUT/$APP_NAME.tpp"
(cd "$ROOT/integrations/touchportal" && zip -qr "$OUT/$APP_NAME.tpp" NabBar -x '*/__pycache__/*')
echo "    $OUT/$APP_NAME.tpp (import in Touch Portal: Settings > Plug-ins)"

echo "==> Done: $APP"
