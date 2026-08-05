#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

if ! command -v xcodegen >/dev/null; then
  cat >&2 <<'MESSAGE'
XcodeGen is not installed.
Install it with Homebrew:
  brew install xcodegen
MESSAGE
  exit 1
fi

cd "${ROOT_DIR}"
xcodegen generate
printf '\nGenerated project: %s\n' "${ROOT_DIR}/POKE64.xcodeproj"
