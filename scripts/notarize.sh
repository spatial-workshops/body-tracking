#!/bin/bash
# Notarizes and staples build/BodyTracking.app, then produces a distributable zip.
# Build first with a Developer ID identity:
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build-app.sh
#
# Required environment:
#   NOTARY_PROFILE  keychain profile created with `xcrun notarytool store-credentials`
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/BodyTracking.app"
ZIP="build/BodyTracking.zip"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile name}"

[[ -d "${APP}" ]] || { echo "error: ${APP} not found; run scripts/build-app.sh first" >&2; exit 1; }
if codesign -dv "${APP}" 2>&1 | grep -q "Signature=adhoc"; then
    echo "error: ${APP} is ad-hoc signed; rebuild with SIGN_IDENTITY set to a Developer ID identity" >&2
    exit 1
fi

echo "==> Zipping for submission"
rm -f "${ZIP}"
ditto -c -k --keepParent "${APP}" "${ZIP}"

echo "==> Submitting to Apple notary service (this can take a few minutes)"
xcrun notarytool submit "${ZIP}" --keychain-profile "${NOTARY_PROFILE}" --wait

echo "==> Stapling ticket"
xcrun stapler staple "${APP}"

echo "==> Re-zipping stapled app"
rm -f "${ZIP}"
ditto -c -k --keepParent "${APP}" "${ZIP}"

spctl --assess --type execute --verbose=2 "${APP}"
echo "==> Done: ${ZIP}"
