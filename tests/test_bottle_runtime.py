"""Fail-closed manual runtime controls: synthetic identities, never live signals."""
import copy
import json
import os
from pathlib import Path
import signal
import sys
import tempfile
import types
import unittest

ROOT=Path(__file__).resolve().parents[1]
TEXT=(ROOT/'install_merlot.command').read_text()
M=types.ModuleType('runtime_contract');M.__file__=str(ROOT/'install_merlot.command')
exec(compile(TEXT.split('# BEGIN BOTTLES PYTHON\n',1)[1].split('# END BOTTLES PYTHON',1)[0],M.__file__,'exec'),M.__dict__)


class RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name).resolve();self.prefix=self.root/'prefix';(self.prefix/'drive_c').mkdir(parents=True)
        wine=self.root/'engine/bin/wine';wine.parent.mkdir(parents=True);wine.write_bytes(b'fixture');wine.chmod(0o755)
        self.config=self.root/'config.json';self.config.write_text(json.dumps({'version':1,'prefixes':[{'id':'fixture','path':str(self.prefix),'wine':str(wine),'name':'Private fixture'}]}))
        self.manager=M.BottleManager(self.config,self.root/'state');self.row=self.manager.bindings()[0][0]
        st=self.prefix.stat();self.namespace='server-%x-%x'%(st.st_dev,st.st_ino)
        self.records=[self.record(1101,'Fixture.exe'),self.record(1102,'wineserver')]
        self.signals=[];self.complete=True;self.exits=True;self.ticks=1000
        self.controller=M.BottleRuntime(self.manager,inspector=lambda:{'processes':copy.deepcopy(self.records),'complete':self.complete,'warnings':[]},identity=self.identity,signaller=self.send,clock=lambda:self.ticks,sleeper=self.sleep)

    def record(self,pid,name,namespace=None):
        return {'pid':pid,'birth':[100,pid],'uid':os.getuid(),'native_path':'/engine/bin/'+('wineserver' if name=='wineserver' else 'wine'),'name':name,'files':['/private/tmp/.wine-%d/%s/tmpmap-fixture'%(os.getuid(),namespace or self.namespace)]}

    def identity(self,pid):
        return copy.deepcopy(next((x for x in self.records if x['pid']==pid),None))

    def send(self,pid,sig):
        self.signals.append((pid,sig))
        if self.exits:self.records=[r for r in self.records if r['pid']!=pid]

    def sleep(self,seconds):self.ticks+=seconds

    def snapshot(self):return self.controller.snapshot(self.row['id'])

    def test_read_only_inventory_does_not_dispatch_wine_or_signals(self):
        value=self.snapshot();self.assertEqual(len(value['processes']),2);self.assertTrue(value['complete']);self.assertFalse(self.signals)
        self.assertTrue(value['token']);self.assertNotIn('files',value['processes'][0])

    def test_same_engine_other_prefix_is_never_selected(self):
        self.records.append(self.record(1103,'Other.exe','server-123-456'))
        value=self.snapshot();self.assertEqual({p['pid'] for p in value['processes']},{1101,1102})
        result=self.controller.act(self.row['id'],value['token'],'quit-all',confirmed=True)
        self.assertTrue(result['stopped']);self.assertEqual({p for p,_ in self.signals},{1101,1102});self.assertEqual(self.records[0]['pid'],1103)

    def test_no_confirmation_no_signal(self):
        with self.assertRaisesRegex(ValueError,'confirmation'):self.controller.act(self.row['id'],self.snapshot()['token'],'quit-all')
        self.assertFalse(self.signals)

    def test_targeted_term_only_selected_process(self):
        result=self.controller.act(self.row['id'],self.snapshot()['token'],'terminate',pid=1101,confirmed=True)
        self.assertTrue(result['stopped']);self.assertEqual(self.signals,[(1101,signal.SIGTERM)])
        self.assertEqual(self.records[0]['pid'],1102)

    def test_force_requires_separate_confirmation_and_is_not_automatic(self):
        self.exits=False;value=self.snapshot()
        result=self.controller.act(self.row['id'],value['token'],'terminate',pid=1101,confirmed=True)
        self.assertFalse(result['stopped']);self.assertEqual(self.signals,[(1101,signal.SIGTERM)])
        self.assertTrue(result['force_required'])
        self.signals=[];self.exits=True
        result=self.controller.act(self.row['id'],self.snapshot()['token'],'force-process',pid=1101,confirmed=True)
        self.assertTrue(result['stopped']);self.assertEqual(self.signals,[(1101,signal.SIGKILL)])

    def test_server_cannot_be_terminated_as_a_single_client(self):
        with self.assertRaisesRegex(ValueError,'server'):self.controller.act(self.row['id'],self.snapshot()['token'],'terminate',pid=1102,confirmed=True)
        self.assertFalse(self.signals)

    def test_pid_reuse_invalidates_whole_bottle_consent(self):
        value=self.snapshot();self.records[0]['birth']=[999,1]
        with self.assertRaisesRegex(ValueError,'changed'):self.controller.act(self.row['id'],value['token'],'quit-all',confirmed=True)
        self.assertFalse(self.signals)

    def test_new_process_invalidates_whole_bottle_consent(self):
        value=self.snapshot();self.records.append(self.record(1103,'New.exe'))
        with self.assertRaisesRegex(ValueError,'changed'):self.controller.act(self.row['id'],value['token'],'quit-all',confirmed=True)
        self.assertFalse(self.signals)

    def test_incomplete_inspection_blocks_whole_bottle_action(self):
        self.complete=False;value=self.snapshot();self.assertFalse(value['complete'])
        with self.assertRaisesRegex(ValueError,'incomplete'):self.controller.act(self.row['id'],value['token'],'quit-all',confirmed=True)
        self.assertFalse(self.signals)

    def test_unattributed_wine_process_blocks_claim_of_complete_bottle_stop(self):
        self.records.append({**self.record(1103,'Unknown.exe'),'files':['/some/working-directory']})
        self.assertFalse(self.snapshot()['complete'])

    def test_conflicting_namespace_never_signalled(self):
        self.records[0]['files'].append('/private/tmp/.wine-%d/server-123-456/tmpmap-other'%os.getuid())
        value=self.snapshot();self.assertFalse(value['complete']);self.assertNotIn(1101,[r['pid'] for r in value['processes']])

    def test_expired_token_and_replayed_token_are_rejected(self):
        value=self.snapshot();self.ticks+=181
        with self.assertRaisesRegex(ValueError,'expired'):self.controller.act(self.row['id'],value['token'],'quit-all',confirmed=True)
        value=self.snapshot();self.controller.act(self.row['id'],value['token'],'terminate',pid=1101,confirmed=True)
        with self.assertRaises(ValueError):self.controller.act(self.row['id'],value['token'],'terminate',pid=1101,confirmed=True)

    def test_unknown_pid_and_unknown_action_never_signal(self):
        with self.assertRaises(ValueError):self.controller.act(self.row['id'],self.snapshot()['token'],'terminate',pid=1109,confirmed=True)
        with self.assertRaises(ValueError):self.controller.act(self.row['id'],self.snapshot()['token'],'magic-auto-repair',confirmed=True)
        self.assertFalse(self.signals)

    def test_changed_prefix_identity_invalidates_snapshot(self):
        value=self.snapshot();self.prefix.rename(self.root/'old-prefix');(self.prefix/'drive_c').mkdir(parents=True)
        with self.assertRaisesRegex(ValueError,'changed'):self.controller.act(self.row['id'],value['token'],'quit-all',confirmed=True)
        self.assertFalse(self.signals)

    def test_changed_engine_binding_invalidates_snapshot(self):
        value=self.snapshot();config=json.loads(self.config.read_text());config['prefixes'][0]['environment']={'WINE_VERSION':'different'};self.config.write_text(json.dumps(config))
        with self.assertRaisesRegex(ValueError,'changed'):self.controller.act(self.row['id'],value['token'],'quit-all',confirmed=True)
        self.assertFalse(self.signals)

    def test_restart_does_not_relaunch_when_any_target_survives(self):
        self.exits=False;self.manager.launch=lambda *a,**kw: self.fail('must not relaunch while old clients remain')
        self.manager.apps=lambda row:[{'id':'steam','kind':'store'}]
        result=self.controller.act(self.row['id'],self.snapshot()['token'],'restart',app_id='steam',confirmed=True)
        self.assertFalse(result['stopped']);self.assertFalse(result['launch_dispatched'])

    def test_restart_dispatches_exactly_one_registered_app_after_verified_stop(self):
        launched=[];self.manager.launch=lambda ident,app_id,**kwargs: launched.append((ident,app_id)) or {'launch_dispatched':True}
        self.manager.apps=lambda row:[{'id':'fixture-link','kind':'application'}]
        result=self.controller.act(self.row['id'],self.snapshot()['token'],'restart',app_id='fixture-link',confirmed=True)
        self.assertTrue(result['stopped']);self.assertTrue(result['launch_dispatched']);self.assertEqual(launched,[(self.row['id'],'fixture-link')])

    def test_restart_rejects_missing_app_before_signals(self):
        self.manager.apps=lambda row:[]
        with self.assertRaisesRegex(ValueError,'application'):self.controller.act(self.row['id'],self.snapshot()['token'],'restart',app_id='unknown',confirmed=True)
        self.assertFalse(self.signals)

    def test_force_restart_requires_separate_explicit_action_and_preserves_route(self):
        launched=[];self.manager.apps=lambda row:[{'id':'steam','kind':'store'}]
        self.manager.launch=lambda ident,app_id,**kw: launched.append((ident,app_id)) or {'launch_dispatched':True}
        self.exits=False
        result=self.controller.act(self.row['id'],self.snapshot()['token'],'restart',app_id='steam',confirmed=True)
        self.assertFalse(result['stopped']);self.assertFalse(launched)
        self.exits=True;self.signals=[]
        result=self.controller.act(self.row['id'],self.snapshot()['token'],'force-restart',app_id='steam',confirmed=True)
        self.assertTrue(result['stopped']);self.assertEqual(launched,[(self.row['id'],'steam')])
        self.assertTrue(all(sig==signal.SIGKILL for _,sig in self.signals))

    def test_snapshot_permissions_are_private(self):
        value=self.snapshot();path=self.controller.token_path(value['token'])
        self.assertEqual(path.stat().st_mode & 0o777,0o600)
        self.assertEqual(path.parent.stat().st_mode & 0o777,0o700)

    def test_other_uid_process_is_never_included(self):
        self.records.append({**self.record(1103,'Foreign.exe'),'uid':os.getuid()+1})
        self.assertEqual({p['pid'] for p in self.snapshot()['processes']},{1101,1102})

    def test_recheck_identity_before_signalling_prevents_late_pid_reuse(self):
        value=self.snapshot();self.controller.identity=lambda pid:{**self.identity(pid),'birth':[800,1]}
        with self.assertRaisesRegex(ValueError,'identity_changed'):self.controller.act(self.row['id'],value['token'],'quit-all',confirmed=True)
        self.assertFalse(self.signals)

    def test_shared_manager_runtime_lock_blocks_concurrent_launch(self):
        with self.manager.runtime_lock():
            with self.assertRaisesRegex(RuntimeError,'operation_is_running'):
                self.controller.act(self.row['id'],self.snapshot()['token'],'quit-all',confirmed=True)
        self.assertFalse(self.signals)

    def test_restart_does_not_replay_installer_shortcut(self):
        self.manager.apps=lambda row:[{'id':'link-fixture','kind':'application','name':'Uninstaller','source':'uninstaller.lnk'}]
        with self.assertRaisesRegex(ValueError,'replayed'):
            self.controller.act(self.row['id'],self.snapshot()['token'],'restart',app_id='link-fixture',confirmed=True)
        self.assertFalse(self.signals)

    def test_no_native_support_on_other_platforms_is_fail_closed(self):
        if sys.platform!='darwin':
            with self.assertRaisesRegex(RuntimeError,'macos'):M.runtime_native_snapshot()


if __name__=='__main__':unittest.main()
