#!/bin/bash
# Rebuild one patched Wine PE DLL into the arm64 build tree and install it
# into the Wine runtime.   Usage: ./build-dll.sh <dll>   e.g. ./build-dll.sh oleaut32
#
# Build tree: ~/reverengineer/wine-build (configured from wine/ at tag wine-11.18)
# Runtime:    ~/reverengineer/runtime/Wine Devel.app  (Gcenx wine-devel 11.18)
set -euo pipefail

DLL="${1:?usage: build-dll.sh <dll>  e.g. build-dll.sh oleaut32}"
BASE="$HOME/reverengineer"
SRC="$BASE/wine"
BUILD="$BASE/wine-build"
DEST="$BASE/runtime/Wine Devel.app/Contents/Resources/wine/lib/wine/x86_64-windows"

# MacOSX26.5 SDK + homebrew bison are required for the PE cross-build (HANDOFF §7+)
export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
export PATH="/opt/homebrew/opt/bison/bin:$PATH"

cd "$BUILD"
make -j8 "dlls/$DLL/x86_64-windows/$DLL.dll"

TS=$(date +%Y%m%d-%H%M%S)
if [ -f "$DEST/$DLL.dll" ]; then
    cp "$DEST/$DLL.dll" "$DEST/$DLL.dll.$TS.bak"
    echo "Backed up the installed DLL to $DLL.dll.$TS.bak"
fi
cp "dlls/$DLL/x86_64-windows/$DLL.dll" "$DEST/$DLL.dll"
echo "Installed $DLL.dll into the runtime (stock DLL backed up as $DLL.dll.stock-11.18 on first override)."
echo "Restart Power BI to pick it up: scripts/run_powerbi.sh"
