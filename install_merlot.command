#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="${SCRIPT_DIR}/app/merlot"
CONFIGS_DIR="${SCRIPT_DIR}/merlot_configs"
INSTALL_ROOT="/Applications"
INSTALL_DIR="${INSTALL_ROOT}/Merlot Apps"
DEFAULT_ICON_PATH="${SCRIPT_DIR}/app/merlot/AppIcon.icns"
LAUNCHER_TEMPLATE="${TEMPLATE_DIR}/MerlotLauncher"
LAUNCHER_NAME="MerlotLauncher"

# --games mode: per-game launcher settings
GAMES_WINE_PREFIX="${GAMES_WINE_PREFIX:-$HOME/.wine-steam-11}"
GAMES_DIR="${GAMES_DIR:-$HOME/Applications/Merlot Games}"
MERLOT_REPO="${MERLOT_REPO:-$HOME/macos-wine-steam}"
ICONCACHE="${ICONCACHE:-$HOME/.cache/merlot-games}"
PLIST_LABEL="local.merlot.games.watch"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"
STEAMAPPS="$GAMES_WINE_PREFIX/drive_c/Program Files (x86)/Steam/steamapps"
LIBCACHE="$GAMES_WINE_PREFIX/drive_c/Program Files (x86)/Steam/appcache/librarycache"
STEAMEXE="$GAMES_WINE_PREFIX/drive_c/Program Files (x86)/Steam/steam.exe"
STARTMENU="$GAMES_WINE_PREFIX/drive_c/users/$USER/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Steam"
GAMEICONS="$GAMES_WINE_PREFIX/drive_c/Program Files (x86)/Steam/steam/games"

log() {
  printf "==> %s\n" "$1"
}

die() {
  printf "Error: %s\n" "$1" >&2
  exit 1
}

ensure_sudo_ready() {
  log "Preparing sudo session (needed to install into /Applications)"
  sudo -v
}

resolve_path() {
  local path="$1"
  local base_dir="$2"

  if [[ "${path}" = /* ]]; then
    [[ -e "${path}" ]] || die "Path does not exist: ${path}"
    printf "%s\n" "${path}"
    return
  fi

  if [[ -e "${base_dir}/${path}" ]]; then
    printf "%s\n" "${base_dir}/${path}"
    return
  fi

  if [[ -e "${SCRIPT_DIR}/${path}" ]]; then
    printf "%s\n" "${SCRIPT_DIR}/${path}"
    return
  fi

  die "Path does not exist: ${path}"
}

xml_escape() {
  local value="$1"
  value="${value//&/&amp;}"
  value="${value//</&lt;}"
  value="${value//>/&gt;}"
  printf "%s" "${value}"
}

write_info_plist() {
  local destination="$1"
  local app_name="$2"
  local bundle_id="$3"
  local app_version="$4"
  local min_system_version="$5"

  cat > "${destination}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$(xml_escape "${app_name}")</string>
    <key>CFBundleDisplayName</key>
    <string>$(xml_escape "${app_name}")</string>
    <key>CFBundleExecutable</key>
    <string>${LAUNCHER_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>$(xml_escape "${bundle_id}")</string>
    <key>CFBundleVersion</key>
    <string>$(xml_escape "${app_version}")</string>
    <key>CFBundleShortVersionString</key>
    <string>$(xml_escape "${app_version}")</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>$(xml_escape "${min_system_version}")</string>
    <key>NSHumanReadableCopyright</key>
    <string>MIT License</string>
</dict>
</plist>
EOF
}

write_runtime_env() {
  local destination="$1"
  local env_name

  {
    printf 'APP_NAME=%q\n' "${APP_NAME}"
    printf 'RUN_ENV_NAMES=(\n'
    if (( ${#RUN_ENV_NAMES[@]} > 0 )); then
      for env_name in "${RUN_ENV_NAMES[@]}"; do
        printf '  %q\n' "${env_name}"
      done
    fi
    printf ')\n'

    if (( ${#RUN_ENV_NAMES[@]} > 0 )); then
      for env_name in "${RUN_ENV_NAMES[@]}"; do
        [[ "${!env_name+x}" == "x" ]] || die "Config ${config_path} is missing ${env_name}"
        printf '%s=%q\n' "${env_name}" "${!env_name}"
      done
    fi
  } > "${destination}"
}

collect_config_paths() {
  local arg
  local config_path

  if (( $# > 0 )); then
    for arg in "$@"; do
      if [[ -f "${arg}" ]]; then
        printf '%s\0' "${arg}"
        continue
      fi

      config_path="${CONFIGS_DIR}/${arg%.conf}.conf"
      [[ -f "${config_path}" ]] || die "Config not found: ${arg}"
      printf '%s\0' "${config_path}"
    done
    return
  fi

  shopt -s nullglob
  local config_paths=("${CONFIGS_DIR}"/*.conf)
  shopt -u nullglob

  (( ${#config_paths[@]} > 0 )) || die "No configs found in ${CONFIGS_DIR}"

  printf '%s\0' "${config_paths[@]}"
}

build_from_config() (
  set -euo pipefail

  local config_path="$1"
  local output_dir="$2"
  local config_dir
  config_dir="$(cd -- "$(dirname -- "${config_path}")" && pwd)"

  local APP_NAME=""
  local BUNDLE_ID=""
  local ICON_PATH="${DEFAULT_ICON_PATH}"
  local APP_VERSION="1.0"
  local LS_MINIMUM_SYSTEM_VERSION="11.0"
  local -a RUN_ENV_NAMES=()

  # shellcheck disable=SC1090
  source "${config_path}"

  [[ -n "${APP_NAME}" ]] || die "Config ${config_path} must set APP_NAME"
  [[ "${APP_NAME}" != */* ]] || die "APP_NAME must not contain '/' in ${config_path}"
  [[ -n "${BUNDLE_ID}" ]] || die "Config ${config_path} must set BUNDLE_ID"

  local icon_source
  icon_source="$(resolve_path "${ICON_PATH}" "${config_dir}")"

  local build_dir="${output_dir}/${APP_NAME}.app"

  log "Building ${APP_NAME}.app"

  rm -rf "${build_dir}"
  mkdir -p "${build_dir}/Contents/MacOS" "${build_dir}/Contents/Resources"

  write_info_plist \
    "${build_dir}/Contents/Info.plist" \
    "${APP_NAME}" \
    "${BUNDLE_ID}" \
    "${APP_VERSION}" \
    "${LS_MINIMUM_SYSTEM_VERSION}"

  printf 'APPL????' > "${build_dir}/Contents/PkgInfo"

  cp "${LAUNCHER_TEMPLATE}" "${build_dir}/Contents/MacOS/${LAUNCHER_NAME}"
  chmod +x "${build_dir}/Contents/MacOS/${LAUNCHER_NAME}"

  cp "${icon_source}" "${build_dir}/Contents/Resources/AppIcon.icns"
  cp "${SCRIPT_DIR}/run.command" "${build_dir}/Contents/Resources/run.command"
  chmod +x "${build_dir}/Contents/Resources/run.command"

  # run.command resolves the CEF wrapper relative to itself, so it has to travel
  # inside the bundle. Launches normally just redeploy the cached binary from
  # ~/.merlot, but shipping the source lets a bundle rebuild it if that is gone.
  if [[ -d "${SCRIPT_DIR}/wrapper" ]]; then
    cp -R "${SCRIPT_DIR}/wrapper" "${build_dir}/Contents/Resources/wrapper"
    chmod +x "${build_dir}/Contents/Resources/wrapper/install-wrapper.sh"
  fi

  write_runtime_env "${build_dir}/Contents/Resources/merlot.env"
)

# ---------------------------------------------------------------------------
# Per-game launchers (./install_merlot.command --games ...)
#
# Steam under Wine drops Windows .url shortcuts that macOS resolves to the
# NATIVE Mac Steam client (wrong Steam, blank icons). Instead, build a real
# .app bundle per installed game with the game's own icon.
# ---------------------------------------------------------------------------

games_detect_wine() {
  local d best=""
  while IFS= read -r d; do
    [ -x "$d/Wine Staging.app/Contents/Resources/wine/bin/wine" ] || continue
    best="$d"
  done < <(ls -d "$HOME"/wine-*/ 2>/dev/null | sed 's:/$::' \
           | grep -E '/wine-[0-9]+([._][0-9]+)*$' | sort -V)
  printf '%s' "${best:+$best/Wine Staging.app/Contents/Resources/wine/bin/wine}"
}

games_installed_list() {  # emits "appid|name"
  local m appid name
  for m in "$STEAMAPPS"/appmanifest_*.acf; do
    [ -e "$m" ] || continue
    appid=$(sed -n 's/.*"appid"[[:space:]]*"\([0-9]*\)".*/\1/p' "$m" | head -1)
    name=$(sed -n 's/.*"name"[[:space:]]*"\([^"]*\)".*/\1/p' "$m" | head -1)
    case "${appid:-}" in ""|228980) continue ;; esac
    echo "$appid|$name"
  done
}

games_make_icon() {  # appid appdir -> icns from Steam's own art
  local appid="$1" app="$2" final="$app/Contents/Resources/game.icns"
  [ -s "$final" ] && return 0
  local icns="$ICONCACHE/$appid.icns"
  [ -s "$icns" ] && { cp "$icns" "$final"; return 0; }
  local T src w h side y cand icohash urlfile
  T=$(mktemp -d) || return 0
  src=""
  # 1) Steam's own 256x256 game icon (referenced by the Start Menu shortcut)
  if [ -d "$STARTMENU" ]; then
    for urlfile in "$STARTMENU"/*.url; do
      [ -e "$urlfile" ] || continue
      grep -q "rungameid/$appid" "$urlfile" || continue
      icohash=$(sed -n 's/.*games\\\([0-9a-f]*\)\.ico.*/\1/p' "$urlfile" | head -1)
      [ -n "$icohash" ] && [ -s "$GAMEICONS/$icohash.ico" ] && src="$GAMEICONS/$icohash.ico" && break
    done
  fi
  # 2) library capsule / hero art
  if [ -z "$src" ]; then
    for cand in "$LIBCACHE/$appid"/*/library_capsule.jpg "$LIBCACHE/$appid"/*/library_hero.jpg; do
      [ -s "$cand" ] && src="$cand" && break
    done
  fi
  if [ -z "$src" ]; then
    echo "  .. no art cached for $appid yet (icon retried next sync)"
    rm -rf "$T"; return 0
  fi
  sips -s format png "$src" --out "$T/base.png" >/dev/null 2>&1
  w=$(sips -g pixelWidth  "$T/base.png" 2>/dev/null | awk '/pixelWidth/{print $2}')
  h=$(sips -g pixelHeight "$T/base.png" 2>/dev/null | awk '/pixelHeight/{print $2}')
  [ -n "$w" ] && [ -n "$h" ] || { rm -rf "$T"; return 0; }
  side=$(( w < h ? w : h ))
  y=$(( (h - side) / 3 ))
  sips -c "$side" "$side" --cropOffset "$y" 0 "$T/base.png" --out "$T/sq.png" >/dev/null 2>&1 \
    || sips -c "$side" "$side" "$T/base.png" --out "$T/sq.png" >/dev/null
  local iconset="$T/icon.iconset" n
  mkdir -p "$iconset"
  for n in 16 32 128 256 512; do
    sips -z "$n" "$n" "$T/sq.png" --out "$iconset/icon_${n}x${n}.png" >/dev/null 2>&1
    sips -z $((n*2)) $((n*2)) "$T/sq.png" --out "$iconset/icon_${n}x${n}@2x.png" >/dev/null 2>&1
  done
  if iconutil -c icns "$iconset" -o "$icns" 2>/dev/null; then
    cp "$icns" "$final"
    echo "  icon: $(basename "$src")"
  else
    echo "  WARN: icns build failed for $appid"
  fi
  rm -rf "$T"
}

games_make_launcher() {  # appid name
  local appid="$1" name="$2" app="$GAMES_DIR/$name.app"
  if [ -d "$app" ]; then
    games_make_icon "$appid" "$app"
    return 0
  fi
  echo "  + $name"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
  local wine_bin
  wine_bin="$(games_detect_wine)"
  [ -n "$wine_bin" ] || die "No Wine tree found under ~/wine-* (run ./run.command first)"
  cat > "$app/Contents/MacOS/$name" <<LAUNCH
#!/bin/bash
# Launches $name via Wine Steam (DXMT/Metal). Built by install_merlot.command --games.
export WINEPREFIX="$GAMES_WINE_PREFIX"
if ! pgrep -f "Steam/steam\.exe" >/dev/null 2>&1; then
  # Cold start: bring Steam up through run.command (wrapper + flags + DXMT env)
  ( cd "$MERLOT_REPO" && nohup ./run.command >/dev/null 2>&1 & )
  # Wait up to 3 min for the client (first-run self-update can be slow)
  for i in \$(seq 1 90); do
    pgrep -f "Steam/steam\.exe" >/dev/null 2>&1 && break
    sleep 2
  done
  sleep 5
fi
exec "$wine_bin" "$STEAMEXE" -silent -applaunch $appid
LAUNCH
  chmod +x "$app/Contents/MacOS/$name"
  cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>$name</string>
  <key>CFBundleIdentifier</key><string>local.merlot.games.$appid</string>
  <key>CFBundleName</key><string>$name</string>
  <key>CFBundleDisplayName</key><string>$name</string>
  <key>CFBundleIconFile</key><string>game</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
  plutil -lint "$app/Contents/Info.plist" >/dev/null || echo "  WARN: bad plist for $name"
  games_make_icon "$appid" "$app"
}

games_sync() {
  echo "merlot-games sync @ $(date '+%H:%M:%S')"
  local line appid name ids="" a bid
  while IFS='|' read -r appid name; do
    games_make_launcher "$appid" "$name"
    ids="$ids $appid"
  done < <(games_installed_list)
  # drop launchers whose game is gone
  for a in "$GAMES_DIR"/*.app; do
    [ -d "$a" ] || continue
    bid=$(plutil -extract CFBundleIdentifier raw "$a/Contents/Info.plist" 2>/dev/null)
    case "$bid" in
      local.merlot.games.*)
        appid=${bid##*.}
        case " $ids " in *" $appid "*) ;; *)
          echo "  - removing $(basename "$a") (uninstalled)"
          rm -rf "$a" ;;
        esac ;;
    esac
  done
  local lsr="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
  "$lsr" -f "$GAMES_DIR" >/dev/null 2>&1 || true
  echo "done"
}

games_watch() {
  mkdir -p "$HOME/Library/LaunchAgents" "$HOME/bin"
  local self="$SCRIPT_DIR/install_merlot.command"
  [ -f "$self" ] || die "Cannot locate install_merlot.command to install the watch agent"
  cp "$self" "$HOME/bin/merlot-games"
  chmod +x "$HOME/bin/merlot-games"
  cat > "$PLIST_PATH" <<AGENT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$PLIST_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$HOME/bin/merlot-games</string>
    <string>--games</string>
    <string>sync</string>
  </array>
  <key>WatchPaths</key>
  <array>
    <string>$STEAMAPPS</string>
    <string>$LIBCACHE</string>
  </array>
  <key>StartInterval</key><integer>1800</integer>
  <key>RunAtLoad</key><false/>
  <key>StandardOutPath</key><string>$ICONCACHE/watch.log</string>
  <key>StandardErrorPath</key><string>$ICONCACHE/watch.log</string>
</dict>
</plist>
AGENT
  plutil -lint "$PLIST_PATH" >/dev/null || die "bad agent plist"
  launchctl unload "$PLIST_PATH" >/dev/null 2>&1
  launchctl load "$PLIST_PATH" && echo "watch agent installed (auto-sync on game installs; log: $ICONCACHE/watch.log)"
}

games_unwatch() {
  launchctl unload "$PLIST_PATH" >/dev/null 2>&1
  rm -f "$PLIST_PATH"
  echo "watch agent removed"
}

games_status() {
  echo "launchers:"
  local a bid ic
  for a in "$GAMES_DIR"/*.app; do
    [ -d "$a" ] || continue
    bid=$(plutil -extract CFBundleIdentifier raw "$a/Contents/Info.plist" 2>/dev/null)
    [ -s "$a/Contents/Resources/game.icns" ] && ic=ok || ic=MISSING
    echo "  $(basename "$a") [$bid] icon:$ic"
  done
  if launchctl list 2>/dev/null | grep -q "$PLIST_LABEL"; then
    echo "watch agent: loaded"
  else
    echo "watch agent: not loaded"
  fi
}

games_main() {
  mkdir -p "$GAMES_DIR" "$ICONCACHE"
  case "${1:-}" in
    sync)    games_sync ;;
    watch)   games_watch ;;
    unwatch) games_unwatch ;;
    status)  games_status ;;
    *) echo "usage: $0 --games {sync|watch|unwatch|status}"; exit 1 ;;
  esac
}

# Generic shortcut import stays in this entrypoint; support sources live in app/merlot.
programs_main() {
  export PROGRAMS_SCRIPT_DIR="$SCRIPT_DIR"
  export PROGRAMS_ENTRYPOINT="${PROGRAMS_ENTRYPOINT:-$SCRIPT_DIR/install_merlot.command}"
  /usr/bin/python3 - "$@" <<'PROGRAMS_PY'
# BEGIN PROGRAMS PYTHON
import configparser
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shlex
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import time
import uuid

OWNER = 'local.chardonnay.shortcuts'
HOME = Path.home()
STATE = HOME / '.cache/chardonnay-shortcuts'
CONFIG = Path(os.environ.get('PROGRAMS_CONFIG', str(HOME / '.config/chardonnay-shortcuts/config.json')))
LABEL = OWNER + '.watch'
AGENT = HOME / 'Applications/Wine Shortcuts.app'


def atomic_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(path.name + '.' + uuid.uuid4().hex + '.new')
    temp.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')
    temp.replace(path)


def host_path(path, profile):
    path = str(path).strip('"')
    if re.match(r'^[Cc]:[\\/]', path):
        return Path(profile['path']) / 'drive_c' / path[3:].replace('\\', '/')
    if re.match(r'^[A-Za-z]:[\\/]', path):
        drive = Path(profile['path']) / 'dosdevices' / (path[0].lower() + ':')
        return drive / path[3:].replace('\\', '/')
    return Path(path) if path.startswith('/') else None


def profile_env(profile):
    env = dict(os.environ)
    for key in ['WINEDLLPATH', 'WINEDLLPATH_PREPEND', 'WINELOADER', 'WINESERVER', 'WINEPREFIX', 'CX_ACTIVE_GRAPHICS_BACKEND', 'CX_APPLEGPTK_LIBD3DSHARED_PATH', 'CX_LIBVULKAN']:
        env.pop(key, None)
    env.update({'WINEPREFIX': profile['path'], 'WINEDEBUG': '-all', 'WINEDLLPATH': ''})
    env.update(profile.get('environment', {}))
    env['WINEPREFIX'] = profile['path']
    return env


def inspect_link(path, profile):
    helper = os.environ.get('PROGRAMS_HELPER', str(STATE / 'ShortcutInfo.exe'))
    winpath = 'Z:' + str(Path(path).absolute()).replace('/', '\\')
    result = subprocess.run([profile['wine'], helper, winpath], env=profile_env(profile),
                            capture_output=True, text=True, encoding='utf-8', timeout=25)
    if result.returncode:
        raise RuntimeError('shell-link inspector failed')
    return json.loads(result.stdout.strip().lstrip('\ufeff'))


def url_metadata(path):
    data = Path(path).read_bytes()
    text = data.decode('utf-16' if data.startswith((b'\xff\xfe', b'\xfe\xff')) else 'utf-8-sig', errors='replace')
    parser = configparser.ConfigParser(interpolation=None)
    parser.read_string(text)
    section = parser['InternetShortcut']
    target = section.get('URL', '').strip()
    scheme = target.partition(':')[0].lower()
    if scheme not in {'steam', 'origin', 'origin2', 'ealink', 'com.epicgames.launcher', 'http', 'https'}:
        raise ValueError('unsupported shortcut URL protocol')
    return {'target': target, 'arguments': '', 'working_dir': '', 'icon': section.get('IconFile', ''), 'icon_index': int(section.get('IconIndex', '0'))}


def safe_name(name):
    name = re.sub(r'[\x00-\x1f/:]', '-', name).strip(' .')
    while len(name.encode('utf-8')) > 150:
        name = name[:-1]
    return name or 'Wine Program'


def pe_icon(path, index=0):
    """Bounded RT_GROUP_ICON/RT_ICON extraction; never loads executable code."""
    if Path(path).stat().st_size > 128*1024*1024: raise ValueError('icon source too large')
    data = Path(path).read_bytes()
    def u16(off): return struct.unpack_from('<H', data, off)[0]
    def u32(off): return struct.unpack_from('<I', data, off)[0]
    if data[:2] != b'MZ': raise ValueError('not PE')
    pe = u32(0x3c)
    if data[pe:pe+4] != b'PE\0\0': raise ValueError('not PE')
    optional = pe + 24
    directories = optional + (112 if u16(optional) == 0x20b else 96)
    section_start = optional + u16(pe+20)
    sections = []
    for i in range(min(u16(pe+6), 96)):
        off = section_start + i*40
        sections.append((u32(off+12), max(u32(off+8), u32(off+16)), u32(off+20)))
    def rva(value):
        for start, length, raw in sections:
            if start <= value < start+length: return raw + value-start
        raise ValueError('unmapped PE resource')
    base = rva(u32(directories+16))
    def entries(relative):
        off = base + relative
        count = u16(off+12)+u16(off+14)
        if count > 4096: raise ValueError('oversized resource directory')
        return [(u32(off+16+i*8), u32(off+20+i*8)) for i in range(count)]
    def payload(entry):
        for _ in range(4):
            if not entry & 0x80000000:
                off = base+entry; start=rva(u32(off)); size=u32(off+4)
                if size > 16*1024*1024 or start+size > len(data): raise ValueError('invalid resource size')
                return data[start:start+size]
            child = entries(entry & 0x7fffffff)
            if not child: raise ValueError('empty resource directory')
            entry = child[0][1]
        raise ValueError('resource depth exceeded')
    root = dict(entries(0))
    groups = entries(root[14] & 0x7fffffff)
    selected = next((value for ident, value in groups if index < 0 and ident == -index), None)
    if selected is None: selected = groups[min(max(index, 0), len(groups)-1)][1]
    group = payload(selected); count=struct.unpack_from('<H', group, 4)[0]
    if not 0 < count <= 256 or len(group) < 6+14*count: raise ValueError('invalid group icon')
    icons = dict(entries(root[3] & 0x7fffffff))
    header = bytearray(struct.pack('<HHH', 0, 1, count)); blobs=[]; position=6+16*count
    for i in range(count):
        entry = group[6+14*i:20+14*i]; ident=struct.unpack_from('<H', entry, 12)[0]
        blob = payload(icons[ident]); header.extend(entry[:8]+struct.pack('<II', len(blob), position)); blobs.append(blob); position+=len(blob)
    return bytes(header)+b''.join(blobs)


class Importer:
    def __init__(self, config, state_dir=STATE, inspect=None):
        self.config=config; self.state=Path(state_dir); self.output=Path(config.get('output_dir', str(HOME/'Desktop'))).expanduser()
        self.state.mkdir(parents=True, exist_ok=True)
        self.inspect=inspect or inspect_link
        path=self.state/'manifest.json'
        self.manifest=json.loads(path.read_text()) if path.exists() else {'entries': {}, 'cache': {}}
        self.complete=True

    def roots(self, profile):
        prefix=Path(profile['path']).expanduser()
        if not (prefix/'drive_c').is_dir(): raise FileNotFoundError('registered prefix unavailable')
        roots=[]
        users=prefix/'drive_c/users'
        for user in users.iterdir():
            if user.is_symlink() or not user.is_dir() or user.name.lower() in {'public', 'all users', 'default'}: continue
            for name in ['Wine Shortcuts', 'Steam Shortcuts', 'Desktop']:
                directory=user/name
                if not directory.is_symlink(): roots.append((directory, 'desktop'))
            roots.append((user/'AppData/Roaming/Microsoft/Windows/Start Menu/Programs', 'start'))
            roots.append((user/'Start Menu/Programs', 'start'))
        roots.append((prefix/'drive_c/ProgramData/Microsoft/Windows/Start Menu/Programs', 'start'))
        return roots

    def scan(self):
        found=[]; self.complete=True
        def failed(error): raise error
        for profile in self.config['prefixes']:
            for root, kind in self.roots(profile):
                if not root.exists(): continue
                for folder, dirs, files in os.walk(root, onerror=failed):
                    dirs[:]=[d for d in dirs if not d.endswith('.app') and not Path(folder,d).is_symlink()]
                    for name in sorted(files):
                        source=Path(folder,name)
                        if source.stem.casefold() in {n.casefold() for n in profile.get('exclude_names', [])}: continue
                        if source.is_symlink() or source.suffix.lower() not in {'.lnk', '.url'}: continue
                        if kind=='start' and re.search(r'(?i)uninstall|updat|recovery|repair|reporter|support|readme|help|documentation', source.stem): continue
                        stat=source.stat()
                        if time.time()-stat.st_mtime < 1: self.complete=False; continue
                        cachekey=profile['id']+'|'+str(source)
                        stamp=[stat.st_size, stat.st_mtime_ns]
                        old=self.manifest.get('cache', {}).get(cachekey, {})
                        try:
                            metadata=old['metadata'] if old.get('stamp')==stamp else (url_metadata(source) if source.suffix.lower()=='.url' else self.inspect(source, profile))
                            if not metadata.get('target'): self.complete=False; continue
                            if kind=='start' and source.suffix.lower()=='.url' and metadata['target'].startswith(('http:', 'https:')): continue
                            if kind=='start' and source.suffix.lower()=='.lnk' and not metadata['target'].lower().endswith(('.exe', '.com', '.bat', '.cmd', '.msi')): continue
                            self.manifest.setdefault('cache', {})[cachekey]={'stamp':stamp, 'metadata':metadata}
                            canonical={'prefix':profile['id'], 'target':metadata['target'].replace('/', '\\').casefold() if source.suffix.lower()=='.lnk' else metadata['target'], 'arguments':metadata.get('arguments',''), 'cwd':metadata.get('working_dir','').casefold()}
                            ident=hashlib.sha256(json.dumps(canonical, sort_keys=True).encode()).hexdigest()[:20]
                            found.append({'id':ident,'name':source.stem,'source':str(source),'kind':kind,'profile':profile,'metadata':metadata})
                        except (OSError, ValueError, KeyError, RuntimeError, configparser.Error, subprocess.SubprocessError):
                            self.complete=False
                            print('shortcut temporarily unreadable; keeping existing launchers', flush=True)
        found.sort(key=lambda item:(item['kind']!='desktop',len(item['name']),item['name'].casefold()))
        ordered = {}
        for item in found: ordered.setdefault(item['id'], item)
        return ordered

    @staticmethod
    def owned(path, ident=None):
        try:
            if Path(path).is_symlink(): return False
            obj=json.loads((Path(path)/'Contents/Resources/shortcut.json').read_text())
            return obj.get('managed_by')==OWNER and (ident is None or obj.get('id')==ident)
        except (OSError, ValueError): return False

    def app_path(self, item):
        previous=self.manifest['entries'].get(item['id'],{}).get('app')
        if previous and Path(previous).parent==self.output and self.owned(previous,item['id']): return Path(previous)
        name=safe_name(item['name']); bottle=safe_name(item['profile'].get('name',item['profile']['id']))
        for suffix in ['', ' ('+bottle+')', ' ('+bottle+'-'+item['id'][:6]+')']:
            path=self.output/(name+suffix+'.app')
            if not path.exists() and not path.is_symlink() or self.owned(path,item['id']): return path
        raise FileExistsError('launcher name collision')

    def icon(self, item, destination):
        fallback=Path(os.environ.get('PROGRAMS_ICON',str(Path(os.environ.get('PROGRAMS_SCRIPT_DIR','.'))/'app/merlot/AppIcon.icns')))
        if fallback.is_file(): shutil.copy2(fallback,destination)
        if sys.platform!='darwin': return
        icon=host_path(item['metadata'].get('icon',''),item['profile'])
        if icon is None or not icon.is_file(): icon=host_path(item['metadata']['target'],item['profile'])
        if icon is None or not icon.is_file(): return
        try:
            with tempfile.TemporaryDirectory(dir=self.state) as temp:
                temp=Path(temp);source=icon
                if icon.suffix.lower() in {'.exe','.dll'}:
                    source=temp/'source.ico';source.write_bytes(pe_icon(icon,item['metadata'].get('icon_index',0)))
                if source.suffix.lower()=='.icns': shutil.copy2(source,destination);return
                png=temp/'base.png'
                subprocess.run(['/usr/bin/sips','-s','format','png',str(source),'--out',str(png)],check=True,capture_output=True,timeout=15)
                iconset=temp/'AppIcon.iconset';iconset.mkdir()
                for size in [16,32,128,256,512]:
                    for scale in [1,2]:
                        filename='icon_%dx%d%s.png'%(size,size,'@2x' if scale==2 else '')
                        subprocess.run(['/usr/bin/sips','-z',str(size*scale),str(size*scale),str(png),'--out',str(iconset/filename)],check=True,capture_output=True,timeout=10)
                subprocess.run(['/usr/bin/iconutil','-c','icns',str(iconset),'-o',str(destination)],check=True,capture_output=True,timeout=15)
        except (OSError, ValueError, KeyError, IndexError, struct.error, subprocess.SubprocessError): pass

    def build(self, item, app):
        entry=self.config.get('entrypoint',os.environ.get('PROGRAMS_ENTRYPOINT',''))
        descriptor={'managed_by':OWNER,**item}
        descriptor.pop('kind',None)
        content=json.dumps(descriptor,ensure_ascii=False,sort_keys=True)
        existing=app/'Contents/Resources/shortcut.json'
        if existing.is_file() and json.dumps(json.loads(existing.read_text()),ensure_ascii=False,sort_keys=True)==content: return False
        self.output.mkdir(parents=True,exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='.wine-app-',dir=self.output) as temp:
            stage=Path(temp)/app.name;mac=stage/'Contents/MacOS';resources=stage/'Contents/Resources';mac.mkdir(parents=True);resources.mkdir()
            plist={'CFBundlePackageType':'APPL','CFBundleName':item['name'],'CFBundleDisplayName':item['name'],'CFBundleExecutable':'launch','CFBundleIdentifier':OWNER+'.app.'+item['id'],'CFBundleVersion':str(int(time.time())),'CFBundleIconFile':'AppIcon','NSHighResolutionCapable':True}
            (stage/'Contents/Info.plist').write_bytes(plistlib.dumps(plist))
            (resources/'shortcut.json').write_text(json.dumps(descriptor,ensure_ascii=False,indent=2)+'\n')
            script='#!/bin/bash\nRESOURCE_DIR="$(cd -- "$(dirname -- "$0")/../Resources" && pwd)"\nexec /bin/bash '+shlex.quote(entry)+' --programs launch "$RESOURCE_DIR/shortcut.json"\n'
            (mac/'launch').write_text(script);(mac/'launch').chmod(0o755)
            self.icon(item,resources/'AppIcon.icns')
            if app.exists():
                if not self.owned(app,item['id']): raise FileExistsError('refusing to overwrite unmanaged app')
                old=self.state/'Replaced'/str(uuid.uuid4())/app.name;old.parent.mkdir(parents=True);shutil.move(str(app),str(old))
            shutil.move(str(stage),str(app))
        if sys.platform=='darwin':
            lsr='/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
            if Path(lsr).exists(): subprocess.run([lsr,'-f',str(app)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=10)
        return True

    def sync(self):
        items=self.scan();self.output.mkdir(parents=True,exist_ok=True)
        changed=0;new={}
        for ident,item in items.items():
            app=self.app_path(item);changed+=self.build(item,app);new[ident]={'app':str(app),'profile':item['profile']['id'],'source':item['source']}
        for ident,old in self.manifest['entries'].items():
            if ident in new: continue
            if not self.complete: new[ident]=old;continue
            app=Path(old['app'])
            if app.parent==self.output and self.owned(app,ident):
                retired=self.state/'Retired'/app.name;retired.parent.mkdir(exist_ok=True)
                if retired.exists(): retired=retired.with_name(retired.stem+'-'+uuid.uuid4().hex[:6]+'.app')
                shutil.move(str(app),str(retired));changed+=1
        for ident,item in items.items():
            if not item['profile'].get('prefer_plain_name'): continue
            current=Path(new[ident]['app']);plain=self.output/(safe_name(item['name'])+'.app')
            if current!=plain and not plain.exists() and not plain.is_symlink() and self.owned(current,ident):
                shutil.move(str(current),str(plain));new[ident]['app']=str(plain);changed+=1
        self.manifest['entries']=new
        atomic_json(self.state/'manifest.json',self.manifest)
        summary={'launchers':len(new),'changed':changed,'complete_scan':self.complete,'desktop':str(self.output),'checked_at':int(time.time())}
        atomic_json(self.state/'status.json',summary)
        if changed: print(json.dumps(summary),flush=True)
        return summary


def launch(descriptor):
    item=json.loads(Path(descriptor).read_text())
    if item.get('managed_by')!=OWNER: raise ValueError('not a managed launcher')
    profile=item['profile'];metadata=item['metadata'];env=profile_env(profile)
    root=Path(profile['path']);target=metadata['target'];name=item['name']
    executable=target.replace('\\','/').rsplit('/',1)[-1].casefold()
    target_rules={key.casefold():value for key,value in profile.get('target_overrides',{}).items()}
    override=target_rules.get(executable) or profile.get('overrides',{}).get(name)
    # A game/argument-bearing link is not the bare client launcher. Let Wine
    # honor its original Windows command line instead of discarding arguments.
    if metadata.get('arguments'): override=None
    if override:
        targets=list(root.glob(override['target_glob']))
        if not targets: raise FileNotFoundError('configured application target is missing')
        target_path=max(targets,key=lambda p:p.stat().st_mtime)
        command=[profile['wine'],str(target_path)]+override.get('arguments',[])
    elif profile.get('role')=='merlot' and not metadata.get('arguments') and (re.match(r'^steam://(?:run|rungameid)/[0-9]+',target) or target.replace('\\','/').lower().endswith('/steam.exe')):
        match=re.match(r'^steam://(?:run|rungameid)/([0-9]+)',target)
        if match: env['STEAM_GAME_ID']=match.group(1)
        command=['/bin/bash',str(Path(profile.get('repo',str(HOME/'macos-wine-steam')))/'run.command')]
    elif item['source'].lower().endswith('.url'):
        command=[profile['wine'],'start',target]
    else:
        command=[profile['wine'],'start','/unix',item['source']]
    cwd=host_path(metadata.get('working_dir',''),profile)
    if cwd is None or not cwd.is_dir(): cwd=root
    STATE.mkdir(parents=True,exist_ok=True)
    with (STATE/('launch-'+item['id']+'.log')).open('ab') as output:
        result=subprocess.run(command,env=env,cwd=str(cwd),stdout=output,stderr=subprocess.STDOUT)
    atomic_json(STATE/('launch-'+item['id']+'.status.json'),{'exit_code':result.returncode,'checked_at':int(time.time())})
    return result.returncode


def install_watch(config, configure=True):
    source=Path(os.environ['PROGRAMS_SCRIPT_DIR']);entry=Path(os.environ['PROGRAMS_ENTRYPOINT']);STATE.mkdir(parents=True,exist_ok=True)
    gcc=shutil.which('x86_64-w64-mingw32-gcc') or '/opt/homebrew/bin/x86_64-w64-mingw32-gcc'
    helper=STATE/'ShortcutInfo.exe'
    subprocess.run([gcc,'-municode','-O2','-Wall',str(source/'app/merlot/ShortcutInfo.c'),'-o',str(helper),'-lole32','-lshell32','-luuid','-ladvapi32'],check=True)
    if configure:
        for profile in config['prefixes']:
            result=subprocess.run([profile['wine'],str(helper),'--setup-desktop'],env=profile_env(profile),capture_output=True,text=True,timeout=30)
            if result.returncode: raise RuntimeError('could not configure private Wine Desktop for '+profile['id'])
            print('private Desktop import folder configured for '+profile['id'],flush=True)
    app=AGENT;mac=app/'Contents/MacOS';resources=app/'Contents/Resources'
    if app.exists():
        info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
        if info.get('CFBundleIdentifier')!=OWNER+'.agent': raise FileExistsError('agent app is not owned by this importer')
    mac.mkdir(parents=True,exist_ok=True);resources.mkdir(parents=True,exist_ok=True)
    env=dict(os.environ)
    if Path('/Applications/Xcode.app/Contents/Developer').exists(): env['DEVELOPER_DIR']='/Applications/Xcode.app/Contents/Developer'
    subprocess.run(['/usr/bin/clang','-fobjc-arc','-O2','-framework','Cocoa',str(source/'app/merlot/ShortcutAgent.m'),'-o',str(mac/'ShortcutAgent')],check=True,env=env)
    shutil.copy2(entry,STATE/'entrypoint.command')
    (resources/'entrypoint.command').write_text('#!/bin/bash\nexec /bin/bash \"$HOME/.cache/chardonnay-shortcuts/entrypoint.command\" \"$@\"\n')
    (resources/'entrypoint.command').chmod(0o755)
    shutil.copy2(helper,resources/'ShortcutInfo.exe');shutil.copy2(source/'app/merlot/AppIcon.icns',resources/'AppIcon.icns')
    plist={'CFBundlePackageType':'APPL','CFBundleExecutable':'ShortcutAgent','CFBundleIdentifier':OWNER+'.agent','CFBundleName':'Wine Shortcuts','CFBundleDisplayName':'Wine Shortcuts','CFBundleVersion':'1','LSUIElement':True,'NSHighResolutionCapable':True,'NSDesktopFolderUsageDescription':'Create native app launchers when Windows programs create Desktop or Start Menu shortcuts.'}
    (app/'Contents/Info.plist').write_bytes(plistlib.dumps(plist))
    subprocess.run(['/usr/bin/codesign','--force','--sign','-',str(app)],check=True,capture_output=True)
    agent=HOME/'Library/LaunchAgents'/(LABEL+'.plist');agent.parent.mkdir(parents=True,exist_ok=True)
    agent.write_bytes(plistlib.dumps({'Label':LABEL,'ProgramArguments':['/usr/bin/open','-g','-W',str(app)],'RunAtLoad':True,'StartInterval':60,'LimitLoadToSessionType':'Aqua','StandardOutPath':str(STATE/'launchd.log'),'StandardErrorPath':str(STATE/'launchd.log')}))
    domain='gui/'+str(os.getuid());subprocess.run(['/bin/launchctl','bootout',domain,str(agent)],capture_output=True)
    subprocess.run(['/bin/launchctl','enable',domain+'/'+LABEL],check=True)
    subprocess.run(['/bin/launchctl','bootstrap',domain,str(agent)],check=True)
    subprocess.run(['/usr/bin/open','-g',str(app)],check=True)
    print('watcher installed; allow Wine Shortcuts access to Desktop if macOS prompts',flush=True)


def main(arguments):
    action=arguments[0] if arguments else 'status'
    if action=='launch': return launch(arguments[1])
    if action=='status':
        status=STATE/'status.json'
        print(status.read_text() if status.exists() else 'No sync yet; start --programs watch and grant Desktop access.')
        return 0
    config=json.loads(CONFIG.read_text())
    config['entrypoint']=os.environ.get('PROGRAMS_ENTRYPOINT',config.get('entrypoint',''))
    if action=='watch': install_watch(config);return 0
    if action=='unwatch':
        agent=HOME/'Library/LaunchAgents'/(LABEL+'.plist')
        subprocess.run(['/bin/launchctl','disable','gui/'+str(os.getuid())+'/'+LABEL],check=True)
        subprocess.run(['/bin/launchctl','bootout','gui/'+str(os.getuid()),str(agent)],capture_output=True)
        record=STATE/'worker.json'
        if record.exists():
            saved=json.loads(record.read_text());pid=int(saved['pid'])
            actual=subprocess.run(['/bin/ps','-p',str(pid),'-o','lstart='],capture_output=True,text=True).stdout.strip()
            if pid>1 and actual and actual==saved['started']: os.kill(pid,signal.SIGTERM)
        print('watcher stopped; Desktop apps, import folders and configuration retained')
        return 0
    if action not in {'sync','daemon'}: raise ValueError('usage: --programs {sync|watch|status|unwatch}')
    STATE.mkdir(parents=True,exist_ok=True)
    with (STATE/'sync.lock').open('a') as lock:
        try: fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError: return 0
        if action=='daemon':
            started=subprocess.run(['/bin/ps','-p',str(os.getpid()),'-o','lstart='],capture_output=True,text=True).stdout.strip()
            atomic_json(STATE/'worker.json',{'pid':os.getpid(),'started':started})
            def stop(signum,frame): raise SystemExit(0)
            signal.signal(signal.SIGTERM,stop)
        importer=Importer(config)
        while True:
            try:
                latest=json.loads(CONFIG.read_text())
                latest['entrypoint']=os.environ.get('PROGRAMS_ENTRYPOINT',latest.get('entrypoint',''))
                importer.config=latest
                importer.sync()
            except (OSError,ValueError,subprocess.SubprocessError) as error:
                atomic_json(STATE/'status.json',{'error':type(error).__name__,'desktop_permission_required':isinstance(error,PermissionError),'checked_at':int(time.time())})
                print('shortcut sync blocked: '+type(error).__name__+'; existing apps retained',flush=True)
                if action=='sync': return 1
            if action=='sync': return 0
            time.sleep(5)


if __name__ == '__main__':
    try: sys.exit(main(sys.argv[1:]))
    except Exception as error:
        print('shortcut importer: '+type(error).__name__+'; no application was auto-launched',file=sys.stderr)
        sys.exit(1)
# END PROGRAMS PYTHON
PROGRAMS_PY
}

storage_main() {
  export STORAGE_ENTRYPOINT="${STORAGE_ENTRYPOINT:-$SCRIPT_DIR/install_merlot.command}"
  /usr/bin/python3 - "$@" <<'STORAGE_PY'
# BEGIN STORAGE PYTHON
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import sys

OWNER = 'local.chardonnay.storage'
MARKER = '.chardonnay-replica.json'
MAX_METADATA = 8 * 1024 * 1024


def read_vdf(path):
    """Read bounded Valve KeyValues data, never evaluate its contents."""
    path = Path(path)
    if path.is_symlink() or path.stat().st_size > MAX_METADATA:
        raise ValueError('unsafe_or_oversized_metadata')
    text = path.read_text(encoding='utf-8-sig')
    tokens = []; offset = 0
    lexer = re.compile(r'\s+|//[^\n]*|"(?:\\.|[^"\\])*"|[{}]')
    while offset < len(text):
        match = lexer.match(text, offset)
        if not match: raise ValueError('malformed_keyvalues')
        token = match.group(); offset = match.end()
        if not token.isspace() and not token.startswith('//'): tokens.append(token)
    position = 0
    def object_value(depth=0):
        nonlocal position
        if depth > 16: raise ValueError('metadata_depth_limit')
        result = {}
        while position < len(tokens) and tokens[position] != '}':
            key = tokens[position]; position += 1
            if not key.startswith('"') or position >= len(tokens): raise ValueError('missing_value')
            key = re.sub(r'\\(["\\])', r'\1', key[1:-1])
            value = tokens[position]; position += 1
            if value == '{':
                value = object_value(depth + 1)
                if position >= len(tokens) or tokens[position] != '}': raise ValueError('unterminated_object')
                position += 1
            elif value.startswith('"'):
                value = re.sub(r'\\(["\\])', r'\1', value[1:-1])
            else: raise ValueError('invalid_value')
            if key in result: raise ValueError('duplicate_key')
            result[key] = value
        return result
    result = object_value()
    if position != len(tokens): raise ValueError('unexpected_terminator')
    return result


def valid_appid(value):
    if not isinstance(value, str) or not re.fullmatch(r'[1-9][0-9]*', value):
        raise ValueError('invalid_appid')
    return value


def safe_component(value):
    if not isinstance(value, str) or value in {'', '.', '..'} or re.search(r'[/\\\x00]', value):
        raise ValueError('unsafe_install_directory')
    return value


def steam_path(profile):
    return Path(profile.get('steam_path', str(Path(profile['path']) / 'drive_c/Program Files (x86)/Steam'))).expanduser()


def mapped_path(value, profile):
    if value.startswith('/'): return Path(value)
    if re.match(r'^[Cc]:[\\/]', value):
        return Path(profile['path']) / 'drive_c' / value[3:].replace('\\', '/')
    if re.match(r'^[A-Za-z]:[\\/]', value):
        return Path(profile['path']) / 'dosdevices' / (value[0].lower() + ':') / value[3:].replace('\\', '/')
    raise ValueError('unmapped_library_path')


def library_roots(profile):
    primary = steam_path(profile)
    if not primary.is_dir(): return []
    roots = {str(primary.resolve()): primary.resolve()}
    folders = primary / 'steamapps/libraryfolders.vdf'
    if folders.exists():
        data = read_vdf(folders)['libraryfolders']
        if not isinstance(data, dict): raise ValueError('invalid_libraryfolders')
        for key, item in data.items():
            if not key.isdigit(): continue
            value = item.get('path', '') if isinstance(item, dict) else item
            path = mapped_path(value, profile).resolve()
            if not (path / 'steamapps').is_dir(): raise ValueError('library_unavailable')
            roots[str(path)] = path
    return list(roots.values())


def payload_usage(root):
    """Logical bytes and metadata fingerprint, NOT exclusive APFS usage."""
    root = Path(root); entries = []; errors = []; logical = files = 0
    if root.is_symlink(): raise ValueError('symlink_payload')
    if not root.is_dir(): raise ValueError('payload_missing')
    def failed(error): errors.append(type(error).__name__)
    for folder, directories, names in os.walk(root, followlinks=False, onerror=failed):
        for name in sorted(directories):
            path = Path(folder) / name
            if path.is_symlink(): errors.append('symlink_directory')
        directories[:] = sorted(name for name in directories if not (Path(folder) / name).is_symlink())
        for name in sorted(names):
            path = Path(folder) / name
            if path == root / MARKER: continue
            st = path.lstat()
            if not stat.S_ISREG(st.st_mode): errors.append('non_regular_file'); continue
            files += 1
            if files > 250000: raise ValueError('payload_entry_limit')
            logical += st.st_size
            entries.append([str(path.relative_to(root)), st.st_dev, st.st_ino, st.st_size, st.st_mtime_ns])
    digest = hashlib.sha256(json.dumps(sorted(entries), separators=(',', ':')).encode()).hexdigest()
    identity = root.stat()
    return {'files': files, 'logical_bytes': logical, 'device': identity.st_dev, 'inode': identity.st_ino,
            'metadata_fingerprint': digest, 'complete': not errors, 'errors': sorted(set(errors))}


def inventory(config):
    if config.get('version', 1) != 1: raise ValueError('unsupported_config_version')
    profiles = config.get('prefixes', [])
    ids = [p['id'] for p in profiles]
    if len(ids) != len(set(ids)): raise ValueError('duplicate_prefix_id')
    report = {'schema_version': 1, 'read_only': True, 'complete_scan': True,
              'installations': [], 'warnings': [], 'duplicate_appids': [], 'exclusive_reclaimable_bytes': None}
    seen = set()
    for profile in profiles:
        ident = profile['id']; prefix = Path(profile['path']).expanduser()
        try:
            if prefix.is_symlink() or not (prefix / 'drive_c').is_dir(): raise ValueError('prefix_unavailable')
            role = profile.get('storage_role', 'active')
            if role not in {'active', 'protected', 'managed_replica'}: raise ValueError('invalid_storage_role')
            for library in library_roots(profile):
                apps = library / 'steamapps'
                if apps.is_symlink() or not apps.is_dir(): raise ValueError('library_unavailable')
                for manifest in sorted(apps.glob('appmanifest_*.acf')):
                    try:
                        data = read_vdf(manifest)['AppState']; appid = valid_appid(data['appid'])
                        if manifest.name != 'appmanifest_' + appid + '.acf': raise ValueError('manifest_id_mismatch')
                        if appid == '228980': continue
                        key = (str(library.resolve()), appid)
                        if key in seen: continue
                        seen.add(key)
                        directory = safe_component(data['installdir']); flags = int(data['StateFlags'])
                        common = apps / 'common'
                        if common.is_symlink(): raise ValueError('symlink_common_directory')
                        game = common / directory
                        usage = payload_usage(game)
                        canonical = {'prefix': ident, 'library': str(library), 'appid': appid}
                        row = {'installation_id': hashlib.sha256(json.dumps(canonical, sort_keys=True).encode()).hexdigest()[:20],
                               'prefix_id': ident, 'prefix': str(prefix), 'role': role, 'library': str(library),
                               'appid': appid, 'name': data['name'], 'manifest': str(manifest), 'payload': str(game),
                               'manifest_state': flags, 'fully_installed': bool(flags & 4 and not flags & 2048),
                               'manifest_sha256': hashlib.sha256(manifest.read_bytes()).hexdigest(), **usage}
                        report['installations'].append(row)
                        if not usage['complete']: raise ValueError('incomplete_payload_inventory')
                    except (OSError, ValueError, KeyError, TypeError) as error:
                        report['complete_scan'] = False
                        report['warnings'].append({'prefix_id': ident, 'manifest': manifest.name, 'reason': str(error) if isinstance(error, ValueError) else type(error).__name__})
        except (OSError, ValueError, KeyError, TypeError) as error:
            report['complete_scan'] = False
            report['warnings'].append({'prefix_id': ident, 'reason': str(error) if isinstance(error, ValueError) else type(error).__name__})
    counts = {}
    for item in report['installations']: counts[item['appid']] = counts.get(item['appid'], 0) + 1
    report['duplicate_appids'] = sorted(key for key, value in counts.items() if value > 1)
    report['logical_copy_bytes'] = sum(item['logical_bytes'] for item in report['installations'])
    return report


def uninstall_proven(profile, record, appid):
    log = steam_path(profile) / 'logs/content_log.txt'
    if log.is_symlink(): return False
    try:
        with log.open('rb') as stream:
            st = os.fstat(stream.fileno()); offset = record['source_log_offset']
            if type(offset) is not int or offset < 0 or offset > st.st_size: return False
            if [st.st_dev, st.st_ino] != [record['source_log_device'], record['source_log_inode']]: return False
            if st.st_size - offset > MAX_METADATA: return False
            stream.seek(offset); text = stream.read(MAX_METADATA).decode('utf-8', errors='replace')
        return bool(re.search(r'\bAppID ' + re.escape(appid) + r' finished uninstall \(No Error\)(?:\r?$|\n)', text, re.M))
    except (OSError, KeyError, TypeError): return False


def uninstall_plan(config, report, appid, primary_prefix=None):
    appid = valid_appid(appid)
    profiles = {p['id']: p for p in config['prefixes']}
    if primary_prefix is not None and primary_prefix not in profiles: raise ValueError('unknown_primary_prefix')
    result = {'schema_version': 1, 'read_only': True, 'apply_supported': False, 'appid': appid,
              'primary_prefix': primary_prefix, 'complete_scan': report['complete_scan'], 'cleanup_candidates': [], 'retained': [],
              'exclusive_reclaimable_bytes': None,
              'requires_before_apply': ['verify_no_active_clients_or_games', 'revalidate_filesystem_and_ownership', 'explicit_cleanup_policy_and_authorization']}
    for item in report['installations']:
        if item['appid'] != appid: continue
        reason = 'not_explicitly_managed_replica'
        records = [r for r in config.get('replicas', []) if r.get('appid') == appid and r.get('replica_prefix_id') == item['prefix_id'] and r.get('library') == item['library']]
        if not report['complete_scan']: reason = 'incomplete_inventory'
        elif item['role'] == 'managed_replica' and len(records) == 1:
            record = records[0]; source = profiles.get(record.get('source_prefix_id'))
            try:
                if not source or source['id'] == item['prefix_id'] or source.get('storage_role', 'active') != 'active': raise ValueError('invalid_primary_owner')
                if primary_prefix is not None and source['id'] != primary_prefix: raise ValueError('different_primary_owner')
                if Path(source['path']).resolve() == Path(profiles[item['prefix_id']]['path']).resolve(): raise ValueError('primary_replica_alias')
                if any((library / 'steamapps' / ('appmanifest_' + appid + '.acf')).exists() for library in library_roots(source)): raise ValueError('primary_manifest_present')
                if any(x['appid'] == appid and x['prefix_id'] == source['id'] for x in report['installations']): raise ValueError('primary_still_has_installation')
                if record.get('managed_by') != OWNER or len(record.get('token', '')) < 16: raise ValueError('missing_ownership_record')
                marker = Path(item['payload']) / MARKER
                if marker.is_symlink() or marker.stat().st_size > 4096: raise ValueError('unsafe_ownership_marker')
                data = json.loads(marker.read_text())
                if any(data.get(k) != record.get(k) for k in ['managed_by', 'replica_id', 'appid', 'token']): raise ValueError('ownership_marker_mismatch')
                if not record.get('replica_id') or record.get('install_dir') != Path(item['payload']).name: raise ValueError('replica_path_mismatch')
                if [record.get('device'), record.get('inode')] != [item['device'], item['inode']]: raise ValueError('replica_identity_changed')
                if record.get('manifest_sha256') != item['manifest_sha256']: raise ValueError('replica_manifest_changed')
                if record.get('metadata_fingerprint') != item['metadata_fingerprint']: raise ValueError('replica_payload_changed')
                if not uninstall_proven(source, record, appid): raise ValueError('source_uninstall_not_proven')
                result['cleanup_candidates'].append({k: item[k] for k in ['installation_id', 'prefix_id', 'appid', 'payload', 'manifest', 'logical_bytes']})
                continue
            except (OSError, ValueError, KeyError, TypeError) as error:
                reason = str(error) if isinstance(error, ValueError) else type(error).__name__
        result['retained'].append({'prefix_id': item['prefix_id'], 'payload': item['payload'], 'reason': reason})
    return result


# BEGIN MANAGED STORAGE
import contextlib
import copy
import fcntl
import plistlib
import shutil
import subprocess
import time
import uuid


def storage_atomic_json(path, value):
    path = Path(path)
    if path.is_symlink(): raise ValueError('symlink_state_file')
    temporary = path.with_name('.' + path.name + '-' + uuid.uuid4().hex)
    with temporary.open('x', encoding='utf-8') as stream:
        os.chmod(temporary, 0o600)
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.flush(); os.fsync(stream.fileno())
    os.replace(temporary, path)


def prefix_activity(profile):
    """Inspect live effective-UID processes; unexplained omissions fail closed."""
    prefix = Path(profile['path']).resolve()
    try:
        def own_live_processes():
            result = subprocess.run(['/bin/ps', '-axo', 'pid=,stat=,uid=,comm='], capture_output=True, text=True, timeout=10, check=True)
            found = set()
            for line in result.stdout.splitlines():
                fields = line.split(None, 3)
                if len(fields) >= 3 and fields[0].isdigit() and fields[2].isdigit() and int(fields[2]) == os.getuid() and 'Z' not in fields[1]: found.add(int(fields[0]))
            return found
        pids = own_live_processes()
        if not pids: return {'verified': False, 'active': False, 'pids': []}
        lsof = shutil.which('lsof') or '/usr/sbin/lsof'
        files = subprocess.run([lsof, '-nP', '-a', '-p', ','.join(map(str, sorted(pids))), '-d', 'cwd,txt', '-Fpn'], capture_output=True, text=True, timeout=15)
        if files.returncode not in {0, 1} or files.stderr.strip(): return {'verified': False, 'active': False, 'pids': []}
        identity = prefix.stat(); server = 'server-%x-%x' % (identity.st_dev, identity.st_ino)
        active = set(); inspected = set(); pid = None; root = str(prefix)
        for line in files.stdout.splitlines():
            if line.startswith('p') and line[1:].isdigit(): pid = int(line[1:])
            elif line.startswith('n') and pid is not None:
                inspected.add(pid); name = line[1:]
                if name == root or name.startswith(root + '/') or ('/' + server + '/') in name or name.endswith('/' + server): active.add(pid)
        # lsof status 1 can mean ps itself exited during the snapshot. Accept
        # only omissions proven gone/zombie; never ignore an uninspected live
        # process owned by this effective UID. Root login services are not ours.
        if (pids - inspected) & own_live_processes(): return {'verified': False, 'active': bool(active), 'pids': sorted(active)}
        return {'verified': True, 'active': bool(active), 'pids': sorted(active)}
    except (OSError, ValueError, subprocess.SubprocessError):
        return {'verified': False, 'active': False, 'pids': []}


def storage_watch_spec(entrypoint, config, state):
    return {'Label': 'local.chardonnay.storage.watch',
            'ProgramArguments': ['/bin/bash', str(entrypoint), '--storage', 'daemon', '--config', str(config), '--state-dir', str(state)],
            'RunAtLoad': True, 'KeepAlive': True, 'ThrottleInterval': 15,
            'StandardOutPath': str(Path(state) / 'watch.log'), 'StandardErrorPath': str(Path(state) / 'watch.log')}


class StorageManager:
    """Only copies created here are eligible. No adoption/delete-by-name API."""
    def __init__(self, config, state_dir, activity=None):
        self.config = copy.deepcopy(config)
        self.state = Path(state_dir).expanduser()
        self.activity = activity or prefix_activity

    def _load(self):
        path = self.state / 'ledger.json'
        if not path.exists(): return {'version': 1, 'managed_by': OWNER, 'replicas': []}
        if self.state.is_symlink() or path.is_symlink() or path.stat().st_size > MAX_METADATA: raise ValueError('unsafe_ledger')
        data = json.loads(path.read_text())
        if data.get('version') != 1 or data.get('managed_by') != OWNER or not isinstance(data.get('replicas'), list): raise ValueError('invalid_ledger')
        identifiers = [item.get('replica_id') for item in data['replicas']]
        if any(not isinstance(x, str) or not re.fullmatch(r'[0-9a-f]{32}', x) for x in identifiers) or len(identifiers) != len(set(identifiers)): raise ValueError('invalid_replica_identity')
        return data

    @contextlib.contextmanager
    def _lock(self):
        if self.state.is_symlink(): raise ValueError('symlink_state_directory')
        self.state.mkdir(parents=True, exist_ok=True, mode=0o700)
        path = self.state / 'manager.lock'
        if path.is_symlink(): raise ValueError('symlink_lock')
        with path.open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            yield

    def _save(self, ledger):
        storage_atomic_json(self.state / 'ledger.json', ledger)

    def _checkpoint(self, phase, record):
        # Fault-injection boundary: the phase has already been durably saved.
        pass

    def combined_config(self, ledger=None):
        config = copy.deepcopy(self.config)
        ledger = self._load() if ledger is None else ledger
        config.setdefault('replicas', []).extend(copy.deepcopy(r) for r in ledger['replicas'] if r.get('phase') in {'ready', 'prepared'})
        return config

    def _profile(self, ident):
        choices = [p for p in self.config['prefixes'] if p['id'] == ident]
        if len(choices) != 1: raise ValueError('unknown_or_duplicate_prefix')
        profile = choices[0]; path = Path(profile['path'])
        if path.is_symlink() or not (path / 'drive_c').is_dir(): raise ValueError('prefix_unavailable')
        return profile

    def _quiet(self, profile):
        state = self.activity(profile)
        if state.get('verified') is not True: raise ValueError('prefix_activity_unverified')
        if state.get('active'): raise ValueError('prefix_has_active_processes')

    def _paths(self, record):
        valid_appid(record['appid']); safe_component(record['install_dir'])
        source = self._profile(record['source_prefix_id']); dest = self._profile(record['replica_prefix_id'])
        if source.get('storage_role', 'active') != 'active' or dest.get('storage_role') != 'managed_replica': raise ValueError('ownership_role_changed')
        if str(Path(source['path']).resolve()) != record['source_prefix_path'] or str(Path(dest['path']).resolve()) != record['replica_prefix_path']: raise ValueError('prefix_path_changed')
        if record['source_prefix_path'] == record['replica_prefix_path']: raise ValueError('primary_replica_alias')
        library = Path(record['library'])
        if library not in library_roots(dest): raise ValueError('replica_library_changed')
        apps = library / 'steamapps'; common = apps / 'common'
        if apps.is_symlink() or common.is_symlink() or not common.is_dir(): raise ValueError('unsafe_replica_parent')
        payload = common / record['install_dir']; ident = record['replica_id']
        if not re.fullmatch(r'[0-9a-f]{32}', ident): raise ValueError('invalid_replica_identity')
        return source, dest, payload, apps / ('appmanifest_' + record['appid'] + '.acf'), common / ('.chardonnay-delete-' + ident), apps / ('.chardonnay-delete-' + ident + '.acf')

    def _marker(self, path, record):
        marker = Path(path) / MARKER
        if marker.is_symlink() or marker.stat().st_size > 4096: raise ValueError('unsafe_marker')
        data = json.loads(marker.read_text())
        if any(data.get(key) != record.get(key) for key in ['managed_by', 'replica_id', 'appid', 'token']): raise ValueError('ownership_marker_mismatch')

    def _payload(self, path, record, complete=True):
        path = Path(path)
        if path.is_symlink() or not path.is_dir(): raise ValueError('replica_payload_missing_or_symlink')
        st = path.stat()
        if [st.st_dev, st.st_ino] != [record['device'], record['inode']]: raise ValueError('replica_identity_changed')
        if complete:
            self._marker(path, record)
            current = payload_usage(path)
            if not current['complete'] or current['metadata_fingerprint'] != record['metadata_fingerprint']: raise ValueError('replica_payload_changed')

    def _manifest(self, path, record):
        if path.is_symlink() or not path.is_file() or path.stat().st_size > MAX_METADATA: raise ValueError('replica_manifest_missing_or_symlink')
        if hashlib.sha256(path.read_bytes()).hexdigest() != record['manifest_sha256']: raise ValueError('replica_manifest_changed')

    def _safe_delete(self, path, record, complete=True):
        if not shutil.rmtree.avoids_symlink_attacks: raise ValueError('safe_recursive_delete_unavailable')
        self._payload(path, record, complete=complete)
        shutil.rmtree(path)

    def _source_uninstalled(self, source, record):
        roots = library_roots(source)
        if not roots: raise ValueError('source_library_unavailable')
        if any((root / 'steamapps' / ('appmanifest_' + record['appid'] + '.acf')).exists() for root in roots): raise ValueError('primary_manifest_present')
        if record.get('phase') not in {'quarantined', 'deleting'} or record.get('uninstall_verified') is not True:
            if not uninstall_proven(source, record, record['appid']): raise ValueError('source_uninstall_not_proven')

    def create_replica(self, appid, source_id, dest_id, auto_cleanup=True):
        valid_appid(appid)
        if not shutil.rmtree.avoids_symlink_attacks: raise ValueError('safe_recursive_delete_unavailable')
        with self._lock():
            ledger = self._load(); source = self._profile(source_id); dest = self._profile(dest_id)
            if source.get('storage_role', 'active') != 'active' or dest.get('storage_role') != 'managed_replica': raise ValueError('explicit_managed_destination_required')
            if Path(source['path']).resolve() == Path(dest['path']).resolve(): raise ValueError('primary_replica_alias')
            self._quiet(source); self._quiet(dest)
            audit = inventory(self.config)
            if not audit['complete_scan']: raise ValueError('incomplete_inventory')
            matches = [x for x in audit['installations'] if x['appid'] == appid and x['prefix_id'] == source_id and x['fully_installed']]
            if len(matches) != 1: raise ValueError('one_installed_source_required')
            item = matches[0]; original = Path(item['payload'])
            if (original / MARKER).exists(): raise ValueError('replica_cannot_be_canonical_source')
            library = steam_path(dest).resolve(); apps = library / 'steamapps'; common = apps / 'common'
            if library not in library_roots(dest) or apps.is_symlink() or common.is_symlink() or not common.is_dir(): raise ValueError('unsafe_destination_library')
            target = common / original.name; manifest = apps / ('appmanifest_' + appid + '.acf')
            if target.exists() or target.is_symlink() or manifest.exists() or manifest.is_symlink(): raise ValueError('destination_already_exists_no_adoption')
            log = steam_path(source) / 'logs/content_log.txt'
            if log.is_symlink() or not log.is_file(): raise ValueError('source_log_required')
            log_stat = log.stat(); ident = uuid.uuid4().hex
            stage = common / ('.chardonnay-create-' + ident)
            record = {'managed_by': OWNER, 'replica_id': ident, 'appid': appid, 'token': uuid.uuid4().hex,
                      'source_prefix_id': source_id, 'replica_prefix_id': dest_id,
                      'source_prefix_path': str(Path(source['path']).resolve()), 'replica_prefix_path': str(Path(dest['path']).resolve()),
                      'library': str(library), 'install_dir': original.name, 'phase': 'creating',
                      'source_log_device': log_stat.st_dev, 'source_log_inode': log_stat.st_ino, 'source_log_offset': log_stat.st_size,
                      'manifest_sha256': item['manifest_sha256'], 'cleanup_on_source_uninstall': bool(auto_cleanup), 'created_at': time.time()}
            ledger['replicas'].append(record); self._save(ledger)
            stage.mkdir(mode=0o700)
            storage_atomic_json(stage / MARKER, {k: record[k] for k in ['managed_by', 'replica_id', 'appid', 'token']})
            stage_stat = stage.stat(); record.update(stage_device=stage_stat.st_dev, stage_inode=stage_stat.st_ino); self._save(ledger)
            try:
                # Copy only this game's payload, never users/registry/Steam userdata.
                if sys.platform == 'darwin':
                    subprocess.run(['/bin/cp', '-a', '-c', str(original), str(stage / 'payload')], check=True, capture_output=True, timeout=300)
                else:
                    if shutil.disk_usage(common).free < item['logical_bytes'] + 64 * 1024 * 1024: raise ValueError('insufficient_copy_space')
                    shutil.copytree(original, stage / 'payload', copy_function=shutil.copy2)
                usage = payload_usage(stage / 'payload')
                if not usage['complete']: raise ValueError('copied_payload_incomplete')
                if payload_usage(original)['metadata_fingerprint'] != item['metadata_fingerprint']: raise ValueError('source_changed_during_copy')
                manifest_data = Path(item['manifest']).read_bytes()
                if hashlib.sha256(manifest_data).hexdigest() != record['manifest_sha256']: raise ValueError('source_manifest_changed_during_copy')
                record.update({k: usage[k] for k in ['device', 'inode', 'metadata_fingerprint', 'logical_bytes']})
                storage_atomic_json(stage / 'payload' / MARKER, {k: record[k] for k in ['managed_by', 'replica_id', 'appid', 'token']})
                with (stage / 'manifest.acf').open('xb') as stream:
                    stream.write(manifest_data); stream.flush(); os.fsync(stream.fileno())
                self._quiet(source); self._quiet(dest)
                record['phase'] = 'publishing'; self._save(ledger); self._checkpoint('publishing', record)
                self._finish_creation(record, ledger)
                return {'replica_id': ident, 'appid': appid, 'payload': str(target), 'phase': 'ready', 'auto_cleanup': bool(auto_cleanup)}
            except Exception as error:
                record['last_error'] = type(error).__name__; self._save(ledger)
                raise

    def _abort_creation(self, record, ledger):
        source, dest, payload, manifest, _, _ = self._paths(record)
        self._quiet(dest)
        if payload.exists() or payload.is_symlink() or manifest.exists() or manifest.is_symlink(): raise ValueError('destination_reappeared')
        stage = payload.parent / ('.chardonnay-create-' + record['replica_id'])
        if stage.exists() or stage.is_symlink():
            if not shutil.rmtree.avoids_symlink_attacks or stage.is_symlink(): raise ValueError('unsafe_creation_rollback')
            st = stage.stat()
            if [st.st_dev, st.st_ino] != [record.get('stage_device'), record.get('stage_inode')]: raise ValueError('creation_stage_identity_changed')
            self._marker(stage, record); shutil.rmtree(stage)
        record['phase'] = 'aborted'; record.pop('last_error', None); self._save(ledger)
        return {'replica_id': record['replica_id'], 'phase': 'aborted'}

    def _finish_creation(self, record, ledger):
        source, dest, target, manifest, _, _ = self._paths(record)
        self._quiet(source); self._quiet(dest)
        stage = target.parent / ('.chardonnay-create-' + record['replica_id'])
        if stage.is_symlink() or not stage.is_dir(): raise ValueError('creation_stage_missing')
        self._marker(stage, record)
        if not target.exists() and not target.is_symlink():
            self._payload(stage / 'payload', record)
            (stage / 'payload').rename(target)
        self._payload(target, record)
        if not manifest.exists() and not manifest.is_symlink():
            self._manifest(stage / 'manifest.acf', record)
            os.link(stage / 'manifest.acf', manifest)
        self._manifest(manifest, record)
        record['phase'] = 'ready'; record.pop('last_error', None); self._save(ledger)
        # Only the private publication stage is retired, after checking its marker.
        if not shutil.rmtree.avoids_symlink_attacks: raise ValueError('safe_recursive_delete_unavailable')
        self._marker(stage, record); shutil.rmtree(stage)

    def _cleanup(self, record, ledger):
        if not shutil.rmtree.avoids_symlink_attacks: raise ValueError('safe_recursive_delete_unavailable')
        source, dest, payload, manifest, quarantine, quarantine_manifest = self._paths(record)
        self._quiet(dest); self._source_uninstalled(source, record)
        if record['phase'] in {'ready', 'prepared'}:
            if payload.exists() and quarantine.exists(): raise ValueError('quarantine_collision')
            location = quarantine if quarantine.exists() else payload
            self._payload(location, record)
            self._manifest(quarantine_manifest if quarantine_manifest.exists() else manifest, record)
            record['phase'] = 'prepared'; record['uninstall_verified'] = True; self._save(ledger)
            self._checkpoint('prepared', record)
            if location == payload:
                if quarantine.exists() or quarantine.is_symlink(): raise ValueError('quarantine_collision')
                payload.rename(quarantine)
            if not quarantine_manifest.exists() and not quarantine_manifest.is_symlink(): manifest.rename(quarantine_manifest)
            record['phase'] = 'quarantined'; self._save(ledger); self._checkpoint('quarantined', record)
        self._quiet(dest); self._source_uninstalled(source, record)
        if payload.exists() or payload.is_symlink() or manifest.exists() or manifest.is_symlink(): raise ValueError('destination_reappeared')
        partial = record['phase'] == 'deleting'
        if quarantine.exists() or quarantine.is_symlink(): self._payload(quarantine, record, complete=not partial)
        if quarantine_manifest.exists() or quarantine_manifest.is_symlink(): self._manifest(quarantine_manifest, record)
        if not partial:
            record['phase'] = 'deleting'; self._save(ledger); self._checkpoint('deleting', record)
        if quarantine.exists() or quarantine.is_symlink(): self._safe_delete(quarantine, record, complete=False)
        if quarantine_manifest.exists():
            self._manifest(quarantine_manifest, record); quarantine_manifest.unlink()
        if quarantine.exists() or quarantine_manifest.exists(): raise ValueError('cleanup_not_complete')
        record['phase'] = 'removed'; record['removed_at'] = time.time(); record.pop('last_error', None); self._save(ledger)
        return {'replica_id': record['replica_id'], 'appid': record['appid'], 'logical_bytes_removed': record['logical_bytes']}

    def reconcile(self, apply=False):
        def perform():
            ledger = self._load(); config = self.combined_config(ledger); report = inventory(config)
            result = {'read_only': not apply, 'planned': [], 'removed': [], 'rolled_back': [], 'deferred': [], 'complete_scan': report['complete_scan']}
            for record in ledger['replicas']:
                if record.get('phase') in {'removed', 'aborted'}: continue
                ident = record['replica_id']
                try:
                    if record.get('phase') == 'publishing':
                        if not apply: result['deferred'].append({'replica_id': ident, 'reason': 'creation_recovery_pending'}); continue
                        self._finish_creation(record, ledger); continue
                    if record.get('phase') == 'creating':
                        if apply: result['rolled_back'].append(self._abort_creation(record, ledger)); continue
                        raise ValueError('creation_rollback_pending')
                    if record.get('phase') not in {'ready', 'prepared', 'quarantined', 'deleting'}: raise ValueError('invalid_transaction_phase')
                    if record.get('cleanup_on_source_uninstall') is not True: raise ValueError('keep_on_uninstall_policy')
                    if record['phase'] == 'ready':
                        if not report['complete_scan']: raise ValueError('incomplete_inventory')
                        plan = uninstall_plan(config, report, record['appid'], record['source_prefix_id'])
                        expected = str(Path(record['library']) / 'steamapps/common' / record['install_dir'])
                        if not any(x['payload'] == expected for x in plan['cleanup_candidates']):
                            reason = next((x['reason'] for x in plan['retained'] if x['payload'] == expected), 'replica_not_in_inventory')
                            raise ValueError(reason)
                    result['planned'].append({'replica_id': ident, 'appid': record['appid']})
                    if apply: result['removed'].append(self._cleanup(record, ledger))
                except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
                    result['deferred'].append({'replica_id': ident, 'reason': str(error) if isinstance(error, ValueError) else type(error).__name__})
                    if apply: record['last_error'] = type(error).__name__; self._save(ledger)
            return result
        if not apply: return perform()
        with self._lock(): return perform()

    def watch_cycle(self):
        return self.reconcile(apply=True)
# END MANAGED STORAGE


def _storage_watch_owner(agent, state):
    if agent.is_symlink(): raise ValueError('symlink_watch_job')
    if not agent.exists(): return False
    try:
        data = plistlib.loads(agent.read_bytes()); args = data['ProgramArguments']
        offset = args.index('--state-dir')
        if data.get('Label') != 'local.chardonnay.storage.watch' or args[:1] != ['/bin/bash'] or '--storage' not in args or 'daemon' not in args or Path(args[offset + 1]).resolve() != Path(state).resolve():
            raise ValueError('watch_job_not_owned_by_this_state')
    except (OSError, ValueError, KeyError, IndexError, TypeError, plistlib.InvalidFileException):
        raise ValueError('watch_job_not_owned_by_this_state')
    return True


def configure_storage_watch(entrypoint, config, state, agent_path=None):
    if sys.platform != 'darwin': raise ValueError('watch_install_requires_macos')
    agent = Path(agent_path) if agent_path else Path.home() / 'Library/LaunchAgents/local.chardonnay.storage.watch.plist'
    owned = _storage_watch_owner(agent, state)
    label = 'local.chardonnay.storage.watch'; domain = 'gui/' + str(os.getuid())
    existing = subprocess.run(['/bin/launchctl', 'print', domain + '/' + label], capture_output=True, text=True)
    if existing.returncode == 0 and not owned: raise ValueError('foreign_or_untracked_watch_job_exists')
    if owned: subprocess.run(['/bin/launchctl', 'bootout', domain + '/' + label], capture_output=True)
    state = Path(state); state.mkdir(parents=True, exist_ok=True, mode=0o700)
    agent.parent.mkdir(parents=True, exist_ok=True)
    content = plistlib.dumps(storage_watch_spec(Path(entrypoint).resolve(), Path(config).resolve(), state.resolve()))
    temporary = agent.with_name('.' + agent.name + '-' + uuid.uuid4().hex)
    with temporary.open('xb') as stream: stream.write(content); stream.flush(); os.fsync(stream.fileno())
    temporary.replace(agent)
    subprocess.run(['/bin/launchctl', 'enable', domain + '/' + label], check=True, capture_output=True)
    subprocess.run(['/bin/launchctl', 'bootstrap', domain, str(agent)], check=True, capture_output=True)
    subprocess.run(['/bin/launchctl', 'print', domain + '/' + label], check=True, capture_output=True)
    if agent.read_bytes() != content: raise ValueError('watch_plist_readback_mismatch')
    return {'installed': True, 'label': label, 'agent': str(agent), 'explicitly_managed_replicas_only': True}


def disable_storage_watch(state, agent_path=None):
    if sys.platform != 'darwin': raise ValueError('watch_install_requires_macos')
    agent = Path(agent_path) if agent_path else Path.home() / 'Library/LaunchAgents/local.chardonnay.storage.watch.plist'
    if not _storage_watch_owner(agent, state): raise ValueError('no_owned_watch_job')
    label = 'local.chardonnay.storage.watch'; domain = 'gui/' + str(os.getuid())
    subprocess.run(['/bin/launchctl', 'disable', domain + '/' + label], check=True, capture_output=True)
    subprocess.run(['/bin/launchctl', 'bootout', domain + '/' + label], capture_output=True)
    live = subprocess.run(['/bin/launchctl', 'print', domain + '/' + label], capture_output=True)
    flags = subprocess.run(['/bin/launchctl', 'print-disabled', domain], capture_output=True, text=True, check=True)
    if live.returncode == 0 or not re.search(re.escape(label) + r'"?\s*=>\s*(?:true|disabled)', flags.stdout, re.I): raise ValueError('watch_disable_not_verified')
    return {'disabled': True, 'running': False, 'label': label, 'replicas_and_ledger_retained': True}


def managed_cli(arguments):
    parser = argparse.ArgumentParser(description='Steam storage inventory and explicit managed-replica lifecycle. Existing bottles are never adopted.')
    parser.add_argument('action', choices=['status', 'plan', 'create-replica', 'reconcile', 'watch', 'unwatch', 'daemon'])
    parser.add_argument('appid', nargs='?')
    parser.add_argument('--config', type=Path)
    parser.add_argument('--state-dir', type=Path, default=Path.home() / '.local/share/chardonnay-storage')
    parser.add_argument('--include-prefix', action='append', default=[], type=Path)
    parser.add_argument('--primary-prefix')
    parser.add_argument('--source-prefix')
    parser.add_argument('--replica-prefix')
    parser.add_argument('--keep-on-uninstall', action='store_true', help='Protect a newly created managed copy from automatic removal')
    parser.add_argument('--apply', action='store_true', help='Reconcile only: permanently delete eligible creation-time-owned replicas')
    parser.add_argument('--yes', action='store_true', help='Acknowledge permanent removal of eligible managed replicas')
    parser.add_argument('--once', action='store_true', help='Run one automatic watcher cycle and exit')
    parser.add_argument('--interval', type=int, default=15)
    args = parser.parse_args(arguments)
    if not 5 <= args.interval <= 300: parser.error('interval must be between 5 and 300 seconds')
    if args.apply and (args.action != 'reconcile' or not args.yes): parser.error('permanent reconciliation requires reconcile --apply --yes')
    if args.include_prefix and args.action not in {'status', 'plan'}: parser.error('additional protected audit prefixes are read-only only')
    home = Path.home(); default = home / '.config/chardonnay-storage/config.json'
    config_path = args.config or (default if default.exists() else home / '.config/chardonnay-shortcuts/config.json')
    def load_config():
        if config_path.is_symlink() or config_path.stat().st_size > MAX_METADATA: raise ValueError('unsafe_config')
        return json.loads(config_path.read_text())
    config = load_config()
    for prefix in args.include_prefix:
        path = str(prefix.expanduser().absolute())
        if any(str(Path(p['path']).expanduser().absolute()) == path for p in config['prefixes']): continue
        config['prefixes'].append({'id': 'included-' + hashlib.sha256(path.encode()).hexdigest()[:10], 'path': path, 'storage_role': 'protected'})
    manager = StorageManager(config, args.state_dir)
    if args.action in {'status', 'plan'}:
        combined = manager.combined_config(); report = inventory(combined)
        if args.action == 'plan':
            if args.appid is None: parser.error('plan requires an exact Steam app ID')
            result = uninstall_plan(combined, report, args.appid, args.primary_prefix)
        else:
            if args.appid is not None: parser.error('status does not take an app ID')
            result = report
        fs = os.statvfs(home); result['native_available_bytes'] = fs.f_bavail * fs.f_frsize; result['config_source'] = str(config_path)
        print(json.dumps(result, ensure_ascii=False, indent=2)); return 0 if report['complete_scan'] else 2
    if args.action == 'create-replica':
        if not args.appid or not args.source_prefix or not args.replica_prefix: parser.error('create-replica requires APPID, --source-prefix and --replica-prefix')
        result = manager.create_replica(args.appid, args.source_prefix, args.replica_prefix, auto_cleanup=not args.keep_on_uninstall)
        result['watcher_install_required_for_background_cleanup'] = not args.keep_on_uninstall
    elif args.action == 'reconcile': result = manager.reconcile(apply=args.apply)
    elif args.action == 'watch':
        entrypoint = os.environ.get('STORAGE_ENTRYPOINT')
        if not entrypoint: raise ValueError('entrypoint_required_for_watch')
        result = configure_storage_watch(entrypoint, config_path, args.state_dir)
    elif args.action == 'unwatch': result = disable_storage_watch(args.state_dir)
    else:
        previous = None
        while True:
            manager.config = load_config()
            result = manager.watch_cycle()
            storage_atomic_json(args.state_dir / 'watch-status.json', result)
            encoded = json.dumps(result, ensure_ascii=False, sort_keys=True)
            if args.once or encoded != previous: print(encoded, flush=True)
            if args.once: return 0
            previous = encoded; time.sleep(args.interval)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


def main(arguments):
    return managed_cli(arguments)


if __name__ == '__main__':
    try: sys.exit(main(sys.argv[1:]))
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        print(json.dumps({'read_only': True, 'complete_scan': False, 'error': type(error).__name__}), file=sys.stderr)
        sys.exit(2)
# END STORAGE PYTHON
STORAGE_PY
}

main() {
  local temp_root=""
  local output_dir=""
  local -a config_paths=()
  local config_path

  while IFS= read -r -d '' config_path; do
    config_paths+=("${config_path}")
  done < <(collect_config_paths "$@")

  (( ${#config_paths[@]} > 0 )) || die "No configs selected"

  ensure_sudo_ready
  temp_root="$(mktemp -d /tmp/merlot-apps.XXXXXX)"
  output_dir="${temp_root}/Merlot Apps"
  mkdir -p "${output_dir}"

  trap 'if [[ -n "${temp_root:-}" ]]; then rm -rf "${temp_root}"; fi' EXIT

  for config_path in "${config_paths[@]}"; do
    build_from_config "${config_path}" "${output_dir}"
  done

  log "Installing to ${INSTALL_DIR}"
  sudo rm -rf "${INSTALL_DIR}"
  sudo mkdir -p "${INSTALL_ROOT}"
  sudo cp -R "${output_dir}" "${INSTALL_ROOT}/"

  log "Installed app folder: ${INSTALL_DIR}"
  echo ""
  echo "Launch any app inside '/Applications/Merlot Apps' from Finder, Launchpad, or Spotlight."
  echo ""
  echo "To create per-game launchers in ~/Applications/Merlot Games, run:"
  echo "  bash ${SCRIPT_DIR}/install_merlot.command --games sync"
}

if [[ "${1:-}" == "--storage" ]]; then
  shift
  storage_main "$@"
  exit $?
fi

if [[ "${1:-}" == "--programs" ]]; then
  shift
  programs_main "$@"
  exit $?
fi

if [[ "${1:-}" == "--games" ]]; then
  shift
  games_main "$@"
  exit 0
fi

main "$@"
