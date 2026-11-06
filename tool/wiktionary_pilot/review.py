"""Prepare deduplicated review artifacts and verify that source inputs stayed intact."""
import collections,hashlib,json,re,time
from pathlib import Path
from html import escape
from urllib.parse import unquote
from pilot import read_json,write_json,lines,dump_line
ROOT=Path('import/wiktionary-pilot')

def sha(path):
    h=hashlib.sha256()
    with Path(path).open('rb') as f:
      while chunk:=f.read(8*1024*1024):h.update(chunk)
    return h.hexdigest()

def prepare(root=ROOT):
    selected={r['id']:r for r in lines(root/'selected.jsonl')}
    native=read_json(root/'native-index.json');native_by_id={r['id']:r for r in native['rows']}
    proto=read_json(root/'interlex-proto-production.json');proto_by_id={r['id']:r for r in proto['rows']}
    chains={}
    for filename in ['etymology-proposals.jsonl','reverse-proto-proposals.jsonl']:
      for number,row in enumerate(lines(root/filename),1):
        source_id=row.get('sourceEntryId',row.get('protoSourceEntryId'))
        assert source_id in selected
        for target in row['nativeCandidates']:
          assert target['lexemeId'] in native_by_id
          for p in row['interlexCandidates']:
            assert p['articleId'] in proto_by_id
            key=(target['lexemeId'],p['articleId'])
            chain=chains.setdefault(key,{'id':hashlib.sha256((key[0]+':'+str(key[1])).encode()).hexdigest(),'lexemeId':key[0],'name':native_by_id[key[0]]['name'],'protoArticleId':key[1],'protoArticleLemma':proto_by_id[key[1]]['lemma'],'protoSourceUrl':proto_by_id[key[1]]['sourceUrl'],'status':'proposed','reviewStatus':'pending','evidence':[]})
            evidence={'sourceEntryId':source_id,'wikiUrl':selected[source_id]['sourceUrl'],'direction':row['direction'],'artifact':filename,'line':number,'nativeMethod':target['method'],'posCompatible':target.get('posCompatible'),'protoMethod':p['method'],'nativeCandidateCount':len(row['nativeCandidates']),'protoCandidateCount':len(row['interlexCandidates'])}
            if 'evidence' in row:evidence.update({k:row['evidence'][k] for k in ['basis','relation','term']})
            else:evidence.update({'basis':'explicit-descendant-tree','relation':row['descendant']['relation'],'term':row['descendant']['word'],'languageCode':row['descendant']['languageCode'],'sourceTags':row['descendant'].get('sourceTags',[]),'sourcePath':row['descendant'].get('sourcePath',[])})
            chain['evidence'].append(evidence)
    result=list(chains.values())
    for chain in result:
      chain['distinctWikiPages']=len({r['wikiUrl'] for r in chain['evidence']})
      chain['priority']='review-first' if any(r['posCompatible'] is True and r['nativeCandidateCount']==r['protoCandidateCount']==1 and r['protoMethod']=='full-proto-head' and r['nativeMethod']!='existing-search-key' and r['basis'] in {'explicit-etymology-template','explicit-etymology-tree-template'} for r in chain['evidence']) else 'review-needed'
    result.sort(key=lambda r:(r['priority']!='review-first',r['name'],r['protoArticleId']))
    with (root/'lexeme-proto-review.jsonl').open('w') as f:
      for row in result:dump_line(f,row)
    rows=[]
    for r in result[:200]:
      pages=sorted({e['wikiUrl'] for e in r['evidence']})
      urls='<br>'.join(f'<a href="{escape(u,quote=True)}">{escape(unquote(u.rsplit("/",1)[-1]))}</a>' for u in pages)
      rows.append('<tr>'+''.join('<td>'+escape(str(x))+'</td>' for x in [r['name'],r['lexemeId'],r['protoArticleLemma'],r['protoArticleId'],r['priority']])+f'<td>{urls}</td></tr>')
    table='''<h2 id="proto">Кандидаты связей с праформами</h2><p>Первые 200 сгруппированных пар. Несколько ссылок одного Викисловаря не считаются независимыми научными подтверждениями. Приоритет означает порядок проверки, не достоверность.</p><table><tr><th>Лексема</th><th>ID typikon-web</th><th>Статья interlex</th><th>ID interlex</th><th>Очередь</th><th>Викисловарь</th></tr>'''+''.join(rows)+'</table>'
    original=(root/'review.html').read_text();original=original.replace('</html>',table+'</html>')
    (root/'review-with-proto.html').write_text(original)
    inputs_before=read_json(root/'inputs-before-matching.json')
    for filename,before in inputs_before.items():assert sha(root/filename)==before['sha256']
    publication=root.parent/'cs-publication-v1.sqlite'
    publication_sha=sha(publication)
    assert publication_sha=='d4b8acb29f590ed501ef6c132aca2a4064ebb17d9c5970c3dc9022fdfe06e158'
    selected_sha=sha(root/'selected.jsonl')
    record_keys=set().union(*(r['raw'].keys() for r in selected.values()))
    manifest={'preparedAtUtc':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),'publicationVersion':native['version'],'publicationSha256':publication_sha,'nativeIndexSha256':sha(root/'native-index.json'),'interlexProtoSnapshotSha256':sha(root/'interlex-proto-production.json'),'inputsPreserved':True,'allCandidateIdsExistInInputs':True,'allEvidenceSourceIdsExist':True,'selectedSha256':selected_sha,'selectedDistinctContentRecords':len(selected),'distinctLexemeProtoCandidatePairs':len(result),'reviewFirstPairs':sum(r['priority']=='review-first' for r in result),'numberOfConfirmedMappings':0,'hasUpstreamRevisionFields':any('revision' in k or k in {'revid','pageid'} for k in record_keys),'appliedToProduction':False,'historicalDatesInferredFromWikiTimestamps':False,'notes':['All IDs are references to existing snapshots. No new lexemes or proto entries are created.','Read-only production proto SELECT and read-only local publication export.','Raw Russian export; English OCS and Proto-Slavic exports are postprocessed, not raw.']}
    write_json(root/'verification.json',manifest)
    proof=[]
    for row in result:
      if row['name'] in ['чꙋ́до','сло́во','землѧ̀','а҆́бїе']:proof.append(row)
    write_json(root/'proof-examples.json',proof)
    # Capture upstream extraction dates and revisions from the archived index pages.
    upstream=[]
    for filename in ['Old-Church-Slavonic-index.html','Proto-Slavic-index.html']:
      text=(root/'raw'/filename).read_text();dates=re.search(r'extracted on (\d{4}-\d\d-\d\d).*?dump.*?dated (\d{4}-\d\d-\d\d)',text,re.S)
      upstream.append({'index':filename,'extractedAtDate':dates[1] if dates else None,'dumpDate':dates[2] if dates else None,'commitLinks':re.findall(r'https://github.com/[^"\s<>]+/commit/[^"\s<>]+',text)})
    ru_log=root/'raw/ru-extract-log-prefix.txt'
    ru_match=re.search(r'ruwiktionary-(\d{4})(\d{2})(\d{2})-pages-articles',ru_log.read_text()) if ru_log.exists() else None
    ru_date='-'.join(ru_match.groups()) if ru_match else None
    write_json(root/'upstream-provenance.json',{'english':upstream,'russianDumpDate':ru_date,'russianDumpDateStatus':'from-associated-extraction-log' if ru_date else 'not-stated-on-raw-download-index','sourceLicenseNotice':'Retain Wiktionary attribution, applicable CC BY-SA terms, source links and modification notices before any publication.','pageRevisionIds':'not exposed in downloaded entry JSON; no revision ids inferred from live pages'})
    print(json.dumps(manifest,ensure_ascii=False,indent=2))
if __name__=='__main__':prepare()
