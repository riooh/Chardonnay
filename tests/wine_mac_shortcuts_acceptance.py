"""Explicit Aqua acceptance for private diagnostic Wine engine clones.

Run through a private LaunchServices host, not SSH. Uses registered prefixes
for individually scoped fixture processes; it never clones account state or
stops their servers. Caller must explicitly authorize that scope.
"""
from pathlib import Path
import json,os,signal,subprocess,sys,time,traceback

if len(sys.argv)!=3 or sys.argv[2]!='--registered-prefix-fixtures':
 sys.exit('usage: wine_mac_shortcuts_acceptance.py PRIVATE_DIAGNOSTIC_STAGE --registered-prefix-fixtures (requires explicit approval)')
stage=Path(sys.argv[1]).resolve();h=Path.home();config=json.loads((h/'.config/chardonnay-shortcuts/config.json').read_text());engines=json.loads((stage/'diagnostic-manifest.json').read_text());results=[]
# This process is launched through the private native LaunchServices host.
for row in engines:
 profile=next(p for p in config['prefixes'] if p['id']==row['name'])
 cases=['minimize','hide','close','close-veto','quit','quit-veto','select-all','undo','control-a','copy','paste','cut','fullscreen']
 for case in cases:
  output=stage/(row['name']+'-'+case);output.mkdir(exist_ok=True)
  native=output/'native.json';win=output/'windows.txt'
  env={'HOME':str(h),'USER':os.environ.get('USER','kurtmonsanto'),'PATH':'/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin'}
  env.update(profile.get('environment',{}));env.update(WINEPREFIX=profile['path'],WINEDEBUG='-all',CHARDONNAY_SHORTCUT_PROBE=str(native),CHARDONNAY_SHORTCUT_CASE=case,CHARDONNAY_SHORTCUT_WIN_REPORT='Z:'+str(win).replace('/','\\'))
  for name in ['__CFBundleIdentifier','WINELOADER','WINESERVER','WINEDLLPATH']:env.pop(name,None)
  command=[str(Path(row['private_engine'])/'bin/wine'),str(stage/'ChardonnayShortcutProbe.exe')]
  record={'engine':row['name'],'case':case};process=None
  try:
   with (output/'wine.log').open('wb') as logfile:
    process=subprocess.Popen(command,env=env,stdin=subprocess.DEVNULL,stdout=logfile,stderr=subprocess.STDOUT,cwd=output)
    status=process.wait(timeout=25)
   text=win.read_text() if win.exists() else '';native_result=json.loads(native.read_text()) if native.exists() else {}
   required={'minimize':'event=minimize passed=1','hide':'event=native-state-check passed=1','close':'event=close passed=1','close-veto':'event=veto-survived passed=1','quit':'event=quit-ended passed=1','quit-veto':'event=veto-survived passed=1','select-all':'event=selected-all passed=1','undo':'event=undo passed=1','control-a':'event=selected-all passed=1','copy':'event=copy-key passed=1','paste':'event=paste-key passed=1','cut':'event=cut-key passed=1','fullscreen':'event=native-state-check passed=1'}[case]
   assert status==0,('exit',status)
   assert required in text,('missing_ack',required,text)
   expected=Path(row['private_engine'])/'lib/wine/x86_64-unix/winemac.so'
   assert Path(native_result.get('driver','')).resolve()==expected.resolve(),('wrong_driver',native_result)
   bindings={b['action']:b for b in native_result['bindings']}
   for action,key in [('terminate:','q'),('performMiniaturize:','m'),('hide:','h'),('performClose:','w')]:
    assert bindings[action]['key']==key and bindings[action]['modifiers']==(1<<20),(action,bindings[action])
   if case=='hide':assert native_result['phase']=='observed' and native_result['hidden'],native_result
   if case=='fullscreen':assert native_result['phase']=='observed' and native_result['fullscreen'],native_result
   if 'veto' in case:assert 'end=1' not in text,text
   record.update(passed=True,native=native_result,windows=text,exit=status)
  except Exception as error:
   record.update(passed=False,error=repr(error),traceback=traceback.format_exc(),windows=win.read_text() if win.exists() else '',native=json.loads(native.read_text()) if native.exists() else {})
   if process and process.poll() is None:
    process.terminate()
    try:process.wait(timeout=8)
    except subprocess.TimeoutExpired:record['cleanup']='owned fixture did not exit after SIGTERM; no escalation'
  results.append(record);(stage/'GUI_RESULTS.json').write_text(json.dumps(results,indent=2));print(json.dumps({k:v for k,v in record.items() if k not in ['native','traceback']}),flush=True)
  if not record['passed']:
   (stage/'GUI_DONE.json').write_text(json.dumps({'success':False,'count':len(results),'failed':record}));sys.exit(1)
(stage/'GUI_DONE.json').write_text(json.dumps({'success':all(r['passed'] for r in results),'count':len(results)}))
