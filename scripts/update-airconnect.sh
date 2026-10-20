#!/bin/bash
# Replaces the bundled airupnp with another AirConnect release.
#
#   scripts/update-airconnect.sh 1.12.5
#
# Afterwards: update Vendor/AirConnect/VERSION.md (tag, commit, hashes), check
# `airupnp -h` for changed flags, run the tests, and try it with your speakers.
set -euo pipefail

VERSION="${1:?Usage: $0 <AirConnect version, e.g. 1.12.5>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${ROOT}/Vendor/AirConnect"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

URL="https://github.com/philippe44/AirConnect/releases/download/${VERSION}/AirConnect-${VERSION}.zip"
echo "==> Downloading ${URL}"
curl -fL --progress-bar -o "${TMP}/AirConnect.zip" "${URL}"
unzip -q -o "${TMP}/AirConnect.zip" airupnp-macos-arm64-static -d "${TMP}"

install -m 0755 "${TMP}/airupnp-macos-arm64-static" "${DEST}/airupnp-macos-arm64-static"
xattr -c "${DEST}/airupnp-macos-arm64-static" 2>/dev/null || true
curl -fsSL -o "${DEST}/LICENSE" "https://raw.githubusercontent.com/philippe44/AirConnect/${VERSION}/LICENSE"

echo "zip sha256:    $(shasum -a 256 "${TMP}/AirConnect.zip" | cut -d' ' -f1)"
echo "binary sha256: $(shasum -a 256 "${DEST}/airupnp-macos-arm64-static" | cut -d' ' -f1)"
echo "commit:        $(git ls-remote https://github.com/philippe44/AirConnect "refs/tags/${VERSION}" | cut -f1)"
"${DEST}/airupnp-macos-arm64-static" -h 2>&1 | head -3 || true
echo "==> Now update Vendor/AirConnect/VERSION.md with the values above."
