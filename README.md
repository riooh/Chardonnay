<!-- FORK NOTE: Chardonnay is a fork of ByMedion/macos-wine-steam with DXMT/D3D11 fixes -->
# Chardonnay 🍷

> Merlot, aged until D3D11 actually works.

One-click **Steam in Wine on Apple Silicon**, plus the fixes that make DXMT-based
D3D11 rendering actually work on Gcenx Wine builds — and a per-game launcher
system so games behave like real Mac apps.

## ⚠️ Vibe-coded project

This fork is a **vibe-coded project**: it was built fast, with AI doing most of
the typing, driven by the goal of getting games running rather than rigorous
engineering. The scripts are battle-tested on real hardware (see
[Tested on](#tested-on)), but:

- **Read before you run.** Especially anything that touches `sudo`.
- **Backups are kept** wherever files are replaced (`.orig`, `.orig-wine`,
  `.pre-merlot-backup`) — but verify them anyway.
- The Wine-on-macOS ecosystem moves monthly. If something breaks, re-run the
  fix and/or open an issue.

## What this fork fixes

Upstream Merlot has two silent graphics bugs on Gcenx Wine builds. Symptoms:
Unity games die with `Failed to initialize graphics`, or run but fall back to
OpenGL; `Failed to create metal view` in the Steam log.

1. **DXMT never loads.** Merlot enables DXMT via `WINEDLLPATH_PREPEND` — a
   variable Gcenx Wine builds do not implement. Result: every game silently
   renders through Wine's builtin wined3d → OpenGL, which caps at GL 4.1 on
   macOS. Games with a Vulkan fallback survive; DX11-only games die.
   **Fix:** `run.command` installs the DXMT builtin tarball per the
   [official wiki layout](https://github.com/3Shain/dxmt/wiki/DXMT-Installation-Guide-for-Geeks)
   into the Wine tree and prefix (originals backed up).
2. **DXMT cannot present frames.** Vanilla Gcenx `winemac.so` hides the
   `macdrv_*` symbols DXMT dlsyms to create Metal surfaces
   (`err: Failed to create metal view, it seems like your Wine has no exported
   symbols needed by DXMT.`). **Fix:** `run.command` rebuilds `winemac.so`
   from matching Wine source with the
   [codeWonderland/neutron](https://github.com/codeWonderland/neutron) patch
   set (adds the `macdrv_functions` export, plus Unity video, splash-hang and
   GL-context fixes).
3. **Steam's client UI renders as a black window.** Included from upstream
   [PR #8](https://github.com/ByMedion/macos-wine-steam/pull/8) (steamwebhelper
   wrapper + `-noverifyfiles` launch flags).

**All of this runs automatically** as part of `run.command` (and every Merlot
app launcher) after the DXMT download step — no separate script step needed.
It is idempotent and self-heals after Wine version updates, which would
otherwise silently revert it. Set `MERLOT_DXMT_FIX=0` to skip it (e.g. when
using the GPTK backend, where it is skipped automatically).
`./run.command --check` reports the graphics stack state without changing
anything.

## Requirements

- Apple Silicon Mac, macOS Sonoma 14+ (Sequoia 15+ recommended)
- ~5 GB for the stack + 10–20 GB per game
- Admin password (Rosetta 2, GStreamer, `/Applications` install)

## Install

1. Click the green `Code` button → `Download ZIP`, and unzip it.
2. In Finder, double-click `install_merlot.command`
   (if macOS blocks it: right-click → `Open` → `Open`).
3. Launch a game or `Steam (Merlot).app` — the DXMT fix runs automatically
   as part of every launch. On the very first run it builds a patched
   `winemac.so` (a few minutes, one-time) and installs the DXMT DLLs.

No manual script steps are required. To verify the graphics stack at any
time: `./run.command --check`.

## Run

- `/Applications/Merlot Apps/Steam (Merlot).app` — plain Steam (or `run.command`).
- Game launchers in `Merlot Apps` — game-specific presets.
- Or make real launchers for every installed game (see below).

## Game launchers (recommended)

Steam under Wine drops Windows `.url` shortcuts on your Desktop, which macOS
resolves to the *native* Mac Steam client — wrong Steam, blank icons.
`install_merlot.command --games` instead builds proper `.app` bundles:

```sh
bash install_merlot.command --games sync    # build launchers for all installed games
bash install_merlot.command --games watch   # auto-add launchers when you install new games
bash install_merlot.command --games status  # list launchers + agent state
```

Launchers appear in `~/Applications/Merlot Games` with each game's real icon
(Steam's own 256×256 `.ico`, falling back to capsule art), cold-start Steam if
needed, and launch straight into the game.

## Stop

`Steam` → `Exit`. With the default `MERLOT_DETACH=1`, closing Terminal does not
kill Steam.

## Uninstall

Two options:

- **Light:** double-click `uninstall.command` (removes the stack, keeps
  Rosetta; per-item confirmation).
- **Full:** `bash uninstall.command --full` — removes the entire stack
  *including* GStreamer and Homebrew when they were installed for it, while
  keeping anything that predates the Wine install (Rosetta, Xcode CLT, native
  Mac Steam, your files). Asks before deleting the prefix (games live there).

## Tested on

- Apple M2 (8 GB), macOS 27.0.1 — Steam + DXMT verified end-to-end:
  How to Fish (Unity 6, DX11-only), Gamble With Your Friends, Golf With Your
  Friends.
- Upstream reports: M1 Max (32 GB) / M2 Pro (16 GB), macOS Sequoia 15.7.4.

## Notes

- First session in a game may stutter — DXMT compiles shaders lazily; the cache
  warms and session 2+ is smoother.
- Kernel-level anti-cheat (Riot Vanguard, some EAC/BattlEye configs) never works
  under Wine on macOS.
- Intel Macs are not supported.

## References & Credits

- Upstream project: [ByMedion/macos-wine-steam](https://github.com/ByMedion/macos-wine-steam) (Merlot)
- Wine builds: [Gcenx/macOS_Wine_builds](https://github.com/Gcenx/macOS_Wine_builds)
- D3D11→Metal: [3Shain/dxmt](https://github.com/3Shain/dxmt) (DXMT)
- winemac patches: [codeWonderland/neutron](https://github.com/codeWonderland/neutron)
- Steam black-window fix: upstream [PR #8](https://github.com/ByMedion/macos-wine-steam/pull/8) by stevemurr
- Inspired by [this Reddit post](https://www.reddit.com/r/macgaming/comments/1r8vsnj/how_to_play_windows_steam_games_on_mac_with_m/);
  discussed in [this one](https://www.reddit.com/r/macgaming/comments/1rflhp8/oneclick_solution_to_run_windows_games_on_apple/).

For developer details, see the [Developer README](README_DEV.md).