"""Validate the immutable dictionary update and rebind unchanged morpheme content."""
import sys,json,sqlite3,hashlib,shutil,os,copy
from pathlib import Path
s=Path(sys.argv[1]);state=json.loads((s/'state.json').read_text());report=json.loads((s/'candidate.report.json').read_text())
def ro(path):return sqlite3.connect(Path(path).resolve().as_uri()+'?mode=ro&immutable=1',uri=True)
def sha(path):
 with open(path,'rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def meta(d):return dict(d.execute('select key,value from metadata'))
def canonical(v):return json.dumps(v,ensure_ascii=False,separators=(',',':'),sort_keys=True)
def strip(a):
 for p in a['paradigms']:
  for slot in p['slots']:
   for f in slot['forms']:f.pop('segments',None)
 return a
base=ro(state['dictionary']);new=ro(state['candidate']);assert meta(base)['version']==state['dictionaryVersion']
assert sha(state['dictionary'])==report['baseSha256'] and sha(state['candidate'])==report['sha256']
assert base.execute('select type,name,tbl_name,sql from sqlite_master order by type,name').fetchall()==new.execute('select type,name,tbl_name,sql from sqlite_master order by type,name').fetchall()
counts={};changed=0
for id,payload in base.execute('select id,payload from articles order by id'):
 old=json.loads(payload);updated=json.loads(new.execute('select payload from articles where id=?',(id,)).fetchone()[0])
 assert strip(copy.deepcopy(old))==strip(copy.deepcopy(updated)),id
 if old!=updated:changed+=1
 for p in updated['paradigms']:
  for slot in p['slots']:
   for f in slot['forms']:
    if f['segments']:assert ''.join(v['text'] for v in f['segments'])==f['value'],id
assert changed==report['changedArticles']
print(json.dumps({'validatedArticles':report['articles'],'changedArticles':changed}),flush=True)
def digest(db,table):
 h=hashlib.sha256();n=0
 try: rows=db.execute('select * from "'+table+'" order by rowid')
 except sqlite3.OperationalError:
  columns=[r[1] for r in db.execute('pragma table_info("'+table+'")')];assert all('"' not in c for c in columns)
  rows=db.execute('select * from "'+table+'" order by '+','.join('"'+c+'"' for c in columns))
 for row in rows:
  h.update(repr(row).encode());h.update(b'\0');n+=1
 return n,h.hexdigest()
for (table,) in base.execute("select name from sqlite_master where type='table' and name not in ('articles','metadata') order by name"):
 assert '"' not in table
 old=digest(base,table);now=digest(new,table);assert old==now,table
 counts[table]={'rows':old[0],'sha256':old[1]};print(json.dumps({'unchangedTable':table,'rows':old[0]}),flush=True)
for k,v in meta(base).items():
 if k not in ('version',):assert meta(new)[k]==v,k
assert new.execute('pragma quick_check').fetchall()==[('ok',)]
# A new morpheme version is needed only because its dictionary binding changes.
m=ro(state['morphemes']);before=meta(m);assert before['dictionaryVersion']==state['dictionaryVersion']
mv=hashlib.sha256(canonical({'format':'cs-morpheme-dictionary-rebind-v1','base':before['version'],'dictionaryVersion':report['version']}).encode()).hexdigest()
mp=Path(state['morphemes']).parent/('morphemes-'+mv+'.sqlite');assert not mp.exists();shutil.copyfile(state['morphemes'],mp);os.chmod(mp,0o600);target=sqlite3.connect(mp)
with target:
 for table in ('words','morphemes'):
  for id,payload in m.execute('select id,payload from '+table):
   a=json.loads(payload);a['version']=mv;target.execute('update '+table+' set payload=? where id=?',(canonical(a),id))
 for k,v in {'version':mv,'dictionaryVersion':report['version']}.items():target.execute('update metadata set value=? where key=?',(v,k))
for table in ('words','morphemes'):
 for id,payload in m.execute('select id,payload from '+table):
  old=json.loads(payload);a=json.loads(target.execute('select payload from '+table+' where id=?',(id,)).fetchone()[0]);assert a.pop('version')==mv;old.pop('version');assert a==old
for (table,) in m.execute("select name from sqlite_master where type='table' and name not in ('words','morphemes','metadata')"):
 assert digest(m,table)==digest(target,table),table
assert target.execute('pragma quick_check').fetchall()==[('ok',)]
target.close();os.chmod(mp,0o444)
result={'dictionaryVersion':report['version'],'dictionarySha256':report['sha256'],'morphemeVersion':mv,'morphemeCandidate':str(mp),'morphemeSha256':sha(mp),'checkedArticles':report['articles'],'changedArticles':changed,'unchangedTables':counts,'allNonSegmentArticleFieldsPreserved':True,'exactSpellingsAndAccentsPreserved':True,'morphemeContentPreserved':True}
(s/'validation.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'validation':'passed','dictionaryVersion':report['version'],'morphemeVersion':mv}),flush=True)
