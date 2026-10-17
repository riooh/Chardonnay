"""Real Cocoa confirmation buttons -> native inspection/signals -> private Wine.

Only newly created EMPTY fixture prefixes are terminated. The intentionally
TERM-resistant fixture is a native process, not a Wine compatibility claim.
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


@unittest.skipUnless(sys.platform=='darwin','requires macOS/Aqua and configured Wine')
class NativeRuntimeTests(unittest.TestCase):
    def test_real_native_runtime_controls(self):
        config_path=Path.home()/'.config/chardonnay-shortcuts/config.json'
        if not config_path.is_file():self.skipTest('configured stack unavailable')
        original=config_path.read_bytes();config=json.loads(original)
        profile=next((p for p in config['prefixes'] if p.get('role')=='merlot' and os.access(p.get('wine',''),os.X_OK)),None)
        compiler=Path('/opt/homebrew/bin/x86_64-w64-mingw32-gcc')
        if not profile or not compiler.is_file():self.skipTest('stable Wine or fixture compiler unavailable')
        artifacts=Path(os.environ.get('CHARDONNAY_TEST_ARTIFACTS',str(Path.home()/'Library/Caches/ChardonnayTests')));artifacts.mkdir(parents=True,exist_ok=True)
        env=dict(os.environ);env['DEVELOPER_DIR']='/Applications/Xcode.app/Contents/Developer'
        with tempfile.TemporaryDirectory(prefix='runtime-',dir=str(artifacts)) as temporary:
            root=Path(temporary).resolve();state=root/'state';private_config=root/'shortcuts.json';app=root/'Runtime Acceptance.app';report=root/'RESULT.json'
            anchor=root/'anchor';(anchor/'drive_c').mkdir(parents=True)
            private_config.write_text(json.dumps({'version':1,'output_dir':str(root/'private-desktop'),'prefixes':[{'id':'engine','name':'Fixture engine','path':str(anchor),'wine':profile['wine'],'environment':profile.get('environment',{})}]}))
            build=subprocess.run(['/bin/bash',str(ROOT/'install_merlot.command'),'--bottles','install-manager','--destination',str(app)],capture_output=True,text=True,env=env,timeout=120)
            self.assertEqual(build.returncode,0,build.stdout+build.stderr)
            info=app/'Contents/Info.plist';value=plistlib.loads(info.read_bytes());value['CFBundleIdentifier']='local.chardonnay.manager.acceptance.'+uuid.uuid4().hex;info.write_bytes(plistlib.dumps(value));subprocess.run(['/usr/bin/codesign','--force','--sign','-',str(app)],check=True,capture_output=True,timeout=30)
            installer=root/'RuntimeInstaller.exe';native=root/'native/wine';native.parent.mkdir()
            for command in [[str(compiler),'-municode','-mwindows','-O2','-Wall','-Wextra','-Werror',str(ROOT/'tests/fixtures/runtime_process_probe.c'),'-o',str(installer),'-lole32','-lshell32','-luuid'],['/usr/bin/clang','-O2','-Wall','-Wextra','-Werror',str(ROOT/'tests/fixtures/runtime_stubborn_probe.c'),'-o',str(native)]]:
                result=subprocess.run(command,capture_output=True,text=True,env=env,timeout=120);self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            specification={'workflow':'runtime','config':str(private_config),'state_dir':str(state),'report':str(report),'bottle_name':'Runtime Control Fixture','launch_name':'Runtime Fixture','fixtures':[{'path':str(installer)}],'stubborn_executable':str(native)}
            spec=root/'spec.json';spec.write_text(json.dumps(specification))
            server=Path(profile['wine']).parent/'wineserver'
            try:
                subprocess.run(['/usr/bin/open',str(app),'--args','--acceptance',str(spec)],check=True,capture_output=True,timeout=15)
                deadline=time.monotonic()+int(os.environ.get('CHARDONNAY_RUNTIME_TEST_TIMEOUT','240'))
                while time.monotonic()<deadline and not report.exists():time.sleep(0.3)
                self.assertTrue(report.exists(),'runtime UI timed out: '+str(root))
                result=json.loads(report.read_text());saved=artifacts/('RUNTIME_RESULT-'+uuid.uuid4().hex+'.json');saved.write_text(json.dumps(result,indent=2))
                for suffix in ['.png','.compositor.png']:
                    image=Path(str(report)+suffix)
                    if image.exists():shutil.copy2(image,Path(str(saved)+suffix))
                self.assertTrue(result['success'],result);self.assertTrue(result['runtime_window_visible'])
                self.assertGreaterEqual(len([e for e in result['events'] if e.startswith('runtime-native-')]),7,result)
                actions=result['runtime_results'];self.assertEqual([a['action'] for a in actions[:3]],['terminate','force-process','restart'])
                self.assertEqual([a['action'] for a in actions[-2:]],['quit-all','force-all'])
                restarted=[a for a in actions if a['launch_dispatched']];self.assertEqual(len(restarted),1);self.assertTrue(restarted[0]['stopped'])
                self.assertFalse(actions[-2]['stopped']);self.assertTrue(actions[-1]['stopped'])
                self.assertTrue(all(not a['automatic_escalation'] for a in actions))
                prefix=Path(result['bottle_path']);self.assertEqual(prefix.parent,state/'bottles')
                launches=(prefix/'drive_c/ChardonnayRuntime-launch.txt').read_text().splitlines();self.assertEqual(len(launches),4,launches)
                self.assertEqual(len(set(launches)),4,'restart did not create a new Windows process')
                self.assertEqual(config_path.read_bytes(),original);self.assertFalse((root/'private-desktop').exists())
                print('Native runtime acceptance:',saved,flush=True)
            finally:
                evidence=artifacts/('runtime-evidence-'+uuid.uuid4().hex);evidence.mkdir()
                for source in [state/'manager-status.json',state/'runtime/last-action.json',report]:
                    if source.is_file():shutil.copy2(source,evidence/source.name)
                if (state/'logs').is_dir():shutil.copytree(state/'logs',evidence/'logs')
                if (state/'runtime').is_dir():shutil.copytree(state/'runtime',evidence/'runtime')
                # No broad process-name cleanup. Retire only a completed private
                # acceptance host (it never owns any real bottle sessions).
                needle=str(app/'Contents/MacOS/Chardonnay')
                ps=subprocess.run(['/bin/ps','-axo','pid=,comm='],capture_output=True,text=True,check=True,timeout=10)
                for line in ps.stdout.splitlines():
                    fields=line.strip().split(None,1)
                    if len(fields)==2 and fields[1]==needle:os.kill(int(fields[0]),15)
                registry=state/'bottles.json'
                if registry.is_file():
                    for row in json.loads(registry.read_text()).get('bottles',[]):
                        prefix=Path(row['path']);self.assertEqual(prefix.parent,state/'bottles');self.assertTrue((prefix/'.chardonnay-bottle.json').is_file())
                        for marker in (prefix/'drive_c').glob('ChardonnayRuntime-*.txt'):shutil.copy2(marker,artifacts/(row['id']+'-'+marker.name))
                        stubborn=prefix/'drive_c/ChardonnayRuntime-stubborn.txt'
                        if stubborn.exists():
                            pid=int(stubborn.read_text().strip().split('=')[1]);actual=subprocess.run(['/bin/ps','-p',str(pid),'-o','comm='],capture_output=True,text=True,timeout=10).stdout.strip()
                            if actual==str(native):os.kill(pid,9)  # deliberate, owned native fixture only
                        stop_env={**env,'WINEPREFIX':str(prefix)}
                        subprocess.run([str(server),'-k'],env=stop_env,capture_output=True,timeout=20)
                        subprocess.run([str(server),'-w'],env=stop_env,capture_output=True,timeout=20,check=True)
                        # Include old native orphans even if the fixture's server
                        # is already gone. Cleanup is itself explicitly scoped.
                        entry=ROOT/'install_merlot.command';text=entry.read_text();namespace={'__name__':'fixture_cleanup','__file__':str(entry)}
                        exec(compile(text.split('# BEGIN BOTTLES PYTHON\n')[1].split('# END BOTTLES PYTHON')[0],str(entry),'exec'),namespace)
                        manager=namespace['BottleManager'](private_config,state);control=namespace['BottleRuntime'](manager);snapshot=control.snapshot(row['id'])
                        if snapshot['processes']:
                            cleaned=control.act(row['id'],snapshot['token'],'force-all',confirmed=True);self.assertTrue(cleaned['stopped'],'owned fixture cleanup incomplete')
                self.assertEqual(config_path.read_bytes(),original)


if __name__=='__main__':unittest.main()
