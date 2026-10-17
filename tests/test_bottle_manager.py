"""Native-manager backend contracts; real Wine/UI acceptance is separate."""
import contextlib
import io
import json
import os
from pathlib import Path
import tempfile
import types
import unittest

ROOT=Path(__file__).resolve().parents[1]
TEXT=(ROOT/'install_merlot.command').read_text()
M=types.ModuleType('bottle_manager');M.__file__=str(ROOT/'install_merlot.command')
if '# BEGIN BOTTLES PYTHON\n' in TEXT:
    exec(compile(TEXT.split('# BEGIN BOTTLES PYTHON\n',1)[1].split('# END BOTTLES PYTHON',1)[0],M.__file__,'exec'),M.__dict__)


class BottleManagerTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.root=Path(self.temp.name)
        wine=self.root/'engine/bin/wine';wine.parent.mkdir(parents=True);wine.write_bytes(b'fixture');wine.chmod(0o755)
        prefix=self.root/'existing';(prefix/'drive_c/users/test').mkdir(parents=True)
        (prefix/'drive_c/users/test/credentials.dat').write_bytes(b'must not copy')
        self.config=self.root/'shortcuts.json'
        self.config.write_text(json.dumps({'version':1,'prefixes':[{'id':'existing','name':'Existing Steam','path':str(prefix),'wine':str(wine),'role':'merlot','repo':'/known/repo','environment':{'WINE_VERSION':'11.18','WINEDLLOVERRIDES':'bcrypt=b'}}]}))
        self.state=self.root/'manager';self.calls=[]
        def run(command,**kwargs):
            self.calls.append((command,kwargs));p=Path(kwargs['env']['WINEPREFIX'])
            if 'wineboot' in command:
                (p/'drive_c/users/test').mkdir(parents=True,exist_ok=True)
                (p/'dosdevices').mkdir(exist_ok=True)
            return types.SimpleNamespace(returncode=0)
        self.fake_runner=run

    def manager(self):
        self.assertTrue(hasattr(M,'BottleManager'),'native bottle backend not implemented')
        return M.BottleManager(self.config,self.state,runner=self.fake_runner)

    def create(self):
        manager=self.manager();engines=manager.status()['engines']
        return manager,manager.create('Fixture Windows App',engines[0]['id'])

    def test_existing_profiles_import_without_config_or_prefix_changes(self):
        before=self.config.read_bytes();manager=self.manager();s=manager.status()
        self.assertEqual(len(s['bottles']),1)
        self.assertTrue(s['bottles'][0]['external'])
        self.assertEqual(self.config.read_bytes(),before)
        self.assertEqual(self.calls,[])

    def test_new_bottle_is_empty_not_a_clone_of_user_data(self):
        manager,row=self.create();p=Path(row['path'])
        self.assertTrue((p/'drive_c').is_dir())
        self.assertFalse((p/'drive_c/users/test/credentials.dat').exists())
        self.assertTrue((p/'.chardonnay-bottle.json').is_file())
        self.assertEqual(manager.status()['bottles'][-1]['phase'],'ready')

    def test_existing_name_creates_distinct_prefixes_without_overwriting(self):
        manager,row=self.create();second=manager.create(row['name'],row['engine_id'])
        self.assertNotEqual(row['path'],second['path'])
        self.assertTrue(Path(row['path']).is_dir())

    def test_new_bottle_registers_optional_shortcut_scope_without_forcing_apps(self):
        _,row=self.create();config=json.loads(self.config.read_text())
        profile=next(p for p in config['prefixes'] if p['path']==row['path'])
        self.assertEqual(profile['wine'],row['wine'])
        self.assertFalse((self.root/'Desktop').exists())
        self.assertNotEqual(profile.get('role'),'merlot')

    def test_exe_installer_path_is_an_argument_not_shell_code(self):
        manager,row=self.create();installer=self.root/"setup ' Ω $(touch nope).exe";installer.write_bytes(b'MZfixture')
        manager.install_file(row['id'],installer)
        command,kwargs=self.calls[-1]
        self.assertEqual(command,[row['wine'],str(installer)])
        self.assertEqual(kwargs['env']['WINEPREFIX'],row['path'])
        self.assertFalse((self.root/'nope').exists())

    def test_msi_uses_msiexec_and_a_windows_path(self):
        manager,row=self.create();installer=self.root/'Setup Ω.msi';installer.write_bytes(b'fixture')
        manager.install_file(row['id'],installer,quiet=True)
        command,_=self.calls[-1]
        self.assertEqual(command[:3],[row['wine'],'msiexec','/i'])
        self.assertEqual(command[3],'Z:'+str(installer).replace('/','\\'))
        self.assertIn('/qn',command)

    def test_unknown_installer_extension_is_rejected(self):
        manager,row=self.create();installer=self.root/'setup.sh';installer.write_text('anything')
        with self.assertRaises(ValueError):manager.install_file(row['id'],installer)

    def test_ambient_backend_and_prefix_cannot_override_binding(self):
        from unittest import mock
        manager,row=self.create();installer=self.root/'setup.exe';installer.write_bytes(b'MZfixture')
        with mock.patch.dict(os.environ,{'WINEPREFIX':'/wrong','CX_ACTIVE_GRAPHICS_BACKEND':'wrong','SteamAppId':'wrong'}):manager.install_file(row['id'],installer)
        env=self.calls[-1][1]['env'];self.assertEqual(env['WINEPREFIX'],row['path']);self.assertNotIn('CX_ACTIVE_GRAPHICS_BACKEND',env);self.assertNotIn('SteamAppId',env)

    def test_failed_bootstrap_is_not_reported_ready(self):
        manager=self.manager();manager.runner=lambda *a,**kw:types.SimpleNamespace(returncode=1)
        with self.assertRaises(RuntimeError):manager.create('Broken',manager.status()['engines'][0]['id'])
        self.assertIn('failed',[b['phase'] for b in manager.status()['bottles'] if not b['external']])

    def test_unavailable_engine_is_rejected_without_fallback(self):
        manager=self.manager()
        with self.assertRaises(ValueError):manager.create('Invalid','unknown-engine')

    def test_imported_steam_launch_keeps_original_merlot_route(self):
        manager=self.manager();row=manager.status()['bottles'][0]
        steam=Path(row['path'])/'drive_c/Program Files (x86)/Steam/steam.exe';steam.parent.mkdir(parents=True);steam.write_bytes(b'fixture')
        manager.launch(row['id'],'steam')
        command,kwargs=self.calls[-1]
        self.assertEqual(command,['/bin/bash','/known/repo/run.command'])
        self.assertEqual(kwargs['env']['WINEPREFIX'],row['path'])

    def add_steam_manifest(self,row,appid,name):
        root=Path(row['path'])/'drive_c/Program Files (x86)/Steam';root.mkdir(parents=True,exist_ok=True)
        (root/'steam.exe').write_bytes(b'fixture');(root/'steamapps').mkdir(exist_ok=True)
        (root/'steamapps'/('appmanifest_'+appid+'.acf')).write_text('"AppState" { "appid" "'+appid+'" "name" "'+name+'" "StateFlags" "4" }')

    def test_steam_redistributable_is_not_a_launchable_game(self):
        manager=self.manager();row=manager.status()['bottles'][0]
        self.add_steam_manifest(row,'228980','Steamworks Common Redistributables')
        self.assertNotIn('steam-228980',[a['id'] for a in manager.apps(row)])

    def test_steam_game_keeps_appid_in_bound_merlot_environment(self):
        manager=self.manager();row=manager.status()['bottles'][0]
        self.add_steam_manifest(row,'123456','Fixture Game')
        manager.launch(row['id'],'steam-123456')
        command,kwargs=self.calls[-1]
        self.assertEqual(command,['/bin/bash','/known/repo/run.command'])
        self.assertEqual(kwargs['env']['STEAM_GAME_ID'],'123456')

    def test_installer_exit_does_not_claim_application_compatibility(self):
        manager,row=self.create();installer=self.root/'setup.exe';installer.write_bytes(b'MZfixture')
        result=manager.install_file(row['id'],installer)
        self.assertTrue(result['installer_process_finished'])
        self.assertNotIn('application_works',result)


if __name__=='__main__':unittest.main()
