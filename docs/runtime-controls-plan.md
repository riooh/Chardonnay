# Explicit per-bottle runtime controls

Approved scope: CrossOver-style manual recovery, not the proposed automatic supervisor.

## Requirements and safety

- Native process list, refresh, selected-process Terminate and separately confirmed Force Quit.
- Selected-bottle Quit All Applications, separately confirmed Force Quit All, and explicit restart of ONE selected registered application. Warn about unsaved game/editor work and installer writes.
- Existing registered engine/prefix routes stay unchanged. Restart never replays an installer/uninstaller, never relaunches every prior process and does not promise restored memory or application rendering.
- Inspection must not launch Wine: a helper could accidentally start a replacement wineserver and hide the dead generation.
- Determine ownership from prefix filesystem identity and the Wine server runtime namespace, not engine/comm/cwd alone. Reject ambiguity. Native birth identity protects against stale selections/PID reuse. Recheck before signalling.
- Confirmation uses a short-lived, private snapshot token binding exact prefix/binding identity and target process identities. Changed/new relevant members invalidate whole-bottle consent. No implicit TERM-to-KILL escalation; KILL only through separately confirmed force action. Inspect server and old-generation orphans.
- Serialize manager-originated operations. No claim of an OS-enforced writer lease over independent store processes; explicit bottle-stop warns it can interrupt them. Unknown ownership must be reported, not declared stopped.
- Preserve prefix files, game/save/account state, Desktop policy, separate bottles and working client sessions during development/deployment.

## Implementation increments

1. Add failing backend contracts for scope attribution, stale snapshots, cancellation/no consent, whole-bottle and process actions, no escalation and restart routing.
2. Add read-only native identity helper and embedded entrypoint runtime implementation; refuse unsupported/uninspectable state. Keep product logic in existing entrypoint and native support source under app/merlot.
3. Add native runtime window and exact snapshot-bound confirmation handlers. Refresh on demand rather than a new always-on daemon. Verify recovery controls cannot act on a different bottle after asynchronous selection changes.
4. Exercise actual Cocoa handlers against private real Win32 fixture processes; test two prefixes sharing one engine, cooperative/noncooperative termination, separately confirmed force and restart markers. Protect the real clients/config with before/after readback.
5. Run full regression suite and strict native compile/signature verification. Back up the deployed app/source, replace only accepted targets, reopen the manager alone and read back new UI health. No client restart for deployment, no automatic recovery policy, no commit/push unless separately requested.
