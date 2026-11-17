"""Reuse the shared bounded three-phase builder with an independent unit and sidecars."""
from pathlib import Path
import sys
import fcntl
from contextlib import ExitStack
import build_portal_candidate as shared
original = shared.bounded_args
def reader_args(*args):
    result = original(*args)
    result[result.index('--unit=typikon-triod-build')] = '--unit=typikon-reader-build'
    result.insert(result.index('--working-directory=' + str(args[0])), '--setenv=CS_READER_REGISTRY_DB=typikon_reader_m202_u17')
    return result
shared.bounded_args = reader_args
if __name__ == '__main__':
    candidate = Path(sys.argv[1]).resolve()
    baseline = candidate / 'next.config.reader-baseline.js'
    baseline.write_bytes((candidate / 'next.config.js').read_bytes())
    with ExitStack() as locks:
        for name in ['/home/admin/.config/interlex-backup/backup.lock', '/var/www/typikon.su/typikon-web-releases/deploy.lock', '/var/www/typikon.su/typikon-ordo-releases/deploy.lock']:
            print('WAIT_COMMON_LOCK ' + name, flush=True)
            lock = locks.enter_context(open(name, 'a')); fcntl.flock(lock, fcntl.LOCK_EX)
        current = Path('/var/www/typikon.su/typikon-web-releases/current').resolve()
        assert str(current) == (candidate / 'M202_BASE').read_text().strip(), 'Active book changed; rebase the candidate'
        shared.build(candidate, Path('/var/www/typikon.su/data.db').resolve(), baseline)
