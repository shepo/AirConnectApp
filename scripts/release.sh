#!/bin/bash
# Builds AirBridge with your Developer ID, notarises it, staples the ticket and
# zips it for release.
#
#   TEAM_ID=ABCDE12345 scripts/release.sh
#
# One-time setup (see README › Signing and notarising):
#   xcrun notarytool store-credentials AirBridge --apple-id you@example.com --team-id ABCDE12345
set -euo pipefail

: "${TEAM_ID:?Set TEAM_ID to your Apple Developer team ID}"
PROFILE="${NOTARY_PROFILE:-AirBridge}"
IDENTITY="Developer ID Application"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${ROOT}/build/release"
APP="${OUT}/AirBridge.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${ROOT}/AirBridge/Info.plist")"
ZIP="${OUT}/AirBridge-${VERSION}.zip"

rm -rf "${OUT}"
mkdir -p "${OUT}"

echo "==> Building ${VERSION}"
xcodebuild \
  -project "${ROOT}/AirBridge.xcodeproj" \
  -scheme AirBridge \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "${ROOT}/build/DerivedData" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="${IDENTITY}" \
  DEVELOPMENT_TEAM="${TEAM_ID}" \
  -quiet \
  clean build

BUILT="${ROOT}/build/DerivedData/Build/Products/Release/AirBridge.app"
ditto "${BUILT}" "${APP}"

echo "==> Checking signatures"
codesign --verify --deep --strict --verbose=2 "${APP}"
for item in "${APP}/Contents/Helpers/airupnp" "${APP}"; do
  info="$(codesign -dvv "${item}" 2>&1)"
  grep -q "Authority=Developer ID Application" <<<"${info}" || { echo "${item} isn't signed with Developer ID" >&2; exit 1; }
  grep -q "flags=.*runtime" <<<"${info}" || { echo "${item} lacks the hardened runtime" >&2; exit 1; }
  grep -q "Timestamp=" <<<"${info}" || { echo "${item} has no secure timestamp" >&2; exit 1; }
done

echo "==> Notarising (this can take a few minutes)"
ditto -c -k --keepParent "${APP}" "${OUT}/notarize.zip"
xcrun notarytool submit "${OUT}/notarize.zip" --keychain-profile "${PROFILE}" --wait
rm "${OUT}/notarize.zip"

echo "==> Stapling"
xcrun stapler staple "${APP}"
xcrun stapler validate "${APP}"
spctl --assess --type execute --verbose=2 "${APP}"

ditto -c -k --keepParent "${APP}" "${ZIP}"
shasum -a 256 "${ZIP}"
echo "==> Done: ${ZIP}"
