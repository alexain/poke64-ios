#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
required=(
  "POKE64/App/ContentView.swift"
  "POKE64/App/EmulatorModel.swift"
  "POKE64/App/FirmwareStore.swift"
  "POKE64/App/FirmwareSettingsView.swift"
  "POKE64/App/SettingsView.swift"
  "POKE64/App/HardwareKeyboardCapture.swift"
  "POKE64/App/C64KeyboardView.swift"
  "POKE64/LibretroHost/LibretroSession.h"
  "POKE64/LibretroHost/LibretroSession.mm"
  "Scripts/build_vice_core.sh"
  "Scripts/prepare_external_firmware_core.py"
  "Scripts/verify_external_firmware_core.py"
  "Scripts/test_external_firmware_tools.py"
  "project.yml"
)

for file in "${required[@]}"; do
  [[ -f "${ROOT}/${file}" ]] || { echo "Missing: ${file}" >&2; exit 1; }
done

grep -q 'func setRawKey' "${ROOT}/POKE64/App/EmulatorModel.swift"
grep -q 'firmwareConfigurationChanged' "${ROOT}/POKE64/App/EmulatorModel.swift"
grep -q 'SettingsView' "${ROOT}/POKE64/App/ContentView.swift"
grep -q 'NavigationSplitView' "${ROOT}/POKE64/App/SettingsView.swift"
grep -q 'FirmwareSettingsView' "${ROOT}/POKE64/App/SettingsView.swift"
grep -q 'setRawKeyCode' "${ROOT}/POKE64/LibretroHost/LibretroSession.h"
grep -q 'prepare_external_firmware_core.py' "${ROOT}/Scripts/build_vice_core.sh"
grep -q 'verify_external_firmware_core.py' "${ROOT}/Scripts/build_vice_core.sh"
! grep -q 'scrub_embedded_firmware.py' "${ROOT}/Scripts/build_vice_core.sh"
grep -q 'RETRO_ENVIRONMENT_SHUTDOWN' "${ROOT}/POKE64/LibretroHost/LibretroSession.mm"
grep -q 'firstRunCompleted' "${ROOT}/POKE64/LibretroHost/LibretroSession.mm"
python3 -m py_compile "${ROOT}/Scripts/prepare_external_firmware_core.py" "${ROOT}/Scripts/verify_external_firmware_core.py" "${ROOT}/Scripts/test_external_firmware_tools.py"
python3 "${ROOT}/Scripts/test_external_firmware_tools.py" >/dev/null

echo "Integrated source checks: OK"
