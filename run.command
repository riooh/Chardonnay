#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="${SCRIPT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}"
# Directory holding this script and the files shipped next to it. Unlike
# SCRIPT_DIR -- which callers override so the WINEPREFIX alias lands beside the
# .app bundle -- this always resolves to the repo root, or to Contents/Resources
# inside a generated Merlot app.
RUN_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

WINE_VERSION="${WINE_VERSION:-11.18}"
DXMT_VERSION="${DXMT_VERSION:-0.80}"

WINE_ROOT="${WINE_ROOT:-$HOME/wine-${WINE_VERSION}}"
WINE_APP="${WINE_ROOT}/Wine Staging.app"
WINE_BIN="${WINE_APP}/Contents/Resources/wine/bin/wine"
WINE_LIB="${WINE_APP}/Contents/Resources/wine/lib/wine"

WINEPREFIX="${WINEPREFIX:-$HOME/.wine-steam-11}"
STEAM_SETUP="/tmp/SteamSetup.exe"
DXMT_ROOT="${DXMT_ROOT:-$HOME/DXMT}"
# Source for the winemac.so patch set (macdrv_functions export for DXMT).
NEUTRON_DIR="${NEUTRON_DIR:-$HOME/neutron-clone}"
# Build output directory for the patched winemac.so rebuild.
DXMT_BUILD_OUT="${DXMT_BUILD_OUT:-$HOME/wine-dxmt-build}"
# GPTK_PATH: optional. When set, the D3D translation backend switches from
# DXMT (default) to Apple's Game Porting Toolkit (D3DMetal). Point this at
# either the GPTK root directory or the folder that contains the .dll files
# (we probe a few common layouts). GPTK is NOT downloaded automatically --
# Apple's EULA forbids redistribution, so the user must obtain it from
# developer.apple.com themselves. DXMT is the default precisely because it
# has no such constraint.
GPTK_PATH="${GPTK_PATH:-}"
WINEPREFIX_ALIAS_NAME="${WINEPREFIX_ALIAS_NAME:-WINEPREFIX}"
WINE_RETINA_MODE="${WINE_RETINA_MODE:-0}" # 1=enable RetinaMode, 0=disable RetinaMode (Default)
# 1=detach Steam from the Terminal after launch so closing the window doesn't kill it (Default).
# 0=keep the original foreground behavior (Terminal window must stay open).
MERLOT_DETACH="${MERLOT_DETACH:-1}"
MERLOT_STEAM_LOG="${MERLOT_STEAM_LOG:-${TMPDIR:-/tmp}/merlot-steam.log}"
# Steam's CEF UI renders as a solid black window under Wine on Apple Silicon.
# 1=install and deploy the steamwebhelper wrapper that fixes it (Default).
# 0=skip it (expect a black Steam window). See wrapper/README.md.
MERLOT_CEF_WRAPPER="${MERLOT_CEF_WRAPPER:-1}"
# Gcenx Wine builds ignore WINEDLLPATH_PREPEND, so on those builds DXMT never
# loads from DXMT_ROOT alone: the payload has to be installed into the Wine
# tree and prefix (wiki layout), and winemac.so has to export the macdrv_*
# symbols DXMT dlsyms to create Metal surfaces.
# 1=install and verify all of that after the DXMT download step (Default).
# 0=skip (not recommended: D3D11 games fall back to wined3d/OpenGL).
MERLOT_DXMT_FIX="${MERLOT_DXMT_FIX:-1}"
# Flags passed to steam.exe. -noverifyfiles is required: without it Steam's
# boot-time checksum pass restores Valve's steamwebhelper.exe over the wrapper
# and the black window comes back. -no-cef-sandbox is needed because Chromium's
# sandbox relies on Windows integrity tokens Wine does not model.
MERLOT_CEF_ARGS="${MERLOT_CEF_ARGS--no-cef-sandbox -cef-single-process -noverifyfiles}"
# Default before we added this: the value is not set in registry (Wine internal default).
# Set to force|enable|disable to override, or leave empty to keep default.
WINE_MOUSE_WARP_OVERRIDE="${WINE_MOUSE_WARP_OVERRIDE:-}"

WINE_URL="https://github.com/Gcenx/macOS_Wine_builds/releases/download/${WINE_VERSION}/wine-staging-${WINE_VERSION}-osx64.tar.xz"
STEAM_URL="https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe"
DXMT_URL="https://github.com/3Shain/dxmt/releases/download/v${DXMT_VERSION}/dxmt-v${DXMT_VERSION}-builtin.tar.gz"

log() {
  printf "\n==> %s\n" "$1"
}

die() {
  printf "Error: %s\n" "$1" >&2
  exit 1
}

require_macos_arm64() {
  log "Checking platform"
  [[ "$(uname -s)" == "Darwin" ]] || die "This script supports macOS only."
  [[ "$(uname -m)" == "arm64" ]] || die "This script is intended for Apple Silicon (arm64)."
}

ensure_sudo_ready() {
  log "Preparing sudo session (needed for Rosetta install if missing)"
  sudo -v
}

ensure_rosetta() {
  log "Ensuring Rosetta 2"
  if /usr/bin/arch -x86_64 /usr/bin/true >/dev/null 2>&1; then
    echo "Rosetta is already available. Skipping."
    return
  fi

  ensure_sudo_ready
  sudo softwareupdate --install-rosetta --agree-to-license

  /usr/bin/arch -x86_64 /usr/bin/true >/dev/null 2>&1 || die "Rosetta installation check failed."
}

ensure_wine_installed() {
  log "Ensuring Wine ${WINE_VERSION} is installed"
  if [[ -x "${WINE_BIN}" ]]; then
    echo "Wine already installed at ${WINE_APP}. Skipping."
    return
  fi

  mkdir -p "${WINE_ROOT}"
  curl -L --fail --retry 5 --retry-delay 1 "${WINE_URL}" | tar xJf - -C "${WINE_ROOT}"
  [[ -x "${WINE_BIN}" ]] || die "Wine binary not found after extraction: ${WINE_BIN}"
}

ensure_wineprefix_alias() {
  log "Ensuring local alias to WINEPREFIX"
  local alias_path="${SCRIPT_DIR}/${WINEPREFIX_ALIAS_NAME}"
  local alias_dir
  alias_dir="$(dirname "${alias_path}")"

  if [[ -e "${alias_path}" && ! -L "${alias_path}" ]]; then
    echo "Path exists and is not a symlink: ${alias_path}. Skipping alias creation."
    return
  fi

  if [[ -L "${alias_path}" ]]; then
    local current_target
    current_target="$(readlink "${alias_path}")"
    if [[ "${current_target}" == "${WINEPREFIX}" ]]; then
      echo "Alias is already up to date: ${alias_path} -> ${WINEPREFIX}"
      return
    fi
  fi

  if [[ ! -d "${alias_dir}" ]]; then
    echo "Alias directory does not exist: ${alias_dir}. Skipping alias creation."
    return
  fi

  if [[ ! -w "${alias_dir}" ]]; then
    echo "Alias directory is not writable: ${alias_dir}. Skipping alias creation."
    return
  fi

  if ! ln -sfn "${WINEPREFIX}" "${alias_path}"; then
    echo "Could not create alias at ${alias_path}. Continuing without it."
    return
  fi

  echo "Alias created: ${alias_path} -> ${WINEPREFIX}"
}

setup_wine_env() {
  export WINEPREFIX
  export PATH
  PATH="$(dirname "${WINE_BIN}"):${PATH}"
}

ensure_wine_prefix() {
  log "Ensuring Wine prefix for Steam"
  if [[ -f "${WINEPREFIX}/system.reg" ]]; then
    echo "Wine prefix already initialized at ${WINEPREFIX}. Skipping."
    return
  fi
  "${WINE_BIN}" wineboot --init
}

ensure_wine_mouse_warp_override() {
  local mode="${WINE_MOUSE_WARP_OVERRIDE}"
  if [[ -z "${mode}" ]]; then
    log "Restoring default Wine MouseWarpOverride"
    if "${WINE_BIN}" reg query "HKCU\\Software\\Wine\\DirectInput" /v MouseWarpOverride >/dev/null 2>&1; then
      "${WINE_BIN}" reg delete "HKCU\\Software\\Wine\\DirectInput" /v MouseWarpOverride /f >/dev/null 2>&1 || true
      echo "Removed MouseWarpOverride from registry (Wine default behavior)."
    else
      echo "MouseWarpOverride is not set. Skipping."
    fi
    return
  fi

  case "${mode}" in
    force|enable|disable) ;;
    *) die "WINE_MOUSE_WARP_OVERRIDE must be one of: force | enable | disable | (empty for default)" ;;
  esac

  log "Configuring Wine MouseWarpOverride=${mode}"
  local query_out
  query_out="$("${WINE_BIN}" reg query "HKCU\\Software\\Wine\\DirectInput" /v MouseWarpOverride 2>/dev/null || true)"
  if printf "%s" "${query_out}" | grep -Eiq "MouseWarpOverride[[:space:]]+REG_SZ[[:space:]]+${mode}"; then
    echo "MouseWarpOverride is already set to ${mode}. Skipping."
    return
  fi

  "${WINE_BIN}" reg add "HKCU\\Software\\Wine\\DirectInput" /v MouseWarpOverride /t REG_SZ /d "${mode}" /f >/dev/null
  echo "Set MouseWarpOverride=${mode}."
}

ensure_wine_retina_mode() {
  local enabled="$1"
  [[ "${enabled}" == "0" || "${enabled}" == "1" ]] || die "WINE_RETINA_MODE must be 0 or 1."

  local desired_value="n"
  if [[ "${enabled}" == "1" ]]; then
    desired_value="y"
  fi

  log "Configuring Wine RetinaMode=${desired_value}"
  local query_out
  query_out="$("${WINE_BIN}" reg query "HKCU\\Software\\Wine\\Mac Driver" /v RetinaMode 2>/dev/null || true)"
  if printf "%s" "${query_out}" | grep -Eiq "RetinaMode[[:space:]]+REG_SZ[[:space:]]+${desired_value}"; then
    echo "RetinaMode is already set to ${desired_value}. Skipping."
    return
  fi

  "${WINE_BIN}" reg add "HKCU\\Software\\Wine\\Mac Driver" /v RetinaMode /t REG_SZ /d "${desired_value}" /f >/dev/null
  echo "Set RetinaMode=${desired_value}."
}

ensure_wine_windows_mouse_accel_disabled() {
  log "Disabling Windows mouse acceleration in Wine"

  # Disable Windows "Enhanced Pointer Precision" (mouse acceleration) inside the prefix.
  # This is independent from macOS pointer acceleration.
  "${WINE_BIN}" reg add "HKCU\\Control Panel\\Mouse" /v MouseSpeed /t REG_SZ /d 0 /f >/dev/null
  "${WINE_BIN}" reg add "HKCU\\Control Panel\\Mouse" /v MouseThreshold1 /t REG_SZ /d 0 /f >/dev/null
  "${WINE_BIN}" reg add "HKCU\\Control Panel\\Mouse" /v MouseThreshold2 /t REG_SZ /d 0 /f >/dev/null

  echo "Set MouseSpeed=0, MouseThreshold1=0, MouseThreshold2=0."
}

find_steam_exe() {
  local steam32="${WINEPREFIX}/drive_c/Program Files (x86)/Steam/steam.exe"
  local steam64="${WINEPREFIX}/drive_c/Program Files/Steam/steam.exe"
  if [[ -f "${steam32}" ]]; then
    printf "%s\n" "${steam32}"
  elif [[ -f "${steam64}" ]]; then
    printf "%s\n" "${steam64}"
  fi
}

cleanup_steam_setup() {
  if [[ -f "${STEAM_SETUP}" ]]; then
    log "Cleaning up Steam installer cache"
    rm -f "${STEAM_SETUP}"
    echo "Removed ${STEAM_SETUP}."
  fi
}

ensure_steam_installed() {
  log "Ensuring Steam is installed in Wine prefix"
  local steam_exe
  steam_exe="$(find_steam_exe || true)"
  if [[ -n "${steam_exe}" ]]; then
    echo "Steam already installed at ${steam_exe}. Skipping installer."
    return
  fi

  if [[ ! -f "${STEAM_SETUP}" ]]; then
    echo "Downloading Steam installer..."
    curl -L --fail --retry 5 --retry-delay 1 -o "${STEAM_SETUP}" "${STEAM_URL}"
  fi

  echo "Launching Steam installer. Complete the wizard in the Wine window."
  "${WINE_BIN}" "${STEAM_SETUP}"

  steam_exe="$(find_steam_exe || true)"
  [[ -n "${steam_exe}" ]] || die "Steam installation appears incomplete (steam.exe not found)."
  cleanup_steam_setup
}

ensure_dxmt_installed() {
  log "Ensuring DXMT ${DXMT_VERSION} is installed"
  if [[ -d "${DXMT_ROOT}/i386-windows" && -d "${DXMT_ROOT}/x86_64-windows" && -d "${DXMT_ROOT}/x86_64-unix" ]]; then
    echo "DXMT already installed at ${DXMT_ROOT}. Skipping."
    return
  fi

  local tmp_dir
  tmp_dir="$(mktemp -d /tmp/dxmt.XXXXXX)"

  curl -L --fail --retry 5 --retry-delay 1 "${DXMT_URL}" | tar xzf - -C "${tmp_dir}"

  local payload_dir=""
  if [[ -d "${tmp_dir}/i386-windows" && -d "${tmp_dir}/x86_64-windows" && -d "${tmp_dir}/x86_64-unix" ]]; then
    payload_dir="${tmp_dir}"
  elif [[ -d "${tmp_dir}/v${DXMT_VERSION}/i386-windows" && -d "${tmp_dir}/v${DXMT_VERSION}/x86_64-windows" && -d "${tmp_dir}/v${DXMT_VERSION}/x86_64-unix" ]]; then
    payload_dir="${tmp_dir}/v${DXMT_VERSION}"
  fi

  [[ -n "${payload_dir}" ]] || die "DXMT extraction failed: payload directories not found."

  mkdir -p "${DXMT_ROOT}"
  rm -rf "${DXMT_ROOT}/i386-windows" "${DXMT_ROOT}/x86_64-windows" "${DXMT_ROOT}/x86_64-unix"
  cp -R "${payload_dir}/i386-windows" "${DXMT_ROOT}/"
  cp -R "${payload_dir}/x86_64-windows" "${DXMT_ROOT}/"
  cp -R "${payload_dir}/x86_64-unix" "${DXMT_ROOT}/"
  rm -rf "${tmp_dir}"
}

enable_dxmt_env() {
  log "Enabling DXMT via WINEDLLPATH_PREPEND"
  export WINEDLLPATH_PREPEND
  case ":${WINEDLLPATH_PREPEND:-}:" in
    *":${DXMT_ROOT}:"*) ;;
    *) WINEDLLPATH_PREPEND="${DXMT_ROOT}${WINEDLLPATH_PREPEND:+:${WINEDLLPATH_PREPEND}}" ;;
  esac

  export DXMT_LOG_LEVEL="${DXMT_LOG_LEVEL:-error}"
  export WINEDEBUG="${WINEDEBUG:--all,err+all}"

  # bcrypt/ncrypt builtin: Wine's stubs collide with Chromium's BoringSSL.
  # gameoverlayrenderer disabled: its D3D11 hook deadlocks games under DXMT, and
  # unchecking the in-game overlay does not stop the DLL being injected.
  export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-bcrypt=b;ncrypt=b;gameoverlayrenderer,gameoverlayrenderer64=d}"
}

use_gptk() {
  [[ -n "${GPTK_PATH}" ]]
}

find_gptk_dll_dir() {
  local root="$1"
  local candidates=(
    "${root}"
    "${root}/redist/lib/external"
    "${root}/lib/external"
    "${root}/lib"
    "${root}/Libraries"
  )
  local c
  for c in "${candidates[@]}"; do
    if [[ -f "${c}/d3d11.dll" ]]; then
      printf '%s\n' "${c}"
      return 0
    fi
  done
  return 1
}

ensure_gptk_installed() {
  log "Installing GPTK DLLs into the Wine prefix"
  [[ -d "${GPTK_PATH}" ]] || die "GPTK_PATH is not a directory: ${GPTK_PATH}"

  local src
  if ! src="$(find_gptk_dll_dir "${GPTK_PATH}")"; then
    die "Could not find d3d11.dll under GPTK_PATH=${GPTK_PATH}. Obtain the Game Porting Toolkit from developer.apple.com and point GPTK_PATH at the root (or directly at the folder containing the DLLs)."
  fi

  local target="${WINEPREFIX}/drive_c/windows/system32"
  [[ -d "${target}" ]] || die "Prefix system32 not found (is the prefix initialized?): ${target}"

  echo "Copying GPTK DLLs from ${src} to ${target}"
  local f copied=0
  for f in "${src}"/*.dll; do
    [[ -f "${f}" ]] || continue
    cp -f "${f}" "${target}/"
    copied=$((copied + 1))
  done
  [[ "${copied}" -gt 0 ]] || die "No .dll files found in ${src}"
  echo "Copied ${copied} DLL(s)."
}

enable_gptk_env() {
  log "Enabling GPTK via WINEDLLOVERRIDES"
  export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-d3d9,d3d10core,d3d11,d3d12,d3d12core,dxgi=n}"
  export WINEDEBUG="${WINEDEBUG:--all,err+all}"
  echo "WINEDLLOVERRIDES=${WINEDLLOVERRIDES}"
}

ensure_cef_wrapper() {
  [[ "${MERLOT_CEF_WRAPPER}" == "0" || "${MERLOT_CEF_WRAPPER}" == "1" ]] \
    || die "MERLOT_CEF_WRAPPER must be 0 or 1."

  if [[ "${MERLOT_CEF_WRAPPER}" == "0" ]]; then
    log "Skipping steamwebhelper wrapper (MERLOT_CEF_WRAPPER=0)"
    return
  fi

  log "Ensuring steamwebhelper wrapper (fixes the black Steam UI)"
  local installer="${RUN_DIR}/wrapper/install-wrapper.sh"
  if [[ ! -x "${installer}" ]]; then
    echo "Wrapper installer not found at ${installer}."
    echo "Steam's UI will render as a black window. See wrapper/README.md."
    return
  fi

  # Steam restores its own helper during boot, so this runs on every launch,
  # not just the first one. Building only happens when the cache is empty.
  if WINEPREFIX="${WINEPREFIX}" "${installer}"; then
    return
  fi

  echo "Could not install the wrapper; Steam's UI may render black."
  echo "See wrapper/README.md, or set MERLOT_CEF_WRAPPER=0 to silence this."
}

# ---------------------------------------------------------------------------
# DXMT enablement. WINEDLLPATH_PREPEND alone is a no-op on Gcenx builds, so
# the payload is installed into the Wine tree and prefix per the official
# DXMT wiki layout, and winemac.so is rebuilt to export the macdrv_*
# symbols DXMT dlsyms for Metal surface creation. Everything below is
# idempotent and re-verified on every launch, so a Wine version update that
# overwrites the patched files simply gets repaired on the next start.
# ---------------------------------------------------------------------------

# Populates DXMT_STATE_ISSUES and returns 0 when the stack is healthy.
dxmt_stack_state() {
  DXMT_STATE_ISSUES=()
  local ok=0

  [[ -d "${WINE_LIB}/x86_64-windows" ]] \
    || { DXMT_STATE_ISSUES+=("Wine tree not found at ${WINE_LIB}"); ok=1; }
  [[ -f "${DXMT_ROOT}/x86_64-windows/d3d11.dll" ]] \
    || { DXMT_STATE_ISSUES+=("DXMT payload missing at ${DXMT_ROOT}"); ok=1; }

  if [[ -d "${WINE_LIB}/x86_64-windows" && -f "${DXMT_ROOT}/x86_64-windows/d3d11.dll" ]]; then
    cmp -s "${DXMT_ROOT}/x86_64-windows/d3d11.dll" "${WINE_LIB}/x86_64-windows/d3d11.dll" 2>/dev/null \
      || { DXMT_STATE_ISSUES+=("Wine tree d3d11.dll is not DXMT (builtin wined3d fallback active)"); ok=1; }
    cmp -s "${DXMT_ROOT}/x86_64-windows/dxgi.dll" "${WINE_LIB}/x86_64-windows/dxgi.dll" 2>/dev/null \
      || { DXMT_STATE_ISSUES+=("Wine tree dxgi.dll is not DXMT"); ok=1; }
    nm -gU "${WINE_LIB}/x86_64-unix/winemac.so" 2>/dev/null | grep -q "_macdrv_functions$" \
      || { DXMT_STATE_ISSUES+=("winemac.so lacks the macdrv_functions export (DXMT cannot present frames)"); ok=1; }
    [[ -f "${WINE_LIB}/x86_64-unix/winemetal.so" ]] \
      || { DXMT_STATE_ISSUES+=("winemetal.so missing from the Wine tree"); ok=1; }
  fi

  [[ -s "${WINEPREFIX}/drive_c/windows/system32/winemetal.dll" ]] 2>/dev/null \
    || { DXMT_STATE_ISSUES+=("prefix system32 missing winemetal.dll (${WINEPREFIX})"); ok=1; }

  return "${ok}"
}

dxmt_install_payload() {
  log "Installing DXMT DLLs into the Wine tree and prefix"
  local f s32
  for f in d3d11 dxgi d3d10core winemetal; do
    if [[ -f "${WINE_LIB}/x86_64-windows/${f}.dll" && ! -f "${WINE_LIB}/x86_64-windows/${f}.dll.orig-wine" ]]; then
      cp "${WINE_LIB}/x86_64-windows/${f}.dll" "${WINE_LIB}/x86_64-windows/${f}.dll.orig-wine"
    fi
    [[ -f "${DXMT_ROOT}/x86_64-windows/${f}.dll" ]] \
      && cp "${DXMT_ROOT}/x86_64-windows/${f}.dll" "${WINE_LIB}/x86_64-windows/${f}.dll"
  done
  cp "${DXMT_ROOT}/x86_64-unix/winemetal.so" "${WINE_LIB}/x86_64-unix/winemetal.so"

  s32="${WINEPREFIX}/drive_c/windows/system32"
  for f in d3d11 dxgi d3d10core; do
    if [[ -f "${s32}/${f}.dll" && ! -f "${s32}/${f}.dll.orig-wine" ]]; then
      cp "${s32}/${f}.dll" "${s32}/${f}.dll.orig-wine"
    fi
    cp "${DXMT_ROOT}/x86_64-windows/${f}.dll" "${s32}/${f}.dll"
  done
  cp "${DXMT_ROOT}/x86_64-windows/winemetal.dll" "${s32}/winemetal.dll"
  echo "DXMT payload installed (originals kept as *.orig-wine)."
}

# neutron's build.sh expects the Wine build root that directly contains
# bin/wine (Gcenx layout: "Wine Staging.app/Contents/Resources/wine").
# WINE_ROOT is normally the version directory that contains the .app, so
# resolve either shape before handing the path to the rebuild.
dxmt_wine_build_root() {
  if [[ -x "${WINE_ROOT}/bin/wine" ]]; then
    printf '%s\n' "${WINE_ROOT}"
  elif [[ -x "${WINE_APP}/Contents/Resources/wine/bin/wine" ]]; then
    printf '%s\n' "${WINE_APP}/Contents/Resources/wine"
  fi
}

dxmt_rebuild_winemac() {
  log "Rebuilding winemac.so with the macdrv_functions export"
  export PATH="/opt/homebrew/bin:/opt/homebrew/opt/bison/bin:/opt/homebrew/opt/flex/bin:${PATH}"
  command -v brew >/dev/null 2>&1 || die "Homebrew not found at /opt/homebrew (required to build winemac.so)"

  local missing="" p
  for p in bison flex mingw-w64; do
    brew list --versions "$p" >/dev/null 2>&1 || missing="${missing} ${p}"
  done
  if [[ -n "${missing}" ]]; then
    log "Installing build dependencies:${missing} (one-time)"
    brew install ${missing} || die "brew install failed"
  fi

  if [[ ! -d "${NEUTRON_DIR}" ]]; then
    log "Fetching the neutron winemac patch set"
    git clone --depth 1 https://github.com/codeWonderland/neutron.git "${NEUTRON_DIR}" \
      || die "neutron clone failed"
  fi

  rm -rf "${DXMT_BUILD_OUT}"
  local wine_build_root
  wine_build_root="$(dxmt_wine_build_root)" || true
  [[ -n "${wine_build_root}" ]] \
    || die "Could not resolve the Wine build root (need bin/wine under ${WINE_ROOT} or ${WINE_APP})."
  # The patch set rebuilds winemac.so against the installed Wine's source and
  # also ships a Unity video fix (mfreadwrite) we deploy alongside.
  sh "${NEUTRON_DIR}/tools/wine-dxmt/build.sh" "${wine_build_root}" "${DXMT_BUILD_OUT}" \
    || die "winemac.so rebuild failed"

  local live="${WINE_LIB}/x86_64-unix/winemac.so" arch
  if [[ -f "${live}" && ! -f "${live}.orig" ]]; then
    cp "${live}" "${live}.orig"
  fi
  cp "${DXMT_BUILD_OUT}/lib/wine/x86_64-unix/winemac.so" "${live}"
  for arch in x86_64-windows i386-windows; do
    [[ -f "${DXMT_BUILD_OUT}/lib/wine/${arch}/mfreadwrite.dll" ]] \
      && cp "${DXMT_BUILD_OUT}/lib/wine/${arch}/mfreadwrite.dll" "${WINE_LIB}/${arch}/mfreadwrite.dll"
  done
  echo "winemac.so replaced (original kept as winemac.so.orig)."
}

# Steam app launches and per-game launchers can cold-start at the same time;
# the rebuild and DLL copies must not interleave. mkdir is atomic on macOS.
# The lock records its holder's PID: a repair that dies (or is killed) leaves
# the directory behind, and the next run reclaims it once the holder is gone
# instead of waiting out the full timeout.
DXMT_LOCK_DIR="${TMPDIR:-/tmp}/merlot-dxmt.lock"
dxmt_lock() {
  if mkdir "${DXMT_LOCK_DIR}" 2>/dev/null; then
    printf '%s\n' "$$" >"${DXMT_LOCK_DIR}/pid"
    return 0
  fi
  local holder
  holder="$(cat "${DXMT_LOCK_DIR}/pid" 2>/dev/null || true)"
  if [[ -z "${holder}" ]] || ! ps -p "${holder}" >/dev/null 2>&1; then
    echo "Removing stale DXMT repair lock (holder ${holder:-unknown} no longer running)."
    rm -rf "${DXMT_LOCK_DIR}"
    if mkdir "${DXMT_LOCK_DIR}" 2>/dev/null; then
      printf '%s\n' "$$" >"${DXMT_LOCK_DIR}/pid"
      return 0
    fi
  fi
  echo "Another DXMT repair is in progress; waiting..."
  local i
  for i in $(seq 1 300); do
    if mkdir "${DXMT_LOCK_DIR}" 2>/dev/null; then
      printf '%s\n' "$$" >"${DXMT_LOCK_DIR}/pid"
      return 0
    fi
    sleep 1
  done
  die "DXMT repair lock held for over 5 minutes: ${DXMT_LOCK_DIR}"
}

dxmt_unlock() {
  rm -rf "${DXMT_LOCK_DIR}"
}

ensure_dxmt_fix() {
  [[ "${MERLOT_DXMT_FIX}" == "0" || "${MERLOT_DXMT_FIX}" == "1" ]] \
    || die "MERLOT_DXMT_FIX must be 0 or 1."

  if [[ "${MERLOT_DXMT_FIX}" == "0" ]]; then
    log "Skipping DXMT repair (MERLOT_DXMT_FIX=0)"
    return
  fi

  if use_gptk; then
    log "GPTK backend selected; skipping DXMT repair"
    return
  fi

  [[ -d "${WINE_LIB}/x86_64-unix" ]] || die "Wine tree not found: ${WINE_LIB} (run the install first)"
  [[ -f "${DXMT_ROOT}/x86_64-windows/d3d11.dll" ]] || die "DXMT payload missing at ${DXMT_ROOT} (run the install first)"
  [[ -d "${WINEPREFIX}/drive_c" ]] || die "Wine prefix not initialized: ${WINEPREFIX}"
  [[ -f "${DXMT_ROOT}/x86_64-unix/winemetal.so" ]] || die "winemetal.so missing from the DXMT payload at ${DXMT_ROOT}"

  dxmt_lock
  # Release the lock even when a step below fails (die exits the script).
  trap 'dxmt_unlock' EXIT
  if ! cmp -s "${DXMT_ROOT}/x86_64-windows/d3d11.dll" "${WINE_LIB}/x86_64-windows/d3d11.dll" 2>/dev/null; then
    dxmt_install_payload
  else
    echo "DXMT DLLs already installed in the Wine tree."
  fi

  if nm -gU "${WINE_LIB}/x86_64-unix/winemac.so" 2>/dev/null | grep -q "_macdrv_functions$"; then
    echo "winemac.so already exports macdrv_functions."
  else
    dxmt_rebuild_winemac
  fi
  dxmt_unlock
  trap - EXIT

  if dxmt_stack_state; then
    log "DXMT active: payload installed, macdrv_functions exported"
  else
    local issue
    for issue in "${DXMT_STATE_ISSUES[@]}"; do
      echo "Warning: ${issue}" >&2
    done
    echo "D3D11 games may fail to start. Re-run with ./run.command --check to inspect." >&2
  fi
}

dxmt_check_mode() {
  log "Checking the DXMT graphics stack"
  if dxmt_stack_state; then
    echo "OK: DXMT installed, winemac.so patched, prefix complete."
    exit 0
  fi
  local issue
  echo "Issues found:" >&2
  for issue in "${DXMT_STATE_ISSUES[@]}"; do
    echo "  - ${issue}" >&2
  done
  exit 2
}

purge_chromium_locks() {
  # A crashed Steam leaves Chromium singleton locks behind; the next launch then
  # trips the single-instance guard and falls back to --silent, with no window.
  local htmlcache="${WINEPREFIX}/drive_c/users/${USER}/AppData/Local/Steam/htmlcache"
  [[ -d "${htmlcache}" ]] || return 0

  # Only safe while Steam is stopped: pulling the lock out from under a live
  # instance would let a second one start alongside it.
  if pgrep -f "Steam[\\\\/]steam\.exe" >/dev/null 2>&1; then
    return 0
  fi

  log "Purging stale Chromium locks"
  find "${htmlcache}" -maxdepth 2 \
    \( -name "Singleton*" -o -name "*.lock" -o -name "CrashpadMetrics*.pma" \) \
    -delete 2>/dev/null || true
}

launch_steam() {
  log "Launching Steam"
  local steam_exe
  steam_exe="$(find_steam_exe || true)"
  [[ -n "${steam_exe}" ]] || die "steam.exe not found."

  local -a steam_cmd=("${WINE_BIN}" "${steam_exe}")
  if [[ -n "${MERLOT_CEF_ARGS}" ]]; then
    # Intentionally unquoted: MERLOT_CEF_ARGS is a space-separated flag list.
    # shellcheck disable=SC2206
    local -a cef_args=(${MERLOT_CEF_ARGS})
    steam_cmd+=("${cef_args[@]}")
  fi
  if [[ -n "${STEAM_GAME_ID:-}" ]]; then
    echo "Launching Steam game ${STEAM_GAME_ID}..."
    steam_cmd+=(-applaunch "${STEAM_GAME_ID}")
  fi

  case "${MERLOT_DETACH}" in
    0)
      "${steam_cmd[@]}"
      ;;
    1)
      log "Detaching Steam from this Terminal (log: ${MERLOT_STEAM_LOG})"
      : >"${MERLOT_STEAM_LOG}" || die "Cannot write to ${MERLOT_STEAM_LOG}"
      nohup "${steam_cmd[@]}" </dev/null >>"${MERLOT_STEAM_LOG}" 2>&1 &
      disown
      echo "Steam is running in the background (PID $!). Safe to close this Terminal window."
      echo "Tail the log with: tail -f ${MERLOT_STEAM_LOG}"
      ;;
    *)
      die "MERLOT_DETACH must be 0 or 1."
      ;;
  esac
}

main() {
  require_macos_arm64
  ensure_rosetta
  ensure_wine_installed
  setup_wine_env
  ensure_wine_prefix
  ensure_wineprefix_alias
  ensure_wine_mouse_warp_override
  ensure_wine_retina_mode "${WINE_RETINA_MODE}"
  ensure_wine_windows_mouse_accel_disabled
  ensure_steam_installed
  if use_gptk; then
    ensure_gptk_installed
    enable_gptk_env
  else
    ensure_dxmt_installed
    ensure_dxmt_fix
    enable_dxmt_env
  fi
  ensure_cef_wrapper
  purge_chromium_locks
  launch_steam
}

case "${1:-}" in
  --check|--dxmt-check)
    require_macos_arm64
    dxmt_check_mode
    ;;
  "")
    main "$@"
    ;;
  *)
    die "Unknown argument: ${1} (supported: --check)"
    ;;
esac