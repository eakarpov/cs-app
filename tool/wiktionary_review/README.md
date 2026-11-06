# Source review of 85 new Wiktionary → interlex pairs

Run from cs-app with Python 3.9+. The review and editorial preparation steps
open databases read-only. The separately authorized candidate builder writes only
a new SQLite file. All output paths must be new directories/files.

`data/wiktionary/review-85.json` contains one explicit decision for each stable
pair ID, reasons and public notes. It pins the original change set and evidence
files by SHA-256. Decisions cover only these 85 pairs. They do not certify the
previous 1,002 proposals or turn repeated Wiktionary text into independent evidence.

## Prepare the reviewed package

```sh
python3 tool/wiktionary_review/build.py --out import/wiktionary-reviewed/package-final
```

The builder checks all 85 IDs, evidence-file hashes, full publication checksum,
source text offsets and proto headings. It writes:

- `audit-85.json` and `review-85.html`: all decisions and selected source contexts;
- `import-bundle.json`: 17 ready source references, all 85 decisions and a registry
  with immutable source records, quoted spans, snapshot IDs and checksums;
- `summary.json`: counts and guards.

`ready` means the historical reference, lexeme identity and meaning have been
checked against the available sources. It does not claim independent scholarly
review or a direct inheritance relation. The staged API reference uses the
existing `attested-in` relation. Its provenance states this restricted scope.

## Prepare the typikon-web editorial merge

```sh
python3 tool/wiktionary_review/prepare_import.py \
  --bundle import/wiktionary-reviewed/package-final/import-bundle.json \
  --decisions ../typikon-web/src/data/csDictionary/review.json \
  --publication import/cs-publication-v1.sqlite \
  --proto-snapshot import/wiktionary-full/interlex-proto-production.json \
  --out import/wiktionary-reviewed/typikon-final
```

This creates **a separate** `review.merged.json` and `plan.json`. The existing
review file and publication stay untouched. All existing fields, relations,
reject decisions, sources and etymology entries survive. The script records
all 85 verdicts in `etymologyReviewDecisions` and source records in
`etymologySources`. The etymology references themselves carry structured
`provenance`; their existing API fields remain compatible with the reader.
The current builder/finalizer passes these objects through without stripping
additional JSON fields. The current Flutter screen reads the existing fields;
full structured provenance remains available in the payload and editorial file.

Existing references are preserved rather than replaced. A competing etymology,
editor rejection, conflicting review/source record, changed article payload or
proto body stops preparation. There is no automatic resolution of such conflicts.
Reusing the merged file as input adds zero links and produces identical JSON.
Input/output checksums in `plan.json` support compare-and-swap at a future step.

## Future publication

Before any release, obtain fresh production-backed inputs, repeat the guards,
back up the current publication, and build a separate candidate. The finalizer
also processes morphology and semantic relations; it is not a narrow etymology
patcher. Verify all IDs, schemes, local edits, existing etymologies and source
records against the full current baseline before switching publications. Keep
`etymologySources`, the decision registry and the complete merged editorial file
with the candidate. Source/body drift requires a new audit rather than a forced
import. No release command is part of this package.

## Tests

```sh
python3 -m unittest discover -s tool/wiktionary_review -p 'test_*.py'
python3 -m unittest discover -s tool/wiktionary_pilot -p 'test_*.py'
```

Regression cases cover truncated multiword proto heads, index pages mistaken for
articles, comparisons after descendant lists, idempotency, preserved editor data,
conflicts, changed/missing targets, source offsets and bundle tampering.
Repeatability checks now use a temporary directory so that a new matcher cannot
overwrite artifacts already cited by a reviewed import.

## Build an authorized etymology-only publication

`candidate.py` is the separate write-capable step added for the approved import.
It creates a new SQLite file with `Connection.backup`; the base stays read-only.
It accepts only the ready set of the checksum-pinned bundle. The SQLite authorizer
blocks changes to forms and all unrelated existing tables and blocks any article
column update except `payload`. Every changed article is then compared field by
field with its baseline, allowing only appended etymologies. Every existing table
keeps its schema and row count, except intentional version metadata additions.
The candidate stores `etymology_sources` and `etymology_review_decisions` as well.
`state=complete` is set only after integrity and preservation checks pass.

```sh
python3 tool/wiktionary_review/candidate.py \
  --base /path/to/frozen-baseline.sqlite \
  --out /path/to/new-etymology-publication.sqlite \
  --bundle import/wiktionary-reviewed/package-final/import-bundle.json \
  --decisions import/wiktionary-applied/editorial-current/review.merged.json \
  --expected-bundle 58c9ecd7c5fcfe74c9a5a167a43076e46b0c8db4df32987e1e65e9b5e5718b4e \
  --report /path/to/new-etymology-publication.json
```

This command does not activate a service. Production activation separately takes
an independent verified backup, keeps the old publication, checks the current
release/configuration, changes only the dictionary path, restarts the reader and
checks all 25 published references through HTTP. A failed activation restores the
previous configuration. The data-only systemd override persists across code
releases; the local deployment environment should point to the same publication.

The approved bundle is now active. The former local baseline is retained at
`import/publication-backups/aa4f4913-before-wiktionary.sqlite`; use it explicitly
with `--publication` when reproducing the pre-application review. The canonical
`import/cs-publication-v1.sqlite` now contains the activated data version.
Application receipt: `qa/wiktionary-import-applied.json`.
