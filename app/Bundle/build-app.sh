#!/usr/bin/env bash
# Build Yes Engineer.app from SwiftPM products.
# Usage: ./Bundle/build-app.sh   (run from app/ root)
#
# Environment variables:
#   BUILD_ARCHS  Space-separated list of architectures to build.
#                Default: "arm64". Set to "arm64 x86_64" for a universal
#                (Intel + Apple Silicon) binary.
#   MACOS_CODESIGN_IDENTITY
#                Codesign identity to use. Default: ad-hoc ("-").
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$(pwd)
APP_NAME="Yes Engineer"
APP="${ROOT}/build/${APP_NAME}.app"

ARCHS=${BUILD_ARCHS:-arm64}
echo "==> swift build -c release (archs: ${ARCHS})"
# SwiftPM only supports a single --arch per invocation, so build each
# arch into its own bin dir, then lipo the executables into a universal
# binary if more than one arch is requested.
BIN_DIRS=()
for ARCH in ${ARCHS}; do
    swift build -c release --arch "${ARCH}"
    BIN_DIR=$(swift build -c release --arch "${ARCH}" --show-bin-path)
    BIN_DIRS+=("${BIN_DIR}")
    echo "    bin dir (${ARCH}): ${BIN_DIR}"
done

# Pick the first arch's bin dir as the source for non-binary resources.
PRIMARY_BIN_DIR="${BIN_DIRS[0]:-}"
NUM_ARCHS=${#BIN_DIRS[@]}

echo "==> assembling bundle at ${APP}"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS"
mkdir -p "${APP}/Contents/Library/LaunchDaemons"
mkdir -p "${APP}/Contents/Resources"

copy_or_lipo() {
    local target_path="$1"
    local binary_name="$2"
    if [[ "${NUM_ARCHS}" -eq 1 ]]; then
        cp "${BIN_DIRS[0]}/${binary_name}" "${target_path}"
    else
        # Lipo all archs into a single universal binary.
        local -a inputs=()
        for DIR in "${BIN_DIRS[@]}"; do
            inputs+=("${DIR}/${binary_name}")
        done
        lipo -create "${inputs[@]}" -output "${target_path}"
    fi
}

copy_or_lipo "${APP}/Contents/MacOS/YesEngineer" YesEngineer
copy_or_lipo "${APP}/Contents/Library/LaunchDaemons/YesEngineerDaemon" YesEngineerDaemon
cp "${ROOT}/Bundle/Info.plist" "${APP}/Contents/Info.plist"
cp "${ROOT}/Bundle/ai.yesengineer.daemon.plist" \
    "${APP}/Contents/Library/LaunchDaemons/ai.yesengineer.daemon.plist"
if [ -f "${ROOT}/Bundle/AppIcon.icns" ]; then
    cp "${ROOT}/Bundle/AppIcon.icns" "${APP}/Contents/Resources/AppIcon.icns"
fi

# Sign with a real identity if MACOS_CODESIGN_IDENTITY is set,
# otherwise fall back to ad-hoc.
SIGN_IDENTITY="${MACOS_CODESIGN_IDENTITY:--}"
SIGN_LABEL="${SIGN_IDENTITY:--}"
if [[ "${SIGN_IDENTITY}" == "-" ]]; then
    echo "==> codesign (ad-hoc)"
else
    echo "==> codesign (identity: ${SIGN_IDENTITY})"
fi
codesign --force --sign "${SIGN_IDENTITY}" --options runtime \
    "${APP}/Contents/Library/LaunchDaemons/YesEngineerDaemon"
codesign --force --sign "${SIGN_IDENTITY}" --deep --options runtime "${APP}"

echo "==> verify"
codesign -dvv "${APP}" 2>&1 | head -10 || true
if [[ "${NUM_ARCHS}" -gt 1 ]]; then
    echo "==> lipo info (universal binary)"
    lipo -info "${APP}/Contents/MacOS/YesEngineer" || true
fi

echo
echo "✓ Built: ${APP}"
echo "  Install:  cp -r '${APP}' /Applications/"
echo "  Run:      open /Applications/${APP_NAME}.app"
echo "  Package:  ./Bundle/build-dmg.sh"
