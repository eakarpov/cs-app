#!/usr/bin/env bash
set +x
set -Eeuo pipefail
stage=/var/www/typikon-data/cs-dictionary/imports/ending-segments-20261111-v1
conf=/etc/systemd/system/typikon-web.service.d/zzzz-cs-ending-segments.conf
sudo_task(){ printf '%s\n' "$_task_sudo_password" | sudo -S -p '' -- "$@"; }
exec 9>/var/www/typikon.su/typikon-web-releases/deploy.lock
flock -n 9
python3 - "$stage" <<'PY'
import json,sys,subprocess,shlex,hashlib,sqlite3,os
from pathlib import Path
s=Path(sys.argv[1]);state=json.loads((s/'state.json').read_text());v=json.loads((s/'validation.json').read_text());p=json.loads((s/'probe-result.json').read_text())
assert p['status']=='passed' and p['dictionaryVersion']==v['dictionaryVersion'] and p['morphemeVersion']==v['morphemeVersion']
assert os.path.realpath('/var/www/typikon.su/typikon-web-releases/current')==state['release']
env=shlex.split(subprocess.check_output(['systemctl','show','typikon-web.service','--property=Environment','--value'],text=True))
for key,path in [('CS_DICTIONARY_DB',state['dictionary']),('CS_MORPHEME_DB',state['morphemes'])]:assert key+'='+path in env
for path,expected in [(state['candidate'],v['dictionarySha256']),(v['morphemeCandidate'],v['morphemeSha256'])]:
 with open(path,'rb') as f:assert hashlib.file_digest(f,'sha256').hexdigest()==expected
(s/'override.conf').write_text('[Service]\nEnvironment="CS_DICTIONARY_DB='+state['candidate']+'"\nEnvironment="CS_MORPHEME_DB='+v['morphemeCandidate']+'"\n')
PY
had=0
if sudo_task test -f "$conf";then had=1;sudo_task cp "$conf" "$stage/override-before.conf";fi
switched=0
rollback(){
 local code=$?
 if (( code != 0 && switched == 1 ));then
  if (( had == 1 ));then sudo_task install -m 0644 "$stage/override-before.conf" "$conf";else sudo_task rm -f "$conf";fi
  sudo_task systemctl daemon-reload
  sudo_task systemctl restart typikon-web.service
 fi
 exit "$code"
}
trap rollback EXIT
switched=1
sudo_task install -m 0644 "$stage/override.conf" "$conf"
sudo_task systemctl daemon-reload
sudo_task systemctl restart typikon-web.service
ready=0
for i in $(seq 1 30);do
 if curl -fsS --max-time 2 http://127.0.0.1:3000/api/health > "$stage/active-health.json";then ready=1;break;fi
 sleep 1
done
[[ "$ready" == 1 ]]
python3 "$stage/verify_http.py" --base http://127.0.0.1:3000/api/v2/cs/ --stage "$stage" --out "$stage/active-result.json"
switched=0
trap - EXIT
printf '%s\n' 'Ending segments publication activated'
