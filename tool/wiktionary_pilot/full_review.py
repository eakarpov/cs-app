"""Human review and coverage comparison for the full read-only trial."""
import collections,hashlib,json
from pathlib import Path
from html import escape
from pilot import lines,read_json,write_json
ROOT=Path('import/wiktionary-full')

def prepare(root=ROOT):
    witnesses=list(lines(root/'historical-spelling-proposals.jsonl'))
    parents={r['id']:r for r in lines(root/'ru-context-sources.jsonl')}
    native_ids={r['id'] for r in read_json(root/'native-index.json')['rows']}
    proto_ids={r['id'] for r in read_json(root/'interlex-proto-production.json')['rows']}
    for w in witnesses:
        assert all(x in parents for x in w['parentSourceEntryIds'])
        assert all(x['lexemeId'] in native_ids for x in w['nativeCandidates'])
        if w['span']:
            p=parents[w['parentSourceEntryIds'][0]]['raw'];texts=([p['etymology_text']] if p.get('etymology_text') else [])+p.get('etymology_texts',[])
            assert texts[w['textIndex']][slice(*w['span'])]==w['word']
    proto_rows=list(lines(root/'historical-proto-proposals.jsonl'))
    assert all(p['articleId'] in proto_ids for r in proto_rows for p in r['interlexCandidates'])
    pools=collections.defaultdict(list)
    for w in witnesses:
        key=(w['classification'],w['basis'],bool(w['nativeCandidates']),bool(w['protoClaims']))
        pools[key].append(w)
    sample=[]
    while len(sample)<200 and any(pools.values()):
        for key in sorted(pools):
            if pools[key] and len(sample)<200:sample.append(pools[key].pop(0))
    rows=[]
    for w in sample:
        p=parents[w['parentSourceEntryIds'][0]]['raw'];texts=([p['etymology_text']] if p.get('etymology_text') else [])+p.get('etymology_texts',[])
        text=texts[w['textIndex']] if w['textIndex'] is not None else '\n'.join(texts)
        start,end=w['span'] or [0,0];context=text[max(0,start-180):end+240]
        candidates='; '.join(c['name']+' ['+c['lexemeId']+'] '+c['method'] for c in w['nativeCandidates'])
        claims='; '.join(r['term']+' / '+r['relation'] for r in w['protoClaims']) or 'Нет допустимого утверждения; контекст не переносится'
        rows.append('<tr>'+''.join('<td>'+escape(str(v))+'</td>' for v in [w['classification'],w['word'],w['basis'],candidates,claims,context])+f'<td><a href="{escape(w["sourceUrl"],quote=True)}">{escape(w["parentWord"])}</a></td></tr>')
    (root/'historical-review.html').write_text('<!doctype html><html lang="ru"><meta charset="utf-8"><title>Исторические написания — пробная сверка</title><style>body{font:16px system-ui;margin:24px;background:#faf8f1;color:#222}table{border-collapse:collapse}td,th{border:1px solid #bbb;padding:10px;vertical-align:top}td:nth-child(2){font-size:24px}th{background:#eee}</style><h1>Исторические написания: 200 свидетельств</h1><p>Выборка по языковым группам, основаниям и наличию кандидатов. Все сопоставления требуют проверки. Древнерусские свидетельства выделены отдельно. Совместная встречаемость с праформой не считается этимологической связью.</p><table><tr><th>Группа</th><th>Написание</th><th>Основание</th><th>typikon-web</th><th>Утверждение о происхождении</th><th>Контекст</th><th>Источник</th></tr>'+''.join(rows)+'</table></html>')
    old=root.parent/'wiktionary-pilot'
    old_pair_rows=list(lines(old/'lexeme-proto-review.jsonl'))
    old_pairs={(r['lexemeId'],r['protoArticleId']) for r in old_pair_rows}
    pairs=list(lines(root/'lexeme-proto-review.jsonl'));new_pairs={(r['lexemeId'],r['protoArticleId']) for r in pairs}
    write_json(root/'proto-pair-changes.json',{'added':[r for r in pairs if (r['lexemeId'],r['protoArticleId']) not in old_pairs],'removed':[r for r in old_pair_rows if (r['lexemeId'],r['protoArticleId']) not in new_pairs],'status':'proposed-only','removedMeaning':'Not reproduced by this raw-snapshot pipeline; not a decision to reject the linguistic relationship'})
    source_rows=list(lines(root/'selected.jsonl'))
    en=read_json(root/'en-full-extraction.json');ru=read_json(root/'ru-full-extraction.json')
    summary={'english':en,'russian':ru,'matching':read_json(root/'matching-summary.json'),'historicalMatching':read_json(root/'historical-matching.json'),'verification':read_json(root/'verification.json'),
      'historicalDistinctSpellingsByClass':{c:len({w['word'] for w in witnesses if w['classification']==c}) for c in sorted({w['classification'] for w in witnesses})},
      'historicalWitnessesWithNativeCandidates':sum(bool(w['nativeCandidates']) for w in witnesses),
      'historicalDistinctNativeLexemes':len({c['lexemeId'] for w in witnesses for c in w['nativeCandidates']}),
      'historicalEligibleProtoRowsWithBothCandidates':sum(bool(r['nativeCandidates'] and r['interlexCandidates']) for r in proto_rows),
      'historicalDistinctLexemeProtoPairs':len({(c['lexemeId'],p['articleId']) for r in proto_rows for c in r['nativeCandidates'] for p in r['interlexCandidates']}),
      'protoPairComparison':{'previous':len(old_pairs),'current':len(new_pairs),'retained':len(old_pairs&new_pairs),'added':len(new_pairs-old_pairs),'removed':len(old_pairs-new_pairs)},
      'nativeDistinctLexemesFromDictionaryEntries':len({r['lexemeId'] for r in lines(root/'spelling-proposals.jsonl')}),
      'sourceRowsByEditionAndClass':dict(collections.Counter(r['edition']+':'+r['classification'] for r in source_rows)),
      'historicalSpanChecksPassed':True,'historicalReviewSampleSize':len(sample),'confirmedMappings':0,'appliedToProduction':False}
    write_json(root/'full-summary.json',summary)
    print(json.dumps({k:summary[k] for k in ['historicalDistinctSpellingsByClass','historicalDistinctNativeLexemes','historicalDistinctLexemeProtoPairs','protoPairComparison','sourceRowsByEditionAndClass']},ensure_ascii=False,indent=2))
if __name__=='__main__':prepare()
