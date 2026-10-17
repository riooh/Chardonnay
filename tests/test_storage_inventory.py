"""Read-only storage inventory/planner. Does not alter shortcut policy."""
import hashlib
import json
import os
from pathlib import Path
import tempfile
import types
import unittest

ROOT = Path(__file__).resolve().parents[1]
TEXT = (ROOT / 'install_merlot.command').read_text()
MODULE = types.ModuleType('storage_inventory')
MODULE.__file__ = str(ROOT / 'install_merlot.command')
exec(compile(TEXT.split('# BEGIN STORAGE PYTHON\n', 1)[1].split('# END STORAGE PYTHON', 1)[0], MODULE.__file__, 'exec'), MODULE.__dict__)


class StorageTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        # macOS /var aliases /private/var; fixture ownership records use the
        # same canonical identity as the production inventory, regardless of TMPDIR.
        self.root = Path(self.tmp.name).resolve()
        self.profiles = []
        self.active = self.prefix('active', 'active')
        self.old = self.prefix('old', 'protected')
        self.config = {'version': 1, 'prefixes': self.profiles, 'replicas': []}

    def prefix(self, ident, role):
        p = self.root / ident
        (p / 'drive_c/users').mkdir(parents=True)
        steam = p / 'drive_c/Program Files (x86)/Steam'
        (steam / 'steamapps/common').mkdir(parents=True)
        self.profiles.append({'id': ident, 'path': str(p), 'storage_role': role})
        return steam

    def game(self, steam, appid='1172380', title='Jedi Fallen Order', flags='4'):
        game = steam / 'steamapps/common' / title
        game.mkdir(parents=True, exist_ok=True)
        (game / 'payload.pak').write_bytes(b'payload' * 100)
        manifest = steam / 'steamapps' / ('appmanifest_' + appid + '.acf')
        manifest.write_text('"AppState" { "appid" "' + appid + '" "name" "' + title + '" "installdir" "' + title + '" "StateFlags" "' + flags + '" }')
        return game, manifest

    def audit(self):
        return MODULE.inventory(self.config)

    def plan(self):
        return MODULE.uninstall_plan(self.config, self.audit(), '1172380', 'active')

    def enroll_fixture(self):
        game, manifest = self.game(self.old)
        self.profiles[1]['storage_role'] = 'managed_replica'
        marker = {'managed_by': MODULE.OWNER, 'replica_id': 'fixture', 'appid': '1172380', 'token': 'fixture-secret-ownership-token'}
        (game / MODULE.MARKER).write_text(json.dumps(marker))
        usage = MODULE.payload_usage(game)
        logs = self.active / 'logs'
        logs.mkdir()
        log = logs / 'content_log.txt'
        log.write_text('historical events\n')
        st = log.stat()
        record = dict(marker, source_prefix_id='active', replica_prefix_id='old', library=str(self.old), install_dir='Jedi Fallen Order',
                      device=game.stat().st_dev, inode=game.stat().st_ino, manifest_sha256=hashlib.sha256(manifest.read_bytes()).hexdigest(),
                      metadata_fingerprint=usage['metadata_fingerprint'], source_log_device=st.st_dev, source_log_inode=st.st_ino, source_log_offset=st.st_size)
        self.config['replicas'].append(record)
        return game, manifest, log

    def test_two_prefix_copies_have_distinct_installation_identity(self):
        self.game(self.active)
        self.game(self.old)
        report = self.audit()
        self.assertEqual(len(report['installations']), 2)
        self.assertEqual(len(set(x['installation_id'] for x in report['installations'])), 2)
        self.assertIsNone(report['exclusive_reclaimable_bytes'])
        self.assertEqual(report['duplicate_appids'], ['1172380'])

    def test_default_registered_prefix_is_active_not_disposable(self):
        self.profiles[1].pop('storage_role')
        self.game(self.old)
        self.assertEqual(self.audit()['installations'][0]['role'], 'active')
        self.assertEqual(self.plan()['cleanup_candidates'], [])

    def test_protected_original_is_not_an_automatic_cleanup_candidate(self):
        self.game(self.old)
        plan = self.plan()
        self.assertEqual(plan['cleanup_candidates'], [])
        self.assertEqual(plan['retained'][0]['reason'], 'not_explicitly_managed_replica')

    def test_missing_prefix_blocks_all_cleanup_plans(self):
        game, manifest, log = self.enroll_fixture()
        with log.open('a') as f: f.write('AppID 1172380 finished uninstall (No Error)\n')
        self.profiles.append({'id': 'offline', 'path': str(self.root / 'missing')})
        self.assertFalse(self.audit()['complete_scan'])
        self.assertEqual(self.plan()['cleanup_candidates'], [])

    def test_corrupt_manifest_is_reported_not_interpreted_as_uninstall(self):
        _, manifest = self.game(self.active)
        manifest.write_text('"AppState" {')
        report = self.audit()
        self.assertFalse(report['complete_scan'])
        self.assertTrue(report['warnings'])

    def test_payload_symlink_is_not_followed(self):
        game, _ = self.game(self.old)
        outside = self.root / 'private'
        outside.write_bytes(b'private')
        (game / 'escape').symlink_to(outside)
        report = self.audit()
        self.assertFalse(report['complete_scan'])
        self.assertEqual(outside.read_bytes(), b'private')

    def test_manifest_path_traversal_is_rejected(self):
        _, manifest = self.game(self.old)
        manifest.write_text(manifest.read_text().replace('"installdir" "Jedi Fallen Order"', '"installdir" "../private"'))
        self.assertFalse(self.audit()['complete_scan'])

    def test_library_alias_is_not_double_counted(self):
        self.game(self.old)
        folders = self.old / 'steamapps/libraryfolders.vdf'
        folders.write_text('"libraryfolders" { "0" { "path" "' + str(self.old) + '" } }')
        self.assertEqual(len(self.audit()['installations']), 1)

    def test_missing_optional_shortcut_has_no_effect_on_inventory(self):
        self.game(self.active, appid='3241660', title='R.E.P.O.')
        self.assertEqual(self.audit()['installations'][0]['appid'], '3241660')
        self.assertFalse((self.root / 'Desktop').exists())

    def test_managed_marker_alone_is_not_ownership(self):
        game, _ = self.game(self.old)
        self.profiles[1]['storage_role'] = 'managed_replica'
        (game / MODULE.MARKER).write_text(json.dumps({'managed_by': MODULE.OWNER, 'appid': '1172380'}))
        self.assertEqual(self.plan()['cleanup_candidates'], [])

    def test_owned_replica_requires_fresh_successful_source_uninstall(self):
        game, manifest, log = self.enroll_fixture()
        self.assertEqual(self.plan()['cleanup_candidates'], [])
        with log.open('a') as f: f.write('AppID 1172380 finished uninstall (No Error)\n')
        plan = self.plan()
        self.assertEqual(len(plan['cleanup_candidates']), 1)
        self.assertTrue(plan['read_only'])
        self.assertFalse(plan['apply_supported'])
        self.assertEqual(plan['cleanup_candidates'][0]['payload'], str(game))
        self.assertTrue(game.exists())
        self.assertTrue(manifest.exists())

    def test_reinstalled_primary_blocks_replica_cleanup(self):
        _, _, log = self.enroll_fixture()
        with log.open('a') as f: f.write('AppID 1172380 finished uninstall (No Error)\n')
        self.game(self.active)
        self.assertEqual(self.plan()['cleanup_candidates'], [])

    def test_modified_replica_is_protected(self):
        game, _, log = self.enroll_fixture()
        with log.open('a') as f: f.write('AppID 1172380 finished uninstall (No Error)\n')
        (game / 'user-save.dat').write_bytes(b'do not lose this')
        plan = self.plan()
        self.assertEqual(plan['cleanup_candidates'], [])
        self.assertIn('replica_payload_changed', [x['reason'] for x in plan['retained']])

    def test_rotated_source_log_cannot_validate_uninstall(self):
        _, _, log = self.enroll_fixture()
        log.rename(log.with_suffix('.old'))
        log.write_text('AppID 1172380 finished uninstall (No Error)\n')
        self.assertEqual(self.plan()['cleanup_candidates'], [])

    def test_fingerprint_and_inventory_are_deterministic(self):
        self.game(self.old)
        a = self.audit()['installations']
        b = self.audit()['installations']
        self.assertEqual(a, b)

    def test_invalid_appid_is_not_normalized(self):
        self.game(self.old)
        with self.assertRaises(ValueError): MODULE.uninstall_plan(self.config, self.audit(), '01172380', 'active')

    def test_alias_of_primary_cannot_be_treated_as_disposable_replica(self):
        _, _, log = self.enroll_fixture()
        with log.open('a') as f: f.write('AppID 1172380 finished uninstall (No Error)\n')
        self.profiles[0]['path'] = self.profiles[1]['path']
        self.assertEqual(self.plan()['cleanup_candidates'], [])

    def test_external_library_windows_path_is_mapped_and_audited(self):
        external = self.root / 'old/drive_c/External Steam'
        self.game(external)
        folders = self.old / 'steamapps/libraryfolders.vdf'
        folders.write_text('"libraryfolders" { "1" { "path" "C:\\\\External Steam" } }')
        report = self.audit()
        self.assertTrue(report['complete_scan'])
        self.assertEqual(len(report['installations']), 1)
        self.assertEqual(report['installations'][0]['library'], str(external))

    def test_cli_plan_is_real_json_and_does_not_change_fixture_files(self):
        import subprocess
        self.game(self.old)
        config = self.root / 'config.json'
        config.write_text(json.dumps(self.config))
        def snapshot():
            return {str(p.relative_to(self.root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in self.root.rglob('*') if p.is_file()}
        before = snapshot()
        completed = subprocess.run(['/bin/bash', str(ROOT / 'install_merlot.command'), '--storage', 'plan', '1172380', '--config', str(config), '--primary-prefix', 'active'], capture_output=True, text=True, check=True)
        report = json.loads(completed.stdout)
        self.assertEqual(report['cleanup_candidates'], [])
        self.assertFalse(report['apply_supported'])
        self.assertEqual(before, snapshot())

    def test_storage_module_has_no_mutating_cli_or_shortcut_generation(self):
        source = TEXT.split('# BEGIN STORAGE PYTHON\n', 1)[1].split('# BEGIN MANAGED STORAGE', 1)[0]
        for forbidden in ['shutil.rmtree', '.unlink(', '.write_text(', 'os.remove(', 'Importer(', 'subprocess.run(']:
            self.assertNotIn(forbidden, source)


if __name__ == '__main__':
    unittest.main()
