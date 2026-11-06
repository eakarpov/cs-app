import contextlib,gzip,hashlib,io,json,tempfile,unittest
from pathlib import Path
from full_pass import scan_en
from pilot import read_json,lines

class FullRawScanTests(unittest.TestCase):
 def archive(self,root,rows,truncate=False):
  path=root/'raw/en-extract.jsonl.gz';path.parent.mkdir()
  data=b''.join(json.dumps(row,ensure_ascii=False).encode()+b'\n' for row in rows)
  packed=gzip.compress(data)
  if truncate:packed=packed[:-6]
  path.write_bytes(packed)
  Path(str(path)+'.http.json').write_text(json.dumps({'sha256':hashlib.sha256(packed).hexdigest(),'bytes':len(packed)}))
  return data
 def test_complete_scan_selects_language_not_mentions_and_keeps_raw(self):
  with tempfile.TemporaryDirectory() as tmp:
   root=Path(tmp)
   rows=[{'word':'example','lang':'English','lang_code':'en','etymology_text':'Compare Church Slavonic.'},
    {'word':'слово','lang':'Old Church Slavonic','lang_code':'cu','pos':'noun','etymology_templates':[{'name':'inh','args':{'1':'cu','2':'sla-pro','3':'*slovo'}}]},
    {'word':'слово','lang':'Church Slavonic','lang_code':'zls-chs','pos':'noun'},
    {'word':'*slovo','lang':'Proto-Slavic','lang_code':'sla-pro','pos':'noun'}]
   data=self.archive(root,rows)
   with contextlib.redirect_stdout(io.StringIO()):scan_en(root)
   report=read_json(root/'en-full-extraction.json');selected=list(lines(root/'selected-en.jsonl'))
   self.assertEqual(report['rowsScanned'],4);self.assertEqual(report['uncompressedBytesScanned'],len(data))
   self.assertEqual(report['selectedRows'],3);self.assertTrue(report['gzipCrcValidated'])
   self.assertEqual(selected[0]['raw'],rows[1]);self.assertEqual(selected[0]['acquisitionKind'],'raw-wiktextract')
 def test_truncated_gzip_cannot_publish_completion(self):
  with tempfile.TemporaryDirectory() as tmp:
   root=Path(tmp);self.archive(root,[{'word':'слово','lang':'Old Church Slavonic','lang_code':'cu'}],truncate=True)
   with self.assertRaises(EOFError):scan_en(root)
   self.assertFalse((root/'en-full-extraction.json').exists());self.assertFalse((root/'selected-en.jsonl').exists())
 def test_wrong_checksum_is_rejected(self):
  with tempfile.TemporaryDirectory() as tmp:
   root=Path(tmp);self.archive(root,[])
   path=root/'raw/en-extract.jsonl.gz';path.write_bytes(path.read_bytes()+b'x')
   with self.assertRaises(ValueError):scan_en(root)
   self.assertFalse((root/'en-full-extraction.json').exists())

if __name__=='__main__':unittest.main()
