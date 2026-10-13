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

if [[ "${1:-}" == "--games" ]]; then
  shift
  games_main "$@"
  exit 0
fi

main "$@"
