"""Create a separate canonical publication preserving every word/link/statistic."""
import argparse,copy,hashlib,json,os,shutil,sqlite3
from pathlib import Path
from canonical import canonical_card,compact

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def ro(p):return sqlite3.connect(Path(p).resolve().as_uri()+'?mode=ro&immutable=1',uri=True)
def build(base,out,research_path,expected):
 assert not out.exists();old=ro(base);meta=dict(old.execute('select * from metadata'))
 assert meta['version']==expected and meta['state']=='complete'
 oldsha=sha(base);research=json.loads(research_path.read_text());assert research['version']==meta['researchVersion']
 cards={id:canonical_card(json.loads(payload),research) for id,payload in old.execute('select id,payload from morphemes')}
 version=hashlib.sha256(compact({'baseSha256':oldsha,'canonical':cards,'builder':sha(__file__),'rules':sha(Path(__file__).with_name('canonical.py'))}).encode()).hexdigest()
 shutil.copyfile(base,out);os.chmod(out,0o600);new=sqlite3.connect(out)
 with new:
  for id,card in cards.items():
   card['version']=version;new.execute('update morphemes set payload=? where id=?',(compact(card),id))
  for id,payload in old.execute('select id,payload from words'):
   a=json.loads(payload);a['version']=version;new.execute('update words set payload=? where id=?',(compact(a),id))
  for key,value in {'version':version,'cardSchemaVersion':'2','schema2BaseVersion':expected}.items():new.execute('insert into metadata values (?,?) on conflict(key) do update set value=excluded.value',(key,value))
 # Membership, analyses, written boundaries, source variants and counts unchanged.
 for id,payload in old.execute('select id,payload from words'):
  a=json.loads(payload);b=json.loads(new.execute('select payload from words where id=?',(id,)).fetchone()[0]);a.pop('version');b.pop('version');assert a==b
 for id,payload in old.execute('select id,payload from morphemes'):
  a=json.loads(payload);b=cards[id]
  for key in a.keys()-{'version','structure','history'}:assert a[key]==b[key],(id,key)
 tables=[]
 for (name,) in old.execute("select name from sqlite_master where type='table' and name not in ('metadata','words','morphemes')"):
  assert '"' not in name
  def digest(d):return hashlib.sha256(compact(d.execute('select * from "'+name+'" order by '+','.join(str(i+1) for i in range(len(d.execute('pragma table_info("'+name+'")').fetchall())))).fetchall()).encode()).hexdigest()
  assert digest(old)==digest(new),name;tables.append(name)
 assert new.execute('pragma quick_check').fetchone()[0]=='ok';new.close();old.close();assert sha(base)==oldsha;os.chmod(out,0o444)
 report={'version':version,'baseVersion':expected,'baseSha256':oldsha,'sha256':sha(out),'dictionaryVersion':meta['dictionaryVersion'],'researchVersion':meta['researchVersion'],'cards':len(cards),'models':sum(len(c['composition']['models']) for c in cards.values()),'historyNotes':sum(len(c['etymology']['notes']) for c in cards.values()),'chains':sum(len(c['etymology']['chains']) for c in cards.values()),'unchangedTables':tables,'allWordAnalysesPreserved':True,'allCommonCardFieldsPreserved':True}
 out.with_suffix('.report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');return report
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--base',type=Path,required=True);p.add_argument('--out',type=Path,required=True);p.add_argument('--expected',required=True);p.add_argument('--research',type=Path,default=Path(__file__).with_name('research-input.json'));a=p.parse_args();print(json.dumps(build(a.base,a.out,a.research,a.expected)))
