#!/usr/bin/env bash
set +x
set -Eeuo pipefail
stage=/var/www/typikon-data/cs-dictionary/imports/morpheme-schema2-20261111
root=/var/www/typikon.su/typikon-web-releases
conf=/etc/systemd/system/typikon-web.service.d/zzzzz-cs-morpheme-schema2.conf
sudo_task(){ printf '%s\n' "$_task_sudo_password" | sudo -S -p '' -- "$@"; }
exec 9>"$root/deploy.lock"
flock -n 9
candidate=$(cat "$stage/candidate-path")
previous=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["release"])' "$stage/state.json")
[[ "$candidate" == "$root"/releases/*-morpheme-schema2 ]]
[[ "$(readlink -f "$root/current")" == "$previous" ]]
if sudo_task test -e "$conf";then echo 'Override already exists; inspect before repeating' >&2;exit 1;fi
python3 - "$stage" "$candidate" "$previous" <<'PY'
import json,sys,hashlib,shlex,subprocess,sqlite3
from pathlib import Path
s,c,previous=map(Path,sys.argv[1:]);state=json.loads((s/'state.json').read_text());report=json.loads((s/'candidate.report.json').read_text());probe=json.loads((s/'probe-result.json').read_text())
assert probe['status']=='passed' and probe['version']==report['version']
env=dict(x.split('=',1) for x in shlex.split(subprocess.check_output(['systemctl','show','typikon-web.service','--property=Environment','--value'],text=True)))
assert env['CS_MORPHEME_DB']==state['morphemes'] and env['CS_DICTIONARY_DB']==state['dictionary']
pub=Path((s/'publication-path').read_text().strip());assert hashlib.sha256(pub.read_bytes()).hexdigest()==report['sha256']
(s/'override.conf').write_text('[Service]\nEnvironment="CS_MORPHEME_DB='+str(pub)+'"\n')
source=sqlite3.connect((previous/'nobles.db').resolve().as_uri()+'?mode=ro',uri=True);destination=sqlite3.connect(c/'nobles.db.activation');source.backup(destination);destination.close();source.close();(c/'nobles.db.activation').replace(c/'nobles.db')
PY
link_to(){ ln -s "$1" "$root/.schema2-link.$$";mv -Tf "$root/.schema2-link.$$" "$root/$2"; }
switched=0
rollback(){
 local code=$?
 if (( code != 0 && switched == 1 ));then
  link_to "$previous" current
  sudo_task rm -f "$conf"
  sudo_task systemctl daemon-reload
  sudo_task systemctl restart typikon-web.service
 fi
 exit "$code"
}
trap rollback EXIT
switched=1
sudo_task install -m 0644 "$stage/override.conf" "$conf"
link_to "$candidate" current
sudo_task systemctl daemon-reload
sudo_task systemctl restart typikon-web.service
ready=0
for i in $(seq 1 30);do
 if curl -fsS --max-time 2 http://127.0.0.1:3000/api/health > "$stage/active-health.json";then ready=1;break;fi
 sleep 1
done
[[ "$ready" == 1 ]]
python3 "$stage/verify_http.py" --base http://127.0.0.1:3000/api/v2/cs/ --stage "$stage" --out "$stage/active-result.json"
link_to "$previous" previous
switched=0
trap - EXIT
printf '%s\n' 'Schema=2 API activated'
