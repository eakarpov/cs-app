#!/usr/bin/env bash
set -Eeuo pipefail
stage=/var/www/typikon-data/cs-dictionary/imports/morpheme-schema2-20261111
candidate=$(cat "$stage/candidate-path")
publication=$(cat "$stage/publication-path")
cd "$candidate"
CS_MORPHEME_DB="$publication" NODE_ENV=production node node_modules/next/dist/bin/next start -H 127.0.0.1 -p 3001 > "$stage/probe-server.log" 2>&1 &
pid=$!
trap 'kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true' EXIT
ready=0
for i in $(seq 1 30);do
 if curl -fsS --max-time 2 http://127.0.0.1:3001/api/health > "$stage/probe-health.json";then ready=1;break;fi
 sleep 1
done
[[ "$ready" == 1 ]]
python3 - "$stage" "$candidate" <<'PY'
import json,sys
from pathlib import Path
s,c=map(Path,sys.argv[1:]);health=json.loads((s/'probe-health.json').read_text());assert health['status']=='ready' and health['buildId']==(c/'.next/BUILD_ID').read_text().strip()
PY
python3 "$stage/verify_http.py" --base http://127.0.0.1:3001/api/v2/cs/ --stage "$stage" --out "$stage/probe-result.json"
