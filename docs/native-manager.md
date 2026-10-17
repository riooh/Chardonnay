# Chardonnay native manager (development increment)

This is a working Cocoa manager over the **existing configured Wine stack**, not a standalone CrossOver replacement or a distributable engine installer. It is the first native-manager increment toward the agreed Steam + EA + generic Windows installer milestone; that overall milestone remains in progress.

## Supported now

- Read existing `~/.config/chardonnay-shortcuts/config.json` bottle/engine bindings without migrating them or rewriting them at startup.
- Show registered bottles, installed Steam/EA clients, installed Steam games and cached Windows application shortcuts inside the manager. Steamworks Common Redistributables is not presented as a playable game.
- Create an **empty** isolated Windows 10 prefix, bind an already-available engine, set up its private Wine Desktop and register its optional-shortcut scope. No game, account or prefix payload is cloned.
- Choose a downloaded `.exe` or `.msi` installer. A new bottle is the guided default; explicitly choosing an existing bottle shares its Windows settings. MSI files run through `msiexec`; arbitrary shell interpolation is not used.
- Discover installer-created shortcuts and launch them with the bound engine, arguments and working directory intact.
- Expose existing Steam/EA launch paths; preserve Merlot routing for the canonical Steam profile and select the actually mapped EA executable before falling back to an installed version.
- Open the bottle's Windows uninstaller after confirmation. Steam/EA games remain managed **inside their store clients**; this command does not delete the bottle or any backup.
- Reopen the same native manager host normally, including while a backend worker is active. No Terminal window is used.

A bottle isolates Windows compatibility state, **not hostile code**. Windows programs can access host files allowed to the user. Install only software you trust.

## Build and use

On the configured Mac, from this checkout:

```bash
bash install_merlot.command --bottles install-manager
open "$HOME/Applications/Chardonnay.app"
```

The build requires full Xcode/clang and uses the currently configured Wine engines. It ad-hoc signs and strictly verifies the app. It refuses to overwrite an existing destination. Use `--destination /another/new/Chardonnay.app` when building another development copy; do not replace a working app silently.

The app's `ChardonnayEntrypoint` points to this checkout's entry point. Keep the checkout available. No engine or Apple graphics framework is bundled, downloaded or redistributed by this mode. Moving it to another machine is **not** a supported installation procedure.

Typical operation:

1. Select a bottle to view its applications, or choose **Install Windows App…**.
2. Select a trusted downloaded EXE/MSI, then confirm a new bottle or an explicitly selected existing bottle.
3. Follow the Windows installer's own prompts and optional shortcut checkboxes.
4. Select the discovered application and choose **Launch**. A process exit/launch dispatch is not a universal compatibility verdict.

## State and CLI

- Manager state: `~/Library/Application Support/Chardonnay/`.
- Owned new prefixes: `bottles/<UUID>/` below that directory, with an ownership marker and a registry record. Imported prefixes remain externally managed.
- Per-bottle private operation logs: `logs/<ID>.log`. Treat logs as private; do not publish account-bearing output.
- UI health: `manager-status.json` records the actual native host PID, visible-window flag, loaded-row counts and control titles after a successful refresh. It does not certify a game's rendering.
- Metadata cache is separate from the existing Desktop shortcut worker. Startup does not rescan Windows links by launching another Wine session.

```bash
bash install_merlot.command --bottles status
bash install_merlot.command --bottles create --name 'Windows App' --engine ENGINE_ID
bash install_merlot.command --bottles install-file --bottle BOTTLE_ID --file /path/setup.exe
bash install_merlot.command --bottles launch --bottle BOTTLE_ID --app APP_ID
bash install_merlot.command --bottles uninstaller --bottle BOTTLE_ID
```

New-bottle creation requires the existing `ShortcutInfo.exe` helper before marking a real prefix ready. Failed initialization remains marked failed rather than being reported as a usable bottle. Creation only extends shortcut scope; it does not synthesize Desktop icons from game manifests. Installers that create neither a Start Menu nor Desktop shortcut may require additional discovery/launcher UI in a later increment.

## HTML/Gecko prerequisite

Before starting a downloaded installer or opening Windows Uninstaller, Chardonnay prepares the Gecko packages required by the bound engine. It matches each architecture's filename and SHA-256 against the engine's actual `appwiz.cpl`, downloads only the pinned official HTTPS package, verifies it, and atomically caches it in `~/.cache/wine`. Valid packages are reusable offline; unknown engine requirements, unsafe targets or mismatched downloads fail before starting the installer. Invalid existing cache files are preserved rather than silently destroyed.

```bash
bash install_merlot.command --bottles ensure-gecko --bottle BOTTLE_ID
```

Cache preparation alone does not rewrite a live prefix or uninstall anything. Wine registers the cached HTML runtime in the target prefix when an actual MSHTML consumer first needs it. The 32-bit and 64-bit native tests instantiate MSHTML, load Gecko's real `xul.dll`, write a small HTML document and read its body text back. A cached MSI or successful COM-object allocation alone is not the runtime acceptance test.

Treat an EA uninstall warning and the actual installer outcome separately. EA's bootstrapper can report `EA Desktop is still running. Canceling uninstall` and still exit with code 0, without reaching MSI removal. Missing Gecko is a real dependency defect, but resolving it is not proof that EA removal succeeded. Close/cancel the failed EA installer and retry the normal UI flow; do not reset the bottle, force-remove game files or automatically repeat a destructive operation as a dependency test.

## Manual runtime recovery

Select the bottle AND the app you would want to relaunch, then choose **Running
Apps / Recovery…**. The process window is bound to that bottle and app even if the
main-window selection changes later.

- **Refresh Processes** inspects native process identity and Wine prefix ownership
  without starting a Windows helper or replacement wineserver. The list is not a
  responsiveness or rendering test.
- **Terminate Process…** sends SIGTERM only to the confirmed native process. The
  server cannot be terminated as an individual app; use a bottle-wide action.
- **Force Quit Process…** sends SIGKILL only after a separate warning/confirmation.
- **Quit All Applications…** sends TERM to the confirmed bottle's clients and
  server, including proven old native orphans. If processes remain, it changes to
  **Force Quit All Applications…**. Nothing escalates automatically.
- **Restart Selected App…** stops the confirmed bottle and relaunches exactly the
  captured registered app through its existing engine/routing recipe only after
  verification that the old session is empty. If TERM leaves survivors, a separate
  **Force Stop & Restart App…** confirmation is required. No previous installer or
  uninstaller command is replayed. Recognized installer shortcuts are rejected.

**Unsaved work can be lost, and installs/repairs/download writes can be interrupted.**
Native TERM is not a guarantee of WM_CLOSE, a Windows save prompt or an application
veto. Use the application's own Quit first when it responds. A native restart is
not session-memory restoration; verify the relaunched app's actual window.

All actions use one-use private confirmation snapshots, expiring after three
minutes. Scope includes prefix device/inode, engine binding/file identity and
process birth microseconds/native executable path. Changed membership invalidates
bottle-wide consent; uncertain scope blocks bottle-wide operations. Revalidation
reduces PID/selection races but is not an atomic kernel process-handle signal or an
OS-enforced writer lease over independent clients. No broad process-name kills,
prefix reset, cache/account/save deletion, engine migration or auto-recovery daemon
is part of these controls. The manager mutex coordinates its own dispatches only.

Read-only CLI inventory (returns the confirmation token):

```bash
bash install_merlot.command --bottles processes --bottle BOTTLE_ID
```

An explicitly authorized action requires that exact token and `--yes`:

```bash
bash install_merlot.command --bottles runtime-action --bottle BOTTLE_ID \
  --snapshot TOKEN --operation terminate --pid MACOS_PID --yes
```

Other operations: `force-process`, `quit-all`, `force-all`, `restart` and
`force-restart`; restart actions additionally require `--app APP_ID`. Prefer the
confirmation UI for ordinary use. Private snapshots/last-action metadata live in
`runtime/` under manager state, separate from game payloads.

The native runtime acceptance uses a new EMPTY prefix and real Win32 GUI message
loop markers. It drives the actual process-list buttons and NSAlert Cancel/confirm
buttons for TERM, force termination, whole-bottle restart, no implicit escalation
and explicit force-all. A deliberately TERM-resistant **native** fixture separately
exercises force escalation; it is not evidence of a Windows compatibility defect.
Other live bottles can share the tested engine and must remain untouched. Actual
compositor capture may be unavailable/denied and is never worked around with global
screen permissions. These tests do not establish the cause of a prior server exit.

## Verification

`python3 -m unittest discover -s tests -v` runs the suite. The Mac-only native-manager acceptance:

- launches a **private Cocoa bundle through ordinary LaunchServices**;
- invokes the actual Create / Install / Launch button handlers;
- initializes a new empty real Wine prefix using a private shortcut configuration;
- executes a small real Win32 EXE installer, builds and installs a real registry-only MSI using Windows Installer APIs, then launches the installer-created `.lnk`;
- reads the launched process's fresh Unicode argument, working-directory, prefix and MSI registry markers;
- performs an ordinary reopen while the first worker is active and verifies the host PID remains unchanged;
- preserves the real shortcut config byte-for-byte, stops only the private prefix's matching wineserver, and cleans up the test prefix;
- captures only its own window through ScreenCaptureKit's **current-process** API where available, without requesting global screen-recording permission. A view-cache image is not a compositor-painting verdict.

The MSI fixture uses explicit column lists in `INSERT INTO` statements: Windows Installer SQL is a subset, not generic SQL. Tests canonicalize temporary fixture roots so macOS's `/var` alias does not create false ownership/path mismatches; production path/ownership checks are unchanged.

## Not completed by this increment

- Dedicated official Steam/EA download, dependency and first-sign-in recipes on an empty/fresh machine.
- Automatic per-game graphics selection or safe in-place renderer/engine switching of an existing bottle.
- Duplicate/export/import backup UI and coordinated store/runtime writer leases.
- Standalone engine acquisition, packaging, upgrades, notarization and public release.
- Universal Windows compatibility or new gameplay verification. The private installer fixture is not an EA/Steam/game compatibility result.

The managed-replica storage backend remains a separate explicit mechanism. This manager does not silently create disposable game copies, enroll old original/rollback bottles, install the storage cleanup watcher or delete real payloads.
