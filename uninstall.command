#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

WINE_VERSION="${WINE_VERSION:-11.18}"
WINE_ROOT="${WINE_ROOT:-$HOME/wine-${WINE_VERSION}}"
WINEPREFIX="${WINEPREFIX:-$HOME/.wine-steam-11}"
DXMT_ROOT="${DXMT_ROOT:-$HOME/DXMT}"
STEAM_SETUP="${STEAM_SETUP:-/tmp/SteamSetup.exe}"
WINEPREFIX_ALIAS_NAME="${WINEPREFIX_ALIAS_NAME:-WINEPREFIX}"
MERLOT_APPS_DIR_NAME="Merlot Apps"
SYSTEM_APPLICATIONS_DIR="/Applications"
# Cache for the compiled steamwebhelper CEF wrapper (see wrapper/README.md).
MERLOT_DATA_DIR="${MERLOT_DATA_DIR:-$HOME/.merlot}"
TOTAL_STEPS=7
CURRENT_STEP=0

log() {
  printf "\n==> %s\n" "$1"
}

die() {
  printf "Error: %s\n" "$1" >&2
  exit 1
}

say()  { printf '\033[1;32m[uninstall]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[uninstall]\033[0m %s\n' "$*"; }

ensure_sudo_ready() {
  log "Preparing sudo session (needed to remove /Applications/Merlot Apps)"
  sudo -v
}

confirm() {
  local prompt="$1"
  local reply=""
  read -r -p "${prompt} [y/N]: " reply
  [[ "${reply}" == "y" || "${reply}" == "Y" ]]
}

# Full mode: --yes skips every confirmation (except the sudo password).
FULL_AUTOYES=0

ask() {
  if [[ "${FULL_AUTOYES}" == "1" ]]; then return 0; fi
  local reply=""
  printf '\033[1;33m[uninstall]\033[0m %s [y/N] ' "$1"
  read -r reply
  case "$reply" in y|Y|yes) return 0 ;; *) return 1 ;; esac
}

step_prefix() {
  printf "[%d/%d]" "${CURRENT_STEP}" "${TOTAL_STEPS}"
}

remove_file() {
  local path="$1"
  local label="$2"
  CURRENT_STEP=$((CURRENT_STEP + 1))

  if [[ -f "${path}" ]]; then
    if confirm "$(step_prefix) Delete ${label}: ${path}?"; then
      rm -f "${path}"
      echo "$(step_prefix) Deleted: ${path}"
    else
      echo "$(step_prefix) Skipped: ${path}"
    fi
    return
  fi

  echo "$(step_prefix) Not found: ${path}"
}

remove_dir() {
  local path="$1"
  local label="$2"
  CURRENT_STEP=$((CURRENT_STEP + 1))

  if [[ -d "${path}" ]]; then
    if [[ "${path}" == "/" ]]; then
      echo "$(step_prefix) Refusing to delete root directory."
      return
    fi
    if confirm "$(step_prefix) Delete ${label}: ${path}?"; then
      rm -rf "${path}"
      echo "$(step_prefix) Deleted: ${path}"
    else
      echo "$(step_prefix) Skipped: ${path}"
    fi
    return
  fi

  echo "$(step_prefix) Not found: ${path}"
}

remove_dir_sudo() {
  local path="$1"
  local label="$2"
  CURRENT_STEP=$((CURRENT_STEP + 1))

  if [[ -d "${path}" ]]; then
    if [[ "${path}" == "/" ]]; then
      echo "$(step_prefix) Refusing to delete root directory."
      return
    fi
    if confirm "$(step_prefix) Delete ${label}: ${path}?"; then
      sudo rm -rf "${path}"
      echo "$(step_prefix) Deleted: ${path}"
    else
      echo "$(step_prefix) Skipped: ${path}"
    fi
    return
  fi

  echo "$(step_prefix) Not found: ${path}"
}

remove_alias_path() {
  local path="$1"
  CURRENT_STEP=$((CURRENT_STEP + 1))

  if [[ -L "${path}" ]]; then
    if confirm "$(step_prefix) Delete symlink alias: ${path}?"; then
      rm -f "${path}"
      echo "$(step_prefix) Deleted: ${path}"
    else
      echo "$(step_prefix) Skipped: ${path}"
    fi
    return
  fi

  if [[ -e "${path}" ]]; then
    echo "$(step_prefix) Alias path exists but is not a symlink: ${path}. Skipping for safety."
    return
  fi

  echo "$(step_prefix) Not found: ${path}"
}

# ---------------------------------------------------------------------------
# Full uninstall (./uninstall.command --full)
#
# Removes Wine + everything installed for the Wine-Steam stack, while keeping
# anything that predates the Wine install (Rosetta 2, Xcode Command Line
# Tools, the native Mac Steam client, all personal files).
# ---------------------------------------------------------------------------

full_uninstall() {
  echo
  echo "  ══════════════════════════════════════════════════════════"
  echo "   MERLOT WINE-STEAM — FULL UNINSTALL (incl. dependencies)"
  echo "   Removes: Wine, DXMT, Merlot, Steam prefix (games!),"
  echo "            GStreamer.framework, Homebrew (all of it)"
  echo "   Keeps:    Rosetta, Xcode CLT, native Mac Steam, your files"
  echo "  ══════════════════════════════════════════════════════════"
  echo
  ask "Continue?" || die "aborted"
  [[ "$(id -u)" != "0" ]] || die "run as your normal user (sudo is invoked only where needed)"

  # --- stop everything ---
  say "stopping Steam, games, wineserver"
  pkill -f "Steam/steam\.exe" 2>/dev/null || true
  pkill -f "steamwebhelper"   2>/dev/null || true
  pkill -f "wineserver"       2>/dev/null || true
  sleep 2

  # --- watch agent ---
  say "removing the merlot-games watch agent"
  launchctl unload "$HOME/Library/LaunchAgents/local.merlot.games.watch.plist" >/dev/null 2>&1 || true
  rm -f "$HOME/Library/LaunchAgents/local.merlot.games.watch.plist"

  # --- user-level stack files ---
  say "removing Wine trees, DXMT, Merlot repo, tooling clones, caches"
  rm -rf "$HOME/wine-dxmt-build" "$HOME/DXMT" "$HOME/macos-wine-steam" \
         "$HOME/macos-wine-steam.bak-upstream" "$HOME/neutron-clone" "$HOME/Bourbon-OSS" \
         "$HOME/Library/Caches/Neutron" "$HOME/.cache/merlot-games" \
         "$HOME/Applications/Merlot Games"
  # remove ALL versioned Wine trees the stack installed (wine-11.10, wine-11.18, ...)
  local d
  for d in "$HOME"/wine-*/; do
    [[ -e "$d" ]] || continue
    case "$(basename "$d")" in
      wine-[0-9]*|wine-*[._][0-9]*) rm -rf "$d" ;;
    esac
  done
  rm -f "$HOME/bin/merlot-games" "$HOME/make-game-launchers.sh" \
        "$HOME/merlot-games" "$HOME/merlot-fix-dxmt.sh"

  # --- the prefix (Steam client + all games) ---
  if [[ -d "$HOME/.wine-steam-11" ]]; then
    if ask "Delete ~/.wine-steam-11 — the Wine prefix holding Steam + ALL INSTALLED GAMES (saves included)?"; then
      say "deleting prefix (Steam client + games)"
      rm -rf "$HOME/.wine-steam-11"
    else
      warn "keeping ~/.wine-steam-11 (delete manually if you change your mind)"
    fi
  fi

  # --- GStreamer.framework (Wine media dependency; needs sudo) ---
  if [[ -d "/Library/Frameworks/GStreamer.framework" ]]; then
    say "removing GStreamer.framework (needs sudo)"
    if sudo -v 2>/dev/null; then
      sudo rm -rf /Library/Frameworks/GStreamer.framework
      local p
      for p in $(pkgutil --pkgs | grep -i gstreamer); do sudo pkgutil --forget "$p" >/dev/null; done
      say "GStreamer removed, package receipts forgotten"
    else
      warn "sudo unavailable — remove manually:"
      warn "  sudo rm -rf /Library/Frameworks/GStreamer.framework"
    fi
  else
    say "GStreamer.framework not present — skipping"
  fi

  # --- Merlot Apps from /Applications (needs sudo) ---
  if [[ -d "/Applications/Merlot Apps" ]]; then
    say "removing /Applications/Merlot Apps (Steam (Merlot).app + game bundles)"
    if sudo -v 2>/dev/null; then
      sudo rm -rf "/Applications/Merlot Apps"
      say "Merlot Apps removed"
    else
      warn "sudo unavailable — remove manually:"
      warn "  sudo rm -rf \"/Applications/Merlot Apps\""
    fi
  else
    say "Merlot Apps not present in /Applications — skipping"
  fi

  # --- Homebrew (if installed for this stack) ---
  if [[ -d /opt/homebrew ]]; then
    say "Homebrew at /opt/homebrew — ALL brew packages will be removed with it:"
    /opt/homebrew/bin/brew leaves 2>/dev/null || true
    if ask "Remove Homebrew entirely (all of /opt/homebrew)?"; then
      if sudo -v 2>/dev/null; then
        sudo rm -rf /opt/homebrew && say "Homebrew removed" \
          || warn "Homebrew removal incomplete — check /opt/homebrew manually"
      else
        rm -rf /opt/homebrew 2>/dev/null || true
        if [[ -d /opt/homebrew ]]; then
          warn "partial removal (root-owned files left) — run: sudo rm -rf /opt/homebrew"
        else
          say "Homebrew removed"
        fi
      fi
      local f
      for f in "$HOME/.zprofile" "$HOME/.zshrc" "$HOME/.bash_profile" "$HOME/.profile"; do
        [[ -f "$f" ]] || continue
        if grep -q "brew shellenv" "$f" 2>/dev/null; then
          cp "$f" "$f.pre-merlot-backup"
          sed -i '' '/brew shellenv/d' "$f"
          say "removed brew shellenv line from $f (backup: $f.pre-merlot-backup)"
        fi
      done
    else
      warn "keeping Homebrew — uninstall manually if desired"
    fi
  else
    say "Homebrew not present — skipping"
  fi

  say "kept (predates the Wine install): Rosetta 2, Xcode Command Line Tools,"
  say "  native Mac Steam (/Applications/Steam.app), all personal files"
  say
  say "full uninstall complete."
}

main() {
  ensure_sudo_ready

  log "Uninstall targets detected"
  echo "1. STEAM_SETUP: ${STEAM_SETUP}"
  echo "2. WINEPREFIX alias: ${SCRIPT_DIR}/${WINEPREFIX_ALIAS_NAME}"
  echo "3. Installed Merlot app folder: ${SYSTEM_APPLICATIONS_DIR}/${MERLOT_APPS_DIR_NAME}"
  echo "4. WINEPREFIX: ${WINEPREFIX}"
  echo "5. DXMT_ROOT: ${DXMT_ROOT}"
  echo "6. WINE_ROOT: ${WINE_ROOT}"
  echo "7. Merlot data (CEF wrapper cache): ${MERLOT_DATA_DIR}"

  log "Removing artifacts from run.command and Merlot app folders"
  remove_file "${STEAM_SETUP}" "Steam installer file"
  remove_alias_path "${SCRIPT_DIR}/${WINEPREFIX_ALIAS_NAME}"
  remove_dir_sudo "${SYSTEM_APPLICATIONS_DIR}/${MERLOT_APPS_DIR_NAME}" "Installed Merlot app folder"
  remove_dir "${WINEPREFIX}" "Wine prefix directory"
  remove_dir "${DXMT_ROOT}" "DXMT directory"
  remove_dir "${WINE_ROOT}" "Wine root directory"
  remove_dir "${MERLOT_DATA_DIR}" "Merlot data directory (CEF wrapper cache)"

  log "Done"
  echo ""
  echo "This removed the core stack. Dependencies installed alongside it"
  echo "(GStreamer.framework, Homebrew, Wine trees, game launchers) need:"
  echo "  bash ${SCRIPT_DIR}/uninstall.command --full"
}

case "${1:-}" in
  --full)
    shift
    [[ "${1:-}" == "--yes" ]] && FULL_AUTOYES=1
    full_uninstall
    ;;
  "")
    main "$@"
    ;;
  *)
    die "Unknown argument: ${1} (supported: --full [--yes])"
    ;;
esac