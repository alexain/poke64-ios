#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPOSITORY_NAME="${1:-poke64-ios}"
VISIBILITY="${2:-public}"
VERSION="$(tr -d '[:space:]' < "${ROOT_DIR}/VERSION")"

if [[ "${VISIBILITY}" != "public" && "${VISIBILITY}" != "private" ]]; then
  echo "Invalid visibility. Use public or private." >&2
  exit 1
fi

for command in gh git xcodegen; do
  if ! command -v "${command}" >/dev/null; then
    echo "Required command not found: ${command}" >&2
    exit 1
  fi
done

if ! gh auth status >/dev/null 2>&1; then
  echo "GitHub CLI is not authenticated. Run: gh auth login" >&2
  exit 1
fi

if ! git config user.name >/dev/null; then
  echo 'Configure Git first: git config --global user.name "Your Name"' >&2
  exit 1
fi

if ! git config user.email >/dev/null; then
  echo 'Configure Git first: git config --global user.email "you@example.com"' >&2
  exit 1
fi

cd "${ROOT_DIR}"
"${SCRIPT_DIR}/check_integrated_sources.sh"
"${SCRIPT_DIR}/bootstrap.sh"

if [[ ! -d .git ]]; then
  git init
  git branch -M main
fi

git add .

# Refuse to publish local build outputs or user-imported firmware.
if git diff --cached --name-only | grep -E '(^|/)(Vendor/vice-libretro-src|DerivedData|xcuserdata)(/|$)|\.dylib$|external-firmware-(source-patch|verification)-report\.json$|\.(bin|rom)$'; then
  echo "Refusing to publish local core, firmware, VICE source, or Xcode user/build data." >&2
  exit 1
fi

if ! git diff --cached --quiet; then
  git commit -m "POKE64 ${VERSION}"
fi

if ! git remote get-url origin >/dev/null 2>&1; then
  gh repo create "${REPOSITORY_NAME}" \
    "--${VISIBILITY}" \
    --source=. \
    --remote=origin \
    --push \
    --description="POKE64: native Commodore 64 emulator for iPad, powered by VICE x64sc and libretro"
else
  git push -u origin main
fi

gh repo edit \
  --description="POKE64: native Commodore 64 emulator for iPad, powered by VICE x64sc and libretro" \
  --homepage="https://www.alexain.it/poke64"

TAG="v${VERSION}"
if ! git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null; then
  git tag -a "${TAG}" -m "POKE64 ${VERSION}"
fi

git push origin "${TAG}"
printf '\nRepository published: %s\n' "$(gh repo view --json url --jq .url)"
