"""Read-only audit. Re-run with --dsl and --lexems pointing to decoded local snapshots."""
import argparse, collections, csv, gzip, hashlib, json, pathlib, re, unicodedata
p=argparse.ArgumentParser();p.add_argument('--dsl',default='Chu-Rus_Reference_v3.dsl.dz');p.add_argument('--lexems',default='/private/tmp/typikon-lexems-audit.json');p.add_argument('--csv',default='/Users/georgecarpow/Documents/own/typikon-web/script-data/data.csv');p.add_argument('--out',default='audit');a=p.parse_args();out=pathlib.Path(a.out);out.mkdir(exist_ok=True)
def norm(s):
 s=unicodedata.normalize('NFD',s or '').lower().replace('ᲂу','у')
 s=''.join(c for c in s if not unicodedata.category(c).startswith('M'))
 for x,y in {'ѣ':'е','ꙋ':'у','ѹ':'у','ѧ':'я','ꙗ':'я','ѩ':'я','ѡ':'о','ѻ':'о','і':'и','ѵ':'и','ѳ':'ф','ѕ':'з','ѱ':'пс','ѯ':'кс','ѿ':'от','є':'е'}.items():s=s.replace(x,y)
 return s.rstrip('ъ').strip()
lex=json.load(open(a.lexems));rows=list(csv.reader(open(a.csv)));csvlex=[r for r in rows[1:] if len(r)>=3]
dsl_path=pathlib.Path(a.dsl)
raw=gzip.open(dsl_path,'rb').read() if dsl_path.suffix=='.dz' else dsl_path.read_bytes()
dsl_text=raw.decode('utf-16') if raw[:2] in (b'\xff\xfe',b'\xfe\xff') else raw.decode('utf-8-sig')
entries=[];heads=[];body=[]
for line in dsl_text.splitlines():
 line=line.rstrip('\n\r')
 if not line or re.match(r'^#[A-Z_]+\s',line):continue
 if line[:1].isspace():body.append(line)
 else:
  if body:entries.append((heads,'\n'.join(body)));heads=[];body=[]
  heads.append(line)
if body:entries.append((heads,'\n'.join(body)))
lookup=collections.defaultdict(list)
for l in lex:lookup[norm(l['name'])].append(l)
labels=collections.Counter();withlabel=collections.Counter();kind=collections.Counter();gram=[];defs=[];targets=set();allheads={h for hs,b in entries for h in hs};broken=collections.Counter();refcount=0
nondefs={'gr','чс'}
for hs,b in entries:
 ls=re.findall(r'\[p\](.*?)\[/p\]',b);labels.update(ls);withlabel.update(set(ls))
 k='lemma_index' if all(h.endswith(':') for h in hs) else 'civil_index' if '[p]' not in b and '[c firebrick]' in b else 'word_or_other';kind[k]+=1
 gs=re.findall(r'\[p\]gr\[/p\]\s*\[ref\](.*?)\[/ref\]\s*([^;\n]*);([^\n]*)',b)
 for target,pos,features in gs:gram.append((hs[0],target,pos.strip(),features));targets.add(target)
 if any(l not in nondefs for l in ls):defs.append((hs,b,sorted(set(ls)-nondefs)))
 for ref in re.findall(r'\[ref\](.*?)\[/ref\]',b):
  refcount+=1
  if ref not in allheads:broken[ref]+=1
exact=[];amb=[];unmatched=[]
for target in sorted(targets):
 matches=lookup.get(norm(target.rstrip(':')),[])
 if len(matches)==1:exact.append(target)
 elif matches:amb.append((target,[m['name'] for m in matches]))
 else:unmatched.append(target)
# Compare all current lemmas to external grammar targets with a broad, lossy candidate key.
externalkeys={norm(t.rstrip(':')) for t in targets};missing=[l for l in lex if norm(l['name']) not in externalkeys]
matcheddefs=[];newdefs=[]
for hs,b,ls in defs:
 (matcheddefs if any(norm(h) in lookup for h in hs) else newdefs).append((hs,ls))
fields=collections.Counter(k for l in lex for k in l);props=collections.Counter((l.get('properties') or '').split(',')[0] for l in lex)
valid=[l for l in lex if l.get('name') and l.get('properties')]
numbered=[t for t in unmatched if re.search(r'_\d+:$',t)]
base_unmatched=[t for t in unmatched if not lookup.get(norm(re.sub(r'_\d+$','',t.rstrip(':'))))]
stat={'method' :'Dump snapshot; normalized matches are candidates, not verified identity. Definition-bearing means any source tag except gr/чс; includes derivation and reference material.', 'dump':{'count':len(lex),'empty_names':sum(not l.get('name') for l in lex),'webmaster_rows':sum(l.get('name')=='webmaster' for l in lex),'empty_properties':sum(not l.get('properties') for l in lex),'zero_scheme':sum(l.get('scheme')=='0' for l in lex),'fields':dict(fields),'empty_scheme':sum(not l.get('scheme') for l in lex),'schemes':len({l['scheme'] for l in lex if l.get('scheme')}),'forms':sum(len(l.get('forms') or []) for l in lex),'empty_forms':sum(not l.get('forms') for l in lex),'pos':dict(props),'duplicate_normalized_keys':sum(len(v)>1 for v in lookup.values())},'csv':{'count':len(csvlex),'valid_rows_same_as_dump':collections.Counter((r[1],r[0],r[2]) for r in csvlex)==collections.Counter((l['name'],l['scheme'],l['properties']) for l in lex if l.get('name') and l.get('name')!='webmaster'),'same_lemma_scheme_pos_as_dump':collections.Counter((r[1],r[0],r[2]) for r in csvlex)==collections.Counter((l['name'],l['scheme'],l['properties']) for l in lex)},'dsl':{'entries':len(entries),'headwords':sum(len(hs) for hs,b in entries),'unique_headwords':len(allheads),'kinds_heuristic':dict(kind),'entries_by_source_tag':dict(withlabel),'grammar_links_parsed':len(gram),'distinct_grammar_targets':len(targets),'source_tagged_excluding_gr_frequency':len(defs),'definition_candidates_matching_current_lemma':len(matcheddefs),'other_definition_candidates':len(newdefs),'refs':refcount,'missing_ref_targets':len(broken),'missing_ref_occurrences':sum(broken.values()),'media_refs':collections.Counter(re.findall(r'\[s\](.*?)\[/s\]',dsl_text))},'join':{'unique_normalized_lemma_candidates':len(exact),'ambiguous_normalized_lemma_candidates':len(amb),'unmatched_external_grammar_targets':len(unmatched),'unmatched_with_homonym_suffix':len(numbered),'unmatched_even_after_removing_homonym_suffix':len(base_unmatched),'remaining_unmatched_examples':base_unmatched[:50],'remaining_unmatched_all_initial_ya':all(t.startswith('я') for t in base_unmatched),'current_lemmas_without_external_grammar_target':len(missing)}}
manifest={str(p):{'bytes':pathlib.Path(p).stat().st_size,'sha256':hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()} for p in [a.dsl,a.lexems,a.csv]}
(out/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2))
(out/'summary.json').write_text(json.dumps(stat,ensure_ascii=False,indent=2))
for name,header,data in [('unmatched-grammar.csv',['external_lemma'],[(x,) for x in unmatched]),('ambiguous-grammar.csv',['external_lemma','current_candidates'],[(t,' | '.join(ms)) for t,ms in amb]),('current-without-external-grammar.csv',['name','scheme','properties'],[(l['name'],l['scheme'],l['properties']) for l in missing]),('new-definition-candidates.csv',['headwords','source_tags'],[(' | '.join(hs),' | '.join(ls)) for hs,ls in newdefs])]:
 with open(out/name,'w') as f:w=csv.writer(f);w.writerow(header);w.writerows(data)
print(json.dumps(stat,ensure_ascii=False,indent=2))
print('unmatched examples',unmatched[:35]);print('ambiguous examples',amb[:10]);print('new definition examples',newdefs[:15])
