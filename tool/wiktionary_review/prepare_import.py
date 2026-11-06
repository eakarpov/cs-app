"""Prepare a merged typikon review JSON; no apply flag and no database writes."""
import argparse,copy,hashlib,json,sys
from pathlib import Path
from build import canonical,objsha,sha,db_readonly,read_json,write_json

def validate_bundle(bundle,manifest):
 if bundle.get('schema')!='cs-reviewed-etymology-import-v1':raise ValueError('Unknown bundle schema')
 content={k:v for k,v in bundle.items() if k!='bundleId'}
 if objsha(content)!=bundle.get('bundleId'):raise ValueError('Bundle checksum mismatch')
 approved={r['pairId']:(r['lexemeId'],r['protoArticleId']) for r in manifest['entries'] if r['decision']=='ready'}
 if bundle['reviewDecisions']!=manifest['entries']:raise ValueError('Review manifest decisions differ')
 refs=bundle['references'];ids=[r['pairId'] for r in refs]
 if len(ids)!=len(set(ids)) or set(ids)!=set(approved):raise ValueError('Import must contain exactly reviewed ready references')
 for r in refs:
  ref=r['reference']
  if (r['lexemeId'],ref['articleId'])!=approved[r['pairId']]:raise ValueError('Reference target differs from review')
  if ref['status']!='verified' or ref['relation']!='attested-in':raise ValueError('Only checked source-attestation references are supported')
  p=ref['provenance']
  if p['reviewId']!=r['pairId'] or any(x not in bundle['sources'] for x in p['sourceIds']):raise ValueError('Missing source provenance')
  wiki=bundle['sources'][p['wiktionary']['sourceId']];raw=wiki['raw'];texts=([raw['etymology_text']] if raw.get('etymology_text') else [])+raw.get('etymology_texts',[])
  q=p['wiktionary']['quote']
  if texts[p['wiktionary']['etymologyTextIndex']][slice(*q['span'])]!=q['text']:raise ValueError('Wiktionary quote differs from source')
 return refs

def check_targets(bundle,publication,proto_snapshot):
 db=db_readonly(publication)
 try:
  if db.execute("SELECT value FROM metadata WHERE key='state'").fetchone()[0]!='complete':raise ValueError('Incomplete publication')
  version=db.execute("SELECT value FROM metadata WHERE key='version'").fetchone()[0]
  if version!=bundle['baseline']['publicationVersion']:raise ValueError('Publication version changed; re-audit against the new snapshot')
  proto={r['id']:r for r in proto_snapshot['rows']}
  for r in bundle['references']:
   row=db.execute('SELECT payload FROM articles WHERE id=?',(r['lexemeId'],)).fetchone()
   if not row:raise ValueError('Unknown lexeme ID')
   if hashlib.sha256(row[0].encode()).hexdigest()!=bundle['baseline']['nativePayloadSha256'][r['lexemeId']]:raise ValueError('Native article changed, including local edits')
   ref=r['reference'];p=proto.get(ref['articleId'])
   if not p or p['lemma']!=ref['lemma'] or p['sourceUrl']!=ref['sourceUrl'] or hashlib.sha256(p['body'].encode()).hexdigest()!=ref['bodySha256']:raise ValueError('Proto target changed or missing')
   quote=ref['provenance']['proto']['quote']
   if p['body'][slice(*quote['span'])]!=quote['text']:raise ValueError('Proto quote differs from source')
 finally:db.close()

def merge(base,bundle):
 result=copy.deepcopy(base);etym=result.setdefault('etymologies',{})
 if not isinstance(etym,dict):raise ValueError('Invalid existing etymology decisions')
 journal=result.setdefault('etymologyReviewDecisions',{});sources=result.setdefault('etymologySources',{})
 if not isinstance(journal,dict) or not isinstance(sources,dict):raise ValueError('Invalid existing provenance registry')
 blocked=set(result.get('rejectedEtymologyIds',[]));added=[];skipped=[]
 # Preserve editor decisions for all 85, including decisions not to publish.
 for d in bundle['reviewDecisions']:
  key=d['pairId'];entry={**d,'reviewManifestSha256':bundle['reviewManifestSha256']}
  if key in journal and journal[key]!=entry:raise ValueError('Conflicting editorial review decision: '+key)
  if d['decision']=='ready' and key in blocked:raise ValueError('Editor rejected this etymology: '+key)
  journal.setdefault(key,entry)
 for r in bundle['references']:
  lid=r['lexemeId'];ref=r['reference'];existing=etym.setdefault(lid,[])
  if not isinstance(existing,list):raise ValueError('Invalid existing reference list')
  same=[e for e in existing if e.get('articleId')==ref['articleId']]
  if same:
   skipped.append({'pairId':r['pairId'],'reason':'existing-reference-preserved'});continue
  # A different existing etymology may be an editorial choice; require a rebase.
  if existing:raise ValueError('Existing etymology for target lexeme needs editorial reconciliation: '+lid)
  existing.append(copy.deepcopy(ref));added.append(r['pairId'])
 for key,source in bundle['sources'].items():
  if key in sources and sources[key]!=source:raise ValueError('Source registry conflict: '+key)
  sources.setdefault(key,copy.deepcopy(source))
 # Explicit invariant: no old key/value, list entry or source is replaced.
 for key,value in base.items():
  if key not in {'etymologies','etymologyReviewDecisions','etymologySources'} and result[key]!=value:raise AssertionError('Unrelated editor data changed')
 for key,values in base.get('etymologies',{}).items():
  if result['etymologies'][key][:len(values)]!=values:raise AssertionError('Existing etymologies changed')
 return result,{'added':added,'skipped':skipped}

def prepare(bundle_path,manifest_path,decisions_path,publication,proto_path,out):
 if out.exists():raise ValueError('Output must be a new directory; input files are never overwritten')
 bundle=read_json(bundle_path);manifest=read_json(manifest_path)
 if sha(manifest_path)!=bundle['reviewManifestSha256']:raise ValueError('Reviewed decisions file changed')
 validate_bundle(bundle,manifest);check_targets(bundle,publication,read_json(proto_path))
 original_bytes=decisions_path.read_bytes();base=json.loads(original_bytes);merged,changes=merge(base,bundle)
 merged_bytes=(json.dumps(merged,ensure_ascii=False,indent=2)+'\n').encode()
 input_hashes={str(p.resolve()):sha(p) for p in [bundle_path,manifest_path,decisions_path,proto_path]}
 plan={'schema':'cs-etymology-prepared-merge-v1','bundleId':bundle['bundleId'],'state':'prepared-only','inputSha256':input_hashes,'expectedOriginalDecisionsSha256':hashlib.sha256(original_bytes).hexdigest(),'mergedDecisionsSha256':hashlib.sha256(merged_bytes).hexdigest(),'publicationVersion':bundle['baseline']['publicationVersion'],'addedReferences':len(changes['added']),'preservedExistingReferences':sum(len(x) for x in base.get('etymologies',{}).values()),'skippedExistingReferences':len(changes['skipped']),'decisionsRecorded':len(bundle['reviewDecisions']),'sourcesPreserved':len(bundle['sources']),'changes':changes,'databaseOpenedReadOnly':True,'productionApplied':False,'requirementsBeforeFutureRelease':['Fresh production export and API/publication version check','Re-run preparation against the current editorial review JSON; compare-and-swap the recorded input hash','Preserve this merged review JSON and its etymologySources registry together','Back up current publication and build a separate candidate; do not run a finalizer against a live input','Verify all old IDs, schemes, local edits, sources and existing editorial decisions; deploy separately with rollback']}
 # Check for input changes during preparation before publishing any output.
 if any(sha(Path(p))!=value for p,value in input_hashes.items()):raise ValueError('Input changed during preparation')
 out.mkdir(parents=True);(out/'review.merged.json').write_bytes(merged_bytes);write_json(out/'plan.json',plan)
 print(json.dumps({k:plan[k] for k in ['state','addedReferences','preservedExistingReferences','skippedExistingReferences','decisionsRecorded','sourcesPreserved','productionApplied']},ensure_ascii=False,indent=2))
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--bundle',type=Path,default=Path('import/wiktionary-reviewed/package-final/import-bundle.json'));p.add_argument('--review-manifest',type=Path,default=Path('data/wiktionary/review-85.json'));p.add_argument('--decisions',type=Path,required=True);p.add_argument('--publication',type=Path,default=Path('import/cs-publication-v1.sqlite'));p.add_argument('--proto-snapshot',type=Path,default=Path('import/wiktionary-full/interlex-proto-production.json'));p.add_argument('--out',type=Path,required=True);a=p.parse_args();prepare(a.bundle,a.review_manifest,a.decisions,a.publication,a.proto_snapshot,a.out)
