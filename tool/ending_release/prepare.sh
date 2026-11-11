#!/usr/bin/env bash
set -Eeuo pipefail
stage=/var/www/typikon-data/cs-dictionary/imports/ending-segments-20261111-v1
python3 - "$stage" <<'PY'
import json,sys,shlex,subprocess,os,sqlite3
from pathlib import Path
s=Path(sys.argv[1]);items=shlex.split(subprocess.check_output(['systemctl','show','typikon-web.service','--property=Environment','--value'],text=True))
paths={x.split('=',1)[0]:x.split('=',1)[1] for x in items if x.startswith(('CS_DICTIONARY_DB=','CS_MORPHEME_DB='))}
assert len(paths)==2
base=paths['CS_DICTIONARY_DB'];morph=paths['CS_MORPHEME_DB'];d=sqlite3.connect('file:'+base+'?mode=ro',uri=True);m=dict(d.execute('select key,value from metadata'));d.close()
assert m['version']=='41e5a92406e4bb03f215a29b6a40edf6848bcb554ae49557dc388f7d6beb4df1'
d=sqlite3.connect('file:'+morph+'?mode=ro',uri=True);mm=dict(d.execute('select key,value from metadata'));d.close()
assert mm['dictionaryVersion']==m['version'] and mm['version']=='d06531f86ee7a5a9a20b162adbc4447f11d6a57d2ff25b0037aacbf3aeb2a603'
release=os.path.realpath('/var/www/typikon.su/typikon-web-releases/current')
state={'dictionary':base,'dictionaryVersion':m['version'],'morphemes':morph,'morphemeVersion':mm['version'],'release':release,'candidate':'/var/www/typikon-data/cs-dictionary/publications/endings-20261111-v1.sqlite'}
assert not Path(state['candidate']).exists() and not (s/'state.json').exists()
(s/'state.json').write_text(json.dumps(state,indent=2)+'\n')
PY
release=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["release"])' "$stage/state.json")
base=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["dictionary"])' "$stage/state.json")
candidate=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["candidate"])' "$stage/state.json")
NODE_PATH="$release/node_modules" node "$stage/resegment.cjs" --base "$base" --out "$candidate" --version 41e5a92406e4bb03f215a29b6a40edf6848bcb554ae49557dc388f7d6beb4df1 --report "$stage/candidate.report.json" > "$stage/build.log" 2>&1
python3 "$stage/validate.py" "$stage"
