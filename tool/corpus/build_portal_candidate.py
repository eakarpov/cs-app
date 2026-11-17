"""Build Next in separate bounded processes, without permission to activate a release."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys


def inputs_sha(web):
    files = sorted(p for p in (web / 'src').rglob('*') if p.is_file())
    files += [web / name for name in ('next.config.js', 'tsconfig.json', 'package.json', 'package-lock.json', 'next-env.d.ts') if (web / name).is_file()]
    digest = hashlib.sha256()
    for path in files:
        digest.update(str(path.relative_to(web)).encode() + b'\0')
        digest.update(hashlib.sha256(path.read_bytes()).digest())
    return digest.hexdigest()


def build(web, database, baseline_config):
    marker = web / 'candidate-build.complete'
    marker.unlink(missing_ok=True)
    config = web / 'next.config.js'
    original = baseline_config.read_text()
    config.write_text(original.replace('cpus: 2', 'cpus: 1').replace('if (!isServer) {', 'config.cache = false;\n    if (!isServer) {', 1))
    phases = [
        ('compile', 1024, ['node', 'node_modules/next/dist/bin/next', 'build', '--no-lint', '--experimental-build-mode', 'compile']),
        ('types', 1536, ['node', 'node_modules/typescript/bin/tsc', '--noEmit', '--incremental', 'false']),
        ('generate', 1024, ['node', 'node_modules/next/dist/bin/next', 'build', '--no-lint', '--experimental-build-mode', 'generate']),
    ]
    try:
        for phase, heap, args in phases:
            done = web / ('candidate-' + phase + '.complete')
            done.unlink(missing_ok=True)
            print('BUILD PHASE ' + phase, flush=True)
            subprocess.run(bounded_args(web, database, heap, done, args), check=True)
            if not done.is_file():
                raise RuntimeError('Build phase was stopped before natural completion: ' + phase)
    finally:
        config.write_text(original)
    marker.write_text(json.dumps({'phases': [p[0] for p in phases], 'inputs_sha256': inputs_sha(web)}, indent=2) + '\n')


def bounded_args(web, database, heap, done, args):
    return [
        'systemd-run', '--wait', '--pipe', '--collect', '--unit=typikon-triod-build',
        '--property=MemoryHigh=1700M', '--property=MemoryMax=2G',
        '--property=MemorySwapMax=0', '--property=CPUQuota=60%',
        '--property=Nice=15', '--property=IOWeight=10', '--uid=admin',
        '--setenv=NODE_OPTIONS=--max-old-space-size=' + str(heap),
        '--setenv=RULES_DB=' + str(database), '--setenv=BUILD_PHASE_MARKER=' + str(done),
        '--working-directory=' + str(web),
        'bash', '-c', '"$@" && touch "$BUILD_PHASE_MARKER"', 'candidate-phase', *args,
    ]


if __name__ == '__main__':
    build(*(Path(arg).resolve() for arg in sys.argv[1:4]))
