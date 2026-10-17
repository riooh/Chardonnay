"""Managed payload lifecycle: all mutating tests use private temporary fixtures."""
import json
import hashlib
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock
import test_storage_inventory as base

M = base.MODULE


class ManagedStorageTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.profiles = []
        self.active = self.prefix('active', 'active')
        self.old = self.prefix('old', 'managed_replica')
        self.config = {'version': 1, 'prefixes': self.profiles, 'replicas': []}
        self.game(self.active)
        (self.active / 'logs').mkdir()
        self.log = self.active / 'logs/content_log.txt'
        self.log.write_text('before registration\n')
        self.saves = self.root / 'old/drive_c/users/test/Saved Games'
        self.saves.mkdir(parents=True)
        (self.saves / 'keep.sav').write_bytes(b'private save')
        self.state = self.root / 'manager-state'

    prefix = base.StorageTests.prefix
    game = base.StorageTests.game

    def manager(self, activity=None):
        self.assertTrue(hasattr(M, 'StorageManager'), 'creation-time ownership and reconciliation are not implemented')
        quiet = lambda profile: {'verified': True, 'active': False, 'pids': []}
        return M.StorageManager(self.config, self.state, activity=activity or quiet)

    def create(self, **kwargs):
        return self.manager().create_replica('1172380', 'active', 'old', **kwargs)

    def uninstall_primary(self):
        manifest = self.active / 'steamapps/appmanifest_1172380.acf'
        manifest.unlink()
        with self.log.open('a') as f: f.write('[time] AppID 1172380 finished uninstall (No Error)\n')

    def test_create_records_new_copy_without_cloning_account_state(self):
        result = self.create()
        replica = Path(result['payload'])
        self.assertTrue((replica / 'payload.pak').is_file())
        self.assertTrue((replica / M.MARKER).is_file())
        ledger = json.loads((self.state / 'ledger.json').read_text())
        self.assertEqual(len(ledger['replicas']), 1)
        self.assertEqual(ledger['replicas'][0]['phase'], 'ready')
        self.assertTrue(ledger['replicas'][0]['cleanup_on_source_uninstall'])
        self.assertEqual((self.saves / 'keep.sav').read_bytes(), b'private save')
        self.assertEqual(set(p.name for p in replica.iterdir()), {'payload.pak', M.MARKER})

    def test_existing_destination_is_never_adopted_or_overwritten(self):
        game, _ = self.game(self.old)
        before = (game / 'payload.pak').read_bytes()
        with self.assertRaises(ValueError): self.create()
        self.assertEqual((game / 'payload.pak').read_bytes(), before)
        self.assertFalse((game / M.MARKER).exists())

    def test_protected_destination_cannot_be_enrolled(self):
        self.profiles[1]['storage_role'] = 'protected'
        with self.assertRaises(ValueError): self.create()
        self.assertFalse((self.old / 'steamapps/common/Jedi Fallen Order').exists())

    def test_active_destination_blocks_creation(self):
        active = lambda profile: {'verified': True, 'active': profile['id'] == 'old', 'pids': [123]}
        with self.assertRaises(ValueError): self.manager(active).create_replica('1172380', 'active', 'old')

    def test_unverified_activity_blocks_creation(self):
        with self.assertRaises(ValueError): self.manager(lambda p: {'verified': False, 'active': False}).create_replica('1172380', 'active', 'old')

    def test_dry_reconcile_does_not_delete_managed_payload(self):
        result = self.create(); self.uninstall_primary()
        before = (self.state / 'ledger.json').read_bytes()
        report = self.manager().reconcile(apply=False)
        self.assertEqual(len(report['planned']), 1)
        self.assertTrue(Path(result['payload']).exists())
        self.assertEqual((self.state / 'ledger.json').read_bytes(), before)

    def test_verified_uninstall_removes_only_newly_owned_payload(self):
        result = self.create(); self.uninstall_primary()
        independent = self.root / 'independent/Jedi Fallen Order'
        independent.mkdir(parents=True); (independent / 'keep.pak').write_bytes(b'backup')
        report = self.manager().reconcile(apply=True)
        self.assertEqual(len(report['removed']), 1)
        self.assertFalse(Path(result['payload']).exists())
        self.assertFalse((self.old / 'steamapps/appmanifest_1172380.acf').exists())
        self.assertTrue((self.saves / 'keep.sav').exists())
        self.assertEqual((independent / 'keep.pak').read_bytes(), b'backup')
        self.assertTrue((self.active / 'steamapps/common/Jedi Fallen Order/payload.pak').exists())

    def test_watcher_cycle_uses_same_guarded_reconciler(self):
        result = self.create(); self.uninstall_primary()
        report = self.manager().watch_cycle()
        self.assertEqual(len(report['removed']), 1)
        self.assertFalse(Path(result['payload']).exists())

    def test_no_success_event_means_no_cleanup(self):
        result = self.create()
        (self.active / 'steamapps/appmanifest_1172380.acf').unlink()
        self.assertEqual(self.manager().reconcile(apply=True)['removed'], [])
        self.assertTrue(Path(result['payload']).exists())

    def test_keep_on_uninstall_policy_preserves_replica(self):
        result = self.create(auto_cleanup=False); self.uninstall_primary()
        self.assertEqual(self.manager().watch_cycle()['removed'], [])
        self.assertTrue(Path(result['payload']).exists())

    def test_running_destination_defers_cleanup_without_killing_it(self):
        result = self.create(); self.uninstall_primary()
        active = lambda p: {'verified': True, 'active': p['id'] == 'old', 'pids': [123]}
        report = self.manager(active).reconcile(apply=True)
        self.assertEqual(report['removed'], [])
        self.assertTrue(Path(result['payload']).exists())

    def test_changed_replica_and_new_save_are_retained(self):
        result = self.create(); self.uninstall_primary()
        (Path(result['payload']) / 'new-save.sav').write_bytes(b'preserve')
        report = self.manager().reconcile(apply=True)
        self.assertEqual(report['removed'], [])
        self.assertEqual((Path(result['payload']) / 'new-save.sav').read_bytes(), b'preserve')

    def test_source_reinstall_prevents_cleanup(self):
        result = self.create(); self.uninstall_primary(); self.game(self.active)
        self.assertEqual(self.manager().reconcile(apply=True)['removed'], [])
        self.assertTrue(Path(result['payload']).exists())

    def test_corrupt_ledger_fails_closed(self):
        self.create(); self.uninstall_primary()
        (self.state / 'ledger.json').write_text('{broken')
        with self.assertRaises(ValueError): self.manager().reconcile(apply=True)
        self.assertTrue((self.old / 'steamapps/common/Jedi Fallen Order').exists())

    def test_marker_swap_is_not_authority(self):
        result = self.create(); self.uninstall_primary()
        marker = Path(result['payload']) / M.MARKER
        data = json.loads(marker.read_text()); data['token'] = 'different'; marker.write_text(json.dumps(data))
        self.assertEqual(self.manager().reconcile(apply=True)['removed'], [])

    def test_payload_symlink_swap_is_not_followed(self):
        result = self.create(); self.uninstall_primary()
        payload = Path(result['payload']); parked = payload.with_name('untouched-backup'); payload.rename(parked); payload.symlink_to(parked)
        self.assertEqual(self.manager().reconcile(apply=True)['removed'], [])
        self.assertTrue((parked / 'payload.pak').exists())

    def test_interruption_after_quarantine_resumes_owned_transaction(self):
        result = self.create(); self.uninstall_primary()
        manager = self.manager()
        def interrupt(phase, record):
            if phase == 'quarantined': raise InterruptedError('fixture interruption')
        with mock.patch.object(manager, '_checkpoint', side_effect=interrupt):
            manager.reconcile(apply=True)
        ledger = json.loads((self.state / 'ledger.json').read_text())
        self.assertEqual(ledger['replicas'][0]['phase'], 'quarantined')
        report = self.manager().reconcile(apply=True)
        self.assertEqual(len(report['removed']), 1)
        self.assertFalse(Path(result['payload']).exists())
        self.assertTrue((self.saves / 'keep.sav').exists())

    def test_partial_delete_error_is_recoverable_and_not_reported_success(self):
        result = self.create(); self.uninstall_primary(); manager = self.manager()
        original = M.shutil.rmtree
        calls = []
        def fail_once(path, *args, **kwargs):
            if '.chardonnay-delete-' in str(path) and not calls:
                calls.append(str(path)); (Path(path) / 'payload.pak').unlink()
                raise OSError('fixture partial deletion')
            return original(path, *args, **kwargs)
        with mock.patch.object(M.shutil, 'rmtree', side_effect=fail_once):
            first = manager.reconcile(apply=True)
        self.assertEqual(first['removed'], [])
        self.assertEqual(len(calls), 1, 'the injected partial delete must actually execute')
        second = self.manager().reconcile(apply=True)
        self.assertEqual(len(second['removed']), 1)
        self.assertFalse(Path(result['payload']).exists())

    def test_unsafe_recursive_delete_backend_is_refused(self):
        result = self.create(); self.uninstall_primary()
        with mock.patch.object(M.shutil.rmtree, 'avoids_symlink_attacks', False):
            report = self.manager().reconcile(apply=True)
        self.assertEqual(report['removed'], [])
        self.assertTrue(Path(result['payload']).exists())

    def test_reconcile_is_idempotent_after_success(self):
        self.create(); self.uninstall_primary()
        self.assertEqual(len(self.manager().watch_cycle()['removed']), 1)
        self.assertEqual(self.manager().watch_cycle()['removed'], [])

    def test_failed_copy_rolls_back_only_its_owned_staging_directory(self):
        manager = self.manager()
        with mock.patch.object(M.sys, 'platform', 'linux'), mock.patch.object(M.shutil, 'copytree', side_effect=OSError('fixture copy failure')):
            with self.assertRaises(OSError): manager.create_replica('1172380', 'active', 'old')
        report = self.manager().reconcile(apply=True)
        self.assertEqual(report['removed'], [])
        self.assertEqual(list((self.old / 'steamapps/common').glob('.chardonnay-create-*')), [])
        self.assertTrue((self.active / 'steamapps/common/Jedi Fallen Order/payload.pak').exists())
        ledger = json.loads((self.state / 'ledger.json').read_text())
        self.assertEqual(ledger['replicas'][0]['phase'], 'aborted')

    def test_keep_policy_stops_an_interrupted_owned_cleanup(self):
        self.create(); self.uninstall_primary(); manager = self.manager()
        def stop(phase, record):
            if phase == 'quarantined': raise InterruptedError('fixture')
        with mock.patch.object(manager, '_checkpoint', side_effect=stop): manager.reconcile(apply=True)
        ledger = json.loads((self.state / 'ledger.json').read_text())
        ledger['replicas'][0]['cleanup_on_source_uninstall'] = False
        (self.state / 'ledger.json').write_text(json.dumps(ledger))
        # Policy changes must not silently finish a deletion against new intent.
        report = self.manager().reconcile(apply=True)
        self.assertEqual(report['removed'], [])
        self.assertTrue(list((self.old / 'steamapps/common').glob('.chardonnay-delete-*')))

    def test_cli_create_then_automatic_cycle_uses_real_guards(self):
        import os
        # A CLI boundary test, with only process inspection substituted; fixture
        # files/copy/publication/deletion and the JSON ledger are all real.
        self.assertTrue(hasattr(M, 'managed_cli'))
        config = self.root / 'config.json'
        config.write_text(json.dumps(self.config))
        quiet = lambda profile: {'verified': True, 'active': False, 'pids': []}
        with mock.patch.object(M, 'prefix_activity', side_effect=quiet):
            made = M.managed_cli(['create-replica', '1172380', '--config', str(config), '--state-dir', str(self.state), '--source-prefix', 'active', '--replica-prefix', 'old'])
            self.assertEqual(made, 0)
            self.uninstall_primary()
            self.assertEqual(M.managed_cli(['daemon', '--once', '--config', str(config), '--state-dir', str(self.state)]), 0)
        self.assertFalse((self.old / 'steamapps/common/Jedi Fallen Order').exists())

    def test_publication_interruption_is_recovered_without_adopting_old_data(self):
        manager = self.manager()
        def stop(phase, record):
            if phase == 'publishing': raise InterruptedError('fixture publication stop')
        with mock.patch.object(manager, '_checkpoint', side_effect=stop):
            with self.assertRaises(InterruptedError): manager.create_replica('1172380', 'active', 'old')
        report = self.manager().reconcile(apply=True)
        self.assertEqual(report['removed'], [])
        self.assertTrue((self.old / 'steamapps/common/Jedi Fallen Order/payload.pak').exists())
        ledger = json.loads((self.state / 'ledger.json').read_text())
        self.assertEqual(ledger['replicas'][0]['phase'], 'ready')

    def test_exited_ps_and_foreign_effective_uid_do_not_block_verified_inspection(self):
        import os, types
        uid = os.getuid()
        first = types.SimpleNamespace(returncode=0, stdout=f'10 S {uid} wine\n11 Z {uid} zombie\n12 Ss {uid + 1} login\n13 S {uid} ps\n', stderr='')
        files = types.SimpleNamespace(returncode=1, stdout='p10\nn/unrelated/path\n', stderr='')
        last = types.SimpleNamespace(returncode=0, stdout=f'10 S {uid} wine\n11 Z {uid} zombie\n12 Ss {uid + 1} login\n', stderr='')
        with mock.patch.object(M.subprocess, 'run', side_effect=[first, files, last]):
            report = M.prefix_activity(self.profiles[1])
        self.assertTrue(report['verified'])
        self.assertFalse(report['active'])

    def test_uninspected_live_own_user_process_still_blocks_inspection(self):
        import os, types
        uid = os.getuid(); table = f'10 S {uid} wine\n13 S {uid} unknown\n'
        ps = types.SimpleNamespace(returncode=0, stdout=table, stderr='')
        files = types.SimpleNamespace(returncode=1, stdout='p10\nn/unrelated/path\n', stderr='')
        with mock.patch.object(M.subprocess, 'run', side_effect=[ps, files, ps]):
            report = M.prefix_activity(self.profiles[1])
        self.assertFalse(report['verified'])

    def test_ps_lsof_failure_blocks_activity_verification(self):
        with mock.patch.object(M.subprocess, 'run', side_effect=OSError('fixture unavailable')):
            report = M.prefix_activity(self.profiles[1])
        self.assertFalse(report['verified'])

    def test_watch_install_and_unwatch_require_owned_job(self):
        self.assertTrue(hasattr(M, 'configure_storage_watch'))
        self.assertTrue(hasattr(M, 'disable_storage_watch'))
        # Platform/service execution is covered separately on macOS. A foreign
        # plist must be rejected before any launchctl operation.
        agent = self.root / 'LaunchAgents/local.chardonnay.storage.watch.plist'
        agent.parent.mkdir(); agent.write_bytes(b'foreign non-plist')
        with mock.patch.object(M.sys, 'platform', 'darwin'), mock.patch.object(M.subprocess, 'run') as run:
            with self.assertRaises(ValueError): M.configure_storage_watch('/safe/entry', '/safe/config', self.state, agent_path=agent)
        run.assert_not_called()

    def test_unwatch_job_spec_never_points_at_shortcut_agent(self):
        self.assertTrue(hasattr(M, 'storage_watch_spec'))
        spec = M.storage_watch_spec('/safe/install_merlot.command', '/safe/config.json', '/safe/state')
        self.assertEqual(spec['Label'], 'local.chardonnay.storage.watch')
        self.assertIn('daemon', spec['ProgramArguments'])
        self.assertNotIn('--programs', spec['ProgramArguments'])


if __name__ == '__main__':
    unittest.main()
