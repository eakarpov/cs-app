"""Read-only acceptance of one immutable schema=2 deployment."""
import argparse,json,urllib.request,urllib.error,urllib.parse,sqlite3
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--base',required=True);p.add_argument('--stage',required=True);p.add_argument('--out',required=True);a=p.parse_args();s=Path(a.stage);report=json.loads((s/'candidate.report.json').read_text());version=report['version'];checks=0

def check(ok,label):
 global checks
 assert ok,label;checks+=1

def get(path,status=200,headers=None):
 req=urllib.request.Request(a.base.rstrip('/')+'/'+path,headers={'Accept':'application/json','Cache-Control':'no-cache',**(headers or {})})
 try:r=urllib.request.urlopen(req,timeout=30)
 except urllib.error.HTTPError as error:r=error
 with r:
  check(r.status==status,(path,r.status));check(r.headers.get('Access-Control-Allow-Origin')=='*','CORS')
  return (None if r.status==304 else json.load(r)),r.headers

def card(id,schema=None,v=version):
 return get('morphemes/'+urllib.parse.quote(id,safe='')+'?'+urllib.parse.urlencode({'version':v,**({'schema':schema} if schema is not None else {})}))
ids=['formative_suffix:INF','derivational_suffix:ост','stem_suffix:THEMATIC_A','root:KAJ']
base=sqlite3.connect('file:'+json.loads((s/'state.json').read_text())['morphemes']+'?mode=ro',uri=True)
for id in ids:
 modern,headers=card(id,2);old,deprecated=card(id)
 check(modern['version']==version and modern['schemaVersion']==2,'modern version')
 check('history' not in modern and 'structure' not in modern,'no legacy fields')
 check(deprecated.get('X-Morpheme-Schema-Deprecated')=='true','deprecation')
 check(headers.get('ETag')!=deprecated.get('ETag'),'schema-aware ETag')
 previous=json.loads(base.execute('select payload from morphemes where id=?',(id,)).fetchone()[0]);previous['version']=version;check(previous==old,'exact old representation')
 check(modern['etymology']['chains']==[] and modern['etymology']['relations']==[] and modern['etymology']['nodes']==[],'no inferred chain')
 check(all(source['publicationYear'] is None and source['kind']=='unclassified' for source in modern['sources']),'no inferred source metadata')
 path='morphemes/'+urllib.parse.quote(id,safe='')+'?'+urllib.parse.urlencode({'version':version,'schema':2})
 get(path,304,{'If-None-Match':headers['ETag']})
 if id=='formative_suffix:INF':
  model=modern['composition']['models'][0];check([p['surface'] for p in model['parts']]==['т','и'],'ti composition');check(model['level']=='historical','historical only');check(bool(modern['etymology']['notes'][0]['evidence']),'source evidence')
get('morphemes/formative_suffix%3AINF?version='+version+'&schema=3',400)
get('morphemes/formative_suffix%3AINF?version='+report['baseVersion']+'&schema=2',409)
for wid in ['68399a217310e32be5d77cfc','68399a217310e32be5d76697','68399a217310e32be5d7aed7','68399a217310e32be5d7cc1c']:
 word,_=get('lexemes/'+wid+'/morphemes');check(word['version']==version and len(word['analyses'])==2,'preserved variants')
god,_=get('lexemes/68399a217310e32be5d76a6c/morphemes');root=next(p for p in god['analyses'][0]['parts'] if p['kind']=='root')['morphemeId'];encoded=urllib.parse.quote(root,safe='')
first,_=get('morphemes/'+encoded+'/words?'+urllib.parse.urlencode({'version':version,'limit':1}));second,_=get('morphemes/'+encoded+'/words?'+urllib.parse.urlencode({'version':version,'limit':1,'cursor':first['nextCursor']}));check(first['items'][0]['id']!=second['items'][0]['id'],'distinct pages')
result={'api':a.base,'version':version,'checks':checks,'status':'passed','legacyDeprecated':True,'legacyContentPreserved':True,'explicitModels':report['models'],'historicalNotes':report['historyNotes'],'chains':0,'wordVariantsPreserved':8}
Path(a.out).write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');print(json.dumps(result,ensure_ascii=False))
