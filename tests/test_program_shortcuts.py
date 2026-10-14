import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import types
import unittest

ROOT = Path(__file__).resolve().parents[1]
TEXT = (ROOT / 'install_merlot.command').read_text()
BEGIN = "# BEGIN PROGRAMS PYTHON\n"
END = "# END PROGRAMS PYTHON"
MODULE = types.ModuleType('shortcut_importer')
MODULE.__file__ = str(ROOT / 'install_merlot.command')
exec(compile(TEXT.split(BEGIN, 1)[1].split(END, 1)[0], MODULE.__file__, 'exec'), MODULE.__dict__)


class ImporterTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        # Pure unit fixtures must not register fake apps with LaunchServices
        # or run icon conversion; the separate Mac E2E covers those paths.
        import unittest.mock
        platform_patch = unittest.mock.patch.object(MODULE.sys, 'platform', 'test')
        platform_patch.start()
        self.addCleanup(platform_patch.stop)
        self.root = Path(self.tmp.name)
        self.desktop = self.root / 'Mac Desktop'
        self.desktop.mkdir()
        self.prefix = self.root / "Bottle's Unicode Ω"
        self.source = self.prefix / 'drive_c/users/test/Wine Shortcuts'
        self.start = self.prefix / 'drive_c/ProgramData/Microsoft/Windows/Start Menu/Programs'
        self.source.mkdir(parents=True)
        self.start.mkdir(parents=True)
        self.metadata = {}
        self.config = {'output_dir': str(self.desktop), 'entrypoint': '/safe/path with spaces/entrypoint.command', 'prefixes': [
            {'id': 'test', 'name': 'Test Bottle', 'path': str(self.prefix), 'wine': '/safe/wine', 'environment': {'WINEDEBUG': '-all'}}]}
        self.imp = MODULE.Importer(self.config, self.root / 'state', inspect=lambda p, profile: self.metadata[str(p)])

    def link(self, directory=None, name='Example.lnk', target=r'C:\Program Files\Example\app.exe', args='', cwd=''):
        p = (directory or self.source) / name
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(b'fixture shell link')
        os.utime(p, (1, 1))
        self.metadata[str(p)] = {'target': target, 'arguments': args, 'working_dir': cwd, 'icon': '', 'icon_index': 0}
        return p

    def sync(self):
        with contextlib.redirect_stdout(io.StringIO()):
            return self.imp.sync()

    def apps(self):
        return sorted(self.desktop.glob('*.app'))

    def test_desktop_and_start_menu_are_deduplicated(self):
        self.link()
        self.link(self.start)
        self.sync()
        self.assertEqual(len(self.apps()), 1)
        self.assertEqual(len(self.imp.manifest['entries']), 1)

    def test_argument_variants_remain_distinct(self):
        self.link(name='Normal.lnk')
        self.link(name='Safe Mode.lnk', args='--safe')
        self.sync()
        self.assertEqual(len(self.apps()), 2)

    def test_user_app_is_never_overwritten(self):
        user = self.desktop / 'Example.app'
        user.mkdir()
        (user / 'keep.txt').write_text('untouched')
        self.link()
        self.sync()
        self.assertEqual((user / 'keep.txt').read_text(), 'untouched')
        self.assertEqual(len(self.apps()), 2)

    def test_removed_shortcut_is_archived_not_deleted(self):
        p = self.link()
        self.sync()
        p.unlink()
        self.sync()
        self.assertEqual(self.apps(), [])
        self.assertEqual(len(list((self.root / 'state/Retired').glob('*.app'))), 1)

    def test_inspector_failure_preserves_owned_launcher(self):
        p = self.link()
        self.sync()
        del self.metadata[str(p)]
        p.write_bytes(b'changed incomplete fixture')
        self.sync()
        self.assertEqual(len(self.apps()), 1)

    def test_unreadable_root_preserves_launchers(self):
        self.link()
        self.sync()
        old = self.imp.scan
        def fail():
            raise PermissionError('source unavailable')
        self.imp.scan = fail
        with self.assertRaises(PermissionError):
            self.sync()
        self.imp.scan = old
        self.assertEqual(len(self.apps()), 1)

    def test_bundle_is_unicode_safe_and_does_not_interpolate_shortcut(self):
        self.link(name="Quote ' Ω $(touch PWNED).lnk", args='--name "A & B"')
        self.sync()
        app = self.apps()[0]
        descriptor = json.loads((app / 'Contents/Resources/shortcut.json').read_text())
        self.assertEqual(descriptor['metadata']['arguments'], '--name "A & B"')
        script = (app / 'Contents/MacOS/launch').read_text()
        self.assertNotIn('touch PWNED', script)
        self.assertIn('--programs launch', script)
        self.assertTrue((app / 'Contents/MacOS/launch').stat().st_mode & 0o111)
        self.assertEqual(descriptor['profile']['path'], str(self.prefix))

    def test_internet_shortcut_protocol_is_validated(self):
        p = self.source / 'Bad.url'
        p.write_text('[InternetShortcut]\nURL=javascript:alert(1)\n')
        os.utime(p, (1, 1))
        self.sync()
        self.assertEqual(self.apps(), [])

    def test_steam_url_keeps_correct_prefix(self):
        p = self.source / 'Steam Game.url'
        p.write_text('[InternetShortcut]\nURL=steam://rungameid/12345\n')
        os.utime(p, (1, 1))
        self.sync()
        d = json.loads((self.apps()[0] / 'Contents/Resources/shortcut.json').read_text())
        self.assertEqual(d['metadata']['target'], 'steam://rungameid/12345')
        self.assertEqual(d['profile']['id'], 'test')

    def test_start_menu_maintenance_links_are_not_desktop_clutter(self):
        self.link(self.start, name='App Recovery.lnk')
        self.sync()
        self.assertEqual(self.apps(), [])

    def test_repeated_sync_is_idempotent(self):
        self.link()
        self.sync()
        app = self.apps()[0]
        before = (app / 'Contents/Info.plist').stat().st_mtime_ns
        self.sync()
        self.assertEqual((app / 'Contents/Info.plist').stat().st_mtime_ns, before)

    def test_excluded_secondary_client_is_retired(self):
        self.link(name='Steam.lnk')
        self.sync()
        self.config['prefixes'][0]['exclude_names'] = ['Steam']
        self.sync()
        self.assertEqual(self.apps(), [])
        self.assertEqual(len(list((self.root / 'state/Retired').glob('*.app'))), 1)

    def test_plain_name_is_reclaimed_after_duplicate_is_removed(self):
        user = self.desktop / 'Example.app'
        user.mkdir()
        self.link()
        self.sync()
        self.assertEqual(len(self.apps()), 2)
        user.rmdir()
        self.config['prefixes'][0]['prefer_plain_name'] = True
        self.sync()
        self.assertEqual([p.name for p in self.apps()], ['Example.app'])

    def test_malformed_url_does_not_remove_good_apps(self):
        self.link()
        self.sync()
        bad = self.source / 'Broken.url'
        bad.write_text('not an internet shortcut')
        os.utime(bad, (1, 1))
        self.sync()
        self.assertEqual(len(self.apps()), 1)
        self.assertFalse(self.imp.complete)

    def test_ambient_graphics_backend_cannot_leak_between_bottles(self):
        import unittest.mock
        with unittest.mock.patch.dict(os.environ, {'CX_ACTIVE_GRAPHICS_BACKEND': 'wrong', 'CX_APPLEGPTK_LIBD3DSHARED_PATH': '/wrong'}):
            env = MODULE.profile_env(self.config['prefixes'][0])
        self.assertNotIn('CX_ACTIVE_GRAPHICS_BACKEND', env)
        self.assertNotIn('CX_APPLEGPTK_LIBD3DSHARED_PATH', env)
        self.assertEqual(env['WINEPREFIX'], str(self.prefix))

    def test_ea_policy_follows_target_not_shortcut_name(self):
        import unittest.mock
        target = self.prefix / 'drive_c/EA/current/EADesktop.exe'
        target.parent.mkdir(parents=True)
        target.write_bytes(b'fixture')
        profile = dict(self.config['prefixes'][0], target_overrides={
            'EALauncher.exe': {'target_glob': 'drive_c/EA/*/EADesktop.exe', 'arguments': ['--in-process-gpu', '--no-sandbox']}})
        descriptor = self.root / 'launcher.json'
        descriptor.write_text(json.dumps({'managed_by': MODULE.OWNER, 'id': 'test-ea', 'name': 'Renamed EA Shortcut',
            'source': str(self.source / 'Renamed EA Shortcut.lnk'), 'profile': profile,
            'metadata': {'target': r'C:\Program Files\EA\EALauncher.exe', 'working_dir': ''}}))
        result = types.SimpleNamespace(returncode=0)
        with unittest.mock.patch.object(MODULE, 'STATE', self.root / 'launch-state'), unittest.mock.patch.object(MODULE.subprocess, 'run', return_value=result) as run:
            self.assertEqual(MODULE.launch(descriptor), 0)
        self.assertEqual(run.call_args.args[0], ['/safe/wine', str(target), '--in-process-gpu', '--no-sandbox'])

    def test_client_override_cannot_swallow_game_link_arguments(self):
        import unittest.mock
        profile = dict(self.config['prefixes'][0], target_overrides={
            'EALauncher.exe': {'target_glob': 'drive_c/EA/*/EADesktop.exe', 'arguments': ['--in-process-gpu']}})
        descriptor = self.root / 'game.json'
        source = str(self.source / 'Game.lnk')
        descriptor.write_text(json.dumps({'managed_by': MODULE.OWNER, 'id': 'test-game', 'name': 'Game',
            'source': source, 'profile': profile,
            'metadata': {'target': r'C:\EA\EALauncher.exe', 'arguments': 'origin2://game/launch', 'working_dir': ''}}))
        result = types.SimpleNamespace(returncode=0)
        with unittest.mock.patch.object(MODULE, 'STATE', self.root / 'launch-state'), unittest.mock.patch.object(MODULE.subprocess, 'run', return_value=result) as run:
            self.assertEqual(MODULE.launch(descriptor), 0)
        self.assertEqual(run.call_args.args[0], ['/safe/wine', 'start', '/unix', source])

    def test_same_name_in_different_prefixes_stays_separate(self):
        self.link()
        second = dict(self.config['prefixes'][0], id='other', name='Other Bottle')
        self.config['prefixes'].append(second)
        self.sync()
        self.assertEqual(len(self.apps()), 2)


if __name__ == '__main__':
    unittest.main()
