#!/usr/bin/env bash
set -Eeuo pipefail
stage=/var/www/typikon-data/cs-dictionary/imports/morpheme-schema2-20261111
root=/var/www/typikon.su/typikon-web-releases
exec 9>"$root/deploy.lock"
flock -n 9
current=$(readlink -f "$root/current")
python3 - "$stage" "$current" <<'PY'
import json,shlex,subprocess,sys
from pathlib import Path
s=Path(sys.argv[1]);env=shlex.split(subprocess.check_output(['systemctl','show','typikon-web.service','--property=Environment','--value'],text=True));env=dict(x.split('=',1) for x in env)
report=json.loads((s/'candidate.report.json').read_text())
assert env['CS_MORPHEME_DB'].endswith('morphemes-'+report['baseVersion']+'.sqlite')
(s/'state.json').write_text(json.dumps({'release':sys.argv[2],'dictionary':env['CS_DICTIONARY_DB'],'morphemes':env['CS_MORPHEME_DB'],'version':report['version']},indent=2)+'\n')
PY
candidate="$root/releases/$(date -u +%Y%m%dT%H%M%SZ)-morpheme-schema2"
mkdir "$candidate"
printf '%s\n' "$candidate" > "$stage/candidate-path"
tar -C "$current" --exclude='./node_modules' --exclude='./.next' --exclude='./.git' -cf - . | tar -C "$candidate" -xf -
cp -al "$current/node_modules" "$candidate/node_modules"
tar -xzf "$stage/server-overlay.tgz" -C "$candidate"
cp "$stage/source-commit" "$candidate/REVISION"
python3 - "$stage" "$candidate" <<'PY'
import sys,json,gzip,hashlib,sqlite3
from pathlib import Path
s,c=map(Path,sys.argv[1:]);r=json.loads((s/'candidate.report.json').read_text());state=json.loads((s/'state.json').read_text());pub=Path('/var/www/typikon-data/cs-dictionary/publications')/('morphemes-'+r['version']+'.sqlite')
assert not pub.exists()
with gzip.open(s/'candidate.sqlite.gz','rb') as f:body=f.read()
assert hashlib.sha256(body).hexdigest()==r['sha256'];pub.write_bytes(body);pub.chmod(0o444)
d=sqlite3.connect('file:'+state['dictionary']+'?mode=ro',uri=True);assert dict(d.execute('select * from metadata'))['version']==r['dictionaryVersion'];d.close()
(s/'publication-path').write_text(str(pub)+'\n')
with (c/'.env.production').open('a') as f:f.write('\nCS_MORPHEME_DB='+str(pub)+'\nCS_DICTIONARY_DB='+state['dictionary']+'\nSQLITE_DB='+str(c/'nobles.db')+'\n')
PY
cd "$candidate"
node -e 'if(require("ajv/package.json").version!=="6.12.6")throw Error("Unexpected validator version")'
NODE_OPTIONS=--max-old-space-size=2048 NODE_ENV=production node node_modules/next/dist/bin/next build > "$stage/build.log" 2>&1
[[ -s .next/BUILD_ID ]]
printf '%s\n' 'Schema=2 candidate built'
