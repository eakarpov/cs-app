import hashlib,io,json,re,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
from download_ranges import download_ranges

class Response(io.BytesIO):
 def __init__(self,data,status,headers):super().__init__(data);self.status=status;self.headers=headers

class RangeDownloadTests(unittest.TestCase):
 def test_ranges_are_written_at_correct_offsets_with_exact_snapshot_hash(self):
  payload=bytes(range(256))*19+b'end';requests=[]
  def fetch(request,timeout=0):
   common={'Content-Length':str(len(payload)),'Last-Modified':'Fri, 30 Oct 2026 20:48:24 GMT','ETag':'snapshot-A'}
   if request.get_method()=='HEAD':return Response(b'',200,common)
   match=re.fullmatch(r'bytes=(\d+)-(\d+)',request.get_header('Range'))
   a,b=map(int,match.groups());requests.append((a,b));return Response(payload[a:b+1],206,{'Content-Range':f'bytes {a}-{b}/{len(payload)}'})
  with tempfile.TemporaryDirectory() as temp,patch('download_ranges.urllib.request.urlopen',side_effect=fetch):
   path=Path(temp)/'archive.gz';download_ranges('https://example.test/archive.gz',path)
   self.assertEqual(path.read_bytes(),payload)
   self.assertEqual(json.loads(Path(str(path)+'.http.json').read_text())['sha256'],hashlib.sha256(payload).hexdigest())
   self.assertEqual(sum(b-a+1 for a,b in requests),len(payload))
   self.assertEqual(sorted(requests)[0][0],0)
   self.assertFalse(Path(str(path)+'.part').exists())
 def test_changed_snapshot_cannot_resume_into_an_old_partial(self):
  def fetch(request,timeout=0):return Response(b'',200,{'Content-Length':'8','Last-Modified':'date-B','ETag':'snapshot-B'})
  with tempfile.TemporaryDirectory() as temp,patch('download_ranges.urllib.request.urlopen',side_effect=fetch):
   path=Path(temp)/'archive.gz';partial=Path(str(path)+'.part');partial.write_bytes(b'previous')
   Path(str(path)+'.ranges.json').write_text(json.dumps({'remote':{'Content-Length':'8','Last-Modified':'date-A','ETag':'snapshot-A'},'ranges':[]}))
   with self.assertRaises(RuntimeError):download_ranges('https://example.test/archive.gz',path)
   self.assertEqual(partial.read_bytes(),b'previous');self.assertFalse(path.exists())
 def test_ignored_range_is_rejected_and_not_published_as_complete(self):
  def fetch(request,timeout=0):return Response(b'12345678',200,{'Content-Length':'8','Last-Modified':'date','ETag':'snapshot'})
  with tempfile.TemporaryDirectory() as temp,patch('download_ranges.urllib.request.urlopen',side_effect=fetch):
   path=Path(temp)/'archive.gz'
   with self.assertRaises(RuntimeError):download_ranges('https://example.test/archive.gz',path)
   self.assertFalse(path.exists());self.assertFalse(Path(str(path)+'.http.json').exists())

if __name__=='__main__':unittest.main()
