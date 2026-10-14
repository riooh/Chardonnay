#!/bin/bash
# Experimental EA UI test. Cloned prefix; no changes to the live EA bottle.
set -euo pipefail
ENGINE="$HOME/cx-build/glueckspilz-dmn-spike"
U="$ENGINE/lib/wine/x86_64-unix"
export WINEPREFIX="$HOME/bottles/ea-dmn-spike"
export WINEDLLPATH=""
export WINEDLLOVERRIDES="d3d11,dxgi=b;bcrypt=b;ncrypt=b;gameoverlayrenderer,gameoverlayrenderer64=d"
export CX_ACTIVE_GRAPHICS_BACKEND=d3dmetal
export CX_APPLEGPTK_LIBD3DSHARED_PATH="$U/libd3dshared.dylib"
export CX_LIBVULKAN="$U/libMoltenVK.dylib"
export WINEDEBUG=-all
export DMN_LOG=info
DIAG="$HOME/cx-build/d3dmetal-native-spike"
EA="$WINEPREFIX/drive_c/Program Files/Electronic Arts/EA Desktop/13.805.11.6320/EA Desktop/EADesktop.exe"
nohup caffeinate -i -t 1200 >/dev/null 2>&1 &
exec "$ENGINE/bin/wine" "$EA" --in-process-gpu --no-sandbox > "$DIAG/ea-dmn-renderer.log" 2>&1
