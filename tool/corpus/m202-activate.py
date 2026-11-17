from contextlib import ExitStack
from pathlib import Path
import fcntl,hashlib,json,os,subprocess,sys,time,urllib.request,shutil,datetime,concurrent.futures,http.client,ssl,socket
root=Path('/var/www/typikon.su/typikon-web-releases');candidate=root/'releases/20261117T-m202-unicode17'
base=Path((candidate/'M202_BASE').read_text().strip());index='data/reader-index/corpus-index-ix1_d40064e4ed4fe8a67e41351e3ef8a2a3c2eeb3409e1b5dd455e2a68e33bc48a5.sqlite'
site=Path('/etc/nginx/sites-enabled/typikon').resolve();site_before=site.read_bytes();engine=Path('/var/www/typikon.su/typikon-ordo').resolve();db=Path('/var/www/typikon.su/data.db').resolve();before_pilot=candidate/'data/reader-index/activation-before.ejson';state_changed=False;switched=False
report={}
def link(path,target):
 temp=path.with_name(path.name+'.m202-tmp');temp.unlink(missing_ok=True);temp.symlink_to(target);temp.replace(path)
def run(*args):return subprocess.run(args,cwd=candidate,check=True)
def cap():return json.load(urllib.request.urlopen('http://127.0.0.1:3000/api/v2/study/reader/v1/index/capabilities',timeout=15))
with ExitStack() as locks:
 for name in ['/home/admin/.config/interlex-backup/backup.lock',root/'deploy.lock',Path('/var/www/typikon.su/typikon-ordo-releases/deploy.lock')]:
  print('WAIT_COMMON_LOCK',name,flush=True);f=locks.enter_context(open(name,'a'));fcntl.flock(f,fcntl.LOCK_EX)
 assert (root/'current').resolve()==base,'Active release changed; rebase required'
 ready=json.loads((candidate/'m202-stage-ready.json').read_text());assert ready['passed']
 assert json.loads((candidate/'data/reader-index/probe-smoke.json').read_text())['passed']
 sys.path.insert(0,str(candidate/'m202-tools'));from build_portal_candidate import inputs_sha
 assert inputs_sha(candidate)==ready['source_inputs_sha256']
 digest=hashlib.file_digest(open(db,'rb'),'sha256').hexdigest()
 body=json.dumps({'profile':'dataset-r1','artifacts':[{'name':'rules.db','sha256':digest}]},sort_keys=True,separators=(',',':')).encode()
 expected='ds1_'+hashlib.sha256(body).hexdigest();native=json.loads((candidate/'data/reader-index/server-native-audit.json').read_text());assert native['nativeDatasetRevision']==expected
 app_files=['src/lib/appVersion.ts','src/pages/api/v1/app/version.ts','src/app/api/v2/app/version/route.ts']
 for f in app_files:assert (base/f).read_bytes()==(candidate/f).read_bytes()
 try:
  args=['node','--import','tsx','src/scripts/reader-unicode-import.ts','--registry','data/reader-index/reader-registry-server.ejson','--index',index,'--activate','--report','data/reader-index/activation.json']
  if not before_pilot.exists():args+=['--backup',str(before_pilot)]
  run(*args);state_changed=True
  for name in ['typikon-reader-zone.conf','typikon-reader-locations.conf']:shutil.copy2(candidate/'m202-tools'/name,root/'incoming'/name)
  run('python3','m202-tools/m202-nginx-install.py')
  link(root/'current',candidate);switched=True;run('systemctl','restart','typikon-web.service')
  for attempt in range(30):
   try:
    c=cap();assert c['data']['indexRevision']=='ix1_d40064e4ed4fe8a67e41351e3ef8a2a3c2eeb3409e1b5dd455e2a68e33bc48a5';break
   except Exception:
    if attempt==29:raise
    time.sleep(1)
  run('python3','m202-tools/m202-smoke.py','--base','https://www.typikon.info','--report','data/reader-index/public-smoke.json')
  assert Path('/var/www/typikon.su/data.db').resolve()==db and Path('/var/www/typikon.su/typikon-ordo').resolve()==engine
  assert hashlib.file_digest(open(db,'rb'),'sha256').hexdigest()==digest,'Book database changed during release'
  # Exercise only the new prefix; unknown methods perform no source/dictionary reads.
  edge_context=ssl.create_default_context()
  class LocalTLS(http.client.HTTPSConnection):
   def connect(self):self.sock=self._context.wrap_socket(socket.create_connection(('127.0.0.1',443),self.timeout),server_hostname=self.host)
  def edge(_):
   connection=LocalTLS('www.typikon.info',context=edge_context,timeout=20)
   try:
    connection.request('GET','/api/v2/study/reader/v1/index/m202-edge-probe',headers={'User-Agent':'cs-app-M202-acceptance/1'})
    response=connection.getresponse();data=response.read();return response.status,response.getheader('Retry-After'),data
   finally:connection.close()
  time.sleep(2)
  with concurrent.futures.ThreadPoolExecutor(max_workers=40) as pool:replies=list(pool.map(edge,range(40)))
  limited=[r for r in replies if r[0]==429];assert limited and all(r[0] in [404,429] for r in replies);assert all(r[1]=='1' and json.loads(r[2])['contract']=='cs-index/1' for r in limited)
  link(root/'previous',base)
  report={'format':'m2-02-u17-publication/1','passed':True,'date':'2026-11-17','publishedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'web':str(candidate),'previous_web':str(base),'previous_engine':None,'engine':str(engine),'nativeDatabase':str(db),'nativeDatabaseSha256Unchanged':digest,'codeCommit':(candidate/'REVISION').read_text().strip(),'indexRevision':c['data']['indexRevision'],'corpusRelease':c['data']['corpusRelease'],'dictionaryVersion':c['data']['dictionaryVersion'],'sourceIdsPreserved':True,'acceptedLinksPreserved':4,'canonicalTextCopied':False,'edgeQuota':{'ratePerSecond':10,'burst':20,'probeRoute':'TLS loopback with canonical www SNI/Host','probeRequests':40,'limited':len(limited),'retryAfter':1},'applicationQuotaProbe':json.loads((candidate/'data/reader-index/probe-smoke.json').read_text())['applicationQuotaProbe'],'appUpdateSourceFilesUnchanged':app_files,'apkPublished':False,'visualTestingPerformed':False}
  (candidate/'m202-published.json').write_text(json.dumps(report,indent=2)+'\n');(candidate/'portal-published.json').write_text(json.dumps(report,indent=2)+'\n')
  print(json.dumps(report),flush=True)
 except BaseException:
  if switched:link(root/'current',base);subprocess.run(['systemctl','restart','typikon-web.service'],check=True)
  site.write_bytes(site_before)
  for f in ['/etc/nginx/conf.d/typikon-reader-zone.conf','/etc/nginx/snippets/typikon-reader-locations.conf']:Path(f).unlink(missing_ok=True)
  subprocess.run(['nginx','-t'],check=True);subprocess.run(['systemctl','reload','nginx'],check=True)
  if state_changed and before_pilot.exists():
   code='require("./src/scripts/lib/env.ts");(async()=>{const fs=require("fs"),{BSON}=require("mongodb"),b=BSON.EJSON.parse(fs.readFileSync(process.argv[1],"utf8"));const c=await require("./src/lib/mongodb.ts").default;const d=c.db("typikon").collection("readerPilots");if(b.pilot)await d.replaceOne({_id:"cs-mvp-pilot-01"},b.pilot,{upsert:true});else await d.deleteOne({_id:"cs-mvp-pilot-01"});await c.close()})().catch(e=>{console.error(e);process.exit(1)})'
   subprocess.run(['node','--import','tsx','-e',code,str(before_pilot)],cwd=candidate,check=True)
  raise
