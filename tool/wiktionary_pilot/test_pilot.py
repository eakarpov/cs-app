import unittest
import tempfile,gzip,json,hashlib
from pathlib import Path
from pilot import spelling_key,orthography_key,proto_key,proto_heads,ProtoIndex,NativeIndex,language_class,proto_references,descendants,features,compatible_pos,extract

class MatchingTests(unittest.TestCase):
 def test_key_tiers_preserve_distinctions(self):
  self.assertEqual(spelling_key('чꙋ́до'),'чꙋдо')
  self.assertNotEqual(spelling_key('пой'),spelling_key('пои'))
  self.assertEqual(orthography_key('чоудо'),orthography_key('чꙋдо'))
  self.assertNotEqual(orthography_key('ѫ'),orthography_key('у'))
  self.assertNotEqual(orthography_key('ѣ'),orthography_key('е'))
  self.assertNotEqual(spelling_key('бг҃ъ'),spelling_key('бгъ'))
 def test_full_proto_forms_are_not_roots(self):
  self.assertNotEqual(proto_key('čudo'),proto_key('čudъ'))
  self.assertNotEqual(proto_key('čudo'),proto_key('cudo'))
  self.assertNotEqual(proto_key('ę'),proto_key('e'))
  self.assertEqual(proto_key('*čúdo',True),proto_key('čudo',True))
  self.assertEqual(proto_heads('čudo род п -dese/*čudъ'),['čudo','čudъ'])
  self.assertEqual(proto_heads('capati*сьrkу'),[])
 def test_proto_phrase_is_not_reduced_to_its_first_word(self):
  self.assertEqual(proto_heads('ob bоkъ'),['ob bоkъ'])
  p=ProtoIndex({'rows':[{'id':1,'lemma':'ob','sourceUrl':'a'},{'id':2,'lemma':'ob bоkъ','sourceUrl':'b'}]})
  self.assertEqual([r['articleId'] for r in p.match('*ob')],[1])
  self.assertEqual(proto_heads('obsnovati (sę) *obsnujǫ (sę)'),['obsnovati','obsnujǫ'])
 def test_proto_index_page_is_not_a_dictionary_article(self):
  p=ProtoIndex({'rows':[{'id':342,'lemma':'ako','sourceUrl':'a','body':'Здесь представлен праславянский лексический фонд на начальные фонемы *ak- на основе объединения этимологических сведений из отдельных славянских языков'},{'id':343,'lemma':'ako','sourceUrl':'b','body':'Словарная статья: старославянское ако.'}]})
  self.assertEqual([r['articleId'] for r in p.match('*ako')],[343])
  self.assertEqual(p.unparsed[0]['reason'],'non-article-index-page')
 def test_proto_collisions_retain_all_ids(self):
  p=ProtoIndex({'rows':[{'id':1,'lemma':'čudo','sourceUrl':'a'},{'id':2,'lemma':'čudo I','sourceUrl':'b'},{'id':3,'lemma':'čudъ','sourceUrl':'c'}]})
  self.assertEqual([x['articleId'] for x in p.match('čudo')],[1,2])
  self.assertEqual([x['articleId'] for x in p.match('čudъ')],[3])
 def test_multiple_native_homonyms_and_pos_conflict_stay_visible(self):
  p=NativeIndex({'rows':[{'id':str(i),'name':'миръ','pos':pos,'variants':[{'value':'миръ','civilKey':'мир','origin':'lemma'}]} for i,pos in [(1,'noun'),(2,'noun'),(3,'verb')]]},{'миръ':'мир'})
  candidates=p.match('миръ','noun')
  self.assertEqual(len(candidates),3)
  self.assertEqual([m['posCompatible'] for m in candidates],[True,True,False])
 def test_legacy_grammar_prevents_letter_numeral_and_conjunction_collisions(self):
  self.assertFalse(compatible_pos('num','other',['CONJ']))
  self.assertFalse(compatible_pos('character','other',[]))
  self.assertTrue(compatible_pos('conj','other',['CONJ']))
  self.assertTrue(compatible_pos('prep','other',['ADV/PR']))
  self.assertTrue(compatible_pos('adv','other',['ADV/PR']))
  self.assertIsNone(compatible_pos('noun','other',[]))
 def test_language_section_is_not_guessed_from_article_text(self):
  self.assertEqual(language_class({'lang':'Старославянский','lang_code':'cu'}),'old-church-slavonic')
  self.assertEqual(language_class({'lang':'Церковнославянский','lang_code':'cu'}),'church-slavonic')
  self.assertIsNone(language_class({'lang':'Русский','lang_code':'ru','etymology_text':'Из старославянского'}))
 def test_etymology_relations_are_typed_and_do_not_import_other_language_templates(self):
  r={'languageCode':'cu','raw':{'etymology_templates':[{'name':'inh','args':{'1':'cu','2':'sla-pro','3':'*čudo'}},{'name':'inh','args':{'1':'ru','2':'sla-pro','3':'*other'}}],'etymology_links':[['*čudo','Reconstruction:Proto-Slavic/čudo']]}}
  refs=proto_references(r);self.assertEqual(len(refs),2);self.assertEqual(refs[0]['relation'],'inh');self.assertEqual(refs[1]['relation'],'unspecified')
 def test_etymology_placeholders_are_not_content(self):
  self.assertFalse(features({'etymology_texts':['От ??','Из ??']})['hasEtymology'])
  self.assertTrue(features({'etymology_texts':['От ??']})['hasUnresolvedEtymology'])
 def test_explicit_russian_proto_origin_is_not_guessed_from_other_mentions(self):
  record={'edition':'ru','raw':{'etymology_texts':['Происходит от праслав. *slovo, далее...']}}
  self.assertEqual(proto_references(record)[0]['term'],'*slovo')
  self.assertEqual(proto_references(record)[0]['relation'],'unspecified-origin-or-base')
  self.assertEqual(proto_references({'edition':'ru','raw':{'etymology_texts':['Ср. *other']}}),[])
 def test_nested_descendants_keep_recension_and_intermediate_nodes(self):
  record={'raw':{'descendants':[{'lang':'Old Church Slavonic','lang_code':'cu','descendants':[{'word':'чꙋдо','lang':'Church Slavonic','lang_code':'zls-chs','raw_tags':['Russian recension']}]}]}}
  result=list(descendants(record))[0]
  self.assertEqual(result['depth'],1)
  self.assertEqual(result['sourcePath'][0]['lang_code'],'cu')
  self.assertEqual(result['sourceTags'],['Russian recension'])
 def test_descendant_depth_is_preserved_without_claiming_direct_inheritance(self):
  r={'raw':{'descendants':[{'depth':4,'text':'Church Slavonic: чꙋдо','templates':[{'name':'desc','args':{'1':'zls-chs','2':'чꙋдо'}}]}]}}
  result=list(descendants(r))[0];self.assertEqual(result['depth'],4);self.assertEqual(result['relation'],'descendant-in-source-tree')

class ExtractionTests(unittest.TestCase):
 def test_language_name_selection_checks_hash_and_commits_only_complete_scan(self):
  with tempfile.TemporaryDirectory() as temp:
   root=Path(temp);(root/'raw').mkdir()
   rows=[{'word':'чꙋдо','lang':'Церковнославянский','lang_code':'custom','pos':'noun'}, {'word':'чудо','lang':'Русский','lang_code':'ru','etymology_texts':['Из церковнославянского']}]
   data=gzip.compress(('\n'.join(json.dumps(r,ensure_ascii=False) for r in rows)+'\n').encode())
   for name,content in [('ru-extract.jsonl.gz',data),('en-ocs.jsonl',b''),('en-proto.jsonl',b'')]:
    path=root/'raw'/name;path.write_bytes(content)
    path.with_suffix(path.suffix+'.http.json').write_text(json.dumps({'sha256':hashlib.sha256(content).hexdigest()}))
   extract(root)
   result=json.loads((root/'selected.jsonl').read_text())
   self.assertEqual(result['word'],'чꙋдо')
   self.assertEqual(result['raw'],rows[0])
   original=(root/'selected.jsonl').read_bytes()
   path=root/'raw/ru-extract.jsonl.gz';path.write_bytes(data[:-4])
   path.with_suffix(path.suffix+'.http.json').write_text(json.dumps({'sha256':hashlib.sha256(data[:-4]).hexdigest()}))
   with self.assertRaises(EOFError):extract(root)
   self.assertEqual((root/'selected.jsonl').read_bytes(),original)

if __name__=='__main__':unittest.main()
