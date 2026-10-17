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

# Source-only Wine integration; never downloads/replaces an engine implicitly.
if [[ "${1:-}" == "--mac-shortcuts" ]]; then
  shift
  /usr/bin/python3 - "$SCRIPT_DIR" "$@" <<'MAC_SHORTCUTS_PY'
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile

root=Path(sys.argv[1])
parser=argparse.ArgumentParser(description='Patch matching Wine source with native macOS menu defaults; build/deploy separately')
parser.add_argument('--source',required=True)
parser.add_argument('--test-probe',action='store_true',help='stage diagnostic header; disabled unless explicitly compiled with CHARDONNAY_SHORTCUT_TESTING')
args=parser.parse_args(sys.argv[2:])
try:
    driver=Path(args.source).expanduser().resolve()/'dlls/winemac.drv'
    source=driver/'cocoa_app.m'
    if source.is_symlink() or not source.is_file():raise ValueError('expected_regular_winemac_cocoa_source')
    text=source.read_text()
    include='#include "chardonnay_shortcuts.h"\n\n'
    marker='@implementation WineApplicationController'
    hook='            chardonnayConfigureMacShortcuts(mainMenu, submenu);\n'
    target='            [NSApp setMainMenu:mainMenu];'
    if text.count(marker)!=1 or text.count(target)!=1:raise ValueError('unrecognized_wine_menu_source')
    if include not in text and 'chardonnay_shortcuts.h' in text:raise ValueError('conflicting_shortcut_include')
    if hook not in text and 'chardonnayConfigureMacShortcuts' in text:raise ValueError('conflicting_shortcut_hook')
    replacement=text
    if include not in replacement:replacement=replacement.replace(marker,include+marker,1)
    if hook not in replacement:replacement=replacement.replace(target,hook+target,1)
    header=(root/'app/merlot/WineMacShortcuts.h').read_bytes()
    window=driver/'cocoa_window.m'
    if window.is_symlink() or not window.is_file():raise ValueError('expected_regular_winemac_window_source')
    window_text=window.read_text()
    window_marker='static inline NSUInteger adjusted_modifiers_for_settings(NSUInteger modifiers)'
    event_marker='    - (void) postKeyEvent:(NSEvent *)theEvent\n    {\n'
    edit_include='#include "chardonnay_edit_shortcuts.h"\n\n'
    edit_hook='        theEvent = chardonnayMacEditEvent(theEvent);\n'
    if window_text.count(window_marker)!=1 or window_text.count(event_marker)!=1:raise ValueError('unrecognized_wine_keyboard_source')
    if edit_include not in window_text and 'chardonnay_edit_shortcuts.h' in window_text:raise ValueError('conflicting_edit_include')
    if edit_hook not in window_text and 'chardonnayMacEditEvent' in window_text:raise ValueError('conflicting_edit_hook')
    window_replacement=window_text
    if edit_include not in window_replacement:window_replacement=window_replacement.replace(window_marker,edit_include+window_marker,1)
    if edit_hook not in window_replacement:window_replacement=window_replacement.replace(event_marker,event_marker+edit_hook,1)
    files=[(driver/'chardonnay_shortcuts.h',header),(driver/'chardonnay_edit_shortcuts.h',(root/'app/merlot/WineMacEditShortcuts.h').read_bytes())]
    if args.test_probe:files.append((driver/'WineMacShortcutProbe.h',(root/'tests/fixtures/WineMacShortcutProbe.h').read_bytes()))
    # All validation precedes writes; refuse symlink targets rather than following them.
    for destination,data in files:
        if destination.is_symlink():raise ValueError('refusing_symlink_header')
    backups=[]
    for original,old,new in [(source,text,replacement),(window,window_text,window_replacement)]:
        if new==old:continue
        backup=original.with_name(original.name+'.before-chardonnay-'+hashlib.sha256(old.encode()).hexdigest()[:16])
        if backup.is_symlink() or (backup.exists() and backup.read_text()!=old):raise ValueError('source_backup_conflict')
        if not backup.exists():backups.append((backup,old))
    for backup,old in backups:
        with backup.open('x') as output:output.write(old)
    files.extend([(source,replacement.encode()),(window,window_replacement.encode())])
    changed=[]
    for destination,data in files:
        if destination.exists() and destination.read_bytes()==data:continue
        mode=destination.stat().st_mode&0o777 if destination.exists() else 0o644
        fd,temporary=tempfile.mkstemp(prefix='.chardonnay-',dir=driver)
        try:
            with os.fdopen(fd,'wb') as output:output.write(data)
            os.chmod(temporary,mode);os.replace(temporary,destination)
        finally:
            if os.path.exists(temporary):os.unlink(temporary)
        changed.append(str(destination))
    print(json.dumps({'source':str(source),'changed':changed,'native_shortcuts':['command-q','command-m','command-h','command-w','control-command-f'],'engine_deployed':False,'test_probe_compile_time_only':args.test_probe}))
except (OSError,ValueError) as error:
    print(json.dumps({'error':str(error)}),file=sys.stderr);sys.exit(2)
MAC_SHORTCUTS_PY
  exit $?
fi

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

bottles_main() {
  export BOTTLES_ENTRYPOINT="${BOTTLES_ENTRYPOINT:-$SCRIPT_DIR/install_merlot.command}"
  /usr/bin/python3 - "$@" <<'BOTTLES_PY'
# BEGIN BOTTLES PYTHON
"""Bottle/app manager. Existing prefixes are imported, never cloned or migrated."""
import argparse
import contextlib
import fcntl
import hashlib
import io
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import time
import types
import uuid

BOTTLE_OWNER = 'local.chardonnay.bottles'
ENTRYPOINT = Path(os.environ.get('BOTTLES_ENTRYPOINT', globals().get('__file__', 'install_merlot.command'))).absolute()
DEFAULT_STATE = Path.home()/'Library/Application Support/Chardonnay'
DEFAULT_CONFIG = Path.home()/'.config/chardonnay-shortcuts/config.json'


def bottle_atomic_json(path, data):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True,mode=0o700)
    if path.is_symlink(): raise ValueError('refusing_symlink_metadata')
    temp=path.with_name(path.name+'.'+uuid.uuid4().hex+'.new')
    descriptor=os.open(str(temp),os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    with os.fdopen(descriptor,'w',encoding='utf-8') as output:
        json.dump(data,output,ensure_ascii=False,indent=2);output.write('\n');output.flush();os.fsync(output.fileno())
    temp.replace(path)


def bottle_read_json(path, fallback):
    path=Path(path)
    if not path.exists(): return fallback
    if path.is_symlink() or path.stat().st_size>8*1024*1024: raise ValueError('unsafe_manager_metadata')
    return json.loads(path.read_text(encoding='utf-8'))


_SHARED={}
def bottle_shared(section):
    if section not in _SHARED:
        text=ENTRYPOINT.read_text(encoding='utf-8')
        body=text.split('# BEGIN '+section+' PYTHON\n',1)[1].split('# END '+section+' PYTHON',1)[0]
        module=types.ModuleType('chardonnay_'+section.lower());module.__file__=str(ENTRYPOINT)
        exec(compile(body,str(ENTRYPOINT),'exec'),module.__dict__);_SHARED[section]=module
    return _SHARED[section]


# Hashes and filenames are verified against the matching appwiz.cpl PE before use.
# Keep prerequisite caches out of prefixes/source bundles; Wine installs the
# matching architecture on demand when an actual HTML consumer needs it.
GECKO_PINS={'2.47.4':{
    'x86':'26cecc47706b091908f7f814bddb074c61beb8063318e9efc5a7f789857793d6',
    'x86_64':'e590b7d988a32d6aa4cf1d8aa3aa3d33766fdd4cf4c89c2dcc2095ecb28d066f'}}


def required_gecko_packages(row):
    engine=Path(row['wine']).expanduser().parent.parent
    packages=[]
    for arch,pe_arch in [('x86','i386'),('x86_64','x86_64')]:
        module=engine/'lib/wine'/(pe_arch+'-windows')/'appwiz.cpl'
        if not module.is_file():continue
        if module.stat().st_size>32*1024*1024:raise ValueError('oversized_appwiz_module')
        data=module.read_bytes();matched=None
        for version,pins in GECKO_PINS.items():
            filename='wine-gecko-'+version+'-'+arch+'.msi'
            if filename.encode('utf-16-le') in data and pins[arch].encode('ascii') in data:
                matched={'version':version,'arch':arch,'filename':filename,'sha256':pins[arch],'url':'https://dl.winehq.org/wine/wine-gecko/'+version+'/'+filename};break
        if matched is None:raise ValueError('unrecognized_gecko_requirement_for_bound_engine_'+arch)
        packages.append(matched)
    if not packages:raise ValueError('bound_engine_appwiz_module_unavailable')
    return packages


def download_gecko_package(url,destination):
    curl='/usr/bin/curl' if Path('/usr/bin/curl').is_file() else shutil.which('curl')
    if not curl:raise RuntimeError('curl_required_for_gecko_prerequisite')
    result=subprocess.run([curl,'--fail','--silent','--show-error','--location','--proto','=https','--proto-redir','=https','--connect-timeout','15','--max-time','180','--max-filesize',str(80*1024*1024),'--output',str(destination),url],capture_output=True,text=True,timeout=190)
    if result.returncode:raise RuntimeError('gecko_download_failed_no_package_published')


def ensure_gecko_cache(row,cache_dir=None,downloader=None):
    packages=required_gecko_packages(row)
    cache=Path(cache_dir) if cache_dir is not None else Path.home()/'.cache/wine'
    if cache.is_symlink():raise ValueError('symlink_gecko_cache')
    cache.mkdir(parents=True,exist_ok=True,mode=0o700)
    lockpath=cache/'.chardonnay-gecko.lock'
    if lockpath.is_symlink():raise ValueError('symlink_gecko_lock')
    downloaded=[]
    def digest(path):
        if path.stat().st_size>80*1024*1024:return None
        checksum=hashlib.sha256()
        with path.open('rb') as source:
            for block in iter(lambda:source.read(1024*1024),b''):checksum.update(block)
        return checksum.hexdigest()
    with lockpath.open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX)
        for package in packages:
            target=cache/package['filename']
            if target.is_symlink() or (target.exists() and not target.is_file()):raise ValueError('unsafe_gecko_package_target')
            if target.is_file() and digest(target)==package['sha256']:continue
            temporary=cache/(package['filename']+'.'+uuid.uuid4().hex+'.part')
            try:
                (downloader or download_gecko_package)(package['url'],temporary)
                if temporary.is_symlink() or not temporary.is_file() or digest(temporary)!=package['sha256']:raise RuntimeError('gecko_package_hash_mismatch_no_package_published')
                os.chmod(temporary,0o600)
                if target.exists():target.rename(target.with_name(target.name+'.invalid-'+uuid.uuid4().hex))
                temporary.replace(target);downloaded.append(package['arch'])
            finally:
                if temporary.is_file() and not temporary.is_symlink():temporary.unlink()
    return {'ready':True,'downloaded':downloaded,'packages':[p['filename'] for p in packages],'cache_dir':str(cache),'existing_bottle_modified':False}


# Native runtime inspection and explicit, snapshot-bound process control.
# SPDX-License-Identifier: MIT
import ctypes
import signal


class RuntimeBSDInfo(ctypes.Structure):
    # Darwin sys/proc_info.h struct proc_bsdinfo; validate size and PID at runtime.
    _fields_=[(n,ctypes.c_uint32) for n in ['flags','status','xstatus','pid','ppid','uid','gid','ruid','rgid','svuid','svgid','reserved']]+[('comm',ctypes.c_char*16),('name',ctypes.c_char*32)]+[(n,ctypes.c_uint32) for n in ['nfiles','pgid','jobc','tdev','tpgid']]+[('nice',ctypes.c_int32),('sec',ctypes.c_uint64),('usec',ctypes.c_uint64)]


def runtime_native_identity(pid):
    if sys.platform!='darwin':raise RuntimeError('runtime_controls_require_macos')
    if not isinstance(pid,int) or pid<=1:raise ValueError('invalid_process_id')
    library=ctypes.CDLL('/usr/lib/libproc.dylib',use_errno=True)
    library.proc_pidinfo.argtypes=[ctypes.c_int,ctypes.c_int,ctypes.c_uint64,ctypes.c_void_p,ctypes.c_int]
    library.proc_pidinfo.restype=ctypes.c_int
    library.proc_pidpath.argtypes=[ctypes.c_int,ctypes.c_void_p,ctypes.c_uint32];library.proc_pidpath.restype=ctypes.c_int
    info=RuntimeBSDInfo();size=ctypes.sizeof(info)
    result=library.proc_pidinfo(pid,3,0,ctypes.byref(info),size)
    if not result and ctypes.get_errno()==3:return None  # ESRCH, not permission denial.
    if size!=136 or result!=size or info.pid!=pid:raise RuntimeError('cannot_verify_native_process_identity')
    if info.status==5:return None  # SZOMB; never signal a zombie.
    path=ctypes.create_string_buffer(4096)
    if library.proc_pidpath(pid,path,len(path))<=0:
        # Recheck whether a short-lived process disappeared between the two calls.
        again=RuntimeBSDInfo();result=library.proc_pidinfo(pid,3,0,ctypes.byref(again),size)
        if not result and ctypes.get_errno()==3:return None
        raise RuntimeError('cannot_read_native_process_path')
    return {'pid':pid,'birth':[int(info.sec),int(info.usec)],'uid':int(info.uid),'native_path':os.fsdecode(path.value)}


def runtime_is_wine(record):
    return Path(record['native_path']).name.casefold() in {'wine','wine64','wine-preloader','wine64-preloader','wineserver'}


def runtime_native_candidates():
    result=subprocess.run(['/bin/ps','-axo','pid=,stat=,uid=,comm='],capture_output=True,text=True,timeout=10,check=True)
    found={};warnings=[]
    for line in result.stdout.splitlines():
        parts=line.split(None,3)
        if len(parts)!=4 or not parts[0].isdigit() or not parts[2].isdigit():continue
        pid=int(parts[0])
        if pid<=1 or int(parts[2])!=os.getuid() or 'Z' in parts[1]:continue
        try:record=runtime_native_identity(pid)
        except (OSError,RuntimeError):
            if re.search(r'(?:\.exe$|wine|wineserver)',parts[3],re.I):warnings.append('uninspectable_wine_candidate')
            continue
        if record and record['uid']==os.getuid() and runtime_is_wine(record):
            # No arguments, account names, environments or window titles in UI records.
            record['name']=re.split(r'[/\\]',parts[3])[-1][:180]
            found[pid]=record
    return found,warnings


def runtime_same_identity(a,b):
    return bool(a and b and all(a.get(key)==b.get(key) for key in ['pid','birth','uid','native_path']))


def runtime_native_snapshot():
    if sys.platform!='darwin':raise RuntimeError('runtime_controls_require_macos')
    candidates,warnings=runtime_native_candidates()
    if len(candidates)>512:raise RuntimeError('too_many_wine_processes_for_safe_inspection')
    if not candidates:return {'processes':[],'complete':not warnings,'warnings':warnings}
    result=subprocess.run(['/usr/sbin/lsof','-nP','-a','-p',','.join(str(pid) for pid in sorted(candidates)),'-d','cwd,txt','-F0pn'],capture_output=True,timeout=15)
    if result.returncode not in {0,1} or result.stderr.strip():warnings.append('runtime_file_inspection_failed')
    if len(result.stdout)>32*1024*1024:raise RuntimeError('runtime_inspection_exceeds_bound')
    pid=None;files={}
    for token in result.stdout.split(b'\0'):
        token=token.lstrip(b'\n')
        if token.startswith(b'p') and token[1:].isdigit():pid=int(token[1:]);files.setdefault(pid,[])
        elif token.startswith(b'n') and pid in candidates:files[pid].append(os.fsdecode(token[1:]))
    after,new_warnings=runtime_native_candidates();warnings+=new_warnings
    if set(after)-set(candidates):warnings.append('runtime_changed_during_inspection')
    records=[]
    for pid,record in candidates.items():
        current=after.get(pid)
        if not current:continue
        if not runtime_same_identity(record,current):warnings.append('process_identity_changed');continue
        if not files.get(pid):warnings.append('runtime_process_files_unavailable');continue
        records.append({**record,'files':files[pid]})
    return {'processes':records,'complete':not warnings,'warnings':sorted(set(warnings))}


class BottleRuntime:
    """Manual, consent-bound signals. Never probes or starts Wine for inspection."""
    ACTIONS={'terminate','force-process','quit-all','force-all','restart','force-restart'}
    def __init__(self,manager,inspector=None,identity=None,signaller=None,clock=None,sleeper=None):
        self.manager=manager;self.inspector=inspector or runtime_native_snapshot
        self.identity=identity or runtime_native_identity;self.signaller=signaller or os.kill
        self.clock=clock or time.time;self.sleeper=sleeper or time.sleep

    @staticmethod
    def binding(row):
        root=Path(row['path']).expanduser().resolve(strict=True);st=root.stat()
        if not root.is_dir() or any(ord(c)<32 for c in str(root)):raise ValueError('unsafe_runtime_prefix')
        wine=Path(row['wine']).expanduser().resolve(strict=True);engine=wine.stat()
        return {'prefix':str(root),'device':st.st_dev,'inode':st.st_ino,'wine':str(wine),'wine_identity':[engine.st_dev,engine.st_ino,engine.st_size,engine.st_mtime_ns],'engine_id':row['engine_id']}

    def inspect(self,row):
        binding=self.binding(row);namespace='server-%x-%x'%(binding['device'],binding['inode'])
        raw=self.inspector();complete=bool(raw.get('complete'));warnings=list(raw.get('warnings',[]));processes=[]
        pattern=re.compile(r'^/(?:private/)?tmp/\.wine-'+str(os.getuid())+r'/(server-[0-9a-f]+-[0-9a-f]+)(?:/|$)')
        for record in raw['processes']:
            if record.get('uid')!=os.getuid() or not runtime_is_wine(record):continue
            spaces={match.group(1) for path in record.get('files',[]) for match in [pattern.match(path)] if match}
            if not spaces:
                complete=False;warnings.append('wine_process_without_proven_prefix');continue
            if namespace not in spaces:continue
            if len(spaces)!=1:
                complete=False;warnings.append('ambiguous_prefix_ownership');continue
            value={key:record[key] for key in ['pid','birth','uid','native_path','name']}
            value['server']=Path(value['native_path']).name=='wineserver';processes.append(value)
        processes.sort(key=lambda p:p['pid'])
        return {'bottle_id':row['id'],'binding':binding,'processes':processes,'complete':complete,'warnings':sorted(set(warnings)),'inspection_starts_wine':False}

    def token_path(self,token):
        if not isinstance(token,str) or not re.fullmatch(r'[0-9a-f]{32}',token):raise ValueError('invalid_runtime_snapshot')
        return self.manager.state/'runtime'/('snapshot-'+token+'.json')

    def snapshot(self,ident):
        row=self.manager.get(ident);value=self.inspect(row);token=uuid.uuid4().hex
        value.update({'token':token,'created_at':self.clock()})
        parent=self.manager.state/'runtime'
        if parent.is_symlink():raise ValueError('symlink_runtime_state')
        parent.mkdir(parents=True,exist_ok=True,mode=0o700)
        # Retain only a bounded number of recent private, unconsumed confirmations.
        for path in parent.glob('snapshot-*.json'):
            if path.is_symlink():raise ValueError('symlink_runtime_snapshot')
            if path.is_file() and self.clock()-path.stat().st_mtime>300:path.unlink()
        if len(list(parent.glob('snapshot-*.json')))>=128:raise RuntimeError('too_many_pending_runtime_snapshots')
        bottle_atomic_json(self.token_path(token),value)
        return value

    def act(self,ident,token,action,pid=None,app_id=None,confirmed=False):
        if not confirmed:raise ValueError('explicit_confirmation_required_unsaved_work_may_be_lost')
        if action not in self.ACTIONS:raise ValueError('unknown_runtime_action')
        # Coordinates manager runtime actions, launches and installers. This is not
        # a lock over independent Steam/EA UI activity; the warning covers that.
        with self.manager.runtime_lock():
            row=self.manager.get(ident);saved=bottle_read_json(self.token_path(token),None)
            if not saved or saved.get('bottle_id')!=ident:raise ValueError('unknown_or_consumed_runtime_snapshot')
            age=self.clock()-saved['created_at']
            if age<0 or age>180:raise ValueError('runtime_snapshot_expired_refresh_required')
            if saved['binding']!=self.binding(row):raise ValueError('bottle_binding_changed_refresh_required')
            current=self.inspect(row);whole=action in {'quit-all','force-all','restart','force-restart'}
            if whole:
                if not saved['complete'] or not current['complete']:raise ValueError('incomplete_runtime_inspection_no_bottle_wide_action')
                if current['processes']!=saved['processes']:raise ValueError('runtime_changed_refresh_and_confirm_again')
                targets=current['processes']
            else:
                if not isinstance(pid,int) or pid<=1:raise ValueError('invalid_process_id')
                old=next((p for p in saved['processes'] if p['pid']==pid),None)
                fresh=next((p for p in current['processes'] if p['pid']==pid),None)
                if not old or old!=fresh:raise ValueError('selected_process_changed_refresh_required')
                if fresh['server']:raise ValueError('server_requires_explicit_bottle_wide_action')
                targets=[fresh]
            if action in {'restart','force-restart'}:
                item=next((a for a in self.manager.apps(row) if a['id']==app_id),None)
                if item is None or item.get('kind') not in {'store','application','steam_game'}:raise ValueError('registered_application_required_for_restart')
                if item.get('source') and any(word in item.get('name','').casefold() for word in ['uninstall','installer','setup','repair']):raise ValueError('installer_shortcut_cannot_be_replayed_as_restart')
            # Preflight EVERY target before the first signal; repeat exact native
            # birth identity immediately before each individual action as well.
            for target in targets:
                if not runtime_same_identity(target,self.identity(target['pid'])):raise ValueError('process_identity_changed_no_action')
            self.token_path(token).unlink()  # consume consent even when later work fails
            sig=signal.SIGKILL if action in {'force-process','force-all','force-restart'} else signal.SIGTERM
            sent=[];changed=[]
            # Clients before server. Native TERM is explicit termination, NOT a
            # guarantee of a Windows save-dialog/WM_CLOSE handshake.
            for target in sorted(targets,key=lambda p:p['server']):
                fresh=self.identity(target['pid'])
                if fresh is None:continue
                if not runtime_same_identity(target,fresh):changed.append(target['pid']);continue
                try:self.signaller(target['pid'],sig);sent.append(target['pid'])
                except ProcessLookupError:pass
            attempts=0
            while True:
                remaining=[p['pid'] for p in targets if runtime_same_identity(p,self.identity(p['pid']))]
                if not remaining or attempts>=25:break
                self.sleeper(0.2);attempts+=1
            post=self.inspect(row) if whole else None
            stopped=not remaining and not changed and (not whole or (post['complete'] and not post['processes']))
            result={'bottle_id':ident,'action':action,'signalled':sent,'remaining':remaining,'identity_changed':changed,'stopped':stopped,'force_required':not stopped and sig!=signal.SIGKILL,'launch_dispatched':False,'automatic_escalation':False}
            if action in {'restart','force-restart'} and stopped:
                # Reuse the existing configured launch route; never persist a
                # list of old commands or replay an install/uninstall operation.
                if self.binding(self.manager.get(ident))!=saved['binding']:raise ValueError('binding_changed_after_stop_no_relaunch')
                result.update(self.manager.launch(ident,app_id,_runtime_locked=True))
            bottle_atomic_json(self.manager.state/'runtime'/'last-action.json',{**result,'checked_at':self.clock()})
            return result


class BottleManager:
    def __init__(self, config_path=DEFAULT_CONFIG, state_dir=DEFAULT_STATE, runner=None):
        self.config_path=Path(config_path).expanduser();self.state=Path(state_dir).expanduser()
        self.runner=runner
        if self.state.is_symlink(): raise ValueError('symlink_manager_state')

    def source_config(self):
        config=bottle_read_json(self.config_path,{'version':1,'prefixes':[]})
        if not isinstance(config,dict) or not isinstance(config.get('prefixes'),list): raise ValueError('invalid_shortcut_config')
        return config

    def registry(self):
        value=bottle_read_json(self.state/'bottles.json',{'version':1,'managed_by':BOTTLE_OWNER,'bottles':[]})
        if value.get('version')!=1 or value.get('managed_by')!=BOTTLE_OWNER or not isinstance(value.get('bottles'),list): raise ValueError('invalid_bottle_registry')
        return value

    @contextlib.contextmanager
    def lock(self):
        self.state.mkdir(parents=True,exist_ok=True,mode=0o700)
        path=self.state/'manager.lock'
        if path.is_symlink(): raise ValueError('symlink_manager_lock')
        with path.open('a') as lock:
            fcntl.flock(lock,fcntl.LOCK_EX);yield

    @contextlib.contextmanager
    def runtime_lock(self):
        self.state.mkdir(parents=True,exist_ok=True,mode=0o700)
        path=self.state/'runtime-actions.lock'
        if path.is_symlink():raise ValueError('symlink_runtime_lock')
        with path.open('a') as lock:
            try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
            except BlockingIOError:raise RuntimeError('another_manager_runtime_operation_is_running')
            yield

    @staticmethod
    def engine_for(profile):
        wine=str(Path(profile['wine']).expanduser())
        environment={str(k):str(v) for k,v in profile.get('environment',{}).items()}
        ident='engine-'+hashlib.sha256(json.dumps([wine,environment],sort_keys=True).encode()).hexdigest()[:12]
        backend='D3DMetal' if environment.get('CX_ACTIVE_GRAPHICS_BACKEND')=='d3dmetal' else 'DXMT' if environment.get('DXMT_VERSION') else 'Configured Wine'
        version=environment.get('WINE_VERSION','')
        return {'id':ident,'name':('Wine '+version+' · '+backend).strip() if version else backend,'wine':wine,'environment':environment,'available':os.access(wine,os.X_OK)}

    def bindings(self):
        registry=self.registry();owned={str(Path(b['path']).resolve()):b for b in registry['bottles']}
        bottles=[];engines={};seen=set()
        for profile in self.source_config()['prefixes']:
            if not all(isinstance(profile.get(k),str) and profile[k] for k in ['id','path','wine']): raise ValueError('invalid_prefix_binding')
            key=str(Path(profile['path']).expanduser().resolve())
            if key in seen or key in owned: continue
            seen.add(key);engine=self.engine_for(profile);engines.setdefault(engine['id'],engine)
            ident='existing-'+hashlib.sha256(key.encode()).hexdigest()[:12]
            bottles.append({**profile,'id':ident,'source_profile_id':profile['id'],'engine_id':engine['id'],'external':True,'phase':'ready' if (Path(key)/'drive_c').is_dir() else 'unavailable','name':profile.get('name',profile['id'])})
        for stored in registry['bottles']:
            engine=self.engine_for(stored);engines.setdefault(engine['id'],engine)
            bottles.append({**stored,'external':False})
        return bottles,list(engines.values())

    def get(self, ident):
        rows,_=self.bindings()
        row=next((x for x in rows if x['id']==ident),None)
        if row is None: raise ValueError('unknown_bottle')
        if row.get('phase')!='ready': raise ValueError('bottle_not_ready')
        if not os.access(row['wine'],os.X_OK): raise ValueError('bound_engine_unavailable')
        return row

    @staticmethod
    def environment(row):
        # Do not inherit another launcher's engine, prefix, app ID or LS identity.
        env={key:os.environ[key] for key in ['HOME','USER','LOGNAME','TMPDIR','LANG','LC_ALL','DEVELOPER_DIR'] if key in os.environ}
        env['PATH']='/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin'
        env.update({str(k):str(v) for k,v in row.get('environment',{}).items()})
        for key in ['WINELOADER','WINESERVER','SteamAppId','SteamGameId','__CFBundleIdentifier','RESOURCEPATH']:env.pop(key,None)
        env.update({'WINEPREFIX':row['path'],'WINEDEBUG':'-all','WINEDLLPATH':''})
        return env

    def execute(self,row,command,wait=True,cwd=None):
        directory=self.state/'logs';directory.mkdir(parents=True,exist_ok=True,mode=0o700)
        logfile=directory/(row['id']+'.log')
        if logfile.is_symlink(): raise ValueError('symlink_operation_log')
        fd=os.open(str(logfile),os.O_WRONLY|os.O_APPEND|os.O_CREAT,0o600)
        with os.fdopen(fd,'ab') as output:
            kwargs={'env':self.environment(row),'cwd':str(cwd or row['path']),'stdin':subprocess.DEVNULL,'stdout':output,'stderr':subprocess.STDOUT}
            if self.runner: return self.runner(command,**kwargs)
            if wait:return subprocess.run(command,**kwargs)
            return subprocess.Popen(command,start_new_session=True,**kwargs)

    def create(self,name,engine_id):
        if not isinstance(name,str) or not name.strip() or len(name)>120 or any(ord(c)<32 for c in name):raise ValueError('invalid_bottle_name')
        with self.lock():
            _,engines=self.bindings();engine=next((e for e in engines if e['id']==engine_id and e['available']),None)
            if engine is None:raise ValueError('unknown_or_unavailable_engine')
            ident=uuid.uuid4().hex;parent=self.state/'bottles';parent.mkdir(exist_ok=True,mode=0o700)
            if parent.is_symlink():raise ValueError('symlink_bottle_root')
            prefix=parent/ident;prefix.mkdir(mode=0o700)
            row={'id':ident,'name':name.strip(),'path':str(prefix),'wine':engine['wine'],'environment':engine['environment'],'engine_id':engine_id,'phase':'creating','managed_by':BOTTLE_OWNER,'source_profile_id':'chardonnay-'+ident,'created_at':int(time.time())}
            bottle_atomic_json(prefix/'.chardonnay-bottle.json',{'managed_by':BOTTLE_OWNER,'id':ident})
            ledger=self.registry();ledger['bottles'].append(row);bottle_atomic_json(self.state/'bottles.json',ledger)
        try:
            result=self.execute(row,[row['wine'],'wineboot','--init'])
            if result.returncode or not (prefix/'drive_c').is_dir():raise RuntimeError('wine_initialization_failed')
            helper=Path(os.environ.get('PROGRAMS_HELPER',str(Path.home()/'.cache/chardonnay-shortcuts/ShortcutInfo.exe')))
            if helper.is_file():
                result=self.execute(row,[row['wine'],str(helper),'--setup-desktop'])
                if result.returncode:raise RuntimeError('private_desktop_setup_failed')
            elif self.runner is None:raise RuntimeError('private_desktop_helper_required_before_installing_apps')
            # Only the new EMPTY prefix is configured. Existing sessions are untouched.
            result=self.execute(row,[row['wine'],'reg','add',r'HKCU\Software\Wine','/v','Version','/d','win10','/f'])
            if result.returncode:raise RuntimeError('windows_version_setup_failed')
            with self.lock():
                config=self.source_config();profile={k:row[k] for k in ['name','path','wine','environment']};profile['id']=row['source_profile_id']
                if not any(p.get('path')==row['path'] for p in config['prefixes']):config['prefixes'].append(profile);bottle_atomic_json(self.config_path,config)
                ledger=self.registry();stored=next(b for b in ledger['bottles'] if b['id']==ident);stored['phase']='ready';row['phase']='ready';bottle_atomic_json(self.state/'bottles.json',ledger)
            return row
        except Exception:
            with self.lock():
                ledger=self.registry();next(b for b in ledger['bottles'] if b['id']==ident)['phase']='failed';bottle_atomic_json(self.state/'bottles.json',ledger)
            raise

    def links(self,row,inspect=False):
        shared=bottle_shared('PROGRAMS');profile={**row,'id':row.get('source_profile_id',row['id'])}
        cache_dir=self.state/'shortcut-cache';cache=shared.Importer({'prefixes':[profile]},cache_dir)
        old=bottle_read_json(Path.home()/'.cache/chardonnay-shortcuts/manifest.json',{'cache':{}})
        cache.manifest['cache']={**old.get('cache',{}),**cache.manifest.get('cache',{})}
        def inspector(path,binding):
            if not inspect:raise RuntimeError('uncached_link_requires_explicit_refresh')
            return shared.inspect_link(path,binding)
        cache.inspect=inspector
        try:
            with contextlib.redirect_stdout(io.StringIO()):items=cache.scan()
        except (OSError,ValueError,RuntimeError):return []
        self.last_scan_complete=cache.complete
        # This only persists metadata, never generates or deletes Desktop apps.
        bottle_atomic_json(cache_dir/'manifest.json',cache.manifest)
        result=[]
        for item in items.values():
            target=item['metadata'].get('target','')
            if target.lower().replace('\\','/').endswith(('/steam.exe','/ealauncher.exe','/eadesktop.exe')) or target.startswith('steam://'):continue
            if not target.lower().endswith(('.exe','.com','.cmd','.bat')):continue
            result.append({'id':'link-'+item['id'],'name':item['name'],'kind':'application','source':item['source'],'metadata':item['metadata']})
        return result

    def apps(self,row,inspect=False):
        if row.get('phase')!='ready':return []
        root=Path(row['path']);apps=[]
        steam=root/'drive_c/Program Files (x86)/Steam/steam.exe'
        if steam.is_file():
            apps.append({'id':'steam','name':'Steam','kind':'store','target':str(steam)})
            storage=bottle_shared('STORAGE')
            try:
                for library in storage.library_roots(row):
                    for manifest in sorted((library/'steamapps').glob('appmanifest_*.acf')):
                        data=storage.read_vdf(manifest)['AppState'];appid=storage.valid_appid(data['appid'])
                        if appid=='228980':continue  # shared runtime, not a playable application
                        if int(data.get('StateFlags','0')) & 4:apps.append({'id':'steam-'+appid,'name':data.get('name',appid),'kind':'steam_game','appid':appid})
            except (OSError,ValueError,KeyError,TypeError):pass
        ea=root/'drive_c/Program Files/Electronic Arts/EA Desktop'
        if list(ea.glob('*/EA Desktop/EADesktop.exe')) or (ea/'EA Desktop/EADesktop.exe').is_file():apps.append({'id':'ea','name':'EA','kind':'store'})
        apps+=self.links(row,inspect)
        return apps

    def status(self):
        bottles,engines=self.bindings()
        return {'version':1,'bottles':[{**b,'apps':self.apps(b)} for b in bottles],'engines':engines,'state_dir':str(self.state),'engine_distribution_included':False}

    def install_file(self,ident,path,quiet=False):
        with self.runtime_lock():return self._install_file(ident,path,quiet)

    def _install_file(self,ident,path,quiet=False):
        row=self.get(ident);path=Path(path).expanduser().absolute()
        if not path.is_file() or path.suffix.lower() not in {'.exe','.msi'}:raise ValueError('choose_an_existing_exe_or_msi')
        if self.runner is None:ensure_gecko_cache(row)
        if path.suffix.lower()=='.msi':
            command=[row['wine'],'msiexec','/i','Z:'+str(path).replace('/','\\')]
            if quiet:command+=['/qn','/norestart']
        else:command=[row['wine'],str(path)]
        result=self.execute(row,command,cwd=path.parent)
        if result.returncode not in {0,3010}:raise RuntimeError('installer_exited_'+str(result.returncode)+'_see_private_bottle_log')
        if self.runner is None:
            for attempt in range(5):
                self.links(row,inspect=True)
                if getattr(self,'last_scan_complete',False):break
                if attempt<4:time.sleep(0.3)
        return {'bottle_id':ident,'installer_process_finished':True,'exit_code':result.returncode,'reboot_required':result.returncode==3010}

    def ea_target(self,row):
        root=Path(row['path']).resolve();base=root/'drive_c/Program Files/Electronic Arts/EA Desktop'
        candidates=list(base.glob('*/EA Desktop/EADesktop.exe'))
        canonical=base/'EA Desktop/EADesktop.exe'
        if canonical.is_file():candidates.append(canonical)
        if not candidates:raise ValueError('ea_client_not_installed')
        # Reuse the executable actually mapped by this prefix's authenticated EA.
        if sys.platform=='darwin':
            ps=subprocess.run(['/bin/ps','-axo','pid=,comm='],capture_output=True,text=True,timeout=10,check=True)
            for line in ps.stdout.splitlines():
                fields=line.strip().split(None,1)
                if len(fields)!=2 or not fields[0].isdigit() or not fields[1].lower().endswith('eadesktop.exe'):continue
                files=subprocess.run(['/usr/sbin/lsof','-nP','-a','-p',fields[0],'-d','cwd,txt','-Fn'],capture_output=True,text=True,timeout=10)
                names={line[1:] for line in files.stdout.splitlines() if line.startswith('n')}
                for candidate in candidates:
                    if str(candidate) in names:return candidate
        if canonical.is_file():return canonical
        def version(path):return tuple(int(x) for x in re.findall(r'\d+',path.parent.parent.name))
        return max(candidates,key=version)

    def launch(self,ident,app_id,_runtime_locked=False):
        if _runtime_locked:return self._launch(ident,app_id)
        with self.runtime_lock():return self._launch(ident,app_id)

    def _launch(self,ident,app_id):
        row=self.get(ident);apps=self.apps(row);item=next((a for a in apps if a['id']==app_id),None)
        if item is None:raise ValueError('application_not_found')
        cwd=Path(row['path']);launch_row=dict(row)
        if app_id=='steam' or item['kind']=='steam_game':
            if row.get('role')=='merlot':
                launch_row['environment']=dict(row.get('environment',{}))
                if item['kind']=='steam_game':launch_row['environment']['STEAM_GAME_ID']=item['appid']
                command=['/bin/bash',str(Path(row.get('repo',str(Path.home()/'macos-wine-steam')))/'run.command')]
            else:
                steam=Path(row['path'])/'drive_c/Program Files (x86)/Steam/steam.exe'
                command=[row['wine'],str(steam),'-noverifyfiles','-no-cef-sandbox','-cef-single-process']
                if item['kind']=='steam_game':command+=['-applaunch',item['appid']]
        elif app_id=='ea':command=[row['wine'],str(self.ea_target(row)),'--in-process-gpu','--no-sandbox']
        else:
            source=Path(item['source'])
            if not source.is_file():raise ValueError('shortcut_source_unavailable')
            command=[row['wine'],'start','/unix',str(source)]
            proposed=bottle_shared('PROGRAMS').host_path(item['metadata'].get('working_dir',''),row)
            if proposed and proposed.is_dir():cwd=proposed
        result=self.execute(launch_row,command,wait=False,cwd=cwd)
        return {'launch_dispatched':True,'bottle_id':ident,'app_id':app_id,'pid':getattr(result,'pid',None)}

    def uninstaller(self,ident):
        with self.runtime_lock():return self._uninstaller(ident)

    def _uninstaller(self,ident):
        row=self.get(ident)
        if self.runner is None:ensure_gecko_cache(row)
        self.execute(row,[row['wine'],'uninstaller'],wait=False)
        return {'uninstaller_dispatched':True}


def bottle_install_manager(destination):
    if sys.platform!='darwin':raise RuntimeError('native_manager_requires_macos')
    source=ENTRYPOINT.parent/'app/merlot/ChardonnayApp.m';destination=Path(destination).expanduser().absolute()
    if destination.suffix!='.app' or destination.exists():raise ValueError('choose_a_new_app_destination')
    if not source.is_file():raise ValueError('native_manager_source_missing')
    destination.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='chardonnay-build-',dir=str(destination.parent)) as temporary:
        staged=Path(temporary)/destination.name;mac=staged/'Contents/MacOS';resources=staged/'Contents/Resources';mac.mkdir(parents=True);resources.mkdir()
        env=dict(os.environ);env['DEVELOPER_DIR']='/Applications/Xcode.app/Contents/Developer'
        subprocess.run(['/usr/bin/clang','-fobjc-arc','-Wall','-Wextra','-Werror','-framework','Cocoa','-framework','CoreGraphics','-framework','ScreenCaptureKit',str(source),'-o',str(mac/'Chardonnay')],env=env,check=True,capture_output=True,text=True)
        icon=ENTRYPOINT.parent/'app/merlot/AppIcon.icns'
        if icon.is_file():shutil.copy2(icon,resources/'AppIcon.icns')
        info={'CFBundleIdentifier':'local.chardonnay.manager','CFBundleName':'Chardonnay','CFBundleDisplayName':'Chardonnay','CFBundleExecutable':'Chardonnay','CFBundlePackageType':'APPL','CFBundleShortVersionString':'0.1.1','CFBundleVersion':'2','NSHighResolutionCapable':True,'LSMinimumSystemVersion':'14.0','ChardonnayEntrypoint':str(ENTRYPOINT)}
        if icon.is_file():info['CFBundleIconFile']='AppIcon.icns'
        (staged/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
        subprocess.run(['/usr/bin/codesign','--force','--sign','-','--identifier','local.chardonnay.manager',str(staged)],check=True,capture_output=True,text=True)
        subprocess.run(['/usr/bin/codesign','--verify','--strict',str(staged)],check=True,capture_output=True,text=True)
        staged.rename(destination)
    return {'app':str(destination),'signature_verified':True,'development_engine_bindings':True}


def bottles_cli(arguments):
    parser=argparse.ArgumentParser(description='Chardonnay bottle/app manager; no implicit prefix copies or migrations')
    parser.add_argument('action',choices=['status','create','install-file','launch','uninstaller','ensure-gecko','install-manager','processes','runtime-action'])
    parser.add_argument('--config',default=str(DEFAULT_CONFIG));parser.add_argument('--state-dir',default=str(DEFAULT_STATE))
    parser.add_argument('--name');parser.add_argument('--engine');parser.add_argument('--bottle');parser.add_argument('--file');parser.add_argument('--app')
    parser.add_argument('--quiet',action='store_true');parser.add_argument('--destination',default=str(Path.home()/'Applications/Chardonnay.app'))
    parser.add_argument('--snapshot');parser.add_argument('--operation',choices=sorted(BottleRuntime.ACTIONS));parser.add_argument('--pid',type=int);parser.add_argument('--yes',action='store_true',help='explicit consent: unsaved work or installer state may be lost')
    args=parser.parse_args(arguments);manager=BottleManager(args.config,args.state_dir)
    if args.action=='status':result=manager.status()
    elif args.action=='create':result=manager.create(args.name,args.engine)
    elif args.action=='install-file':result=manager.install_file(args.bottle,args.file,quiet=args.quiet)
    elif args.action=='launch':result=manager.launch(args.bottle,args.app)
    elif args.action=='uninstaller':result=manager.uninstaller(args.bottle)
    elif args.action=='ensure-gecko':result=ensure_gecko_cache(manager.get(args.bottle))
    elif args.action=='processes':result=BottleRuntime(manager).snapshot(args.bottle)
    elif args.action=='runtime-action':result=BottleRuntime(manager).act(args.bottle,args.snapshot,args.operation,pid=args.pid,app_id=args.app,confirmed=args.yes)
    else:result=bottle_install_manager(args.destination)
    print(json.dumps(result,ensure_ascii=False));return 0


if __name__=='__main__':
    try:sys.exit(bottles_cli(sys.argv[1:]))
    except (OSError,ValueError,KeyError,TypeError,RuntimeError,subprocess.SubprocessError) as error:
        print(json.dumps({'error':str(error) if isinstance(error,(ValueError,RuntimeError)) else type(error).__name__}),file=sys.stderr);sys.exit(2)
# END BOTTLES PYTHON
BOTTLES_PY
}

if [[ "${1:-}" == "--bottles" ]]; then
  shift
  bottles_main "$@"
  exit $?
fi

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
