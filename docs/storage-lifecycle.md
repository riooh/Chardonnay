# Steam storage ownership and managed-replica lifecycle

## Scope and default safety

Storage modes live in `install_merlot.command --storage`, independent of the unchanged `--programs` shortcut importer. They never generate Desktop apps or change the installer's optional shortcut choice. No old bottle, backup or matching game directory is automatically adopted.

- `status` and `plan APPID` remain read-only.
- `create-replica APPID` copies one game's payload/manifest into an explicitly configured managed destination, recording ownership at creation. It does **not** clone the Windows user profile, registry, EA login or Steam userdata directories.
- `reconcile` previews eligible owned cleanup; `reconcile --apply --yes` performs it.
- `watch` explicitly installs the macOS background reconciler. `unwatch` persistently disables and stops only that owned job, retaining data/ledger.
- `daemon --once` runs one automatic-policy cycle; `daemon` repeats every 15 seconds. Creation does not silently install a background job.

**Permanent removal is supported only for new copies this manager created. Existing original JFO/diagnostic bottles are not enrolled or deleted.** These commands are development-facing infrastructure, not yet a seamless store-install UI or a replacement for the native Steam/Windows uninstall flow.

## Audit and plans

```bash
./install_merlot.command --storage status
./install_merlot.command --storage status --include-prefix "$HOME/bottles/ea"
./install_merlot.command --storage plan 1172380 --primary-prefix ea --include-prefix "$HOME/bottles/ea"
```

Output is JSON. Read-only inventory exits 0 when complete, 2 for incomplete/invalid input. An empty candidate list is not proof that no copies exist outside the audited scope. A completed reconcile can defer all copies; inspect `removed` and `deferred`, not just exit code.

Default configuration: `~/.config/chardonnay-storage/config.json`, falling back read-only to `~/.config/chardonnay-shortcuts/config.json`. `--config PATH` overrides it. Neither file is automatically rewritten. `--include-prefix` is read-only only, protecting extra prefixes without persistent enrollment.

Manager state is separate: `~/.local/share/chardonnay-storage`, or explicit `--state-dir PATH`. Ownership ledger and transaction updates are atomically written and fsynced under a single-writer lock. Read-only actions do not create state. Tokens are provenance identifiers, not secret credentials or an adversarial security boundary against the local account modifying its own files.

Inventory supports external Windows/Unix Steam library paths, exact app IDs, stable installation identities, manifest state, logical file bytes, device/inode and a file-metadata fingerprint. `exclusive_reclaimable_bytes` stays null: APFS logical copy size is not exclusive reclaimable storage.

## Explicit new managed copies

A dedicated storage config may mark a destination prefix `storage_role: managed_replica`. Its prefix, Steam library and common directory must already exist; the manager does not create full Windows bottles. Source defaults to `active`; protected destinations cannot be enrolled. Existing game payloads or manifests always cause refusal, never adoption/overwrite.

```bash
./install_merlot.command --storage create-replica APPID \
  --source-prefix canonical --replica-prefix disposable \
  --config /path/to/storage-config.json
./install_merlot.command --storage reconcile --config /path/to/storage-config.json
./install_merlot.command --storage reconcile --apply --yes --config /path/to/storage-config.json
./install_merlot.command --storage watch --config /path/to/storage-config.json
./install_merlot.command --storage unwatch --config /path/to/storage-config.json
```

New replicas opt into cleanup after a verified canonical-source uninstall. `--keep-on-uninstall` opts out. The background watcher must be explicitly installed for unattended cleanup. Configuration and IDs above are examples, not existing user enrollments.

macOS creation uses APFS `cp -a -c` with no silent full-copy fallback. The portable fixture backend uses ordinary copy with a space check. Both source and destination must be verifiably quiet during creation; no application is killed to obtain quiet. Unknown process-inspection state blocks creation/removal. macOS activity inspection uses own-user `ps`/`lsof` mapped executable/cwd paths plus Wine server identities, not executable names alone.

Only payload and manifest are copied; per-user saved-game/account directories remain outside that scope. Changes inside a replica, including a new in-install save/config/cache, block automatic cleanup. Do not interpret this as complete game-specific save discovery: the general save-management/UI layer is still unfinished.

## Ownership gates and recovery

Cleanup requires the manager's creation ledger plus a matching `.chardonnay-replica.json`, unchanged payload device/inode, manifest SHA256 and metadata fingerprint, no canonical-source manifest, and successful source-uninstall text **after** the captured source-log device/inode/byte boundary. The destination must be verifiably idle. Default/protected copies, malformed/offline inventory, symlinks/path traversal, aliases, changed data, unknown activity, source reinstall and rotated/truncated pre-proof logs defer cleanup. A metadata fingerprint is not a full-content integrity proof.

Private publication phases: `creating -> publishing -> ready`. Failed pre-publication copies can roll back only their marker/inode-verified staging tree; interrupted publication can finish only its already owned paths. Existing destination data is never adopted.

Uninstall phases: `prepared -> quarantined -> deleting -> removed`. Payload and manifest are first moved to unique same-library quarantine names, revalidated, then removed. Recursive deletion requires Python's symlink-attack-resistant backend. The journal distinguishes a partial delete from success and can resume an owned interrupted transaction. A reappearing source/destination, changed policy or new activity blocks continuation. Recovery uses recorded prior uninstall proof only after quarantine/deletion began and still refuses a new source manifest. Interrupted deletion is resumable, not undoable; quarantine does not claim to be a backup.

Native process inspection is a conservative check, not an OS-enforced lease against an unrelated Steam instance starting in the tiny interval after the final check. Broader store/runtime binding still needs coordinated single-writer launch/install locks before production-grade shared-library support can be claimed. Preserve this limitation in release claims.

The watcher uses `local.chardonnay.storage.watch`, distinct from both shortcut watchers. Installation verifies the exact plist and live launchd job; unwatch verifies persistent disable plus job absence. Existing foreign jobs/plists are refused. It is not automatically enabled on existing user data.

## Remaining native-experience integration

- Record canonical install/runtime bindings in the actual bottle/installer workflow rather than asking users to invoke developer CLI modes.
- Avoid silently cloning already installed payloads; prefer one canonical owner, with single-writer coordination for any shared library.
- Add game-specific save boundaries, user-facing blocked-cleanup/recovery notifications and explicit protected-backup policy.
- Exercise actual Steam uninstall -> watcher -> cleanup with an intentionally created disposable real-title copy before claiming real store-flow support.
- Measure container free-space changes without promising full logical-size recovery.

## Verification

```bash
python3 -m unittest discover -s tests -v
bash -n install_merlot.command
```

Regression fixtures cover creation/no-adoption, real file publication/rollback/deletion, absent uninstall evidence, active/unverified clients, changed replicas/new saves, independent backups, keep policy, source reinstall, corrupt ledger, ownership/symlink swaps, interrupted publication/quarantine/partial deletion, idempotence, read-only CLI invariants and refusal of foreign launchd jobs. Mac-only end-to-end fixtures additionally exercise real APFS cloning, unmodified process guards and the actual launchd watcher while leaving real Steam/EA sessions untouched. Fixture uninstall events are explicitly synthetic; they are not evidence of a newly executed real-game Steam uninstall.
