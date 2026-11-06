"""Package a source-audited review. Never writes a dictionary or editorial input."""
import argparse,collections,hashlib,json,sqlite3,sys
from pathlib import Path
from html import escape
from urllib.parse import unquote
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'wiktionary_pilot'))
from pilot import lines,read_json,write_json,spelling_key

def sha(path):
 h=hashlib.sha256()
 with Path(path).open('rb') as f:
  while data:=f.read(8*1024*1024):h.update(data)
 return h.hexdigest()
def canonical(value):return json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':'))
def objsha(value):return hashlib.sha256(canonical(value).encode()).hexdigest()
def db_readonly(path):
 p=Path(path).resolve()
 if not p.is_file() or (Path(str(p)+'-wal').exists() and Path(str(p)+'-wal').stat().st_size):raise ValueError('Use an existing, checkpointed publication snapshot')
 return sqlite3.connect(p.as_uri()+'?mode=ro',uri=True)
def checked_quote(text,needle=None,limit=650):
 start=max(0,text.index(needle)-60) if needle else 0
 end=min(len(text),start+limit)
 return {'text':text[start:end],'span':[start,end],'offsetUnit':'unicode-codepoints'}
PROTO_NEEDLES={3:'др.-русск., русск.-цслав. брити',10:'др.-русск., русск.-цслав. корень',71:'Первичное значение',75:'обручитися'}

def build(trial,decisions_path,publication,out):
 if out.exists():raise ValueError('Output must be a new directory')
 decisions=read_json(decisions_path);changes=trial/'proto-pair-changes.json'
 if sha(changes)!=decisions['sourceChangesSha256']:raise ValueError('Reviewed candidate set changed')
 for name,expected in decisions['evidenceInputSha256'].items():
  if sha(trial/name)!=expected:raise ValueError('Reviewed evidence changed: '+name)
 pairs=read_json(changes)['added'];by_id={r['id']:r for r in pairs}
 entries=decisions['entries']
 if len(by_id)!=85 or len(entries)!=85 or {e['pairId'] for e in entries}!=set(by_id):raise ValueError('Review must cover exactly all 85 pairs')
 if any(e['decision'] not in {'ready','defer','reject'} for e in entries):raise ValueError('Unknown decision')
 baseline=read_json(trial/'verification.json')
 for name,expected in read_json(trial/'inputs-before-matching.json').items():
  if sha(trial/name)!=expected['sha256']:raise ValueError('Source snapshot changed: '+name)
 if sha(publication)!=baseline['publicationSha256']:raise ValueError('Publication changed since the source audit')
 proto={r['id']:r for r in read_json(trial/'interlex-proto-production.json')['rows']}
 wanted={e['sourceEntryId'] for p in pairs for e in p['evidence']}
 witnesses={r['id']:r for r in lines(trial/'historical-witnesses.jsonl') if r['id'] in wanted}
 parent_ids={p for w in witnesses.values() for p in w['parentSourceEntryIds']}
 parents={r['id']:r for r in lines(trial/'ru-context-sources.jsonl') if r['id'] in parent_ids}
 db=db_readonly(publication);version=db.execute("SELECT value FROM metadata WHERE key='version'").fetchone()[0]
 if version!=baseline['publicationVersion']:raise ValueError('Wrong publication version')
 refs=[];source_registry={};review_rows=[];native_guards={}
 for verdict in entries:
  p=by_id[verdict['pairId']]
  if (p['lexemeId'],p['protoArticleId'],p['name'])!=(verdict['lexemeId'],verdict['protoArticleId'],verdict['name']):raise ValueError('Reviewed pair identity changed')
  row=db.execute('SELECT payload FROM articles WHERE id=?',(p['lexemeId'],)).fetchone()
  if not row or p['protoArticleId'] not in proto:raise ValueError('Unknown target ID')
  a=json.loads(row[0]);article=proto[p['protoArticleId']]
  if a['name']!=p['name'] or article['lemma']!=verdict['protoArticleLemma']:raise ValueError('Reviewed headings changed')
  evidence=[];seen=set()
  for e in p['evidence']:
   w=witnesses[e['sourceEntryId']];parent=parents[w['parentSourceEntryIds'][0]];raw=parent['raw']
   texts=([raw['etymology_text']] if raw.get('etymology_text') else [])+raw.get('etymology_texts',[])
   text=texts[w['textIndex']];start,end=w['span']
   if text[start:end]!=w['word']:raise ValueError('Historical evidence offset changed')
   key=(w['word'],w['classification'],text)
   if key in seen:continue
   seen.add(key)
   evidence.append({'witness':w,'parent':parent,'text':text,'method':e['nativeMethod'],'protoMethod':e['protoMethod'],'term':e['term']})
  evidence.sort(key=lambda e:(spelling_key(unquote(e['witness']['sourceUrl'].rsplit('/',1)[-1]))!=spelling_key(e['witness']['word']),e['method']=='existing-search-key',len(e['text']),e['witness']['id']))
  ev=evidence[0];w=ev['witness'];start,end=w['span'];wiki_quote={'text':ev['text'][max(0,start-180):end+230],'span':[max(0,start-180),min(len(ev['text']),end+230)],'offsetUnit':'unicode-codepoints'}
  proto_quote=checked_quote(article['body'],PROTO_NEEDLES.get(verdict['number']))
  native_sources=[{k:s[k] for k in ['id','title','sourceCode','preview','mappingStatus']} for s in a['sources']]
  review_rows.append({**verdict,'nativePos':a['pos'],'nativeProperties':a['properties'],'nativeSources':native_sources,'protoBodySha256':hashlib.sha256(article['body'].encode()).hexdigest(),'protoSourceUrl':article['sourceUrl'],'protoQuote':proto_quote,'selectedWitnessId':w['id'],'wikiUrl':w['sourceUrl'],'wikiQuote':wiki_quote,'historicalSpelling':w['word'],'sourceClassification':w['classification'],'allWitnessIds':sorted({e['sourceEntryId'] for e in p['evidence']}),'numberOfIndependentScholarlyConfirmations':None})
  if verdict['decision']!='ready':continue
  wiki_id='wiktionary:ru:'+ev['parent']['id'];proto_id='interlex:proto:'+str(article['id'])
  source_registry[wiki_id]={'id':wiki_id,'kind':'wiktionary','edition':'ru','pageUrl':ev['parent']['sourceUrl'],'recordId':ev['parent']['id'],'snapshotSha256':ev['parent']['snapshotSha256'],'recordSha256':objsha(ev['parent']),'revisionId':None,'raw':ev['parent']['raw'],'licenseNotice':'Wiktionary attribution and applicable CC BY-SA / page-specific terms must accompany publication.'}
  source_registry[proto_id]={'id':proto_id,'kind':'interlex-proto','articleId':article['id'],'lemma':article['lemma'],'sourceUrl':article['sourceUrl'],'bodySha256':hashlib.sha256(article['body'].encode()).hexdigest(),'snapshotSha256':baseline['interlexProtoSnapshotSha256'],'quote':proto_quote,'bibliographyLocation':'interlex article body; retained unchanged','ocrCorrected':False}
  provenance={'schema':'cs-etymology-provenance-v1','reviewId':p['id'],'reviewedAtDate':decisions['reviewedAtDate'],'reviewer':decisions['reviewer'],'decisionScope':'historical-source-correspondence; no direct-inheritance or all-senses assertion','sourceIds':[wiki_id,proto_id],'wiktionary':{'sourceId':wiki_id,'witnessId':w['id'],'historicalSpelling':w['word'],'classification':w['classification'],'quote':wiki_quote,'etymologyTextIndex':w['textIndex'],'term':ev['term']},'proto':{'sourceId':proto_id,'quote':proto_quote},'nativeSourceIds':[s['id'] for s in a['sources']]}
  reference={'articleId':article['id'],'lemma':article['lemma'],'relation':'attested-in','evidence':verdict['publicNote']+' Источник сопоставления: '+w['sourceUrl']+'. Проверена историческая ссылка на статью; прямое наследование не утверждается.','sourceUrl':article['sourceUrl'],'bodySha256':source_registry[proto_id]['bodySha256'],'status':'verified','provenance':provenance}
  native_guards[a['id']]=hashlib.sha256(row[0].encode()).hexdigest()
  refs.append({'pairId':p['id'],'lexemeId':a['id'],'reference':reference})
 db.close()
 payload={'schema':'cs-reviewed-etymology-import-v1','reviewManifestSha256':sha(decisions_path),'baseline':{'publicationVersion':version,'publicationSha256':baseline['publicationSha256'],'protoSnapshotSha256':baseline['interlexProtoSnapshotSha256'],'nativePayloadSha256':native_guards},'reviewDecisions':entries,'references':refs,'sources':source_registry,'policy':{'appendOnly':True,'preserveAllExistingFields':True,'overwriteEditorialDecisions':False,'requiresFreshSnapshotCheckBeforeRelease':True,'directInheritanceAsserted':False,'productionApplied':False}}
 bundle={**payload,'bundleId':objsha(payload)}
 out.mkdir(parents=True)
 write_json(out/'import-bundle.json',bundle);write_json(out/'audit-85.json',review_rows)
 rows=[]
 for r in review_rows:
  text=lambda v:escape(str(v))
  rows.append('<tr data-decision="'+r['decision']+'">'+''.join('<td>'+text(v)+'</td>' for v in [r['number'],r['decision'],r['name'],str(r['protoArticleId'])+' '+r['protoArticleLemma'],r['reason'],'; '.join(s['preview'] for s in r['nativeSources'])[:700],r['wikiQuote']['text'],r['protoQuote']['text']])+f'<td><a href="{escape(r["wikiUrl"],quote=True)}">Викисловарь</a><br><a href="{escape(r["protoSourceUrl"],quote=True)}">Источник interlex</a></td></tr>')
 (out/'review-85.html').write_text('<!doctype html><html lang="ru"><meta charset="utf-8"><title>Проверка 85 этимологических связей</title><style>body{font:15px system-ui;margin:24px;background:#faf8f1;color:#222}table{border-collapse:collapse}th,td{padding:10px;border:1px solid #bbb;vertical-align:top}th{position:sticky;top:0;background:#eee}tr[data-decision=reject]{background:#f9e5e3}tr[data-decision=defer]{background:#fff3ce}tr[data-decision=ready]{background:#e7f3e5}button{padding:10px;margin:5px}</style><h1>85 новых пар: проверка источников и значений</h1><p>Все пары получили отдельное решение; фильтры показывают готовые, спорные и отклонённые ссылки. Рабочие базы не изменены. OCR в цитатах сохранён; принятое соответствие не утверждает единственную этимологию или прямое наследование.</p><div>'+''.join('<button onclick="filter(\''+v+'\')">'+label+'</button>' for v,label in [('all','Все'),('ready','Готовы'),('defer','Спорные'),('reject','Отклонены')])+'</div><table><tr><th>№</th><th>Решение</th><th>Лексема</th><th>interlex</th><th>Основание</th><th>Значения нашей статьи</th><th>Викисловарь</th><th>Proto-статья</th><th>Ссылки</th></tr>'+''.join(rows)+'</table><script>function filter(v){document.querySelectorAll("tr[data-decision]").forEach(r=>r.hidden=v!=="all"&&r.dataset.decision!==v)}</script></html>')
 summary={'reviewedPairs':len(entries),'decisions':dict(collections.Counter(e['decision'] for e in entries)),'readyLexemes':len(native_guards),'bundleId':bundle['bundleId'],'sources':len(source_registry),'baseline':payload['baseline'],'allSourceSpansValidated':True,'sourceSnapshotsPreserved':True,'productionApplied':False}
 write_json(out/'summary.json',summary);print(json.dumps(summary,ensure_ascii=False,indent=2))
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--trial',type=Path,default=Path('import/wiktionary-full'));p.add_argument('--decisions',type=Path,default=Path('data/wiktionary/review-85.json'));p.add_argument('--publication',type=Path,default=Path('import/cs-publication-v1.sqlite'));p.add_argument('--out',type=Path,default=Path('import/wiktionary-reviewed/package-final'));a=p.parse_args();build(a.trial,a.decisions,a.publication,a.out)
