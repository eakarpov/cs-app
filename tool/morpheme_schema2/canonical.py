"""Import existing descriptions; never parse prose into historical edges."""
import copy,hashlib,json,re,unicodedata

def compact(x):return json.dumps(x,ensure_ascii=False,sort_keys=True,separators=(',',':'))
def identity(x):return hashlib.sha256(compact(x).encode()).hexdigest()[:24]
def clean(x):return re.sub(r'(?:data|import|/private/tmp)/[^\s;,)]+','редакторский материал',x)
def target(x):
 if x.get('morphemeId'):return {'kind':'morpheme','id':x['morphemeId']}
 if x.get('protoId'):return {'kind':'interlex','protoId':x['protoId'],'bodySha256':x.get('bodySha256')}
 return None

def canonical_card(card,research):
 if card.get('schemaVersion')==2:return copy.deepcopy(card)
 out={k:copy.deepcopy(v) for k,v in card.items() if k not in ('structure','history')}
 registry={}
 def evidence(sources):
  result=[]
  for source in sources:
   sid='source:'+identity(source['title'])
   registry[sid]={'id':sid,'title':source['title'],'publicationYear':None,'kind':'unclassified'}
   result.append({'sourceId':sid,'locator':source.get('locator',''),'quote':None,'supports':'Ссылка из опубликованного описания; область подтверждения изложена в пояснении.'})
  return result
 def note(x,namespace):
  # IDs are assigned once on import, then persisted in the canonical publication.
  return {'id':namespace+':'+identity(x),'title':x['title'],'text':x.get('note',''),'reconstruction':x.get('reconstruction'),'status':x['status'],'evidence':evidence(x.get('sources',[])),'target':target(x)}
 history=card.get('history',[])
 composition={'state':'partial' if card.get('structure') else 'undescribed','models':[],'notes':[note(x,'composition-note') for x in card.get('structure',[])]}
 etymology={'state':'partial' if history else 'undescribed','nodes':[],'relations':[],'chains':[],'notes':[note(x,'history-note') for x in history]}
 allos={v['id']:v for v in card['allomorphs']};morphs={m['id']:m for m in research['morphemes']};sources={s['id']:s for s in research['sources']}
 for e in research['morpheme_etymologies']:
  if e['morpheme_id']!=card['id'] or len(e['components'])<2 or e['allomorph_id'] not in allos:continue
  # The research may be newer than the active database. Only attach a model to
  # an exactly matching published claim; never silently import new research.
  expected={'title':clean(sources[e['source_id']]['title']),'locator':clean(e['locator'])}
  h=next((h for h in history if h.get('reconstruction')==clean(e['reconstruction']) and h.get('note')==clean(e['note']) and h.get('status')==e['status'] and expected in h.get('sources',[])),None)
  if h is None:continue
  parts=[]
  for c in e['components']:
   key={k:c.get(k) for k in ('surface','historical_element','function','morpheme_id')}
   mid=c.get('morpheme_id');m=morphs.get(mid)
   kind=('thematic_vowel' if m and m['kind']=='stem_suffix' and 'THEMATIC' in m['id'] else m['kind']) if m else None
   parts.append({'id':e['id']+':part:'+identity(key),'label':c.get('surface') or c.get('historical_element') or 'Компонент','surface':c.get('surface'),'reconstruction':c.get('historical_element'),'kind':kind,'function':c.get('function'),'status':e['status'],'note':clean(c.get('origin_hypothesis',e['note'])),'evidence':[],'target':{'kind':'morpheme','id':mid} if m and mid!=card['id'] else None})
  assert len({p['id'] for p in parts})==len(parts),'Components need explicit distinct IDs'
  surface=allos[e['allomorph_id']]['surface']
  mode='concatenative' if e['mapping_mode']=='concatenative' and ''.join(p['surface'] or '' for p in parts)==surface else 'unmapped'
  alignment=[];offset=0
  # Align only if each written component begins at a real grapheme boundary.
  # Nontrivial joins are left unmapped for the server's Intl.Segmenter audit.
  for p in parts:
   text=p['surface'] or ''
   if not text or any(unicodedata.combining(ch) for ch in text):mode='unmapped';break
   alignment.append({'allomorphId':e['allomorph_id'],'startGrapheme':offset,'endGrapheme':offset+len(text),'partIds':[p['id']]});offset+=len(text)
  if mode=='unmapped':alignment=[]
  composition['models'].append({'id':e['id'],'title':'Исторический состав','level':'historical','allomorphIds':[e['allomorph_id']],'mappingMode':mode,'status':e['status'],'note':clean(e['note'])+(' Буквенное соответствие компонентов не установлено.' if mode=='unmapped' else ''),'evidence':evidence(h['sources']),'parts':parts,'alignment':alignment})
 if composition['models']:composition['state']='partial'
 out.update(schemaVersion=2,composition=composition,etymology=etymology,sources=list(registry.values()))
 return out
