#!/bin/bash
# glueckspilz wine build — Wine 11.0 + CX 26.3 patches, from CodeWeavers' dump.
# Produces an x86_64-host engine with i386+x86_64 PE support (CX demo shape).
# Run under: arch -x86_64 bash build-wine.sh
set -euo pipefail
export PATH=/opt/homebrew/bin:/opt/homebrew/sbin:/opt/homebrew/opt/bison/bin:/opt/homebrew/opt/flex/bin:$PATH
# CLT's libxcrun is arm64-only; full Xcode's toolchain is universal.
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export CC="clang -arch x86_64"
export CXX="clang++ -arch x86_64"
export MACOSX_DEPLOYMENT_TARGET=12.0

ROOT="$HOME/cx-build"
SRC="$ROOT/sources/wine"
BUILD="$ROOT/wine-build"
PREFIX="$ROOT/glueckspilz"      # engine tree root, mirrors cx-engine layout
GST_CORE="$ROOT/gst-devel-x/gstreamer-1.0-core-devel-1.28.6-universal.pkg"
GST_BASE="$ROOT/gst-devel-x/base-system-1.0-devel-1.28.6-universal.pkg"
export PKG_CONFIG_PATH="$ROOT/dep-prefix/lib/pkgconfig:$GST_CORE/lib/pkgconfig:$GST_BASE/lib/pkgconfig"
export CPPFLAGS="-I$ROOT/dep-prefix/include -I$GST_CORE/include -I$GST_BASE/include"
export LDFLAGS="-L$ROOT/dep-prefix/lib"

step() { printf '\n===== %s =====\n' "$*" >&2; }

step "configure wine (x86_64 host, i386+x86_64 PE)"
mkdir -p "$BUILD" && cd "$BUILD"
rm -f config.cache
"$SRC/configure" --prefix="$PREFIX" \
  --enable-archs=i386,x86_64 \
  --without-x --without-xcb --without-alsa --without-oss \
  --without-capi --without-cups --without-udev --without-hal \
  --without-v4l2 --without-sane \
  --build=x86_64-apple-darwin --host=x86_64-apple-darwin \
  2>&1 | tail -35

step "config sanity: key components"
grep -E "^(CC|CROSSCC|PE_ARCHS|TOOLSDIR)" Makefile 2>/dev/null | head -6
grep -E "freetype|gnutls|gstreamer|sdl|coreaudio" config.log | grep -iE "yes|found" | head -8
# CW HACK 25909 (vulkan.c) references SONAME_LIBVULKAN unguarded; configure
# leaves it undef when no Vulkan loader is found. CX's own engine dlopens
# MoltenVK, so define it to match production — dlopen fails gracefully at
# runtime, DX11/DXMT never touches Vulkan.
if ! grep -q '^#define SONAME_LIBVULKAN' include/config.h; then
  sed -i "" "s|^/\* #undef SONAME_LIBVULKAN \*/|#define SONAME_LIBVULKAN \"libMoltenVK.dylib\"|" include/config.h
fi
grep -q '^#define SONAME_LIBVULKAN' include/config.h || { echo "FATAL: SONAME_LIBVULKAN patch failed"; exit 1; }

step "build wine (this is the long pole)"
make -j8 2>&1 | tail -8

step "install engine tree"
make install 2>&1 | tail -5

step "verify engine shape"
echo "--- bin/wine:"; ls -la "$PREFIX/bin/wine" 2>/dev/null || ls "$PREFIX/bin/" | head
echo "--- lib/wine arch dirs:"; ls "$PREFIX/lib/wine/" 2>/dev/null
echo "--- wine version:"; "$PREFIX/bin/wine" --version 2>/dev/null || true
echo "--- winemac symbols (DXMT requirement):"; nm -gU "$PREFIX/lib/wine/x86_64-unix/winemac.so" 2>/dev/null | grep -E "macdrv_functions" || echo "macdrv_functions NOT exported"

printf '\nGLUECKSPILZ ENGINE BUILT at %s\n' "$PREFIX"