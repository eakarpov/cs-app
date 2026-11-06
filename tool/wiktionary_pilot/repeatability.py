"""Repeat both matchers and require identical content artifacts (timestamps excluded)."""
import argparse,hashlib,subprocess,sys,tempfile,shutil
from pathlib import Path
from pilot import write_json
FILES=['native-proposals.jsonl','unmatched.jsonl','spelling-proposals.jsonl','etymology-proposals.jsonl','reverse-proto-proposals.jsonl','interlex-heads-needing-review.jsonl','review-sample.json','review.html','historical-spelling-proposals.jsonl','historical-proto-proposals.jsonl','historical-proto-context-only.jsonl']
def sha(path):
 h=hashlib.sha256()
 with path.open('rb') as f:
  while data:=f.read(8*1024*1024):h.update(data)
 return h.hexdigest()
def check(root):
 before={name:sha(root/name) for name in FILES}
 tool=Path(__file__).parent
 # Trial artifacts can be cited by a reviewed import. Never regenerate in place.
 with tempfile.TemporaryDirectory(prefix='cs-wiki-repeat-') as tmp:
  check_root=Path(tmp)
  for name in ['selected.jsonl','native-index.json','interlex-proto-production.json','civil-keys.json','historical-witnesses.jsonl']:
   shutil.copyfile(root/name,check_root/name)
  for script,action in [('pilot.py','match'),('full_pass.py','match-history')]:
   subprocess.run([sys.executable,str(tool/script),action,'--root',str(check_root)],check=True,stdout=subprocess.DEVNULL)
  after={name:sha(check_root/name) for name in FILES}
 assert before==after,'Non-reproducible matching artifacts'
 write_json(root/'repeatability.json',{'identical':True,'comparedFiles':len(FILES),'sha256':after,'timestampsExcluded':True,'appliedToProduction':False})
 print('Identical content artifacts:',len(FILES))
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--root',type=Path,default=Path('import/wiktionary-full'));check(p.parse_args().root)
