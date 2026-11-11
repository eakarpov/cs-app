#!/usr/bin/env bash
set +x
set -euo pipefail
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# Credentials stay in the existing private release target; send only over SSH stdin.
source "${CS_RELEASE_TARGET_SCRIPT:-$script_dir/../../../typikon-web/scripts/release-target.sh}"
{ printf '%s\n' "${SUDO_PASSWORD:-$PASSWORD}"; cat "$script_dir/activate.sh"; } |
 ssh_run "bash -c 'set +x; IFS= read -r _task_sudo_password; source /dev/stdin > /var/www/typikon-data/cs-dictionary/imports/ending-segments-20261111-v1/activate.log 2>&1'"
