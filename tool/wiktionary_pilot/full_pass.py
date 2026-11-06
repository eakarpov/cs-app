"""Full raw snapshot pass; all database access happens through read-only exports."""
import argparse, collections, gzip, hashlib, json, re, time
from pathlib import Path
from urllib.parse import quote
from pilot import digest,read_json,write_json,dump_line,lines,language_class,features,NativeIndex,ProtoIndex,proto_references
from history import extract_witnesses
ROOT=Path('import/wiktionary-full')
RU_ARCHIVE=Path('import/wiktionary-pilot/raw/ru-extract.jsonl.gz')

def verified_metadata(path):
    metadata=read_json(Path(str(path)+'.http.json'));h=hashlib.sha256()
    with path.open('rb') as f:
        while chunk:=f.read(8*1024*1024):h.update(chunk)
    if metadata['sha256']!=h.hexdigest() or metadata['bytes']!=path.stat().st_size:raise ValueError('Snapshot checksum mismatch: '+str(path))
    return metadata

def wrap(raw,line,edition,metadata):
    kind=language_class(raw)
    title=raw.get('original_title') or ('Reconstruction:Proto-Slavic/'+raw['word'].lstrip('*') if kind=='proto-slavic' and edition=='en' else raw['word'])
    return {'id':digest((edition+'\0').encode()+line),'edition':edition,'language':raw.get('lang'),'languageCode':raw.get('lang_code'),'classification':kind,'word':raw['word'],'pos':raw.get('pos'),'sourceUrl':f'https://{edition}.wiktionary.org/wiki/'+quote(title,safe=':/'),'acquisitionKind':'raw-wiktextract','snapshotSha256':metadata['sha256'],'revisionId':None,'revisionStatus':'not-exposed-by-export','historicalDate':None,'raw':raw,'features':features(raw)}

def scan_ru(root):
    metadata=verified_metadata(RU_ARCHIVE);count=selected=parents=0;hist={};unresolved=0;by_group=collections.Counter();started=time.monotonic()
    outputs={name:(root/(name+'.jsonl.part')).open('w') for name in ['selected-ru','ru-context-sources','ru-parent-proto-context','ru-unresolved-markers']}
    try:
      with gzip.open(RU_ARCHIVE,'rb') as f:
        for line in f:
          count+=1
          if count%250000==0:print(json.dumps({'ruRows':count,'selected':selected,'historicalWitnesses':len(hist),'seconds':round(time.monotonic()-started)}),flush=True)
          if b'etymology' not in line and not any(x in line for x in [b'cu',b'chu',b'zls-chs',b'sla-pro']):continue
          raw=json.loads(line)
          if not raw.get('word'):continue
          r=wrap(raw,line,'ru',metadata)
          if r['classification']:
            dump_line(outputs['selected-ru'],r);selected+=1;by_group[r['classification']]+=1
          ety=extract_witnesses(raw)
          refs=proto_references(r)
          if not ety['witnesses'] and not refs and not ety['unresolvedMarkers']:continue
          dump_line(outputs['ru-context-sources'],r);parents+=1
          if refs:dump_line(outputs['ru-parent-proto-context'],{'parentSourceEntryId':r['id'],'parentWord':r['word'],'parentLanguage':r['language'],'parentPos':r['pos'],'sourceUrl':r['sourceUrl'],'references':refs,'eligibleForHistoricalLexemeProto':False,'reason':'Parent etymology does not establish the origin of each cited historical word'})
          for item in ety['unresolvedMarkers']:
            dump_line(outputs['ru-unresolved-markers'],{'parentSourceEntryId':r['id'],'parentWord':r['word'],'sourceUrl':r['sourceUrl'],**item});unresolved+=1
          ety_hash=digest(json.dumps(ety['texts'],ensure_ascii=False).encode())
          for witness in ety['witnesses']:
            identity=json.dumps([r['word'],r['language'],raw.get('etymology_number'),ety_hash,witness['word'],witness['classification'],witness['textIndex'],witness['span']],ensure_ascii=False)
            wid=digest(identity.encode())
            if wid in hist:
              hist[wid]['parentSourceEntryIds'].append(r['id']);continue
            hist[wid]={'id':wid,'recordKind':'historical-spelling-mention','offsetUnit':'unicode-codepoints','parentSourceEntryIds':[r['id']],'parentWord':r['word'],'parentLanguage':r['language'],'sourceUrl':r['sourceUrl'],'snapshotSha256':metadata['sha256'],'historicalDate':None,'revisionId':None,'status':'proposed','contextualProtoReferences':ety['protoContexts'],**witness}
    finally:
      for f in outputs.values():f.close()
    for name in outputs:(root/(name+'.jsonl.part')).replace(root/(name+'.jsonl'))
    with (root/'historical-witnesses.jsonl').open('w') as f:
      for r in sorted(hist.values(),key=lambda x:x['id']):
        r['parentSourceEntryIds']=sorted(set(r['parentSourceEntryIds']));dump_line(f,r)
    report={'archive':str(RU_ARCHIVE),'download':metadata,'rowsScanned':count,'selectedRows':selected,'selectedByClassification':dict(by_group),'contextParentRecords':parents,'distinctHistoricalWitnesses':len(hist),'witnessesByClassification':dict(collections.Counter(r['classification'] for r in hist.values())),'witnessesByBasis':dict(collections.Counter(r['basis'] for r in hist.values())),'unresolvedMarkerOccurrences':unresolved,'eligibleSharedOriginClaims':sum(len(r['protoClaims']) for r in hist.values()),'gzipCrcValidated':True,'completeScan':True,'appliedToProduction':False}
    write_json(root/'ru-full-extraction.json',report);print(json.dumps(report,ensure_ascii=False,indent=2),flush=True)

def scan_en(root):
    path=root/'raw/en-extract.jsonl.gz';metadata=verified_metadata(path);count=selected=bytes_scanned=0;by_group=collections.Counter();started=time.monotonic()
    hints=[b'"cu"',b'"chu"',b'"zls-chs',b'"sla-pro"',b'Old Church Slavonic',b'Church Slavonic',b'Proto-Slavic']
    tmp=root/'selected-en.jsonl.part'
    with gzip.open(path,'rb') as f,tmp.open('w') as output:
      for line in f:
        count+=1;bytes_scanned+=len(line)
        if count%500000==0:print(json.dumps({'enRows':count,'uncompressedMiB':round(bytes_scanned/2**20),'selected':selected,'seconds':round(time.monotonic()-started)}),flush=True)
        if not any(hint in line for hint in hints):continue
        raw=json.loads(line)
        if not raw.get('word') or not language_class(raw):continue
        r=wrap(raw,line,'en',metadata);dump_line(output,r);selected+=1;by_group[r['classification']]+=1
    tmp.replace(root/'selected-en.jsonl')
    report={'archive':str(path),'download':metadata,'rowsScanned':count,'uncompressedBytesScanned':bytes_scanned,'selectedRows':selected,'selectedByClassification':dict(by_group),'gzipCrcValidated':True,'completeScan':True,'appliedToProduction':False}
    write_json(root/'en-full-extraction.json',report);print(json.dumps(report,ensure_ascii=False,indent=2),flush=True)

def combine(root):
    for name in ['ru','en']:
      if not read_json(root/(name+'-full-extraction.json'))['completeScan']:raise ValueError('Incomplete extraction')
    with (root/'selected.jsonl.part').open('wb') as out:
      for name in ['selected-ru.jsonl','selected-en.jsonl']:
        with (root/name).open('rb') as f:
          while data:=f.read(8*1024*1024):out.write(data)
    (root/'selected.jsonl.part').replace(root/'selected.jsonl')

def match_history(root):
    native=NativeIndex(read_json(root/'native-index.json'),read_json(root/'civil-keys.json'));proto=ProtoIndex(read_json(root/'interlex-proto-production.json'))
    counts=collections.Counter();proto_rows=0;out=root/'historical-spelling-proposals.jsonl';eout=root/'historical-proto-proposals.jsonl';coout=root/'historical-proto-context-only.jsonl'
    with out.open('w') as f,eout.open('w') as ef,coout.open('w') as cf:
      for witness in lines(root/'historical-witnesses.jsonl'):
        targets={}
        for word in dict.fromkeys([witness['word'],witness.get('lemmaTarget',witness['word'])]):
          for candidate in native.match(word):targets.setdefault(candidate['lexemeId'],candidate)
        result={**witness,'nativeCandidates':list(targets.values()),'reviewStatus':'pending'}
        dump_line(f,result)
        counts[witness['classification']+':witnesses']+=1
        counts[witness['classification']+':'+('ambiguous' if len(targets)>1 else 'unique-candidate' if targets else 'no-candidate')]+=1
        for ref in witness['protoClaims']:
          if witness['classification']=='old-east-slavic' or not ref['eligibleForLexemeProto']:continue
          dump_line(ef,{'sourceEntryId':witness['id'],'word':witness['word'],'sourceUrl':witness['sourceUrl'],'nativeCandidates':list(targets.values()),'interlexCandidates':proto.match(ref['term']),'evidence':ref,'status':'proposed','direction':'historical-witness-to-proto'});proto_rows+=1
        for ref in witness['contextualProtoReferences']:
          dump_line(cf,{'historicalWitnessId':witness['id'],'word':witness['word'],'sourceUrl':witness['sourceUrl'],'context':ref,'interlexCandidates':proto.match(ref['term']),'eligibleForLexemeProto':False,'status':'context-only'})
    write_json(root/'historical-matching.json',{'counts':dict(counts),'eligibleProtoEvidenceRows':proto_rows,'allMappingsProposed':True,'cooccurrencesExcludedFromProtoMappings':True,'appliedToProduction':False})
    print(json.dumps(dict(counts),ensure_ascii=False),flush=True)
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('action',choices=['ru','en','combine','match-history']);p.add_argument('--root',type=Path,default=ROOT);a=p.parse_args()
    {'ru':scan_ru,'en':scan_en,'combine':combine,'match-history':match_history}[a.action](a.root)
