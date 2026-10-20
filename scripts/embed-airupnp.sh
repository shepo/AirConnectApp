#!/bin/bash
# Xcode build phase: copies airupnp into AirBridge.app/Contents/Helpers, makes it
# executable, signs it with the app's identity and the hardened runtime, and
# copies AirConnect's licence files into Contents/Resources/AirConnect.
#
# Runs before Xcode signs the app itself, so the helper is sealed inside the
# app's signature. Code must live in Contents/Helpers (not Resources), or
# codesign treats it as data and notarisation rejects it.
set -euo pipefail

SRC="${SRCROOT}/Vendor/AirConnect"
CONTENTS="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}"
HELPERS="${CONTENTS}/Helpers"
RESOURCES="${CONTENTS}/Resources/AirConnect"
HELPER="${HELPERS}/airupnp"

mkdir -p "${HELPERS}" "${RESOURCES}"
install -m 0755 "${SRC}/airupnp-macos-arm64-static" "${HELPER}"
# A downloaded binary carries com.apple.quarantine; it must not reach the app.
xattr -c "${HELPER}" 2>/dev/null || true

install -m 0644 "${SRC}/LICENSE" "${RESOURCES}/LICENSE.txt"
install -m 0644 "${SRC}/COPYING" "${RESOURCES}/COPYING.txt"
install -m 0644 "${SRC}/VERSION.md" "${RESOURCES}/VERSION.md"

if [[ "${CODE_SIGNING_ALLOWED:-YES}" == "NO" ]]; then
  echo "Code signing disabled; leaving airupnp with its upstream signature."
  exit 0
fi

IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-}"
if [[ -z "${IDENTITY}" ]]; then
  IDENTITY="-" # ad hoc: enough to run on this Mac
fi

FLAGS=(--force --options runtime)
if [[ "${IDENTITY}" == "-" || "${CONFIGURATION}" != "Release" ]]; then
  FLAGS+=(--timestamp=none)
else
  FLAGS+=(--timestamp) # notarisation needs a secure timestamp
fi

/usr/bin/codesign "${FLAGS[@]}" --sign "${IDENTITY}" "${HELPER}"
/usr/bin/codesign --verify --strict --verbose=1 "${HELPER}"
echo "Embedded and signed airupnp with ${IDENTITY}"
