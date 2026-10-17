# Native manager and recovery — test handoff

This feature branch checkpoints the native bottle manager, manual recovery
controls, guarded storage lifecycle, native launcher reopen host and macOS
keyboard integration on top of the existing engine/shortcut development line.
It is not merged into `main` and is not a standalone engine release.

## Installed increment

Chardonnay development app **0.1.1** exposes **Running Apps / Recovery…** after
selecting a bottle and application. These are explicit controls, not an automatic
watchdog. Existing engine/prefix routing, account state, game files and optional
Desktop-shortcut policy are retained.

## User testing — pending

Start with idle clients and finish/cancel any installer or download first.
Termination can lose unsaved work; do not use a real game/editor as a disposable
force-quit fixture.

1. Open Chardonnay normally; select the intended bottle and app, then open
   **Running Apps / Recovery…**. Check the bottle and restart target shown there.
2. Refresh the process list. Confirm it does not launch a client or switch bottles.
3. For a deliberately disposable/stale app process, choose **Terminate Process…**,
   then **Cancel**. Confirm nothing closes. Repeat and confirm termination only
   when losing that process's unsaved state is acceptable.
4. Test **Quit All Applications…** only when the ENTIRE selected bottle is idle.
   A surviving process should produce a separately confirmed **Force Quit All**
   action, not an automatic kill.
5. Test **Restart Selected App…** under the same idle-bottle conditions. It must
   restart only the captured app after the old session stops. If TERM cannot stop
   it, **Force Stop & Restart App…** requires another confirmation.
6. Check that the other bottle/client stays running and that the relaunched app
   actually renders and responds. A process list or dispatch result alone is not
   a rendering/compatibility verdict.
7. Separately, when convenient, verify Command-Q/M/H/W, Control-Command-F and edit
   shortcuts after a NORMAL relaunch of the Windows app. Keep original engine
   bindings and working game installs available as rollback during experiments.

If anything freezes, capture the selected bottle/action and fresh logs BEFORE
restarting. Do not reset a prefix, clear saved login, repeat an uninstall or change
engines as an incidental troubleshooting step.

## Automated evidence

- Full macOS suite: **122 tests passed**, including actual Cocoa button/NSAlert
  actions, empty-prefix Win32 GUI fixtures, EXE/MSI and 32/64-bit Gecko consumers.
- Linux suite: **122 tests, three Mac-only skips**, no failures.
- Runtime fixtures exercised targeted TERM/KILL, Cancel, normal restart stopping
  on a surviving service, separately confirmed force-restart, no automatic
  escalation and explicit force-all. Private fixtures were cleaned.
- Native signing and normal manager reopen were verified. Original live runtime
  process identities and shortcut configuration were unchanged across deployment.
- Own-window compositor capture was unavailable in the final run; no screenshot
  or painting proof is claimed. Independent cloud review was unavailable and is
  not counted as passed.

These results predate the owner's hands-on testing, which remains **pending**.
The earlier unexpected wineserver exit's trigger is still unknown. These controls
are a recovery mechanism, not proof of a permanent engine fix.

## Preservation and rollback

Keep the installed app, original engine bindings, deliberately retained bottles
and private deployment backup intact. Before changing anything next session,
verify the live branch/commit, deployed app version, exact runtime ownership and
config against the private operator handoff. Do not publish raw account-bearing
logs, private configs, prefixes or proprietary engine/framework binaries.

The public source contains build/test recipes and fixtures only. Exact private
backup/evidence paths and runtime identities are recorded in the operator handoff,
not bundled into this repository.
