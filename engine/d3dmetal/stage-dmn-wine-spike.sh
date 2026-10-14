#!/bin/bash
set -euo pipefail
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
ROOT="$HOME/cx-build/d3dmetal-native-spike"
SRC="$HOME/cx-build/glueckspilz"
DST="$HOME/cx-build/glueckspilz-dmn-spike"
[[ ! -e "$DST" ]] || { printf 'Refusing to overwrite existing experiment\n'; exit 2; }
clang -arch x86_64 -mmacosx-version-min=14.0 -dynamiclib -O2 -Wall -Wextra \
  "$ROOT/dmn-wine-adapter.c" -o "$ROOT/libdmn-wine-adapter.dylib"
# APFS clone copy: preserve symlinks; no hardlinks to live-engine files.
cp -a -c "$SRC" "$DST"
U="$DST/lib/wine/x86_64-unix"
cp "$ROOT/build/libd3dmetal-native.dylib" "$U/libd3dmetal-native.dylib"
cp "$ROOT/libdmn-wine-adapter.dylib" "$U/libdmn-wine-adapter.dylib"
for name in d3d11 dxgi d3d12 atidxx64 nvapi64 nvngx; do
  [[ -L "$U/$name.so" && "$(readlink "$U/$name.so")" == libd3dshared.dylib ]] || { printf 'Unexpected alias %s\n' "$name"; exit 3; }
  mv "$U/$name.so" "$U/$name.so.before-dmn"
  ln -s libdmn-wine-adapter.dylib "$U/$name.so"
done
printf 'Experimental engine staged at %s\n' "$DST"
