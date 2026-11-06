import unittest
from history import extract_witnesses

class HistoricalWitnessTests(unittest.TestCase):
 def extract(self,text,links=()):
  return extract_witnesses({'etymology_texts':[text],'etymology_links':list(links)})
 def test_explicit_anchor_and_marker_are_preserved_as_one_witness(self):
  r=self.extract('Из ст.-слав. сло́во, русск. слово.',[['ст.-слав.','старославянский язык'],['сло́во','слово#Старославянский'],['слово','слово#Русский']])
  self.assertEqual(len(r['witnesses']),1)
  w=r['witnesses'][0];self.assertEqual(w['word'],'сло́во');self.assertEqual(w['basis'],'language-marker-and-anchored-wikilink')
  self.assertEqual(w['lemmaTarget'],'слово')
 def test_language_scoping_stops_at_next_language_or_parenthesis(self):
  r=self.extract('Др.-русск. въ, въ-, вън-, ст.-слав. въ, въ-, вън- (греч. текст), русск. в.', [['въ-','въ-'],['вън-','вън-']])
  self.assertEqual([(w['classification'],w['word']) for w in r['witnesses']],[('old-east-slavic','въ'),('old-east-slavic','въ-'),('old-east-slavic','вън-'),('old-church-slavonic','въ'),('old-church-slavonic','въ-'),('old-church-slavonic','вън-')])
 def test_shared_origin_list_is_evidence_but_not_direct_inheritance(self):
  r=self.extract('Происходит от праслав. *slovo, от которого в числе прочего произошли: ст.-слав. слово (род. п. словесе), русск. слово.')
  w=r['witnesses'][0];self.assertEqual(w['protoClaims'][0]['term'],'*slovo');self.assertEqual(w['protoClaims'][0]['relation'],'source-asserted-common-origin')
 def test_comparison_after_descendant_list_is_not_inherited_origin(self):
  for transition in ['; ср.:', '; сюда же']:
   r=self.extract('От праслав. *briti, от которого произошли: ст.-слав. брити'+transition+' ст.-слав. бритва.')
   self.assertEqual(r['witnesses'][1]['protoClaims'],[])
 def test_parent_proto_is_not_given_to_every_comparison_word(self):
  r=self.extract('Происходит от праслав. *rukomojьnikъ. Для сравнения см. ст.-слав. рѫка.')
  self.assertEqual(r['witnesses'][0]['protoClaims'],[])
  self.assertFalse(r['protoContexts'][0]['eligibleForLexemeProto'])
 def test_sentence_boundary_and_negative_context_prevent_false_claims(self):
  r=self.extract('От праслав. *foo, от которого произошли разные слова. Ошибочно сравнивают со ст.-слав. баръ.')
  self.assertEqual(r['witnesses'][0]['protoClaims'],[])
  r=self.extract('Не происходит от праслав. *foo, от которого произошли: ст.-слав. баръ.')
  self.assertEqual(r['witnesses'][0]['protoClaims'],[])
 def test_proto_indoeuropean_mention_is_not_mislabelled_proto_slavic(self):
  r=self.extract('Праслав. слово сопоставляют с праиндоевр. *h3ebhi; ст.-слав. слово.')
  self.assertEqual(r['protoContexts'],[])
 def test_generic_language_explanation_is_queued_not_invented_as_word(self):
  r=self.extract('Из старославянского языка; церк.-слав. суффикс здесь неизвестен.')
  self.assertEqual(r['witnesses'],[]);self.assertEqual(len(r['unresolvedMarkers']),2)
 def test_old_east_slavic_is_not_automatically_a_cs_proto_mapping(self):
  r=self.extract('От праслав. *slovo, от которого произошли: др.-русск. слово.')
  self.assertEqual(r['witnesses'][0]['classification'],'old-east-slavic');self.assertEqual(r['witnesses'][0]['protoClaims'],[])
 def test_explanatory_prose_is_not_a_spelling(self):
  for text in ['Из церк.-слав. при исконнорусск. всток.', 'Из ст.-слав. сербск. пример.', 'Из др.-русск. производное на -ио.', 'Из церк.-слав. прич. прошедшего времени.', 'Из церк.-слав. вместо *веремя.', 'Церк.-слав. название — иже, икъ.', 'Церк.-слав. знач. народ.']:
   self.assertEqual(self.extract(text)['witnesses'],[],text)
  r=self.extract('Др.-русск. ѩвѣ, также ѩвити, ст.-слав. ѩвѣ.')
  self.assertEqual([w['word'] for w in r['witnesses']],['ѩвѣ','ѩвѣ'])
 def test_comma_prose_requires_lexical_link(self):
  r=self.extract('Ст.-слав. слово, некая пояснительная фраза.')
  self.assertEqual([w['word'] for w in r['witnesses']],['слово'])
 def test_prefix_recension_qualifier_is_preserved_without_inventing_date(self):
  r=self.extract('Позднецерк.-слав. штоудо.')
  self.assertEqual(r['witnesses'][0]['sourceQualifier'].lower(),'поздне')
  self.assertEqual(r['witnesses'][0]['word'],'штоудо')

if __name__=='__main__':unittest.main()
