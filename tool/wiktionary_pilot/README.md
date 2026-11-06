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

## Full raw English snapshot and Russian etymology witnesses

Use a **separate** `import/wiktionary-full/` directory; retain the original pilot.
Do not unpack the English gzip to disk. `download_ranges.py` uses at most four
validated byte ranges, resumes only the same HTTP snapshot and computes SHA-256.

```sh
mkdir -p import/wiktionary-full/raw
python3 tool/wiktionary_pilot/download_ranges.py https://kaikki.org/dictionary/raw-wiktextract-data.jsonl.gz import/wiktionary-full/raw/en-extract.jsonl.gz
python3 tool/wiktionary_pilot/full_pass.py ru
python3 tool/wiktionary_pilot/full_pass.py en
python3 tool/wiktionary_pilot/full_pass.py combine
```

The Russian pass reuses the checksum-verified full Russian raw archive in the
original pilot. It scans etymologies in **all language sections**, preserves
parent records and Unicode codepoint offsets, and separates Old East Slavic
witnesses from Church Slavonic / Old Church Slavonic. A parent article's own
etymon is never automatically assigned to a cited historical spelling.
Only an explicit shared-origin enumeration is eligible for a *proposed* relation;
co-occurrence-only evidence is written separately and excluded from that relation.
Explanatory prose after a language marker goes to the unresolved queue. Comma
continuations require a lexical Wikilink; this deliberately sacrifices recall.
Raw parent texts remain available for later reprocessing.

Export fresh read-only native/proto snapshots as above, using an explicit native
destination argument (`../cs-app/import/wiktionary-full/native-index.json`) and
redirecting proto output to the new root. Record input hashes before matching.
From typikon-web:

```sh
node --import tsx ../cs-app/tool/wiktionary_pilot/prepare_keys.cjs ../cs-app/import/wiktionary-full
```

Then from cs-app:

```sh
python3 tool/wiktionary_pilot/pilot.py match --root import/wiktionary-full
python3 tool/wiktionary_pilot/full_pass.py match-history
python3 tool/wiktionary_pilot/review.py --root import/wiktionary-full
python3 tool/wiktionary_pilot/full_review.py
```

`en-full-extraction.json` attests full archive row/byte counts and gzip CRC through
EOF; `full-summary.json` compares candidate pairs to the earlier pilot.
`historical-review.html` provides a stratified 200-witness review alongside the
existing dictionary/proto review. All generated correspondences remain pending;
there is no database-application operation.

To repeat both matchers and check deterministic content artifacts:

```sh
python3 tool/wiktionary_pilot/repeatability.py
```

This excludes timestamp-bearing summaries and requires identical SHA-256 for
11 proposal/review artifacts. The full review also verifies that every stored
historical text span reproduces its spelling exactly.

The subsequent audit of the 85 added pairs is in
`tool/wiktionary_review/README.md`. It identified truncated multiword proto heads,
non-article index pages and comparisons over-interpreted as origins. Those
regressions are fixed for future runs. The full trial is retained as the original
candidate snapshot; its 1,087 pairs are not a verified import. New extraction runs
should use a separate root. `repeatability.py` now compares outputs generated in
a temporary directory and leaves the original trial artifacts intact on mismatch.
