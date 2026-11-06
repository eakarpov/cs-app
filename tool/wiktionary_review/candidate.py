"""Build an append-only etymology publication from a checkpointed immutable base.
Never modifies the base, never changes a service, and never regenerates morphology.
"""
import argparse,collections,hashlib,json,os,shutil,sqlite3,sys
from pathlib import Path

def canonical(x):return json.dumps(x,ensure_ascii=False,sort_keys=True,separators=(',',':'))
def objsha(x):return hashlib.sha256(canonical(x).encode()).hexdigest()
def sha(p):
 h=hashlib.sha256()
 with Path(p).open('rb') as f:
  while d:=f.read(8*1024*1024):h.update(d)
 return h.hexdigest()
def read(p):return json.loads(Path(p).read_text())
def ro(p):return sqlite3.connect(Path(p).resolve().as_uri()+'?mode=ro',uri=True)
def identifier(s):return '"'+s.replace('"','""')+'"'
def shape(db):
 return {r[0]:{'sql':r[1],'rows':db.execute('SELECT COUNT(*) FROM '+identifier(r[0])).fetchone()[0]} for r in db.execute("SELECT name,sql FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'").fetchall()}
def write_guard(action,table,column,db,trigger):
 if action in {sqlite3.SQLITE_INSERT,sqlite3.SQLITE_UPDATE,sqlite3.SQLITE_DELETE}:
  if table=='articles':return sqlite3.SQLITE_OK if action==sqlite3.SQLITE_UPDATE and column=='payload' else sqlite3.SQLITE_DENY
  if table not in {'metadata','etymology_sources','etymology_review_decisions','sqlite_master'}:return sqlite3.SQLITE_DENY
 if action in {sqlite3.SQLITE_DROP_TABLE,sqlite3.SQLITE_DROP_INDEX,sqlite3.SQLITE_ALTER_TABLE}:return sqlite3.SQLITE_DENY
 return sqlite3.SQLITE_OK

def build(base,out,bundle_path,decisions_path,expected_bundle,report_path):
 base=Path(base).resolve();out=Path(out).resolve();report_path=Path(report_path)
 if out.exists() or report_path.exists() or out==base:raise ValueError('Candidate and report must be new files')
 if Path(str(base)+'-wal').exists() and Path(str(base)+'-wal').stat().st_size:raise ValueError('Checkpoint the source snapshot first')
 bundle=read(bundle_path);editor=read(decisions_path)
 if bundle.get('bundleId')!=expected_bundle or objsha({k:v for k,v in bundle.items() if k!='bundleId'})!=expected_bundle:raise ValueError('Reviewed bundle checksum differs')
 if sha(base)!=bundle['baseline']['publicationSha256']:raise ValueError('Base differs from the reviewed publication')
 decisions=bundle['reviewDecisions'];refs=bundle['references'];ready={r['pairId'] for r in decisions if r['decision']=='ready'}
 if len(refs)!=len(ready) or {r['pairId'] for r in refs}!=ready:raise ValueError('Only the reviewed ready set can be applied')
 for d in decisions:
  old=editor['etymologyReviewDecisions'].get(d['pairId'])
  if not old or any(old.get(k)!=v for k,v in d.items()):raise ValueError('Editorial review journal differs')
 for key,source in bundle['sources'].items():
  if editor['etymologySources'].get(key)!=source:raise ValueError('Editorial source registry differs')
 source=ro(base);meta=dict(source.execute('SELECT key,value FROM metadata'))
 if meta.get('state')!='complete' or meta.get('scopeChecked')!='1' or meta['version']!=bundle['baseline']['publicationVersion']:raise ValueError('Wrong source publication state/version')
 if meta.get('etymologyBundleId')==expected_bundle:raise ValueError('Bundle already applied')
 before=shape(source);changes={}
 for r in refs:
  lid=r['lexemeId'];row=source.execute('SELECT payload FROM articles WHERE id=?',(lid,)).fetchone()
  if not row or hashlib.sha256(row[0].encode()).hexdigest()!=bundle['baseline']['nativePayloadSha256'][lid]:raise ValueError('Lexeme or local edits changed: '+lid)
  a=json.loads(row[0]);reference=r['reference']
  if reference['status']!='verified' or reference['relation']!='attested-in':raise ValueError('Unreviewed reference')
  if reference not in editor['etymologies'].get(lid,[]):raise ValueError('Reference missing from editorial layer')
  if a.get('etymologies'):raise ValueError('Target has an existing editorial etymology; reconcile explicitly')
  next_a={**a,'etymologies':a.get('etymologies',[])+[reference]}
  changes[lid]=(row[0],json.dumps(next_a,ensure_ascii=False,separators=(',',':')))
 # Preserve the original file as-is; make a separate SQLite snapshot.
 out.parent.mkdir(parents=True,exist_ok=True)
 with out.open('xb'):pass
 candidate=sqlite3.connect(out)
 source.backup(candidate)
 candidate.set_authorizer(write_guard)
 version=objsha({'format':'cs-etymology-patch-v1','base':meta['version'],'bundleId':expected_bundle,'editorialSha256':sha(decisions_path)})
 with candidate:
  candidate.execute("UPDATE metadata SET value='building' WHERE key='state'")
  candidate.execute('CREATE TABLE IF NOT EXISTS etymology_sources(id TEXT PRIMARY KEY,payload TEXT NOT NULL)')
  candidate.execute('CREATE TABLE IF NOT EXISTS etymology_review_decisions(id TEXT PRIMARY KEY,payload TEXT NOT NULL)')
  for key,value in bundle['sources'].items():
   payload=canonical(value);old=candidate.execute('SELECT payload FROM etymology_sources WHERE id=?',(key,)).fetchone()
   if old and old[0]!=payload:raise ValueError('Conflicting existing source')
   candidate.execute('INSERT OR IGNORE INTO etymology_sources VALUES (?,?)',(key,payload))
  for d in decisions:
   key=d['pairId'];payload=canonical(editor['etymologyReviewDecisions'][key]);old=candidate.execute('SELECT payload FROM etymology_review_decisions WHERE id=?',(key,)).fetchone()
   if old and old[0]!=payload:raise ValueError('Conflicting editorial decision')
   candidate.execute('INSERT OR IGNORE INTO etymology_review_decisions VALUES (?,?)',(key,payload))
  for lid,(old,new) in changes.items():
   if candidate.execute('UPDATE articles SET payload=? WHERE id=? AND payload=?',(new,lid,old)).rowcount!=1:raise ValueError('Compare-and-swap failed')
  for key,value in {'version':version,'etymologyBaseVersion':meta['version'],'etymologyBundleId':expected_bundle,'etymologyEditorialSha256':sha(decisions_path),'state':'building'}.items():
   candidate.execute('INSERT INTO metadata(key,value) VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',(key,value))
 candidate.set_authorizer(None)
 # Compare every article, including all fields, schemes and local editorial data.
 candidate.execute('ATTACH DATABASE ? AS baseline',(base.as_uri()+'?mode=ro',))
 lost=candidate.execute('SELECT count(*) FROM baseline.articles b LEFT JOIN main.articles a ON a.id=b.id WHERE a.id IS NULL').fetchone()[0]
 gained=candidate.execute('SELECT count(*) FROM main.articles a LEFT JOIN baseline.articles b ON a.id=b.id WHERE b.id IS NULL').fetchone()[0]
 actual={}
 for lid,old,new in candidate.execute('SELECT a.id,b.payload,a.payload FROM main.articles a JOIN baseline.articles b ON b.id=a.id WHERE a.payload!=b.payload'):
  a=json.loads(old);b=json.loads(new)
  if {k:v for k,v in a.items() if k!='etymologies'}!={k:v for k,v in b.items() if k!='etymologies'}:raise ValueError('Non-etymology article fields changed')
  if b['etymologies'][:len(a.get('etymologies',[]))]!=a.get('etymologies',[]):raise ValueError('Existing references lost')
  actual[lid]=len(b['etymologies'])-len(a.get('etymologies',[]))
 if lost or gained or set(actual)!=set(changes) or any(v!=1 for v in actual.values()):raise ValueError('Unexpected article delta')
 after=shape(candidate)
 if any(after.get(t)!=value for t,value in before.items() if t!='metadata'):raise ValueError('Existing table shape/count changed')
 if before['metadata']['sql']!=after['metadata']['sql']:raise ValueError('Metadata schema changed')
 new_meta=dict(candidate.execute('SELECT key,value FROM metadata'))
 if any(new_meta.get(k)!=v for k,v in meta.items() if k not in {'version','state'}):raise ValueError('Unrelated metadata changed')
 if candidate.execute('PRAGMA quick_check').fetchall()!=[('ok',)]:raise ValueError('Candidate integrity failed')
 counts={'articles':after['articles']['rows'],'changedArticles':len(actual),'newReferences':sum(actual.values()),'sourceRecords':after['etymology_sources']['rows'],'decisions':after['etymology_review_decisions']['rows']}
 candidate.execute('DETACH DATABASE baseline')
 with candidate:candidate.execute("UPDATE metadata SET value='complete' WHERE key='state'")
 candidate.close();source.close()
 result={'version':version,'bundleId':expected_bundle,'baseVersion':meta['version'],'baseSha256':bundle['baseline']['publicationSha256'],'candidateSha256':sha(out),'editorialSha256':sha(decisions_path),'counts':counts,'allIdsPreserved':True,'allNonEtymologyArticleFieldsPreserved':True,'allExistingTableSchemasAndCountsPreserved':True,'writeAuthorizerRestrictedToEtymologyPayloadAndMetadata':True,'quickCheck':'ok','productionActivated':False}
 report_path.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');print(json.dumps(result,ensure_ascii=False,indent=2),flush=True)
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--base',required=True,type=Path);p.add_argument('--out',required=True,type=Path);p.add_argument('--bundle',required=True,type=Path);p.add_argument('--decisions',required=True,type=Path);p.add_argument('--expected-bundle',required=True);p.add_argument('--report',required=True,type=Path);a=p.parse_args();build(a.base,a.out,a.bundle,a.decisions,a.expected_bundle,a.report)
