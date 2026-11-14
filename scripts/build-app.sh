#!/bin/bash
# Builds BodyTracking with SwiftPM and wraps the binary in a signed .app bundle.
#
# Environment overrides:
#   SIGN_IDENTITY  codesign identity (default "-" = ad-hoc, runs on this Mac only)
#   BUNDLE_ID      bundle identifier (default com.spatial-workshops.BodyTracking)
#   VERSION        marketing version (default 0.1.0)
#   BUILD_NUMBER   build number (default: git commit count)
#   UNIVERSAL=1    build arm64 + x86_64 (requires full Xcode, not just CLT)
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="BodyTracking"
BUNDLE_ID="${BUNDLE_ID:-com.spatial-workshops.BodyTracking}"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP="build/${APP_NAME}.app"

ARCH_FLAGS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

echo "==> Compiling (release)"
swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

echo "==> Assembling ${APP}"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BIN_DIR}/${APP_NAME}" "${APP}/Contents/MacOS/${APP_NAME}"
cp Support/Info.plist "${APP}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${BUNDLE_ID}" "${APP}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${APP}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "${APP}/Contents/Info.plist"

echo "==> Signing with identity: ${SIGN_IDENTITY}"
SIGN_FLAGS=(--force --options runtime --entitlements Support/BodyTracking.entitlements --sign "${SIGN_IDENTITY}")
if [[ "${SIGN_IDENTITY}" != "-" ]]; then
    SIGN_FLAGS+=(--timestamp)
fi
codesign "${SIGN_FLAGS[@]}" "${APP}"
codesign --verify --strict --verbose=2 "${APP}"

echo "==> Done: ${APP}"
echo "    Run it with: open ${APP}"
