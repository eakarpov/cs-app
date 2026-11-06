import json,sqlite3,tempfile,unittest
from pathlib import Path
from candidate import build,sha,objsha,write_guard
class CandidateTests(unittest.TestCase):
 def fixture(self,root):
  base=root/'base.sqlite';db=sqlite3.connect(base);db.executescript('CREATE TABLE metadata(key TEXT PRIMARY KEY,value TEXT);CREATE TABLE articles(id TEXT PRIMARY KEY,name TEXT,pos TEXT,payload TEXT);CREATE TABLE forms(id TEXT PRIMARY KEY,payload TEXT);')
  db.executemany('INSERT INTO metadata VALUES (?,?)',[('state','complete'),('scopeChecked','1'),('version','old'),('local','keep')]);db.execute('INSERT INTO forms VALUES (?,?)',('f','local form'))
  article={'id':'a','name':'слово','pos':'noun','scheme':'local','etymologies':[],'localNote':'keep'};payload=json.dumps(article,ensure_ascii=False)
  db.execute('INSERT INTO articles VALUES (?,?,?,?)',('a','слово','noun',payload));db.execute('INSERT INTO articles VALUES (?,?,?,?)',('b','иное','noun',json.dumps({**article,'id':'b','etymologies':[{'articleId':8,'note':'editor'}]},ensure_ascii=False)));db.commit();db.close()
  ref={'articleId':42,'status':'verified','relation':'attested-in','provenance':{'sources':['s']}};decision={'pairId':'p','lexemeId':'a','decision':'ready'}
  bundle={'baseline':{'publicationSha256':sha(base),'publicationVersion':'old','nativePayloadSha256':{'a':__import__('hashlib').sha256(payload.encode()).hexdigest()}},'references':[{'pairId':'p','lexemeId':'a','reference':ref}],'reviewDecisions':[decision,{'pairId':'r','decision':'reject'}],'sources':{'s':{'raw':'source'}}};bundle['bundleId']=objsha(bundle)
  editor={'etymologyReviewDecisions':{'p':decision,'r':bundle['reviewDecisions'][1]},'etymologySources':bundle['sources'],'etymologies':{'a':[ref],'b':[{'articleId':8,'note':'editor'}]}}
  bp=root/'bundle.json';ep=root/'review.json';bp.write_text(json.dumps(bundle,ensure_ascii=False));ep.write_text(json.dumps(editor,ensure_ascii=False))
  return base,bp,ep,bundle
 def test_build_preserves_original_and_all_other_fields(self):
  with tempfile.TemporaryDirectory() as tmp:
   root=Path(tmp);base,bp,ep,b=self.fixture(root);before=base.read_bytes();out=root/'new.sqlite';report=root/'report.json'
   build(base,out,bp,ep,b['bundleId'],report);self.assertEqual(before,base.read_bytes())
   r=json.loads(report.read_text());self.assertEqual(r['counts']['newReferences'],1);self.assertTrue(r['allIdsPreserved'])
   db=sqlite3.connect(out);a=json.loads(db.execute("SELECT payload FROM articles WHERE id='a'").fetchone()[0]);self.assertEqual(a['scheme'],'local');self.assertEqual(a['localNote'],'keep');self.assertEqual(len(a['etymologies']),1)
   self.assertEqual(db.execute('SELECT payload FROM forms').fetchone()[0],'local form');self.assertEqual(db.execute("SELECT value FROM metadata WHERE key='state'").fetchone()[0],'complete');self.assertEqual(db.execute('SELECT count(*) FROM etymology_review_decisions').fetchone()[0],2);db.close()
   with self.assertRaises(ValueError):build(base,out,bp,ep,b['bundleId'],root/'another.json')
 def test_wrong_base_and_bundle_are_refused(self):
  with tempfile.TemporaryDirectory() as tmp:
   root=Path(tmp);base,bp,ep,b=self.fixture(root)
   with self.assertRaisesRegex(ValueError,'bundle'):build(base,root/'no.sqlite',bp,ep,'wrong',root/'no.json')
   db=sqlite3.connect(base);db.execute("UPDATE forms SET payload='new editor form'");db.commit();db.close()
   with self.assertRaisesRegex(ValueError,'Base differs'):build(base,root/'no.sqlite',bp,ep,b['bundleId'],root/'no.json')
   self.assertFalse((root/'no.sqlite').exists())
 def test_write_guard_refuses_form_and_grammar_updates(self):
  db=sqlite3.connect(':memory:');db.executescript('CREATE TABLE forms(value TEXT);CREATE TABLE articles(payload TEXT,scheme TEXT);');db.set_authorizer(write_guard)
  with self.assertRaises(sqlite3.DatabaseError):db.execute("UPDATE forms SET value='x'")
  with self.assertRaises(sqlite3.DatabaseError):db.execute("UPDATE articles SET scheme='x'")
  db.close()
if __name__=='__main__':unittest.main()
