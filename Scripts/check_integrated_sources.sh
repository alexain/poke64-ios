#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
required=(
  "POKE64/App/ContentView.swift"
  "POKE64/App/EmulatorModel.swift"
  "POKE64/App/FirmwareStore.swift"
  "POKE64/App/FirmwareSettingsView.swift"
  "POKE64/App/HardwareKeyboardCapture.swift"
  "POKE64/App/C64KeyboardView.swift"
  "POKE64/LibretroHost/LibretroSession.h"
  "POKE64/LibretroHost/LibretroSession.mm"
  "Scripts/build_vice_core.sh"
  "Scripts/scrub_embedded_firmware.py"
  "project.yml"
)

for file in "${required[@]}"; do
  [[ -f "${ROOT}/${file}" ]] || { echo "Missing: ${file}" >&2; exit 1; }
done

grep -q 'func setRawKey' "${ROOT}/POKE64/App/EmulatorModel.swift"
grep -q 'firmwareConfigurationChanged' "${ROOT}/POKE64/App/EmulatorModel.swift"
grep -q 'FirmwareSettingsView' "${ROOT}/POKE64/App/ContentView.swift"
grep -q 'setRawKeyCode' "${ROOT}/POKE64/LibretroHost/LibretroSession.h"
grep -q 'scrub_embedded_firmware.py' "${ROOT}/Scripts/build_vice_core.sh"
python3 -m py_compile "${ROOT}/Scripts/scrub_embedded_firmware.py"

echo "Integrated source checks: OK"
