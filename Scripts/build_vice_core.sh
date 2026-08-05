#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SOURCE_DIR="${ROOT_DIR}/Vendor/vice-libretro-src"
OUTPUT_DIR="${ROOT_DIR}/Vendor/Core"
OUTPUT_CORE="${OUTPUT_DIR}/vice_x64sc_libretro_ios.dylib"
SOURCE_PATCH_REPORT="${OUTPUT_DIR}/external-firmware-source-patch-report.json"
VERIFICATION_REPORT="${OUTPUT_DIR}/external-firmware-verification-report.json"
VICE_REF="${VICE_REF:-master}"
DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-17.0}"
JOBS="${JOBS:-$(sysctl -n hw.logicalcpu 2>/dev/null || echo 4)}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script must run on macOS with Xcode installed." >&2
  exit 1
fi

xcode-select -p >/dev/null
command -v git >/dev/null
command -v make >/dev/null
command -v python3 >/dev/null
command -v sed >/dev/null

if [[ ! -d "${SOURCE_DIR}/.git" ]]; then
  git clone https://github.com/libretro/vice-libretro.git "${SOURCE_DIR}"
fi

# Vendor/vice-libretro-src is managed by this script. Always reset to the
# selected upstream revision before applying the local iOS compatibility fix.
git -C "${SOURCE_DIR}" reset --hard HEAD >/dev/null
git -C "${SOURCE_DIR}" fetch --tags origin
git -C "${SOURCE_DIR}" checkout "${VICE_REF}"
if [[ "${VICE_REF}" == "master" ]]; then
  git -C "${SOURCE_DIR}" pull --ff-only origin master
fi

# Apple Clang 17+ predefines TARGET_OS_* based on the compilation target.
# The old vendored zlib branch otherwise replaces fdopen() on iOS.
ZUTIL_HEADER="${SOURCE_DIR}/deps/libz/zutil.h"
ZUTIL_OLD='#if defined(MACOS) || defined(TARGET_OS_MAC)'
ZUTIL_NEW='#if (defined(MACOS) || defined(TARGET_OS_MAC)) && !defined(IOS)'

if grep -Fqx "${ZUTIL_OLD}" "${ZUTIL_HEADER}"; then
  sed -i '' \
    's/^#if defined(MACOS) || defined(TARGET_OS_MAC)$/#if (defined(MACOS) || defined(TARGET_OS_MAC)) \&\& !defined(IOS)/' \
    "${ZUTIL_HEADER}"
elif ! grep -Fqx "${ZUTIL_NEW}" "${ZUTIL_HEADER}"; then
  echo "Unable to apply the zlib compatibility patch: unexpected file structure in ${ZUTIL_HEADER}" >&2
  exit 1
fi

# Disable the libretro embedded-firmware path in the fetched source tree before
# compilation. The patch script fails closed if upstream layout has changed.
python3 "${SCRIPT_DIR}/prepare_external_firmware_core.py" \
  --source "${SOURCE_DIR}" \
  --report "${SOURCE_PATCH_REPORT}"

make -C "${SOURCE_DIR}" clean EMUTYPE=x64sc || true
make -C "${SOURCE_DIR}" \
  -j"${JOBS}" \
  platform=ios-arm64 \
  EMUTYPE=x64sc \
  MINVERSION="-miphoneos-version-min=${DEPLOYMENT_TARGET}"

mkdir -p "${OUTPUT_DIR}"
cp -f "${SOURCE_DIR}/vice_x64sc_libretro_ios.dylib" "${OUTPUT_CORE}"

# Verify the linked dylib without modifying it. Any exact ROM payload found in
# the final Mach-O is a hard build failure.
python3 "${SCRIPT_DIR}/verify_external_firmware_core.py" \
  --core "${OUTPUT_CORE}" \
  --source "${SOURCE_DIR}" \
  --report "${VERIFICATION_REPORT}"

printf '\nSource-level external-firmware-only core created at:\n  %s\n' "${OUTPUT_CORE}"
printf 'Source patch report:\n  %s\n' "${SOURCE_PATCH_REPORT}"
printf 'Firmware verification report:\n  %s\n' "${VERIFICATION_REPORT}"
file "${OUTPUT_CORE}"
printf 'VICE revision:\n  %s\n' "$(git -C "${SOURCE_DIR}" rev-parse HEAD)"
