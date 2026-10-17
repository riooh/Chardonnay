"""Real Aqua -> Cocoa button -> backend -> Wine -> EXE/MSI/link acceptance.

Uses an EMPTY private prefix and a private shortcut config. No existing bottle,
Desktop app, account session, engine binding or game payload is changed.
"""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
import uuid

ROOT=Path(__file__).resolve().parents[1]


@unittest.skipUnless(sys.platform=='darwin','requires macOS/Aqua and the configured Wine stack')
class NativeBottleManagerTests(unittest.TestCase):
    def test_real_native_buttons_exe_msi_and_installed_app(self):
        real_config=Path.home()/'.config/chardonnay-shortcuts/config.json'
        if not real_config.is_file():self.skipTest('configured Wine stack unavailable')
        before_config=real_config.read_bytes();config=json.loads(before_config)
        desired=os.environ.get('CHARDONNAY_TEST_PROFILE')
        profile=next((p for p in config['prefixes'] if (p.get('id')==desired if desired else p.get('role')=='merlot') and os.access(p.get('wine',''),os.X_OK)),None)
        if not profile:self.skipTest('stable configured Wine engine unavailable')
        helper=Path.home()/'.cache/chardonnay-shortcuts/ShortcutInfo.exe'
        compiler=Path('/opt/homebrew/bin/x86_64-w64-mingw32-gcc')
        if not helper.is_file() or not compiler.is_file():self.skipTest('Wine shortcut helper or mingw-w64 unavailable')
        artifacts=Path(os.environ.get('CHARDONNAY_TEST_ARTIFACTS',str(Path.home()/'Library/Caches/ChardonnayTests')))
        artifacts.mkdir(parents=True,exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='native-',dir=str(artifacts)) as temporary:
            root=Path(temporary);app=root/'Chardonnay Acceptance.app';state=root/'state';config_path=root/'shortcuts.json';report=root/'GUI_RESULT.json'
            anchor=root/'engine-anchor';(anchor/'drive_c/users/test').mkdir(parents=True)
            binding={'id':'fixture-engine','name':'Private engine binding','path':str(anchor),'wine':profile['wine'],'environment':profile.get('environment',{})}
            config_path.write_text(json.dumps({'version':1,'output_dir':str(root/'private-desktop'),'prefixes':[binding]}))
            env=dict(os.environ);env['DEVELOPER_DIR']='/Applications/Xcode.app/Contents/Developer'
            build=subprocess.run(['/bin/bash',str(ROOT/'install_merlot.command'),'--bottles','install-manager','--destination',str(app)],env=env,capture_output=True,text=True,timeout=120)
            self.assertEqual(build.returncode,0,build.stdout+build.stderr)
            info_path=app/'Contents/Info.plist';info=plistlib.loads(info_path.read_bytes());info['CFBundleIdentifier']='local.chardonnay.manager.acceptance.'+uuid.uuid4().hex;info_path.write_bytes(plistlib.dumps(info))
            subprocess.run(['/usr/bin/codesign','--force','--sign','-',str(app)],check=True,capture_output=True,timeout=30)
            installer=root/'Installer Ω.exe';builder=root/'BuildMsi.exe';msi=root/'Fixture Ω.msi'
            commands=[
                [str(compiler),'-municode','-mwindows','-O2','-Wall','-Wextra','-Werror',str(ROOT/'tests/fixtures/native_installer_probe.c'),'-o',str(installer),'-lole32','-lshell32','-luuid','-ladvapi32'],
                [str(compiler),'-municode','-O2','-Wall','-Wextra','-Werror',str(ROOT/'tests/fixtures/build_msi_probe.c'),'-o',str(builder),'-lmsi','-loleaut32'],
            ]
            for arch,compiler_name in [('32','i686-w64-mingw32-gcc'),('64','x86_64-w64-mingw32-gcc')]:
                commands.append(['/opt/homebrew/bin/'+compiler_name,'-municode','-mwindows','-O2','-Wall','-Wextra','-Werror',str(ROOT/'tests/fixtures/mshtml_probe.c'),'-o',str(root/('GeckoProbe'+arch+'.exe')),'-lole32','-loleaut32','-luuid'])
            for command in commands:
                result=subprocess.run(command,env=env,capture_output=True,text=True,timeout=120)
                self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            spec={'config':str(config_path),'state_dir':str(state),'report':str(report),'bottle_name':'Private Installer Fixture','launch_name':'Chardonnay Fixture','fixtures':[{'path':str(installer)},{'path':str(msi),'quiet':True},{'path':str(root/'GeckoProbe64.exe')},{'path':str(root/'GeckoProbe32.exe')}]}
            spec_path=root/'acceptance.json';spec_path.write_text(json.dumps(spec,ensure_ascii=False))
            server=Path(profile['wine']).parent/'wineserver'
            try:
                subprocess.run(['/usr/bin/open',str(app),'--args','--acceptance',str(spec_path)],check=True,capture_output=True,timeout=15)
                deadline=time.monotonic()+240;reopened=False;original_host=None
                while time.monotonic()<deadline and not report.exists():
                    if not reopened and (state/'bottles.json').exists():
                        processes=subprocess.run(['/bin/ps','-axo','pid=,command='],capture_output=True,text=True,check=True,timeout=10)
                        needle=str(app/'Contents/MacOS/Chardonnay')
                        hosts=[int(line.strip().split(None,1)[0]) for line in processes.stdout.splitlines() if needle in line]
                        if len(hosts)==1:
                            original_host=hosts[0];subprocess.run(['/usr/bin/open',str(app)],check=True,capture_output=True,timeout=15);reopened=True
                    time.sleep(0.4)
                self.assertTrue(report.exists(),'native app did not finish; private diagnostics at '+str(root))
                result=json.loads(report.read_text());saved=artifacts/('GUI_RESULT-'+uuid.uuid4().hex+'.json');saved.write_text(json.dumps(result,indent=2))
                screenshot=report.with_name(report.name+'.png')
                if screenshot.is_file():shutil.copy2(screenshot,saved.with_suffix('.png'))
                compositor=report.with_name(report.name+'.compositor.png')
                if compositor.is_file():shutil.copy2(compositor,saved.with_suffix('.compositor.png'))
                self.assertTrue(result['success'],result)
                self.assertTrue(result['window_visible']);self.assertEqual(result['window_title'],'Chardonnay')
                self.assertTrue(reopened,'ordinary-open test never ran while the first worker was active')
                self.assertEqual(result['pid'],original_host,'ordinary reopen replaced the manager host')
                self.assertEqual(len(result['events']),len(spec['fixtures'])+2,result)
                prefix=Path(result['bottle_path']);self.assertEqual(prefix.parent,state/'bottles')
                self.assertEqual(json.loads((prefix/'.chardonnay-bottle.json').read_text())['id'],result['bottle_id'])
                marker=(prefix/'drive_c/ChardonnayFixture-launch.txt').read_text(encoding='utf-8')
                self.assertIn('argv=--launch-probe Ω',marker)
                self.assertIn('cwd=C:\\Program Files\\Chardonnay Fixture',marker)
                self.assertIn('prefix='+str(prefix),marker)
                self.assertIn('msi=passed',marker)
                for arch in ['32','64']:
                    gecko=(prefix/'drive_c'/('ChardonnayGecko-'+arch+'.txt')).read_text()
                    self.assertIn('passed=1',gecko);self.assertIn('architecture='+arch,gecko);self.assertIn('2.47.4',gecko)
                operation_log=(state/'logs'/(result['bottle_id']+'.log')).read_text(errors='replace')
                self.assertNotIn('Could not find Wine Gecko',operation_log)
                self.assertTrue((prefix/'drive_c/ChardonnayFixture-install.txt').is_file())
                self.assertFalse((root/'private-desktop').exists(),'test forced a public/native Desktop launcher')
                self.assertEqual(real_config.read_bytes(),before_config,'test rewrote real prefix bindings')
                self.assertTrue(saved.exists());print('Native manager acceptance:',saved,flush=True)
            finally:
                logs=state/'logs'
                if logs.is_dir():
                    saved_logs=artifacts/('fixture-logs-'+uuid.uuid4().hex);saved_logs.mkdir()
                    for logfile in logs.glob('*.log'):
                        if logfile.stat().st_size<2*1024*1024:shutil.copy2(logfile,saved_logs/logfile.name)
                registry=state/'bottles.json'
                if registry.is_file():
                    for row in json.loads(registry.read_text()).get('bottles',[]):
                        prefix=Path(row['path'])
                        if prefix.parent!=state/'bottles' or not (prefix/'.chardonnay-bottle.json').is_file():raise RuntimeError('refusing unowned fixture cleanup')
                        for textfile in (prefix/'drive_c').glob('Chardonnay*.txt'):
                            shutil.copy2(textfile,artifacts/(row['id']+'-'+textfile.name))
                        stop_env=dict(env);stop_env['WINEPREFIX']=str(prefix)
                        subprocess.run([str(server),'-k'],env=stop_env,capture_output=True,timeout=20,check=True)
                        subprocess.run([str(server),'-w'],env=stop_env,capture_output=True,timeout=20,check=True)
                self.assertEqual(real_config.read_bytes(),before_config)


if __name__=='__main__':unittest.main()
