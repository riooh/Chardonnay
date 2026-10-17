# Native macOS shortcuts for Wine

## Status

Built and deployed to both currently configured engines: the Wine 11.0/CX-derived
engine and the patched Gcenx Wine 11.18 engine. Each retained its original exported
symbols, including `_macdrv_functions`. Deployment used atomic file replacement
with verified original-driver backups; running clients were not restarted.

Acceptance: **26 real GUI cases passed**, 13 per matching private diagnostic engine.
Two additional Aqua/Win32 smoke tests loaded the exact installed production driver
paths and matched their recorded SHA256 values. Production binaries exclude the
diagnostic input/report hooks. Seven source-patcher tests passed on macOS; the
Linux suite ran 96 tests without failures, with two existing Mac-only tests skipped.
This verifies the integration, not universal compatibility with every Windows app,
game, fullscreen mode or keyboard layout.

## Bindings

- Command-Q: existing Wine application termination request, not a wineserver kill.
- Command-M: native minimize action for the current eligible window.
- Command-H: hide this Wine process's application windows.
- Command-W: native responder-chain window close, allowing Windows close handling.
- Control-Command-F: existing native fullscreen action, where supported.
- Command-A/C/V/X/Z: standard edit chords routed to their Windows Control equivalents
  if not already consumed by the existing native Edit menu.

Quit/close vetoes, actual minimize/hide state, select-all, undo and physical
Control-A were exercised. Copy/cut/paste delivery was acknowledged through the
fixture's Windows accelerators/control messages before any clipboard operation;
no user clipboard data was read or replaced by the test. Fullscreen was verified
on the normal fixture window, not a game's exclusive fullscreen renderer.

The edit fallback intentionally does not rewrite ordinary keys, physical Control,
physical Option, shifted/combined chords, or general Command combinations. It does
not implement every macOS text-navigation or application-specific shortcut.
Its hardware-key matching is validated on the current layout, not international
layouts. Command-W closes a window, not necessarily a browser tab.

No event tap, global remapper, Accessibility permission or clipboard interception
is introduced. Explicit user macOS menu-key overrides can still take precedence.
`CHARDONNAY_MAC_SHORTCUTS=0` restores original menu/input behavior in a new process.
**Existing Wine processes keep their already-loaded driver until exited normally.**
Restart the Windows app/client when convenient; restarting Chardonnay alone does
not replace a driver mapped inside an existing Windows process. Do not kill the
whole bottle or clear authentication just to adopt the bindings.

## Source integration

Implementation is in `app/merlot/WineMacShortcuts.h` and
`app/merlot/WineMacEditShortcuts.h`. The existing entrypoint provides a source-only,
fail-closed integration step:

```sh
./install_merlot.command --mac-shortcuts --source /path/to/matching/wine/source
```

This stages the headers and patches only the recognized native menu initializer
and keyboard event entry point, retaining original source backups. It does not
compile, install, download, restart Wine, modify a prefix, or replace an engine.
Unexpected hook layouts and symlink targets are rejected. Repeating the command
against unchanged patched sources is a no-op.

Build `dlls/winemac.drv/winemac.so` using the engine's existing configured build,
matching Wine version, original compiler settings and pre-existing DXMT/native
sharing patches. Never exchange Wine 11.0 and Wine 11.18 driver binaries. Require
all original exported symbols, especially `_macdrv_functions`, to remain available.

Preserve the previous installed driver and atomically rename a staged replacement
into place. Never truncate/copy over an inode used by running Wine processes.
Rollback likewise uses an atomic replacement from the verified original backup.
Do not re-sign/restart the unrelated native manager merely to change Wine's driver.
**Engine reinstalls overwrite this integration unless it is reapplied**;
fresh-machine packaging/automatic engine upgrades are not implemented here.

## Reproducing acceptance

`tests/test_wine_mac_shortcuts.py` exercises source recognition, idempotence,
backup preservation and fail-closed symlink/unknown-source handling.

For private diagnostic engine builds only, stage the input generator with
`--test-probe` and explicitly compile with `CHARDONNAY_SHORTCUT_TESTING` defined.
`tests/fixtures/WineMacShortcutProbe.h` sends complete modifier-down/key-down/
key-up/modifier-up NSEvent sequences into the fixture process's own normal Cocoa
loop. It never posts system-wide events or captures foreign windows.
`tests/fixtures/wine_shortcut_probe.c` supplies a real Win32 window with close/quit
vetoes, edit accelerators/control-message interception, private markers and a
bounded timer. Production smoke uses the same fixture with no injected inputs.

The explicitly opt-in runner is `tests/wine_mac_shortcuts_acceptance.py`:

```sh
python3 tests/wine_mac_shortcuts_acceptance.py PRIVATE_DIAGNOSTIC_STAGE --registered-prefix-fixtures
```

Run it via a private background LaunchServices host in Aqua, not a bare SSH
session. It expects matching private cloned engines, a freshly compiled fixture
EXE and `diagnostic-manifest.json` recording engine name, private_engine and engine
paths; names must match the existing shortcut config profile IDs. It appends
results to `GUI_RESULTS.json`/`GUI_DONE.json` in that private stage. Obtain explicit
approval because it opens individually scoped fixture processes in registered
prefixes. It never copies their account state or stops their servers. Use unique
private stage directories; archive completed prior results before re-running.

Each engine runs minimize, hide, close, close-veto, quit, quit-veto, select-all,
undo, physical Control-A, copy, paste, cut and fullscreen. Require real Windows
acknowledgements, native state, exact loaded driver paths, bounded exits and
preserved real client processes. A locked desktop prevents key-window readiness:
ask the owner to unlock it and keep it open, never bypass the lock. A bounded
awake assertion during the test worker may prevent idle display sleep without
changing lock settings.

Private engine copies must preserve relative graphics shared-library aliases.
Do not change an existing prefix's engine version, reset it, kill its server,
copy authentication or remove EA as part of keyboard testing. Compile final
production drivers without `CHARDONNAY_SHORTCUT_TESTING`, confirm diagnostic strings
are absent, then verify installed hashes/exports, native manager signature,
unchanged bindings and exact installed runtime module paths from fresh fixtures.
Keep private deployment evidence and rollback binaries outside the source repo.
