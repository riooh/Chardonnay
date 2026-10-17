# Per-bottle runtime supervision and recovery

Status: **proposed strategy, not implemented or enabled**. Existing source and the
configured Wine server's `--help` were inspected. No automatic policy or launch
agent was enabled. Separately, after the owner's follow-up, the old orphaned Wine
control-panel process was closed manually without signalling the current MSI
service, Steam or either bottle's server. This design mitigates a failure mode;
it does not establish why the original Wine server exited.

## What recovery can and cannot do

A dead wineserver can leave native Cocoa windows and waiting Windows threads.
Restarting that server alone does not reconnect those old clients. Recovery means
retiring proven orphaned clients and starting a new session, not restoring their
in-memory application state. Unsaved gameplay/editor state cannot be guaranteed.

The current native launcher tracks shell workers, not Wine session generations.
The bottle backend dispatches launch/uninstaller subprocesses but has no durable
maintenance lease spanning detached Windows bootstrapper descendants. Its UI busy
flag or a successful subprocess exit is not sufficient recovery coordination.

## Recommended architecture

Use one lightweight native **Runtime Supervisor** in the logged-in Aqua session,
with independent per-bottle state. Integrate it with Chardonnay and generated
launchers; do not duplicate a watchdog in every Desktop app. Keep it separate from
the shortcut filesystem reconciler's destructive authority. It should not require
Screen Recording, Accessibility, administrator access or protected-folder grants.
The manager can close without terminating Windows apps; explicitly enabled
supervision must not depend on its window staying open.

Keep control functionality in the existing entrypoint and native support code in
`app/merlot/`, following the project's entrypoint convention. Proposed controls:
observe/status, explicit per-bottle client-recovery opt-in, recover-with-confirmation,
and disable. No global enablement for imported bottles and no implicit migration.

For a *new, idle* supervised session, start the exact bound engine's wineserver
with `--foreground` as a directly owned child, then launch clients through their
registered recipes. The inspected server supports this option. This enables
recording actual exit status/signal and stderr. Validate this launch arrangement on
both engine versions before adoption. Do not stop an existing healthy session just
to adopt supervision. Existing sessions can initially be observed, with less exit
attribution, until their next normal start.

Use native process-exit notifications plus sleep/wake/session notifications rather
than continuous expensive subprocess polling. `launchd` may maintain the supervisor
if explicitly enabled; it must not blindly KeepAlive/restart wineserver itself.

## Session identity and health

Record a session generation: prefix filesystem identity (device/inode and resolved
path), engine identity, server PID plus process birth identity, and an incarnation
UUID. Associate clients with that generation *while it is healthy*: exact executable,
PID/birth identity and prefix runtime ownership. Process names, executable engine
path alone, old tmpmap files and a server directory are insufficient attribution.
Multiple bottles may share an engine. Inventory *all* attributed processes,
including Wine's builtin `uninstaller.exe` control panel, rather than only a named
vendor uninstaller and Steam helpers. A stale control panel can remain from the
old generation after the vendor process has exited. Classify UI-only orphans
separately from actual bootstrapper/MSI writers. Revalidate identity immediately before every
signal; ambiguous ownership or PID reuse means no automatic action.

Track these separate signals:

- Exact server generation alive, with runtime lock ownership evidence.
- Expected client instances alive in that generation.
- Bounded `SendMessageTimeout(WM_NULL)` responses from the intended visible windows.
- Rendering as a separate concern: responsiveness does not prove non-black painting.

A WM_NULL timeout or black window with a live server is **not** permission to kill
anything. Slow loading, modal dialogs, driver stalls and busy message loops need
separate handling. Reset timeout suspicion after sleep/wake; pause intrusive actions
while locked/sleeping, with startup/resume grace. Do not change security/power
settings or simulate global input to make recovery pass.

Never run a Wine health helper after confirmed server loss: it could create a new
server and obscure the old generation's failure. Use native process/runtime
observation first. After a replacement session is deliberately established, run a
bounded health probe and verify that it belongs to that session.

## State machine and automatic-action policy

States: stopped, starting, healthy, suspect, server-lost, collecting-evidence,
blocked-by-maintenance, blocked-by-app-risk, recovering, verifying, cooldown,
manual-attention. Persist transitions and incident identifiers atomically.

1. **Normal exit:** clients stop and the server becomes idle/exits. Stay stopped;
   do not reopen a client the user intentionally quit. Respect explicit stop/quit
   requests and never turn intentional bottle shutdown into a restart loop.
2. **Suspect UI:** server lives but repeated probes miss. Capture bounded evidence
   and offer a client restart; never infer a dead session from a slow UI alone.
3. **Unexpected server loss with surviving old clients:** capture first, then apply
   the following gates under the per-bottle coordination lock.
4. **Safe client-only case:** recovery was explicitly enabled; every relevant
   process is accounted for; no game, unsaved document, unknown app or active/uncertain
   install/uninstall/repair/update/download operation exists. Revalidate the snapshot,
   SIGTERM only proven orphaned store-client/helper instances, and verify exit.
   Never automatically escalate to SIGKILL. If retirement fails, stop and notify.
5. Recreate the exact configured runtime and relaunch only the approved store client
   through its ordinary launch recipe, preserving engine/backend/options/login.
   Never replay an installer, uninstall command, game launch, purchase or update.
6. Verify the new generation and actual client responses; report recovered, not
   merely 'process launched'. Painting can still require user confirmation.
7. Apply a persisted retry budget/cooldown and a circuit breaker. A failed attempt
   or repeated incident stops automation and surfaces one actionable notification.

No global pkill, healthy-server kill, prefix reset, cache/account deletion, save
modification, payload copy, engine switch or cleanup of deliberate backups is part
of automatic recovery. Actions are serialized per bottle; unrelated bottles remain
untouched.

## Maintenance and gameplay safety

Before *any* installer/uninstaller operation, create a durable maintenance lease
covering its real Windows descendant tree and final outcome, not just the short-lived
Unix launcher PID. Clear it only after completion is verified. An interrupted or
ambiguous lease survives supervisor restart and blocks automatic retirement/replay.
Do not treat a successful installer exit code as successful installation/removal.

Games and generic document applications are prompt-only. Unknown executables or
uninspectable processes also block automatic action. External Steam/EA operations
must be considered: a Chardonnay-only mutex cannot prevent their UI from starting
writes. If independent activity cannot be observed reliably, the safe-idle condition
is unknown and automatic recovery must defer. Installation-state logs/process
heuristics are supporting evidence, not an OS-enforced writer lock.

**For the just-observed Steam + uninstaller incident:** detect and explain the lost
session automatically, capture it, but request confirmation to retire clients while
maintenance state is active/uncertain. Never automatically restart the EA uninstaller.
The intended unattended success case is a lost *idle store-client* session, not a
silent game or installation restart.

## Diagnostics and acceptance

Maintain a private, size/retention-bounded incident journal: host timestamps and
sleep/wake markers, session generation, process identity/mapping evidence, bounded
samples, server exit result, redacted fresh log offsets and every decision/action.
Do not export tokens, account identifiers, full environments or authentication logs.
Use the journal to investigate the still-unknown server-exit cause, independently
of improving recovery.

Roll out in stages: read-only observation; private fault-injection fixtures;
prompted recovery; explicit client-only automatic mode. Do not enable an automatic
killer as part of writing this strategy.

Acceptance before enabling real automation:

- Owned EMPTY fixture prefixes and matching engines; never inject a server failure
  into a real game/account bottle or copy authenticated prefixes for tests.
- Unexpected private server exit with safe fixture clients: collect, retire only
  old-generation fixtures, relaunch exactly once, verify real Windows responses.
- Healthy server plus a deliberately slow/nonresponsive window: no automatic kill.
- Game/editor, unknown process, active installer and ambiguous stale lease: block.
- Normal client quit/server idle exit: no restart. Locked desktop/sleep/resume:
  no false recovery or security workaround.
- PID reuse, prefix aliases, simultaneous launch/recovery, supervisor crash and
  queued operations: fail closed without killing a replacement or another bottle.
- Failed termination/relaunch/verification and repeated failures: circuit breaker,
  bounded logs, no signal escalation or repeated install/update requests.
- Verify both configured engines, correct module paths, preserved separate bottle,
  unchanged account/save data, and the actual ordinary-launch user flow.

The experimental engine's fresh-prefix bootstrap remains a separate unverified
prerequisite; resolve it safely before claiming full fault-injection coverage there.
