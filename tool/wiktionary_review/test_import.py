import copy,hashlib,json,sqlite3,tempfile,unittest
from pathlib import Path
from build import objsha
from prepare_import import merge,validate_bundle,check_targets

def fixture():
 native={'id':'a','name':'слово','scheme':'local-scheme','localNote':'keep'}
 raw=json.dumps(native,ensure_ascii=False);body='ст.-слав. слово: речь';wikitext='От *slovo: ст.-слав. слово.'
 entry={'pairId':'pair-a','lexemeId':'a','protoArticleId':42,'decision':'ready','reason':'checked'}
 q=lambda text:{'text':text,'span':[0,len(text)]}
 reference={'articleId':42,'lemma':'slovo','status':'verified','relation':'attested-in','sourceUrl':'https://example.test/proto','bodySha256':hashlib.sha256(body.encode()).hexdigest(),'evidence':'checked sources','provenance':{'reviewId':'pair-a','sourceIds':['wiki','proto'],'wiktionary':{'sourceId':'wiki','etymologyTextIndex':0,'quote':q(wikitext)},'proto':{'sourceId':'proto','quote':q(body)}}}
 bundle={'schema':'cs-reviewed-etymology-import-v1','reviewManifestSha256':'review','baseline':{'publicationVersion':'v1','nativePayloadSha256':{'a':hashlib.sha256(raw.encode()).hexdigest()}},'reviewDecisions':[entry,{'pairId':'deferred','decision':'defer'},{'pairId':'rejected','decision':'reject'}],'references':[{'pairId':'pair-a','lexemeId':'a','reference':reference}],'sources':{'wiki':{'raw':{'etymology_texts':[wikitext]}},'proto':{'bodySha256':reference['bodySha256']}}}
 bundle['bundleId']=objsha(bundle)
 proto={'rows':[{'id':42,'lemma':'slovo','body':body,'sourceUrl':reference['sourceUrl']}]}
 return bundle,{'entries':bundle['reviewDecisions']},raw,proto

class MergeTests(unittest.TestCase):
 def test_preserves_local_fields_existing_etymology_and_sources(self):
  b,*_=fixture();base={'reviewNote':'local','relations':[{'manual':True}],'rejectedRelationIds':['old'],'unknownFutureField':{'anything':[1,2]},'etymologies':{'untouched':[{'articleId':8,'custom':'local'}]},'etymologySources':{'local-source':{'raw':'manual'}}};before=copy.deepcopy(base)
  result,changes=merge(base,b)
  self.assertEqual(base,before)
  for key in ['reviewNote','relations','rejectedRelationIds','unknownFutureField']:self.assertEqual(result[key],base[key])
  self.assertEqual(result['etymologies']['untouched'],base['etymologies']['untouched']);self.assertEqual(result['etymologySources']['local-source'],{'raw':'manual'})
  self.assertEqual(changes['added'],['pair-a']);self.assertNotIn('deferred',changes['added']);self.assertNotIn('rejected',changes['added'])
  self.assertEqual(len(result['etymologyReviewDecisions']),3)
 def test_idempotent_merge(self):
  b,*_=fixture();once,_=merge({},b);twice,changes=merge(once,b)
  self.assertEqual(once,twice);self.assertEqual(changes['added'],[]);self.assertEqual(len(changes['skipped']),1)
 def test_existing_same_reference_is_kept_byte_for_byte(self):
  b,*_=fixture();old={'articleId':42,'evidence':'editor text','status':'proposed','local':'preserve'}
  result,changes=merge({'etymologies':{'a':[old]}},b)
  self.assertEqual(result['etymologies']['a'],[old]);self.assertFalse(changes['added'])
 def test_other_existing_etymology_is_a_conflict(self):
  b,*_=fixture()
  with self.assertRaisesRegex(ValueError,'reconciliation'):merge({'etymologies':{'a':[{'articleId':99}]}},b)
 def test_explicit_editor_rejection_is_not_overwritten(self):
  b,*_=fixture()
  with self.assertRaisesRegex(ValueError,'rejected'):merge({'rejectedEtymologyIds':['pair-a']},b)
  with self.assertRaisesRegex(ValueError,'Conflicting'):merge({'etymologyReviewDecisions':{'pair-a':{'decision':'reject','reason':'manual'}}},b)
 def test_source_conflict_is_not_overwritten(self):
  b,*_=fixture()
  with self.assertRaisesRegex(ValueError,'Source registry conflict'):merge({'etymologySources':{'wiki':{'raw':'changed by editor'}}},b)

class ValidationTests(unittest.TestCase):
 def test_valid_bundle(self):
  b,m,*_=fixture();self.assertEqual(len(validate_bundle(b,m)),1)
 def test_tampered_bundle_and_unreviewed_reference_rejected(self):
  b,m,*_=fixture();b['references'][0]['reference']['articleId']=404
  with self.assertRaisesRegex(ValueError,'checksum'):validate_bundle(b,m)
  b,m,*_=fixture();b['references'].append(copy.deepcopy(b['references'][0]));b['bundleId']=objsha({k:v for k,v in b.items() if k!='bundleId'})
  with self.assertRaisesRegex(ValueError,'exactly reviewed'):validate_bundle(b,m)
 def test_missing_provenance_and_bad_quote_rejected(self):
  for mode in ['missing','quote']:
   b,m,*_=fixture()
   if mode=='missing':del b['sources']['wiki']
   else:b['references'][0]['reference']['provenance']['wiktionary']['quote']['text']='invented'
   b['bundleId']=objsha({k:v for k,v in b.items() if k!='bundleId'})
   with self.assertRaises(ValueError):validate_bundle(b,m)
 def test_targets_checked_readonly_and_local_changes_block_import(self):
  b,m,raw,proto=fixture()
  with tempfile.TemporaryDirectory() as tmp:
   path=Path(tmp)/'snapshot.sqlite';db=sqlite3.connect(path);db.executescript('CREATE TABLE metadata(key TEXT,value TEXT); CREATE TABLE articles(id TEXT,payload TEXT);');db.executemany('INSERT INTO metadata VALUES (?,?)',[('version','v1'),('state','complete')]);db.execute('INSERT INTO articles VALUES (?,?)',('a',raw));db.commit();db.close()
   before=path.read_bytes();check_targets(b,path,proto);self.assertEqual(path.read_bytes(),before)
   wrong=copy.deepcopy(proto);wrong['rows'][0]['body']+=' editor change'
   with self.assertRaisesRegex(ValueError,'Proto target'):check_targets(b,path,wrong)
   missing=copy.deepcopy(proto);missing['rows']=[]
   with self.assertRaisesRegex(ValueError,'Proto target'):check_targets(b,path,missing)
   db=sqlite3.connect(path);db.execute('UPDATE articles SET payload=?',(raw+' ',));db.commit();db.close()
   with self.assertRaisesRegex(ValueError,'Native article changed'):check_targets(b,path,proto)
   db=sqlite3.connect(path);db.execute("UPDATE metadata SET value='new' WHERE key='version'");db.commit();db.close()
   with self.assertRaisesRegex(ValueError,'Publication version'):check_targets(b,path,proto)
 def test_all_85_have_explicit_decisions(self):
  path=Path(__file__).resolve().parents[2]/'data/wiktionary/review-85.json';r=json.loads(path.read_text())['entries']
  self.assertEqual(len(r),85);self.assertEqual(len({x['pairId'] for x in r}),85)
  self.assertEqual({s:sum(x['decision']==s for x in r) for s in ['ready','defer','reject']},{'ready':17,'defer':11,'reject':57})

if __name__=='__main__':unittest.main()
