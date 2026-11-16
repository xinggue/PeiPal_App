#!/usr/bin/env bash
set -euo pipefail

for name in MACOS_CERTIFICATE_BASE64 MACOS_CERTIFICATE_PASSWORD MACOS_TEAM_ID MACOS_NOTARY_KEY_BASE64 MACOS_NOTARY_KEY_ID MACOS_NOTARY_ISSUER_ID; do
  if [[ -z "${!name:-}" ]]; then
    printf 'Missing %s\n' "$name" >&2
    exit 1
  fi
done

APP="build/macos/Build/Products/Release/PeiPal.app"
DMG="PeiPal-macOS.dmg"
[[ -d "$APP" ]] || { printf 'Build PeiPal.app before packaging.\n' >&2; exit 1; }

WORK=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/peipal-signing.XXXXXX")
KEYCHAIN="$WORK/signing.keychain-db"
KEYCHAIN_PASSWORD=$(openssl rand -hex 32)
if [[ "${GITHUB_ACTIONS:-}" == true ]]; then
  printf '::add-mask::%s\n' "$KEYCHAIN_PASSWORD"
fi
cleanup() {
  security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT
umask 077
printf '%s' "$MACOS_CERTIFICATE_BASE64" | base64 --decode > "$WORK/certificate.p12"
printf '%s' "$MACOS_NOTARY_KEY_BASE64" | base64 --decode > "$WORK/notary.p8"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$WORK/certificate.p12" -k "$KEYCHAIN" \
  -P "$MACOS_CERTIFICATE_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: \
  -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null

IDENTITY=$(security find-identity -v -p codesigning "$KEYCHAIN" | \
  python3 -c 'import os,re,sys
matches = re.findall(r"([A-F0-9]{40}) \"Developer ID Application: [^\"]+ \(" + re.escape(os.environ["MACOS_TEAM_ID"]) + r"\)\"", sys.stdin.read())
if len(matches) != 1:
    sys.exit("Expected exactly one valid Developer ID Application identity for MACOS_TEAM_ID")
print(matches[0])')

# Sign nested code before its containing bundles; do not use --deep to sign.
while IFS= read -r -d '' binary; do
  if file -b "$binary" | /usr/bin/grep -q 'Mach-O'; then
    codesign --force --timestamp --options runtime --keychain "$KEYCHAIN" \
      --sign "$IDENTITY" "$binary"
  fi
done < <(find "$APP/Contents" -type f -print0)
while IFS= read -r -d '' bundle; do
  codesign --force --timestamp --options runtime --keychain "$KEYCHAIN" \
    --sign "$IDENTITY" "$bundle"
done < <(find "$APP/Contents" -depth -type d \( -name '*.framework' -o -name '*.app' -o -name '*.xpc' \) -print0)
codesign --force --timestamp --options runtime --keychain "$KEYCHAIN" \
  --entitlements macos/Runner/Release.entitlements --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

notarize() {
  xcrun notarytool submit "$1" --key "$WORK/notary.p8" \
    --key-id "$MACOS_NOTARY_KEY_ID" --issuer "$MACOS_NOTARY_ISSUER_ID" \
    --wait --output-format json > "$WORK/notary-result.json"
  python3 -c 'import json,sys
result=json.load(open(sys.argv[1]))
print("Apple notarization:", result.get("status"), "submission:", result.get("id"))
if result.get("status") != "Accepted":
    sys.exit("Apple did not accept the notarization submission")' "$WORK/notary-result.json"
}

ditto -c -k --keepParent "$APP" "$WORK/PeiPal.zip"
notarize "$WORK/PeiPal.zip"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"

mkdir "$WORK/installer"
ditto "$APP" "$WORK/installer/PeiPal.app"
ln -s /Applications "$WORK/installer/Applications"
hdiutil create -volname PeiPal -srcfolder "$WORK/installer" -ov -format UDZO "$DMG"
codesign --force --timestamp --keychain "$KEYCHAIN" --sign "$IDENTITY" "$DMG"
notarize "$DMG"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
