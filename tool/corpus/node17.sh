#!/usr/bin/env bash
set -euo pipefail
workspace=$(cd "$(dirname "$0")/../.." && pwd)
case "$(uname -s)-$(uname -m)" in
  Darwin-x86_64) platform=darwin-x64;; Darwin-arm64) platform=darwin-arm64;;
  Linux-x86_64) platform=linux-x64;; Linux-aarch64) platform=linux-arm64;;
  *) echo 'Unsupported corpus build platform' >&2; exit 1;;
esac
runtime="$workspace/import/toolchains/node-v22.23.2-$platform"
if [[ ! -x "$runtime/bin/node" ]]; then
  mkdir -p "$workspace/import/toolchains"
  archive=$(mktemp)
  trap 'rm -f "$archive"' EXIT
  curl --fail --silent --show-error --location "https://nodejs.org/dist/v22.23.2/node-v22.23.2-$platform.tar.gz" --output "$archive"
  python3 - "$workspace/tool/corpus/runtime.json" "$archive" "$platform" <<'PY'
import hashlib,json,sys
manifest=json.load(open(sys.argv[1])); actual=hashlib.sha256(open(sys.argv[2],'rb').read()).hexdigest()
assert actual==manifest['archives']['node-v22.23.2-'+sys.argv[3]+'.tar.gz'], 'Node archive SHA256 mismatch'
PY
  tar -xzf "$archive" -C "$workspace/import/toolchains"
fi
"$runtime/bin/node" -e 'if(process.version!=="v22.23.2"||process.versions.unicode!=="17.0"||process.versions.icu!=="78.2")process.exit(1)'
cd "$workspace/../typikon-web"
export RULES_DB=${RULES_DB:-"$workspace/../typikon-rules/src/data.db"}
exec "$runtime/bin/node" "$@"
