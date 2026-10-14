# Experimental Wine engine source checkpoint

These are the source changes and build recipes used for the self-built
`glueckspilz` engine and the separate D3DMetal sharing experiment. They are
checkpointed alongside the Desktop launcher feature, but are **not** yet a
turnkey, distributable engine or an automatically selected retail backend.
Jedi: Fallen Order's actual Steam -> EA -> game path is still unverified.

## What is and is not included

- `build/build-deps.sh`: x86_64 GMP/nettle/GnuTLS/FreeType build recipe.
- `build/build-wine.sh`: CodeWeavers-patched Wine build/install recipe, including
  the generated SONAME_LIBVULKAN configuration fix.
- `build/build-wined3d-engine.sh`: historical stock-Wine graphics negative control.
  **This did not fix EA rendering**: stock Wine 11.0 also lacks the needed
  shared-resource implementation. Do not mistake it for the working backend.
- `build/pbzx_x.py`: the tested compressed-chunk extractor used for the required
  GStreamer development package payloads; not a general installer/package parser.
- `patches/gnutls-configure-quoting.patch`: the actual quoting correction to the
  dump's generated GnuTLS configure script. The unquoted multi-token NETTLE_LIBS
  and HOGWEED_LIBS tests prevented ENABLE_NETTLE from becoming true.
- `patches/d3dmetal-native-cube-view-slices.patch`: the upstream cube-view bug fix.
- `d3dmetal/`: native sharing adapter, its staging recipe, the exercised x86_64
  cross file, and the **current** working EA diagnostic launch policy.
- `tests/`: real Windows shared-texture pixel-readback and native Metal cube-view
  regression probes.

No Apple frameworks, CodeWeavers binaries, Wine build products, external source
archives, installed prefixes, account data, cookies, authentication codes, or
raw authenticated application logs are included. Obtain external components
under their own licenses. The open-source CodeWeavers source dump is not a
license to redistribute separate proprietary graphics components.

The retained cross file/patch target `utmapp/d3dmetal-native` under MIT; its
copyright/license is preserved in `d3dmetal/UPSTREAM-LICENSE.txt`. The full upstream
implementation is not vendored. These integration sources do not replace Apple's
closed D3DMetal.framework with an open-source implementation.

## Source/build prerequisites

The engine was built from CodeWeavers' published CX 26.3.0 source dump:

`https://media.codeweavers.com/pub/crossover/source/crossover-sources-26.3.0.tar.gz`

The historical working layout is `~/cx-build`:

- `sources/wine` and `sources/gnutls/{gmp,nettle,gnutls}`, plus `sources/freetype`.
- `dep-prefix`, `wine-build`, and the final base tree `glueckspilz`.
- GStreamer 1.28.6 core-devel and base-system-devel extracted under `gst-devel-x`.
- Full Xcode, Rosetta, Homebrew MinGW, bison/flex and pkg-config. Export
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; the CLT libxcrun was
  arm64-only and unsuitable for x86_64 build tools on this host.

Some source-dump snapshots lack generated release files. Matching official
nettle 3.10 and FreeType 2.13.3 release sources supplied those generated files.
Before running the dependency recipe against fresh sources, apply the GnuTLS
configure patch from its source directory (`patch -p1 --dry-run`, then apply).
The exported library flags alone do not repair the unquoted configure guards.
Check `ENABLE_NETTLE_TRUE` in generated config.status, not just config.h.

**Do not run these historical build/install scripts against a running engine.**
They write their documented `~/cx-build` paths, use existing staging inputs, and
some refresh generated files. Preserve the working trees and use a separate,
reviewed build workspace when rebuilding. No full engine rebuild is performed by
checkpointing these files.

After Wine installation, runtime dependency staging was also necessary:
`libfreetype.6.dylib` and `libgnutls.30.dylib` must be discoverable beside the Unix
modules. User-obtained Apple graphics PE stubs, `libd3dshared.dylib`,
`D3DMetal.framework`, and `libMoltenVK.dylib` belong in the appropriate in-tree
locations; Wine's mac preloader does not make DYLD_* environment injection a
reliable substitute. This manual staging is a prerequisite, not an automated
binary download supplied by this checkpoint.

Preserve the six Unix graphics aliases (`d3d11`, `dxgi`, `d3d12`, `atidxx64`,
`nvapi64`, `nvngx`) as symlinks to **one** shared host image. Dereferencing them
into independent copies splits Win32 dispatch state and previously caused a
null call. For the unmodified base they target one libd3dshared.dylib; in the
experimental clone they target one adapter, which loads that original host once.

## Native sharing integration

Upstream pin:
`c31fbbf688908268081306ba405c4d234b70d950` in
`https://github.com/utmapp/d3dmetal-native`.

1. Check out that upstream revision into the separate native build workspace.
2. Check/apply `d3dmetal-native-cube-view-slices.patch` with `git apply --check`
   then `git apply`. The only upstream source change is the available view slice
   count: 3D retains one; Cube/CubeArray uses arrayLength * 6; other types use
   arrayLength. The class-wide swizzle also affects ordinary unshared textures.
3. Copy the retained cross file into that workspace and build x86_64 with Meson.
   Use the user's existing framework path for `-Ddev_framework_path`; build with
   two jobs on an 8GB host. No licensed framework is downloaded by this recipe.
4. Copy `dmn-wine-adapter.c`, `stage-dmn-wine-spike.sh` and the two probe sources
   into the build workspace paths expected by the historical staging script.
   The stage script refuses to overwrite an existing experiment and APFS-clones
   the base engine before changing aliases. Do not rerun it on the active tree.
5. Run acceptance probes in an isolated prefix through a native `.app` wrapper
   and `open`, not bare SSH or a new Terminal window. Keep GUI diagnostics
   terminal-free and keep test prefixes separate from the authenticated EA one.

The adapter exports the existing two Unix calls, keeps Wine's original GFXT
Win32 host, and hooks successful D3D11 device creation. It deliberately does NOT
call `dmn_init()` and install upstream's native pseudo-HWND host. Its ABI is
version-specific: inspected dispatch size 0x160, factory offsets 0x38/0x40, MS-ABI
factory signatures and native SysV hook callbacks. Reinspect the bridge before
using another Apple/CodeWeavers version.

Native pointer/POD/file-descriptor handles are **not Win32 NT handles**. The
validated scope is same-process GPU resource sharing. Separate CEF renderer and
network helpers were exercised while the GPU stayed in the browser process;
this does not prove arbitrary cross-process D3DKMT or DuplicateHandle support.

## EA launch policy and runtime verification

`d3dmetal/launch-ea.sh` preserves the current diagnostic policy:
`--in-process-gpu --no-sandbox`, with original, unwrapped CEF renderer/network
helpers. Use it as the executable of a background LaunchServices `.app`; do not
run interactive Wine directly from SSH. Its historical version/prefix paths are
explicit diagnostics, not a universal EA installer API. The generic Desktop
importer keeps an equivalent per-target launch policy in local profile config.

`--single-process` was enough to paint sign-in but broke the post-login Qt
WebChannel callback (`onLoginSuccess` undefined). Restoring separate renderers
with in-process GPU allowed saved login to resume, native authenticated state,
entitlement/content readiness, and the visible main EA UI. The user confirmed
that UI, but JFO playability still requires its own end-to-end test.

Verification exercised on the existing M2 build, separately from any full rebuild:

- Native abi-check, com-contract, shared-texture, shared-contract and
  shared-open-preserve: all five selected tests passed.
- Native cube-view probe: cube, two-cube array, second-cube range and normal
  2D-array cases passed. The unpatched sharing swizzle reproduced Metal's
  multiple-of-six slice assertion, while hooks-disabled control passed.
- Windows PE probe: GetSharedHandle/OpenSharedResource S_OK and actual BGRA
  readback `0,0,255,255` on the second device. A D3D11_QUERY_EVENT establishes
  producer completion; Flush alone only submits work and can read zero pixels.
- The original bridge's negative control returned E_NOTIMPL for GetSharedHandle.

Compile the Windows probe using MinGW and `-ld3d11 -ldxgi -ldxguid`; compile the
native cube probe as x86_64 ObjC++17/ARC against the pinned upstream headers and
built native library, with Foundation/Metal. Keep raw EA logs and credentials
outside Git; verify using aggregate state and redact URI queries from all schemes.
