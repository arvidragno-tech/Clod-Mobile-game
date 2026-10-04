#!/usr/bin/env bash
# Exports the Windows build and packages it as a distributable zip:
#   build/UndercityRipper-<version>-windows-x64.zip
#     UndercityRipper.exe   (single file, .pck embedded)
#     README.txt            (controls, save location)
#     LICENSES/             (font licences)
# Usage: tools/package_windows.sh [path-to-godot]   (default: godot on PATH)
set -euo pipefail
GODOT="${1:-godot}"
cd "$(dirname "$0")/.."
VERSION="$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot)"
NAME="UndercityRipper-${VERSION}-windows-x64"
OUT="build/${NAME}"
[ -d .godot ] || "$GODOT" --headless --path . --import >/dev/null 2>&1
mkdir -p build/windows
"$GODOT" --headless --path . --export-release "Windows Desktop" build/windows/UndercityRipper.exe
rm -rf "$OUT" "build/${NAME}.zip"
mkdir -p "$OUT"
cp build/windows/UndercityRipper.exe "$OUT/"
cp -r LICENSES "$OUT/"
cat > "$OUT/README.txt" <<TXT
UNDERCITY: RIPPER ${VERSION} - Windows PC (1920x1080, mouse + keyboard)

Run UndercityRipper.exe. No installation or admin rights needed.

Controls: left click select/use tool, drag to cut and move, right click puts
the tool down, wheel zooms, ESC pause/back, TAB cycle panels, 1-9 tools,
Q/R previous/next tool, Z/X/V emergency actions, SPACE contextual action,
I inventory, B cyberware database, J journal, M facility, C customer,
F5 quick save, F9 quick load. Rebind keys in SETTINGS > CONTROLS.

Saves and settings: %APPDATA%\\UndercityRipper\\
  (C:\\Users\\<you>\\AppData\\Roaming\\UndercityRipper\\saves\\slot_1.json ...)

Requires Windows 10/11 64-bit and an OpenGL 3.3 capable GPU.
TXT
(cd build && zip -qr "${NAME}.zip" "${NAME}")
echo "packaged build/${NAME}.zip"
