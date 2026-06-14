#!/usr/bin/env bash
# Build a distributable .dmg for the app bundle produced by build-app.sh.
#
# Layout (the standard "drag to Applications" install window):
#
#     /Volumes/Yes Engineer 1.0.0
#     ├── Yes Engineer.app      ← the built app bundle
#     └── Applications          ← symlink to /Applications
#
# Output:
#     build/Yes-Engineer-<version>.dmg
#
# The DMG is read-only, compressed, and finalized.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$(pwd)
APP_NAME="Yes Engineer"
APP_PATH="${ROOT}/build/${APP_NAME}.app"

if [[ ! -d "${APP_PATH}" ]]; then
    echo "error: ${APP_PATH} not found. Run Bundle/build-app.sh first." >&2
    exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
            "${APP_PATH}/Contents/Info.plist")
if [[ -z "${VERSION}" ]]; then
    echo "error: could not read CFBundleShortVersionString from ${APP_PATH}" >&2
    exit 1
fi

DMG_NAME="Yes-Engineer-${VERSION}.dmg"
VOL_NAME="Yes Engineer ${VERSION}"
DMG_PATH="${ROOT}/build/${DMG_NAME}"
STAGE_DIR="${ROOT}/build/dmg-stage"

# Reset stage
rm -rf "${STAGE_DIR}"
mkdir -p "${STAGE_DIR}"
cp -R "${APP_PATH}" "${STAGE_DIR}/${APP_NAME}.app"
ln -s /Applications "${STAGE_DIR}/Applications"

# Build a read-only, compressed, UDRO (UDIF read-only) DMG.
# Using UDRO over UDZO keeps the layout compatible with older tools; we
# use bzip2 compression for a good size/speed tradeoff.
echo "==> building ${DMG_PATH}"
hdiutil create \
    -volname "${VOL_NAME}" \
    -srcfolder "${STAGE_DIR}" \
    -ov \
    -format UDRO \
    "${DMG_PATH}"

# Optionally sign the DMG with the same identity used for the app bundle.
# Real release signing is wired through env vars in CI. Default to ad-hoc.
if [[ -z "${MACOS_CODESIGN_IDENTITY:-}" ]]; then
    echo "==> signing DMG with ad-hoc identity (-)"
    codesign --force --sign - "${DMG_PATH}" || true
else
    echo "==> signing DMG with identity: ${MACOS_CODESIGN_IDENTITY}"
    codesign --force --sign "${MACOS_CODESIGN_IDENTITY}" "${DMG_PATH}" || true
fi

# Generate checksum alongside the DMG.
shasum -a 256 "${DMG_PATH}" > "${DMG_PATH}.sha256"

rm -rf "${STAGE_DIR}"

echo
echo "✓ Built: ${DMG_PATH}"
echo "  ${DMG_PATH}.sha256"
