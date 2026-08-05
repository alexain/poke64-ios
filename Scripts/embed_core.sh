#!/usr/bin/env bash
set -euo pipefail

CORE_NAME="vice_x64sc_libretro_ios.dylib"
SOURCE_CORE="${SRCROOT}/Vendor/Core/${CORE_NAME}"

# The supplied VICE build is for real iOS arm64 devices only.
if [[ "${PLATFORM_NAME:-}" != "iphoneos" ]]; then
  echo "note: VICE core not embedded for ${PLATFORM_NAME:-unknown}; simulator runs UI only."
  exit 0
fi

if [[ ! -f "${SOURCE_CORE}" ]]; then
  echo "warning: ${CORE_NAME} missing. Run Scripts/build_vice_core.sh first."
  exit 0
fi

DESTINATION_DIR="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"
DESTINATION_CORE="${DESTINATION_DIR}/${CORE_NAME}"
mkdir -p "${DESTINATION_DIR}"
cp -f "${SOURCE_CORE}" "${DESTINATION_CORE}"

if [[ "${CODE_SIGNING_ALLOWED:-NO}" == "YES" && -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]]; then
  /usr/bin/codesign \
    --force \
    --sign "${EXPANDED_CODE_SIGN_IDENTITY}" \
    --timestamp=none \
    "${DESTINATION_CORE}"
fi
