import argparse,json,urllib.request,urllib.parse
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--base',required=True);p.add_argument('--stage',required=True);p.add_argument('--out',required=True);a=p.parse_args()
s=Path(a.stage);validation=json.loads((s/'validation.json').read_text());dv=validation['dictionaryVersion'];mv=validation['morphemeVersion'];checks=0;results=[]
def check(value,label):
 global checks
 assert value,label
 checks+=1
def get(path):
 url=a.base.rstrip('/')+'/'+path
 req=urllib.request.Request(url,headers={'Accept':'application/json','Cache-Control':'no-cache'})
 with urllib.request.urlopen(req,timeout=30) as r:
  check(r.status==200,path);check(r.headers.get('Access-Control-Allow-Origin')=='*','CORS')
  return json.load(r)
def article(id):
 r=get('lexemes/'+id+'?_ending_check='+dv);check(r['version']==dv,'dictionary version')
 for p in r['paradigms']:
  for slot in p['slots']:
   for f in slot['forms']:
    if f['segments']:check(''.join(x['text'] for x in f['segments'])==f['value'],'exact spelling and accents')
 return r
def endings(r,kind,slot):
 return [v['text'] for p in r['paradigms'] if p['kind']==kind for cell in p['slots'] if cell['id']==slot for f in cell['forms'] for v in f['segments'] or [] if v['kind']=='ending']
v=article('68399a217310e32be5d772b6');check('еши' in endings(v,'verb','presSg2'),'еши')
check('ꙋ' in endings(v,'participle-brev','sgMNDat'),'participle own ending')
check('омꙋ' in endings(v,'participle-plen','sgMNDat'),'passive participle ending')
w=article('68399a217310e32be5d76e64');check('иши' in endings(w,'verb','presSg2'),'иши without competing infinitive stem')
adj=article('68399a217310e32be5d7654e');check('омꙋ' in endings(adj,'adjective-plen','sgMNDat'),'adjective омꙋ');check('ъ' in endings(adj,'adjective-brev','sgMNomAcc'),'hard sign ending')
f=next(f for p in adj['paradigms'] if p['kind']=='adjective-plen' for cell in p['slots'] if cell['id']=='sgMNomAcc' for f in cell['forms'] if f['value']=='без̑печа́лный');check(f['segments'] is None,'unconfirmed spelling stays null')
for id in ['68399a217310e32be5d77cfc','68399a217310e32be5d76697','68399a217310e32be5d7aed7','68399a217310e32be5d7cc1c']:
 r=get('lexemes/'+id+'/morphemes?_ending_check='+mv);check(r['version']==mv,'morpheme binding');check(len(r['analyses'])==2,'all eight variants preserved')
god=get('lexemes/68399a217310e32be5d76a6c/morphemes?_ending_check='+mv);check(god['version']==mv,'word morphemes version')
root=next(p for p in god['analyses'][0]['parts'] if p['kind']=='root')['morphemeId'];encoded=urllib.parse.quote(root,safe='')
card=get('morphemes/'+encoded+'?version='+mv);check(card['version']==mv and card['statistics']['lexemes']>1,'morpheme statistics')
first=get('morphemes/'+encoded+'/words?'+urllib.parse.urlencode({'version':mv,'limit':1}));check(bool(first['nextCursor']),'pagination')
second=get('morphemes/'+encoded+'/words?'+urllib.parse.urlencode({'version':mv,'limit':1,'cursor':first['nextCursor']}));check(first['items'][0]['id']!=second['items'][0]['id'],'no duplicate page')
unknown=get('lexemes/03ee6a4e9f26a3208ca52399/morphemes?_ending_check='+mv);check(unknown['analyses']==[],'unassigned analysis stays empty')
search=get('search?'+urllib.parse.urlencode({'q':'земли','direction':'cu-ru','_ending_check':dv}));check(search['version']==dv,'search version')
with_source=article(search['items'][0]['id']);check(bool(with_source['sources']),'source-backed sample')
source=with_source['sources'][0]['id'];r=get('source-entries/'+urllib.parse.quote(source,safe='')+'?_ending_check='+dv);check(r['publicationVersion']==dv,'source payload available')
result={'api':a.base,'dictionaryVersion':dv,'morphemeVersion':mv,'checks':checks,'status':'passed','confirmedEndings':['еши','иши','ꙋ','омꙋ','ъ'],'unconfirmedSpellingRemainsNull':True,'morphemeVariantsPreserved':8}
Path(a.out).write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');print(json.dumps(result,ensure_ascii=False))
