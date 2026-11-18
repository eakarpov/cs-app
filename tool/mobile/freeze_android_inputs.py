"""Record exact Android client inputs; exclude credentials and generated caches."""
import hashlib,json,subprocess,tarfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def inputs():
 paths=[ROOT/'pubspec.yaml',ROOT/'pubspec.lock',ROOT/'analysis_options.yaml']
 for directory in ['lib','assets','android']:
  for p in (ROOT/directory).rglob('*'):
   if not p.is_file():continue
   rel=p.relative_to(ROOT);parts=rel.parts
   if any(x in {'build','.gradle','.cxx','.kotlin','.idea','.DS_Store'} for x in parts):continue
   if p.name in {'local.properties','key.properties','signing.properties','GeneratedPluginRegistrant.java','gradlew.bat'}:continue
   if p.suffix in {'.jks','.keystore','.log','.p12','.pem','.iml'} or p.name.startswith('.env'):continue
   paths.append(p)
 return sorted({p for p in paths if p.is_file()})
def freeze(out,archive=None):
 files=[{'path':str(p.relative_to(ROOT)),'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'bytes':p.stat().st_size} for p in inputs()]
 digest=hashlib.sha256(json.dumps(files,sort_keys=True,separators=(',',':')).encode()).hexdigest()
 value={'format':'android-source-inputs-v1','gitHead':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),'gitWorkingTreeClean':not bool(subprocess.check_output(['git','status','--porcelain'],cwd=ROOT,text=True).strip()),'sourceTreeSha256':digest,'files':files,'scope':'Android inputs from current worktree; signing material external; generated plugin registration from locked dependencies','secretFilesIncluded':False}
 Path(out).write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n')
 if archive:
  with tarfile.open(archive,'w:gz') as tar:
   for row in files:tar.add(ROOT/row['path'],arcname=row['path'])
 print(json.dumps({'sourceTreeSha256':digest,'files':len(files),'gitWorkingTreeClean':value['gitWorkingTreeClean']}))
if __name__=='__main__':
 import argparse
 p=argparse.ArgumentParser();p.add_argument('--out',required=True);p.add_argument('--archive');a=p.parse_args();freeze(a.out,a.archive)
