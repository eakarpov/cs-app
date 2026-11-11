import copy,json,unittest
from pathlib import Path
from canonical import canonical_card,clean
class CanonicalTest(unittest.TestCase):
 def setUp(self):self.research=json.loads(Path(__file__).with_name('research-input.json').read_text())
 def card(self,ety_id='ETYM-INF-NOMINAL'):
  e=next(e for e in self.research['morpheme_etymologies'] if e['id']==ety_id);src=next(s for s in self.research['sources'] if s['id']==e['source_id']);v=next(v for v in self.research['allomorphs'] if v['id']==e['allomorph_id'])
  return {'id':e['morpheme_id'],'allomorphs':[{'id':v['id'],'surface':v['surface']}],'history':[{'title':'Происхождение морфемы','reconstruction':clean(e['reconstruction']),'note':clean(e['note']),'status':e['status'],'sources':[{'title':clean(src['title']),'locator':clean(e['locator'])}]}],'structure':[]}
 def test_existing_components_are_scoped_but_prose_never_creates_edges(self):
  c=self.card();before=copy.deepcopy(c);new=canonical_card(c,self.research);self.assertEqual(c,before)
  m=new['composition']['models'][0];self.assertEqual(m['allomorphIds'],['formative_suffix:INF:ти']);self.assertEqual([p['surface'] for p in m['parts']],['т','и']);self.assertTrue(all(p['kind'] is None for p in m['parts']))
  self.assertEqual(new['etymology']['chains'],[]);self.assertEqual(new['etymology']['nodes'],[]);self.assertIsNone(new['sources'][0]['publicationYear']);self.assertEqual(new['sources'][0]['kind'],'unclassified')
 def test_changed_claim_is_not_silently_imported_from_newer_research(self):
  c=self.card();c['history'][0]['note']+=' Different source decision.';new=canonical_card(c,self.research);self.assertEqual(new['composition']['models'],[]);self.assertEqual(new['etymology']['notes'][0]['text'],c['history'][0]['note'])
 def test_fusion_without_explicit_alignment_stays_unmapped(self):
  c=self.card('ETYM-DUSH-FUSION');m=canonical_card(c,self.research)['composition']['models'][0];self.assertEqual(m['mappingMode'],'unmapped');self.assertEqual(m['alignment'],[])
if __name__=='__main__':unittest.main()
