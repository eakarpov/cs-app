#!/usr/bin/env bash
set -Eeuo pipefail
stage=/var/www/typikon-data/cs-dictionary/imports/ending-segments-20261111-v1
release=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["release"])' "$stage/state.json")
base=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["dictionary"])' "$stage/state.json")
candidate=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["candidate"])' "$stage/state.json")
[[ ! -e "$stage/candidate.report.json" ]]
mv "$stage/build.log" "$stage/build-initial.log"
NODE_PATH="$release/node_modules" node "$stage/resegment.cjs" --resume-building --base "$base" --out "$candidate" --version 41e5a92406e4bb03f215a29b6a40edf6848bcb554ae49557dc388f7d6beb4df1 --report "$stage/candidate.report.json" > "$stage/build.log" 2>&1
python3 "$stage/validate.py" "$stage"
