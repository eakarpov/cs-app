// Run from typikon-web with node --import tsx /absolute/path/to/audit_corpus.cjs
// Reads public corpus exports only; does not connect to MongoDB.
const fs=require('node:fs'),zlib=require('node:zlib'),path=require('node:path');
const root=process.cwd(), out='/Users/georgecarpow/Documents/own/cs-app/audit';
const {normalizeChurchSlavonic}=require(path.join(root,'src/utils/churchSlavonic.ts'));
const {WORD_PATTERN,isAbbreviated}=require(path.join(root,'src/lib/accents/core.ts'));
const {decline,conjugate,declineAdjective}=require(path.join(root,'src/lib/morphology/decline.ts'));
const {partOfSpeech}=require(path.join(root,'src/lib/morphology/tags.ts'));
const key=s=>normalizeChurchSlavonic(s||'').trim().replace(/ъ$/,'');
const readLines=file=>zlib.gunzipSync(fs.readFileSync(file)).toString('utf8').trim().split('\n').map(l=>JSON.parse(l));
const lex=JSON.parse(fs.readFileSync('/private/tmp/typikon-lexems-audit.json'));
let stored=new Set(),generated=new Set(),dsl=new Set();
for(const l of lex){if(!l.name||l.name==='webmaster')continue;stored.add(key(l.name));if(l.search)stored.add(key(l.search));for(const f of l.forms||[])if(f.value)stored.add(key(f.value));let fn={noun:decline,adjective:declineAdjective,verb:conjugate}[partOfSpeech(l.properties||'')];if(fn){let p=fn(l);if(p){let walk=x=>{if(typeof x==='string')generated.add(key(x));else if(x&&typeof x==='object')Object.values(x).forEach(walk);};walk(p);}}}
console.log('Built current indices',stored.size,generated.size);
let heads=[],body=[],dslEntries=0;
function flush(){if(body.some(l=>l.includes('[p]gr[/p]')&&l.includes('[ref]')))for(const h of heads)if(!h.endsWith(':'))dsl.add(key(h));heads=[];body=[];dslEntries++;}
const dslFile='/Users/georgecarpow/Documents/own/cs-app/Chu-Rus_Reference_v3.dsl.dz';
for(const l of zlib.gunzipSync(fs.readFileSync(dslFile)).toString('utf8').split(/\r?\n/)){if(!l||l.startsWith('#')||l.charCodeAt(0)===0xfeff)continue;if(/^\s/.test(l))body.push(l);else{if(body.length)flush();heads.push(l);}}if(body.length)flush();
console.log('Built external form index',dsl.size);
const books=readLines(path.join(root,'data-dump/corpus/books.jsonl.gz'));const byBook=new Map(books.map(b=>[b._id,b]));
const texts=readLines(path.join(root,'data-dump/corpus/texts.jsonl.gz'));
const selected=texts.filter(d=>['cu','cu_gr'].includes(byBook.get(d.bookId)?.language)&&typeof d.content==='string');
let categories={},unknown=new Map(),types={};let docsByLang={};
function scan(doc,lang){docsByLang[lang]=(docsByLang[lang]||0)+1;let count=categories[lang]??={tokens:0,stored:0,generated_candidate:0,external_grammar_candidate:0,unresolved:0,unresolved_abbreviated:0,unresolved_mixed_script:0};let unique=types[lang]??={all:new Set(),unresolved:new Set()};let content=doc.content.replace(/<[^>]*>/g,' ').replace(/\{k\|([^}]*)\}/g,'$1').replace(/\{[^}]*\}/g,' ');for(const m of content.matchAll(/[\p{L}][\p{L}\p{M}]*/gu)){let spelling=m[0],k=key(spelling);if(!k||!/[\p{Script=Cyrillic}]/u.test(spelling))continue;let cat=stored.has(k)?'stored':generated.has(k)?'generated_candidate':dsl.has(k)?'external_grammar_candidate':'unresolved';count.tokens++;count[cat]++;unique.all.add(k);if(cat==='unresolved'){unique.unresolved.add(k);let abbr=isAbbreviated(spelling);if(abbr)count.unresolved_abbreviated++;if(/\p{Script=Latin}/u.test(spelling))count.unresolved_mixed_script++;let row=unknown.get(k);if(!row){row={key:k,count:0,texts:new Set(),spellings:new Map(),examples:[],abbreviated:false,layers:new Set()};unknown.set(k,row);}row.count++;row.texts.add(doc._id);row.layers.add(lang);row.spellings.set(spelling,(row.spellings.get(spelling)||0)+1);row.abbreviated ||= abbr;if(row.examples.length<3&&!row.examples.some(e=>e.textId===doc._id))row.examples.push({textId:doc._id,alias:doc.alias||null,bookId:doc.bookId,spelling,context:content.slice(Math.max(0,m.index-65),m.index+spelling.length+65).replace(/\s+/g,' ')});}}}
for(const d of selected)scan(d,byBook.get(d.bookId).language);
// Bible is a separate control layer, not mixed with the prose totals.
for(const d of readLines(path.join(root,'data-dump/bible/bible-verses-cs-eliz.jsonl.gz')))scan(d,'bible_cs_eliz');
let summary={snapshot:'2026-09-26 public corpus export',selection:'books.language in cu/cu_gr; content only; excludes ru/orv/other languages. Bible is a separate layer.',tokenizer:'Unicode letter/mark sequences containing Cyrillic, retaining mixed-script words as whole tokens; HTML tags and brace metadata removed; no cross-line hyphen joining; broad project normalization removes accents, graphic variants and final hard sign; existing lexeme.search aliases are included; tokens without Unicode letters are excluded. Matching only yields candidates, not disambiguated analyses.',priority:['stored','generated_candidate','external_grammar_candidate','unresolved'],documents:docsByLang,indices:{stored:stored.size,generated:generated.size,external_grammar:dsl.size},layers:{}};
for(const [lang,c] of Object.entries(categories))summary.layers[lang]={...c,unique_normalized_tokens:types[lang].all.size,unique_unresolved_tokens:types[lang].unresolved.size};
const sorted=[...unknown.values()].sort((a,b)=>b.count-a.count);const esc=s=>'"'+String(s??'').replaceAll('"','""')+'"';
const header=['key','tokens','documents','spellings','layers','has_abbreviation','example_text_id','example_alias','example_context'];
fs.writeFileSync(path.join(out,'corpus-unresolved.csv'),[header.map(esc).join(','),...sorted.map(r=>[r.key,r.count,r.texts.size,[...r.spellings].sort((a,b)=>b[1]-a[1]).slice(0,4).map(([s,n])=>`${s} (${n})`).join(' | '),[...r.layers].join(' | '),r.abbreviated,r.examples[0]?.textId,r.examples[0]?.alias,r.examples[0]?.context].map(esc).join(','))].join('\n'));
fs.writeFileSync(path.join(out,'corpus-unresolved-examples.json'),JSON.stringify(sorted.slice(0,300).map(r=>({key:r.key,count:r.count,documents:r.texts.size,examples:r.examples})),null,2));
fs.writeFileSync(path.join(out,'corpus-summary.json'),JSON.stringify(summary,null,2));console.log(JSON.stringify(summary,null,2));console.log('Top unresolved',sorted.slice(0,20).map(r=>({key:r.key,count:r.count,documents:r.texts.size})));
