from contextlib import ExitStack
from pathlib import Path
import fcntl,hashlib,json,os,pwd,socket,subprocess,sys,time,urllib.request,shutil
root=Path('/var/www/typikon.su/typikon-web-releases')
incoming=root/'incoming/m202-unicode17-20261117';final=root/'releases/20261117T-m202-unicode17';port=3187
with ExitStack() as locks:
 for name in ['/home/admin/.config/interlex-backup/backup.lock',root/'deploy.lock',Path('/var/www/typikon.su/typikon-ordo-releases/deploy.lock')]:
  print('WAIT_COMMON_LOCK',name,flush=True);f=locks.enter_context(open(name,'a'));fcntl.flock(f,fcntl.LOCK_EX)
 candidate=incoming if incoming.exists() else final
 assert candidate.exists();base=Path((candidate/'M202_BASE').read_text().strip());assert (root/'current').resolve()==base,'Book publication changed: rebase required'
 sys.path.insert(0,str(candidate/'m202-tools'));from build_portal_candidate import inputs_sha
 marker=json.loads((candidate/'candidate-build.complete').read_text());assert marker['inputs_sha256']==inputs_sha(candidate)
 assert marker['phases']==['compile','types','generate']
 assert hashlib.sha256((candidate/'src/data/library/coverage.json').read_bytes()).hexdigest()=='e1129813a40cb6877cdd2bfec4b98e94d293a6d3cc7ac135a8d631eaa8bbecc2'
 assert (candidate/'.next/BUILD_ID').stat().st_size>0
 app_files=['src/lib/appVersion.ts','src/pages/api/v1/app/version.ts','src/app/api/v2/app/version/route.ts']
 for name in app_files:assert (candidate/name).read_bytes()==(base/name).read_bytes(),'App update endpoint changed'
 if candidate==incoming:
  assert not final.exists();incoming.rename(final);candidate=final
 # Keep a live candidate PID so the normal retention helper protects this directory.
 try:
  with socket.create_connection(('127.0.0.1',port),timeout=1):raise RuntimeError('Probe port already occupied')
 except ConnectionRefusedError:pass
 admin=pwd.getpwnam('admin');env=dict(os.environ,CS_READER_REGISTRY_DB='typikon_reader_m202_u17',NODE_ENV='production')
 log=open(candidate/'m202-probe.log','ab')
 proc=subprocess.Popen(['node','node_modules/next/dist/bin/next','start','-H','127.0.0.1','-p',str(port)],cwd=candidate,env=env,stdin=subprocess.DEVNULL,stdout=log,stderr=subprocess.STDOUT,start_new_session=True,user=admin.pw_uid,group=admin.pw_gid)
 (candidate/'candidate.pid').write_text(str(proc.pid)+'\n')
 for attempt in range(30):
  if proc.poll() is not None:raise RuntimeError('Probe process stopped')
  try:
   data=json.load(urllib.request.urlopen(f'http://127.0.0.1:{port}/api/v2/study/reader/v1/index/capabilities',timeout=15));assert data['data']['available'];break
  except Exception:
   if attempt==29:raise
   time.sleep(1)
 report=dict(candidate=str(candidate),base=str(base),port=port,pid=proc.pid,build_id=(candidate/'.next/BUILD_ID').read_text().strip(),source_inputs_sha256=marker['inputs_sha256'],app_update_files_unchanged=app_files,coverage_sha256='e1129813a40cb6877cdd2bfec4b98e94d293a6d3cc7ac135a8d631eaa8bbecc2',passed=True)
 (candidate/'m202-stage-ready.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report),flush=True)
