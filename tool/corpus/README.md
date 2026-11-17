# Corpus pilot: Unicode17 release evidence

`node17.sh` runs the backend with pinned Node v22.23.2 / ICU78.2 / Unicode17,
using official archive SHA256 values in `runtime.json`. It caches the runtime in
ignored `import/toolchains`, changes cwd to adjacent typikon-web and supplies its
local read-only rules path unless explicitly overridden. Dictionary publications
must be selected explicitly; no implicit latest D is used for a build.

The actual migration/build/import implementation is committed in typikon-web:
`src/scripts/reader-unicode-{baseline,migrate,import}.ts`, reader/index modules,
`.nvmrc`, and `docs/cs-reader-unicode17.md`.

These Python/shell helpers record the 2026-11-17 publication procedure and its
fixed pilot I/C/D. They are acceptance/recovery tools, not generic unattended
release commands. Main evidence: `qa/mobile/m2-02-u17/acceptance.json`.

- `build_reader_candidate.py` reuses the shared three-phase bounded builder:
  common backup/Web/Ordo locks, 2GiB RAM, no swap, separate compile/types/generate.
- `merge_coverage.py` merges only scoped pilot evidence while retaining other
  book publications. Freeze a completed canonical snapshot with the other agent.
- `m202-stage-final.py` checks natural build completion/source hashes, protects
  the candidate from retention and starts a private loopback acceptance process.
- `m202-smoke.py` performs scoped API/HTML/contract/quota checks without visual
  inspection or APK publication.
- `m202-activate.py` rechecks active release/native digest under common locks,
  imports only reader sidecars, switches the Web release, validates HTTPS and
  rolls back on failure. App update source files and Ordo/SQLite are checked unchanged.
- nginx snippets limit only reader/index: 10/s burst20, OPTIONS exempt.

Prepare candidates from the CURRENT server release, not a stale local env/SQLite.
Preserve the actual running dictionary/morpheme paths when they override `.env`.
If native container SHA differs, explicitly re-audit its exact raw hashes and all
201 Unicode16/17 projection hashes via `reader-unicode-import --rebind-native`
before export/activation. Never import synthetic contract fixtures into production.

After publication invoke the existing recovery/S3 helper. Do not manually prune
previous releases before its verified readback. Next code-only releases retain
reader flags and the private immutable index via typikon-web's
`scripts/preserve-reader-publication.mjs`. Unrelated book/container changes remain
readable only when the original body's raw SHA still exactly matches; moved or
changed bytes require evidence or produce 410.
