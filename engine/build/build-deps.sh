#!/bin/bash
# glueckspilz dep chain — build gmp, nettle, gnutls, freetype from the
# CodeWeavers source dump as x86_64 static libs, into ~/cx-build/dep-prefix.
# All sources are the LGPL components CodeWeavers ships for CX 26.3.0.
# Run under: arch -x86_64 bash build-deps.sh  (Rosetta shell)
set -euo pipefail
export PATH=/opt/homebrew/bin:/opt/homebrew/sbin:/opt/homebrew/opt/bison/bin:/opt/homebrew/opt/flex/bin:$PATH
# CLT's libxcrun is arm64-only; full Xcode's toolchain is universal.
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export CC="clang -arch x86_64"
export CXX="clang++ -arch x86_64"
export MACOSX_DEPLOYMENT_TARGET=12.0
export PKG_CONFIG_PATH="$HOME/cx-build/dep-prefix/lib/pkgconfig"
export CPPFLAGS="-I$HOME/cx-build/dep-prefix/include"

ROOT="$HOME/cx-build"
SRC="$ROOT/sources"
PREFIX="$ROOT/dep-prefix"
HOSTFLAGS="--host=x86_64-apple-darwin --build=x86_64-apple-darwin"
mkdir -p "$PREFIX"

step() { printf '\n===== %s =====\n' "$*" >&2; }

step "gmp (static, x86_64)"
mkdir -p "$ROOT/build-gmp" && cd "$ROOT/build-gmp"
if [[ ! -f .done ]]; then
  "$SRC/gnutls/gmp/configure" --prefix="$PREFIX" --enable-shared --enable-static --disable-assembly ABI=64 $HOSTFLAGS --quiet
  make -j8 --quiet
  make install --quiet
  touch .done
fi
echo "gmp: $(ls "$PREFIX/lib/" | grep -c libgmp) libs installed"

step "nettle (static, x86_64)"
mkdir -p "$ROOT/build-nettle" && cd "$ROOT/build-nettle"
if [[ ! -f .done ]]; then
  "$SRC/gnutls/nettle/configure" --prefix="$PREFIX" --enable-shared --enable-static \
    --with-include-path="$PREFIX/include" --with-lib-path="$PREFIX/lib" $HOSTFLAGS --quiet
  make -j8 --quiet
  make install --quiet
  touch .done
fi
echo "nettle: $(ls "$PREFIX/lib/" | grep -cE 'libnettle|libhogweed') libs installed"

step "gnutls (static, x86_64)"
mkdir -p "$ROOT/build-gnutls" && cd "$ROOT/build-gnutls"
if [[ ! -f .done ]]; then
  # NETTLE_LIBS/HOGWEED_LIBS must be EXPORTED env vars, not configure args:
  # the dump's hooks.m4 tests them as shell vars at configure runtime
  # ("if test x$NETTLE_LIBS = x") — VAR=value args are recorded by AC_ARG_VAR
  # but do not become runtime shell vars, so ENABLE_NETTLE came out FALSE and
  # lib/nettle/ + accelerated/ were silently dropped from the build.
  export NETTLE_LIBS="-L$PREFIX/lib -lnettle -lgmp"
  export HOGWEED_LIBS="-L$PREFIX/lib -lhogweed -lnettle -lgmp"
  "$SRC/gnutls/gnutls/configure" --prefix="$PREFIX" --enable-shared --enable-static \
    --with-included-unistring --without-p11-kit --disable-doc \
    --disable-tools --disable-nls --without-idn --without-brotli --without-zlib --without-zstd --with-included-libtasn1 LDFLAGS="-L$PREFIX/lib" $HOSTFLAGS --quiet
  unset NETTLE_LIBS HOGWEED_LIBS
  # configure writes GNUTLS_LIBS_PRIVATE without nettle/hogweed/gmp; the
  # libgnutls.la link then fails with undefined nettle symbols. Patch it in.
  sed -i "" "s|^GNUTLS_LIBS_PRIVATE = .*|GNUTLS_LIBS_PRIVATE = -L$PREFIX/lib -lnettle -lhogweed -lgmp -framework Security -framework CoreFoundation|" lib/Makefile
  make -j8 --quiet
  make install --quiet
  touch .done
fi
echo "gnutls: $(ls "$PREFIX/lib/" | grep -c libgnutls) libs installed"

step "freetype (static, x86_64)"
mkdir -p "$ROOT/build-freetype" && cd "$ROOT/build-freetype"
if [[ ! -f .done ]]; then
  # --without-png: sfnt PNG support drags in libpng (not in the dump);
  # PNG-in-font support is irrelevant for wine's font rendering.
  "$SRC/freetype/configure" --prefix="$PREFIX" --enable-shared --enable-static \
    --without-harfbuzz --without-png --without-brotli $HOSTFLAGS --quiet
  make -j8 --quiet
  make install --quiet
  touch .done
fi
echo "freetype: $(ls "$PREFIX/lib/" | grep -c libfreetype) libs installed"

step "verify arch"
for lib in libgmp.a libnettle.a libhogweed.a libgnutls.a libfreetype.a; do
  f="$PREFIX/lib/$lib"
  [[ -f "$f" ]] || { echo "MISSING: $lib"; exit 1; }
  lipo -archs "$f"
done

printf '\nDEP CHAIN COMPLETE — all x86_64 static libs in %s\n' "$PREFIX"