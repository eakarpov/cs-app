"""Explicit historical spelling witnesses from Russian Wiktionary etymologies.
A Russian headword's reconstruction is NOT automatically the etymon of a cited word.
"""
import re, unicodedata
from urllib.parse import unquote
from pilot import proto_references, spelling_key

MARKER=re.compile(r'(?<!\w)(?P<qualifier>поздне|ранне|ново)?(?P<label>ст\.-слав\.|старослав\.|старославянск(?:ого|ий)|церк\.-слав\.|церковнославянск(?:ого|ий)|цслав\.|др\.-русск\.|древнерусск(?:ого|ий))',re.I)
ABBREVIATIONS={'русск','белор','укр','болг','сербохорв','словенск','чешск','польск','словацк','греч','лат','санскр','лит','праслав','индоевр','др','ст','нов','род','вин','дат','мест','мн','ед','ср','см','п','сербск','церк','прич','нареч','местоим','прилаг','сущ','глаг','рус','стар','слав','древн','им','твор','зват','жен','муж'}
BLOCKED={'далее','затем','язык','языка','языке','языков','слов','слова','словообразование','формы','форм','форме','форма','суффикс','суффикса','приставка','приставки','существительного','существительное','глагола','глагол','вариант','варианта','см','ср','из','от','в','который','которого','также','при','для','с','со','как','производное','исконнорусск','заимствование','заимствовано','предлог','предлога','книжное','книжн','русизм','калька','перевод','буквально','первоначально','обычно','собственно','преимущественно','только','вместо','названием','название','названия','знач','значение','значении','употребляется','обозначение','обозначения','происхождение','словообразовательный','употребление','употребления','источники','источниках','памятниках','памятники','засвидетельствовано','заимств','через','по','и','а'}

def classify_label(label):
    value=label.lower()
    if value.startswith(('ст.-','старослав')):return 'old-church-slavonic'
    if value.startswith(('др.-','древнерус')):return 'old-east-slavic'
    return 'church-slavonic'

def anchor_class(target):
    if '#' not in target:return None
    anchor=unquote(target.split('#',1)[1]).replace('_',' ').lower()
    for prefix,kind in [('старославянский','old-church-slavonic'),('церковнославянский','church-slavonic'),('древнерусский','old-east-slavic')]:
        if anchor.startswith(prefix):return kind
    return None

def is_cyrillic_word(term):
    letters=[c for c in term if c.isalpha()]
    return bool(letters) and all('CYRILLIC' in unicodedata.name(c,'') for c in letters) and all(c.isalpha() or unicodedata.category(c).startswith('M') or c in '-’\u02bc' for c in term)

def read_term(text,offset):
    while offset<len(text) and (text[offset].isspace() or text[offset] in '«„“"'):offset+=1
    start=offset
    while offset<len(text) and (text[offset].isalpha() or unicodedata.category(text[offset]).startswith('M') or text[offset] in '-’\u02bc'):offset+=1
    term=text[start:offset]
    # A following dot often means another abbreviated language or a case label.
    if not term or term.lower() in BLOCKED or not is_cyrillic_word(term) or (offset<len(text) and text[offset]=='.' and term.lower() in ABBREVIATIONS):return None
    return term,start,offset

def negative_near(text,offset):
    left=text[max(0,offset-120):offset]
    return bool(re.search(r'\b(?:неверн\w*|ошибоч\w*|отверг\w*|неправил\w*|несостоятель\w*)\b|\bне\s+(?:происходит|связан\w*|восходит|заимств\w*)',left,re.I))

def proto_contexts(text):
    result=[]
    for marker in re.finditer(r'\bпраслав(?:\.|янск\w*)',text,re.I):
        tail=text[marker.end():marker.end()+130]
        star=re.search(r'\*([^\s,;«»]+)',tail)
        if not star:continue
        between=tail[:star.start()]
        if re.search(r'праиндо|индоевр|др\.-|греч|санскр|лит\.',between,re.I):continue
        term='*'+star[1].rstrip('.:')
        result.append({'term':term,'markerSpan':[marker.start(),marker.end()],'termSpan':[marker.end()+star.start(),marker.end()+star.end()],'negativeContext':negative_near(text,marker.start())})
    return result

def shared_origin_claims(text,witness,refs):
    span=witness.get('span')
    if span is None:return []
    results=[]
    for ref in refs:
        if ref['negativeContext'] or witness.get('negativeContext'):continue
        end=ref['termSpan'][1]
        if end>=span[0]:continue
        between=text[end:span[0]]
        # Only an explicit descendant enumeration licenses this source assertion.
        if len(between)>2500 or re.search(r'[.!?]\s+(?=[А-ЯЁA-Z])',between) or not re.search(r'от\s+котор(?:ого|ой|ых).*?(?:произошл|происход|образовал)',between,re.I|re.S):continue
        if re.search(r'\bпраслав|праиндо|(?:сложен|состоит|образован)\w*\s+из',between,re.I):continue
        if re.search(r'сюда\s+же|[;:]\s*ср\.?\s*:',between,re.I):continue
        results.append({**ref,'basis':'explicit-shared-origin-enumeration','relation':'source-asserted-common-origin','eligibleForLexemeProto':True})
    return results

def extract_witnesses(raw):
    texts=raw.get('etymology_texts',[])
    if raw.get('etymology_text'):texts=[raw['etymology_text']]+texts
    texts=[x for x in texts if isinstance(x,str)]
    linked_terms={spelling_key(v) for link in raw.get('etymology_links',[]) if isinstance(link,list) for v in link[:1] if isinstance(v,str) and is_cyrillic_word(v)}
    witnesses=[];unresolved=[];contexts=[]
    for index,text in enumerate(texts):
        refs=proto_contexts(text)
        for ref in refs:contexts.append({**ref,'textIndex':index,'eligibleForLexemeProto':False,'basis':'proto-context-only','relation':'co-occurrence-only'})
        for marker in MARKER.finditer(text):
            classification=classify_label(marker['label']);offset=marker.end();found=[]
            for position_in_list in range(12):
                term=read_term(text,offset)
                if term is None:break
                word,start,end=term
                # Comma-separated prose tails need a linked lexical witness.
                if position_in_list and spelling_key(word) not in linked_terms:break
                w={'word':word,'classification':classification,'basis':'explicit-language-marker-prose','textIndex':index,'span':[start,end],'markerSpan':[marker.start(),marker.end()],'sourceLanguageLabel':marker['label'],'sourceQualifier':marker['qualifier'],'negativeContext':negative_near(text,marker.start()),'protoClaims':[]}
                w['protoClaims']=shared_origin_claims(text,w,refs) if classification!='old-east-slavic' else []
                found.append(w);witnesses.append(w)
                offset=end
                while offset<len(text) and text[offset].isspace():offset+=1
                if offset>=len(text) or text[offset] not in ',/':break
                offset+=1
            if not found:unresolved.append({'textIndex':index,'span':[marker.start(),marker.end()],'label':marker[0],'context':text[max(0,marker.start()-70):marker.end()+180]})
    for position,link in enumerate(raw.get('etymology_links',[])):
        if not isinstance(link,list) or len(link)<2 or not isinstance(link[1],str):continue
        classification=anchor_class(link[1])
        if classification is None:continue
        target=unquote(link[1].split('#',1)[0]);display=link[0] if isinstance(link[0],str) else target
        if not is_cyrillic_word(target):continue
        spelling=display if is_cyrillic_word(display) and spelling_key(display)==spelling_key(target) else target
        existing=[w for w in witnesses if w['classification']==classification and spelling_key(w['word'])==spelling_key(spelling)]
        if existing:
            for w in existing:w.setdefault('wikiLinks',[]).append({'position':position,'display':display,'target':link[1]});w['basis']='language-marker-and-anchored-wikilink';w['lemmaTarget']=target
        else:
            witnesses.append({'word':spelling,'lemmaTarget':target,'classification':classification,'basis':'explicit-language-anchor','wikiLinks':[{'position':position,'display':display,'target':link[1]}],'textIndex':None,'span':None,'sourceLanguageLabel':classification,'sourceQualifier':None,'negativeContext':None,'protoClaims':[]})
    return {'witnesses':witnesses,'unresolvedMarkers':unresolved,'protoContexts':contexts,'texts':texts}
