#!/bin/bash
# Builds NabBar, ad-hoc signs it, verifies the signature and packages the
# Touch Portal plugin. NabBar's name, bundle id, URL scheme, settings folder
# (~/.nabbar) and provider lineup all come from Sources/App/Info.plist.
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
HOME_DIR_NAME=".nabbar"
DEST="/Applications/$APP_NAME.app"

[[ "$DEST" == "/Applications/ClaudeBar.app" ]] && { echo "refusing to touch ClaudeBar" >&2; exit 1; }

echo "==> Generating the project (without the AWS SDK; Bedrock is hidden)"
tuist install
tuist generate --no-open

echo "==> Building (Release)"
xcodebuild build \
  -workspace NabBar.xcworkspace \
  -scheme NabBar \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$OUT/DerivedData" \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  -quiet

APP="$OUT/$APP_NAME.app"
rm -rf "$APP"
ditto "$OUT/DerivedData/Build/Products/Release/$APP_NAME.app" "$APP"

# Ad-hoc signatures change with every build, so macOS asks again for NabBar's
# Keychain item after each one. A stable identity makes one "Always Allow"
# last across rebuilds. In order: $NABBAR_SIGN_IDENTITY, a self-signed
# "NabBar Local" certificate, the Mac's Apple Development certificate, ad hoc.
identities=$(security find-identity -p codesigning 2>/dev/null)
if [[ -n "${NABBAR_SIGN_IDENTITY:-}" ]]; then
  SIGN_IDENTITY="$NABBAR_SIGN_IDENTITY"
elif grep -q '"NabBar Local"' <<<"$identities"; then
  SIGN_IDENTITY="NabBar Local"
else
  SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk '/"Apple Development: /{print $2; exit}')
fi
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  echo "==> Ad-hoc signing (asked for)"
elif [[ -n "$SIGN_IDENTITY" ]]; then
  echo "==> Signing with a stable identity"
else
  echo "==> Ad-hoc signing (no certificate found; macOS will ask for Keychain access after each rebuild)"
  SIGN_IDENTITY="-"
fi
codesign --force --deep --sign "$SIGN_IDENTITY" \
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
