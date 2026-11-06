# Read-only Wiktionary pilot

Python 3.9+; no extra Python dependencies. Native search-key export also needs
Node 22 and the installed `tsx` / `better-sqlite3` dependencies of typikon-web.
Run Python commands from cs-app. Generated data stays in the ignored
`import/wiktionary-pilot/` directory. There is no apply command.

## Downloads

```sh
mkdir -p import/wiktionary-pilot/raw
python3 tool/wiktionary_pilot/download.py https://kaikki.org/dictionary/downloads/ru/ru-extract.jsonl.gz import/wiktionary-pilot/raw/ru-extract.jsonl.gz
python3 tool/wiktionary_pilot/download.py 'https://kaikki.org/dictionary/Old%20Church%20Slavonic/kaikki.org-dictionary-OldChurchSlavonic.jsonl' import/wiktionary-pilot/raw/en-ocs.jsonl
python3 tool/wiktionary_pilot/download.py 'https://kaikki.org/dictionary/Proto-Slavic/kaikki.org-dictionary-ProtoSlavic.jsonl' import/wiktionary-pilot/raw/en-proto.jsonl
```

The last two are postprocessed language exports. Do not silently replace these
with raw exports under the same snapshot identity. The downloader saves HTTP
metadata and SHA-256, supports resume, and refuses to mix partial snapshots.
Archive the download index and the two language index pages for upstream dates.
The associated Russian extraction log prefix identifies its original XML dump.

## Input snapshots

The typikon publication must match the version of the live API (verified for the
2026-11-06 trial in `baseline-live-check.json`). The existing `cs-publication-v1.sqlite`
was used read-only. From the adjacent typikon-web directory:

```sh
node --import tsx ../cs-app/tool/wiktionary_pilot/export_native.cjs
```

For proto articles, use the established SSH helper from adjacent interlex. It
selects the active release and configures the actual shared database path. Only
public proto columns are read; auth/corpus/user databases are not exported.
From interlex:

```sh
bash -c 'set +x; source scripts/ops/remote.sh; remote_app node -' < ../cs-app/tool/wiktionary_pilot/export_proto.cjs > ../cs-app/import/wiktionary-pilot/interlex-proto-production.json
```

Keep snapshots identified and immutable during a trial. Record their SHA-256
and byte sizes in `inputs-before-matching.json` before matching.

## Extraction, matching, review

```sh
python3 tool/wiktionary_pilot/pilot.py extract
```

Then, from typikon-web, generate loose keys using its actual search normalizer:

```sh
node --import tsx ../cs-app/tool/wiktionary_pilot/prepare_keys.cjs
```

Back in cs-app:

```sh
python3 tool/wiktionary_pilot/pilot.py match
python3 tool/wiktionary_pilot/review.py
python3 -m unittest discover -s tool/wiktionary_pilot -p 'test_*.py' -v
```

`review.py` verifies the known publication SHA-256 of this specific trial.
For a future publication, create a separate identified trial and update the
expected baseline deliberately; do not bypass a checksum failure.

The trial preserves source records, language labels, unknown revision IDs,
original spelling, links, source relation types and nested descendant paths.
Raw `forms` includes romanizations and table metadata: it is not a ready-made
form inventory. Placeholders and dirty template expansions are flagged.

All mappings remain proposals. Do not infer synonymy, direct inheritance or
historical dates from a spelling key, a shared proto article or a wiki timestamp.
Do not overwrite human decisions by editing generated JSON. Source texts remain
attributed to their Wiktionary pages and snapshot; preserve applicable CC BY-SA
terms and page-specific notices before any publication.
