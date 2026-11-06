"""Read-only Wiktionary pilot. All writes are confined to an artifact directory.
Source spellings are preserved. Matching keys are never published spellings.
"""
import argparse, collections, gzip, hashlib, json, re, time, unicodedata
from pathlib import Path
from urllib.parse import quote, unquote

LANGS={'старославянский':'old-church-slavonic','церковнославянский':'church-slavonic','old church slavonic':'old-church-slavonic','church slavonic':'church-slavonic','proto-slavic':'proto-slavic','праславянский':'proto-slavic'}
CS_CODES={'cu','chu','chu-ru','zls-chs'}
RU_HINTS=(b'cu',b'chu',b'zls-chs',b'sla-pro')+tuple(name.encode('utf-8') for key in LANGS for name in [key,key.capitalize()])
SOURCE_FILES=[('ru-extract.jsonl.gz','ru','raw-wiktextract'),('en-ocs.jsonl','en','postprocessed-language-export'),('en-proto.jsonl','en','postprocessed-language-export')]
ACCENTS='\u0300\u0301\u0302\u0311\u030f\u0485\u0486'

def digest(data): return hashlib.sha256(data).hexdigest()
def read_json(path): return json.loads(Path(path).read_text())
def write_json(path,data): Path(path).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
def lines(path):
    with Path(path).open() as f:
        for line in f:
            yield json.loads(line)
def dump_line(file,data): file.write(json.dumps(data,ensure_ascii=False,separators=(',',':'))+'\n')

def spelling_key(word):
    # Keep breve (й), diaeresis, titlo, yers, yat and nasal letters distinct.
    text=unicodedata.normalize('NFD',word.lower().strip())
    return unicodedata.normalize('NFC',''.join(c for c in text if c not in ACCENTS))

ORTHO_MAP=str.maketrans({'ѹ':'у','ꙋ':'у','ꙑ':'ы','є':'е','ѻ':'о','ᲂ':'о','ᲀ':'в','ᲁ':'д','ᲃ':'с','ᲄ':'т','ᲅ':'т','ᲆ':'ъ','ᲇ':'ѣ','ᲈ':'у'})
def orthography_key(word):
    return spelling_key(word).replace('ᲂу','у').replace('оу','у').translate(ORTHO_MAP)

def proto_key(word,fold_accents=False,repair=False):
    value=unquote(word).strip().lstrip('*').rstrip('.,;').strip()
    if repair: value=value.translate(str.maketrans({'а':'a','о':'o','е':'e','р':'r','с':'c','х':'h','у':'u','в':'v','н':'n','к':'k','м':'m','т':'t'}))
    value=unicodedata.normalize('NFD',value)
    if fold_accents:value=''.join(c for c in value if c not in '\u0300\u0301\u030f\u0311')
    return unicodedata.normalize('NFC',value)

def proto_heads(lemma):
    # Keep phrases intact: 'ob bokъ' must never become the head 'ob'.
    # Strip only explicit grammatical/homonym metadata, never arbitrary words.
    terms=[]
    for part in lemma.split('/'):
        part=part.strip().lstrip('*').strip()
        part=re.sub(r'\s+род\s+п\b.*$', '', part)
        part=re.sub(r'\s+(?:I{1,3}|IV|V|VI{0,3}|IX|X|l)$', '', part)
        part=re.sub(r'\s*\(sę\)', '', part)
        for token in re.split(r'\s+\*',part):
            token=token.strip().lstrip('*').rstrip('.,;:')
            if not token or '*' in token or any(c in token for c in '()[]{}=+'):continue
            if all(c.isalpha() or unicodedata.category(c).startswith('M') or c.isspace() or c in "ьъ-ʹ’'" for c in token):terms.append(token)
    return list(dict.fromkeys(terms))

def language_class(raw):
    name=raw.get('lang','').lower().removesuffix(' язык')
    if name in LANGS:return LANGS[name]
    code=raw.get('lang_code','')
    if code in CS_CODES or code.startswith('zls-chs-'):return 'unclassified-church-slavonic'
    return None

def features(raw):
    senses=raw.get('senses',[])
    ety=[raw.get('etymology_text','')]+raw.get('etymology_texts',[])
    meaningful=[t for t in ety if isinstance(t,str) and t.strip() and not re.fullmatch(r'(?:из|от|происходит от)?\s*\?+[. ]*',t.strip(),re.I)]
    return {'senses':sum(bool(s.get('glosses')) and 'no-gloss' not in s.get('tags',[]) for s in senses),
      'examples':sum(len(s.get('examples',[])) for s in senses),'forms':len(raw.get('forms',[])),
      'hasEtymology':bool(meaningful),'hasUnresolvedEtymology':any('??' in t for t in ety if isinstance(t,str)),
      'hasTemplateExpansionWarning':any('data-lang=' in t.get('expansion','') for t in raw.get('etymology_templates',[]))}

def extract(root):
    counts=collections.Counter();source_stats=[]
    out=root/'selected.jsonl.part'
    with out.open('w') as output:
      for filename,edition,kind in SOURCE_FILES:
        path=root/'raw'/filename
        meta=read_json(path.with_suffix(path.suffix+'.http.json'))
        sha=hashlib.sha256()
        with path.open('rb') as f:
          while chunk:=f.read(8*1024*1024):sha.update(chunk)
        if sha.hexdigest()!=meta['sha256']:raise ValueError('Archive checksum mismatch: '+filename)
        count=selected=0;langs=collections.Counter()
        stream=gzip.open(path,'rb') if path.suffix=='.gz' else path.open('rb')
        with stream:
          for line in stream:
            count+=1
            # JSON is parsed before a record can be selected; no substring-based language attribution.
            if edition=='ru' and not any(hint in line for hint in RU_HINTS):continue
            raw=json.loads(line);group=language_class(raw)
            if group is None or not raw.get('word'):continue
            if edition=='en' and group not in {'old-church-slavonic','church-slavonic','proto-slavic'}:continue
            selected+=1;langs[group]+=1
            title=raw.get('original_title') or ('Reconstruction:Proto-Slavic/'+raw['word'].lstrip('*') if group=='proto-slavic' and edition=='en' else raw['word'])
            source_id=digest((edition+'\0'+line.decode()).encode())
            record={'id':source_id,'edition':edition,'language':raw.get('lang'),'languageCode':raw.get('lang_code'),'classification':group,'word':raw['word'],'pos':raw.get('pos'),'sourceUrl':f'https://{edition}.wiktionary.org/wiki/'+quote(title,safe=':/'),
              'acquisitionKind':kind,'snapshotSha256':meta['sha256'],'revisionId':None,'revisionStatus':'not-exposed-by-export','historicalDate':None,'raw':raw,'features':features(raw)}
            dump_line(output,record);counts[edition+':'+group]+=1
        source_stats.append({'file':filename,'edition':edition,'kind':kind,'rowsScanned':count,'selectedRows':selected,'byClassification':dict(langs),'download':meta,'gzipCrcValidated':path.suffix=='.gz'})
    out.rename(root/'selected.jsonl')
    report={'completedAtUtc':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),'counts':dict(counts),'sources':source_stats,'rawRecordsPreserved':True,'writesToWorkingDatabases':False}
    write_json(root/'extraction.json',report);print(json.dumps(report['counts'],ensure_ascii=False))

def form_of(raw):
    return list(dict.fromkeys(v['word'] for sense in raw.get('senses',[]) for v in sense.get('form_of',[]) if isinstance(v,dict) and isinstance(v.get('word'),str)))

def candidate_terms(record):
    raw=record['raw'];parents=form_of(raw)
    # Inflected entries are aligned through the source's lemma, never silently promoted to lexemes.
    result=[(x,'source-form-of') for x in parents] if parents else [(record['word'],'headword')]
    if not parents:
      for f in raw.get('forms',[]):
        if 'romanization' in f.get('tags',[]):continue
        if set(f.get('tags',[])) & {'canonical','alternative','alternative-form','Cyrillic'} and f.get('form'):result.append((f['form'],'source-alternative'))
    return list(dict.fromkeys(result))

class NativeIndex:
    def __init__(self,data,civil_keys):
        self.rows={r['id']:r for r in data['rows']};self.civil=civil_keys
        self.maps=[collections.defaultdict(list) for _ in range(3)]
        for row in data['rows']:
          for v in row['variants']:
            for index,key in enumerate([spelling_key(v['value']),orthography_key(v['value']),v['civilKey']]):
              self.maps[index][key].append((row['id'],v['value'],v['origin']))
    def match(self,word,pos=None):
        result=[]
        for level,key in enumerate([spelling_key(word),orthography_key(word),self.civil.get(word)]):
          if not key:continue
          for id,value,origin in self.maps[level].get(key,[]):
            row=self.rows[id]
            result.append({'lexemeId':id,'name':row['name'],'pos':row['pos'],'method':['accent-insensitive-spelling','script-variant-key','existing-search-key'][level],'matchedSpelling':value,'nativeSpellingOrigin':origin,'posCompatible':compatible_pos(pos,row['pos'],row.get('properties',[])),'nativeGrammarProperties':row.get('properties',[])})
          if result:break
        dedup={}
        for r in result:dedup.setdefault(r['lexemeId'],r)
        return list(dedup.values())

def compatible_pos(source,target,properties=()):
    groups={'noun':'noun','name':'noun','proper-name':'noun','verb':'verb','adj':'adjective','adjective':'adjective','adv':'adverb','adverb':'adverb','pron':'pronoun','pronoun':'pronoun','num':'numeral','numeral':'numeral','prep':'preposition','preposition':'preposition','conj':'conjunction','conjunction':'conjunction','particle':'particle','intj':'interjection','interjection':'interjection'}
    if source in {'character','symbol','punct','punctuation'}:return source==target
    a=groups.get(source);targets={groups[target]} if target in groups else set()
    if not targets and properties:
      legacy={'ADV':'adverb','ADVPRO':'adverb','NUM':'numeral','CONJ':'conjunction','SPRO':'pronoun','PR':'preposition','PART':'particle','INTJ':'interjection','N':'noun','S':'noun','V':'verb','A':'adjective','APRO':'adjective'}
      targets={legacy[t] for t in properties[0].split('/') if t in legacy}
    return None if a is None or not targets else a in targets

class ProtoIndex:
    def __init__(self,data):
        self.rows={row['id']:row for row in data['rows']}
        self.maps=[collections.defaultdict(set) for _ in range(3)];self.unparsed=[]
        for row in data['rows']:
          body=' '.join(row.get('body','').split())
          if body.startswith('Здесь представлен праславянский лексический фонд на начальные фонемы') and 'на основе объединения этимологических сведений' in body:
            self.unparsed.append({'id':row['id'],'lemma':row['lemma'],'reason':'non-article-index-page'});continue
          heads=proto_heads(row['lemma'])
          if not heads:self.unparsed.append({'id':row['id'],'lemma':row['lemma']})
          for head in heads:
            for level,key in enumerate([proto_key(head),proto_key(head,True),proto_key(head,True,True)]):self.maps[level][key].add(row['id'])
    def match(self,term):
        for level,key in enumerate([proto_key(term),proto_key(term,True),proto_key(term,True,True)]):
          if key and key in self.maps[level]:
            return [{'articleId':id,'lemma':self.rows[id]['lemma'],'sourceUrl':self.rows[id]['sourceUrl'],'method':['full-proto-head','accent-folded-full-proto-head','homoglyph-repair-full-proto-head'][level]} for id in sorted(self.maps[level][key])]
        return []

def proto_references(record):
    raw=record['raw'];refs=[];code=record.get('languageCode')
    for t in raw.get('etymology_templates',[]):
      args=t.get('args',{});name=t.get('name','')
      if name in {'inh','inherited','der','derived','bor','borrowed'} and args.get('1')==code and args.get('2')=='sla-pro' and args.get('3'):
        refs.append({'term':args['3'].split('<')[0],'basis':'explicit-etymology-template','relation':name,'template':t})
      elif name=='ety' and args.get('1')==code:
        m=re.match(r'sla-pro:([^<\s]+)',args.get('3',''))
        if m:refs.append({'term':m[1],'basis':'explicit-etymology-tree-template','relation':args.get('2','unknown'),'template':t})
    for link in raw.get('etymology_links',[]):
      if isinstance(link,list) and len(link)>1 and isinstance(link[1],str) and link[1].startswith('Reconstruction:Proto-Slavic/'):
        refs.append({'term':unquote(link[1].split('/',1)[1].split('#')[0]),'basis':'untyped-etymology-link','relation':'unspecified','target':link[1]})
    if record.get('edition')=='ru':
      for text in raw.get('etymology_texts',[]):
        match=re.search(r'(?:из|от)\s+праслав(?:янского|\.)?\s*([*][^\s,;«»]+)',text,re.I)
        if match:
          term=match[1].rstrip('.:')
          refs.append({'term':term,'basis':'explicit-proto-origin-in-prose','relation':'unspecified-origin-or-base','sourceText':text})
    # Preserve other prose, but never guess proto terms out of arbitrary quotations.
    dedup={}
    for ref in refs:dedup.setdefault((ref['term'],ref['basis'],ref['relation']),ref)
    return list(dedup.values())

def descendants(record):
    def walk(rows,path):
      for n,row in enumerate(rows):
        if not isinstance(row,dict):continue
        node={k:row[k] for k in ['lang','lang_code','word','raw_tags','tags'] if k in row}
        trail=path+[node];code=row.get('lang_code','')
        if isinstance(row.get('word'),str) and (code in CS_CODES or code.startswith('zls-chs-')):
          yield {'word':row['word'],'languageCode':code,'depth':len(path),'sourcePath':trail,'sourceText':row.get('text'),'sourceTags':row.get('raw_tags',[])+row.get('tags',[]),'relation':'descendant-in-source-tree'}
        for template in row.get('templates',[]):
          args=template.get('args',{});code=args.get('1','')
          if template.get('name') not in {'desc','descendant','l','m'} or not (code in CS_CODES or code.startswith('zls-chs-')):continue
          for key in sorted((k for k in args if k.isdigit() and int(k)>=2),key=int):
            value=args[key]
            if isinstance(value,str) and value.strip():yield {'word':value.split('<')[0],'languageCode':code,'depth':row.get('depth'),'lineIndex':n,'sourceText':row.get('text'),'template':template,'sourcePath':trail,'relation':'descendant-in-source-tree'}
        yield from walk(row.get('descendants',[]),trail)
    yield from walk(record['raw'].get('descendants',[]),[])

def match(root):
    records=list(lines(root/'selected.jsonl'));native_data=read_json(root/'native-index.json');proto_data=read_json(root/'interlex-proto-production.json')
    keys=read_json(root/'civil-keys.json');native=NativeIndex(native_data,keys);proto=ProtoIndex(proto_data)
    counts=collections.Counter();features_by_group=collections.defaultdict(collections.Counter);page_groups=collections.defaultdict(set)
    native_links=[];proto_links=[];unmatched=[];spelling_links=[];proto_wiki=[];all_entries=[]
    for r in records:
      group=r['edition']+':'+r['classification'];page_groups[group].add((r['word'],r['languageCode']))
      features_by_group[group].update({k:int(v) for k,v in r['features'].items()})
      if r['classification']=='proto-slavic':proto_wiki.append(r);continue
      options=[]
      for term,role in candidate_terms(r):
        for m in native.match(term,r['pos']):options.append({**m,'queriedSpelling':term,'spellingRole':role})
      unique={}
      for item in options:unique.setdefault(item['lexemeId'],item)
      options=list(unique.values());compatible=[m for m in options if m['posCompatible'] is not False]
      result={k:r[k] for k in ['id','edition','classification','word','pos','sourceUrl','features']}
      result.update({'status':'proposed' if compatible else 'unmatched','reviewStatus':'pending','candidates':options,'formOf':form_of(r['raw']),'sourceClassificationOnly':True,'historicalDate':None})
      counts[group+':entries']+=1
      category='unique-candidate' if len(compatible)==1 else 'ambiguous' if compatible else 'no-compatible-candidate'
      counts[group+':'+category]+=1;result['matchCategory']=category
      (native_links if compatible else unmatched).append(result);all_entries.append(result)
      for candidate in compatible:
        spelling_links.append({'sourceEntryId':r['id'],'word':r['word'],'sourceLanguage':r['language'],'sourceLanguageCode':r['languageCode'],'izvodClassification':r['classification'],'izvodBasis':'source-language-label-only','lexemeId':candidate['lexemeId'],'currentSpelling':candidate['name'],'method':candidate['method'],'status':'proposed','historicalDate':None,'sourceUrl':r['sourceUrl'],'formOf':form_of(r['raw']),'kind':'inflected-form' if form_of(r['raw']) else 'lemma-spelling'})
      if not form_of(r['raw']):
        for alternative in r['raw'].get('forms',[]):
          if not (set(alternative.get('tags',[])) & {'alternative','alternative-form'}) or not alternative.get('form'):continue
          for candidate in compatible:
            spelling_links.append({'sourceEntryId':r['id'],'word':alternative['form'],'sourceWord':r['word'],'sourceLanguage':r['language'],'sourceLanguageCode':r['languageCode'],'izvodClassification':r['classification'],'izvodBasis':'source-language-label-only','lexemeId':candidate['lexemeId'],'currentSpelling':candidate['name'],'method':'explicit-source-alternative-via-headword','sourceTags':alternative.get('tags',[]),'status':'proposed','historicalDate':None,'sourceUrl':r['sourceUrl'],'kind':'source-alternative-spelling'})
      for ref in proto_references(r):
        proto_links.append({'sourceEntryId':r['id'],'word':r['word'],'sourceUrl':r['sourceUrl'],'nativeCandidates':compatible,'evidence':ref,'interlexCandidates':proto.match(ref['term']),'status':'proposed','direction':'entry-to-proto'})
    reverse=[]
    for r in proto_wiki:
      matches=proto.match(r['word'])
      for desc in descendants(r):
        targets=native.match(desc['word'])
        reverse.append({'protoSourceEntryId':r['id'],'protoWord':r['word'],'protoSourceUrl':r['sourceUrl'],'descendant':desc,'nativeCandidates':targets,'interlexCandidates':matches,'status':'proposed','direction':'proto-to-descendant'})
    outputs={'native-proposals':native_links,'unmatched':unmatched,'spelling-proposals':spelling_links,'etymology-proposals':proto_links,'reverse-proto-proposals':reverse,'interlex-heads-needing-review':proto.unparsed}
    for name,items in outputs.items():
      with (root/(name+'.jsonl')).open('w') as out:
        for item in items:dump_line(out,item)
    # Reproducible stratified review set: no candidate becomes a confirmed identity.
    pools=collections.defaultdict(list)
    for r in all_entries:pools[(r['edition'],r['classification'],r['matchCategory'])].append(r)
    for pool in pools.values():pool.sort(key=lambda r:r['id'])
    sample=[]
    while len(sample)<200 and any(pools.values()):
      for key in sorted(pools):
        if pools[key] and len(sample)<200:sample.append(pools[key].pop(0))
    write_json(root/'review-sample.json',sample)
    from html import escape
    def html_item(r):
      candidates='; '.join(m['name']+' ['+m['lexemeId']+'] — '+m['method']+(' (конфликт части речи)' if m['posCompatible'] is False else '') for m in r['candidates'])
      return '<tr>'+''.join('<td>'+escape(str(x))+'</td>' for x in [r['edition'],r['classification'],r['word'],r['pos'],r['matchCategory'],candidates])+f'<td><a href="{escape(r["sourceUrl"],quote=True)}">Источник</a></td></tr>'
    html='''<!doctype html><html lang="ru"><meta charset="utf-8"><title>Пробное сопоставление Викисловаря</title><style>@font-face{font-family:Monomakh;src:url(../../assets/fonts/MonomakhUnicode.otf)}@font-face{font-family:Shafarik;src:url(../../assets/fonts/Shafarik-Regular.otf)}td:nth-child(3){font-family:Monomakh,Shafarik,serif;font-size:22px}body{font:16px system-ui;margin:24px;color:#202020;background:#faf8f1}table{border-collapse:collapse;width:100%}td,th{border:1px solid #bbb;padding:10px;vertical-align:top}th{position:sticky;top:0;background:#e8e3d6}a{color:#00509a}</style><h1>Пробное сопоставление Викисловаря</h1><p>200 записей для ручной проверки. Все соответствия — предложения. Рабочие базы не изменены. Совпадение ключа не доказывает тождество лексем.</p><table><tr><th>Редакция</th><th>Раздел</th><th>Слово</th><th>Часть речи</th><th>Результат</th><th>Кандидаты typikon-web</th><th>Статья</th></tr>'''+''.join(html_item(r) for r in sample)+'</table></html>'
    (root/'review.html').write_text(html)
    report={'completedAtUtc':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),'publicationVersion':native_data['version'],'nativeArticles':len(native_data['rows']),'interlexProtoArticles':len(proto_data['rows']),'protoSnapshotSource':proto_data['source'],'protoSnapshotExportedAtUtc':proto_data['exportedAtUtc'],'selectedRecords':len(records),'counts':dict(counts),'distinctSourcePages':{k:len(v) for k,v in page_groups.items()},'content':{k:dict(v) for k,v in features_by_group.items()},'nativeProposals':len(native_links),'spellingProposals':len(spelling_links),'directProtoEvidenceRows':len(proto_links),'directProtoEvidenceWithInterlexMatch':sum(bool(r['interlexCandidates']) for r in proto_links),'directProtoChainsWithNativeAndInterlex':sum(bool(r['interlexCandidates'] and r['nativeCandidates']) for r in proto_links),'reverseProtoEvidenceRows':len(reverse),'reverseProtoChainsWithNativeAndInterlex':sum(bool(r['interlexCandidates'] and r['nativeCandidates']) for r in reverse),'protoArticleHeadsNeedingReview':len(proto.unparsed),'reviewSampleSize':len(sample),'distinctDirectLexemeProtoCandidates':len({(m['lexemeId'],p['articleId']) for r in proto_links for m in r['nativeCandidates'] for p in r['interlexCandidates']}),'distinctReverseLexemeProtoCandidates':len({(m['lexemeId'],p['articleId']) for r in reverse for m in r['nativeCandidates'] for p in r['interlexCandidates']}),'confirmedLinksCreated':0,'writesToWorkingDatabases':False,'limitations':['Acquisition kinds in this trial: '+', '.join(sorted({r['acquisitionKind'] for r in records})),'Revision IDs are not exposed by these exports','Language labels do not independently prove an izvod attribution','Search-key and script-variant collisions are review candidates, not identities','Unparsed etymological prose remains in raw records; no invented reconstructions','No automatic new lexemes, schemes, stress or spellings were published']}
    write_json(root/'matching-summary.json',report);print(json.dumps(report,ensure_ascii=False,indent=2))

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('action',choices=['extract','match']);p.add_argument('--root',type=Path,default=Path('import/wiktionary-pilot'));a=p.parse_args()
    (extract if a.action=='extract' else match)(a.root)
