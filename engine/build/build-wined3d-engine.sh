#!/bin/bash
# Build glueckspilz-wined3d: a copy of the glueckspilz engine with Wine's
# STOCK d3d11/dxgi/d3d10core (wined3d -> opengl32 -> mac GL) instead of
# Apple's D3DMetal hybrid DLLs. Used to run EA App (which needs ANGLE's
# GetSharedHandle, unsupported by D3DMetal).
set -euo pipefail
SRC="$HOME/cx-build/glueckspilz"
DST="$HOME/cx-build/glueckspilz-wined3d"
BLD="$HOME/cx-build/wine-build/dlls"
if [[ ! -d "$SRC" ]]; then echo "no source engine"; exit 1; fi
if [[ -d "$DST" ]]; then
  echo "refreshing existing $DST"
else
  cp -a "$SRC" "$DST"
  echo "copied engine -> $DST"
fi
W="$DST/lib/wine/x86_64-windows"
I="$DST/lib/wine/i386-windows"
# Restore Wine's stock PE DLLs (forward to wined3d), overwriting Apple's stubs.
for dll in d3d11 dxgi d3d10core; do
  if [[ -f "$BLD/$dll/x86_64-windows/$dll.dll" ]]; then
    cp -f "$BLD/$dll/x86_64-windows/$dll.dll" "$W/$dll.dll"; echo "restored x86_64-windows/$dll.dll"
  fi
  if [[ -f "$BLD/$dll/i386-windows/$dll.dll" ]]; then
    cp -f "$BLD/$dll/i386-windows/$dll.dll" "$I/$dll.dll"; echo "restored i386-windows/$dll.dll"
  fi
done
# Remove Apple's unix-side DXMT aliases so nothing can pull D3DMetal in this tree.
U="$DST/lib/wine/x86_64-unix"
for so in d3d11.so dxgi.so d3d12.so atidxx64.so nvapi64.so nvngx.so; do
  if [[ -L "$U/$so" ]] && [[ "$(readlink "$U/$so")" == "libd3dshared.dylib" ]]; then
    rm -f "$U/$so"; echo "removed Apple alias $so"
  fi
done
echo "--- verify ---"
ls -la "$W"/d3d11.dll "$W"/dxgi.dll "$W"/d3d10core.dll
echo "d3d11.so present? $([[ -e "$U/d3d11.so" ]] && echo yes || echo no)"
"$DST/bin/wine" --version 2>/dev/null || echo "(version check skipped)"
