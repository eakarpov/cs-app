# Morpheme schema=2 publication

`canonical.py` imports existing published descriptions and strictly matched research components. It never builds chains from reconstruction prose. Existing historical descriptions remain notes. Unknown source class/year remain unclassified/null. Fusion without explicit grapheme coverage remains unmapped. Inputs and written word analyses are never edited.

`research-input.json` is a frozen projection of research 0.53 (only sources, morphemes, allomorphs, etymological records) used for this migration. It is an audit input, not a second editable research database. Future exports pass the current authoritative research explicitly; the full exporter calls the same canonical module and includes its rules in the publication version.

Build against a retained immutable publication:

```sh
python3 tool/morpheme_schema2/build.py --base BASE.sqlite --expected BASE_VERSION --out NEW.sqlite
python3 -m unittest discover -s tool/morpheme_schema2 -p 'test_*.py'
```

Output must be a new path. All common card fields, word analyses and membership/provenance tables are independently checked. The report records hashes, binding and counts. Run the server's `src/scripts/validate-morpheme-schema2.ts BASE.sqlite NEW.sqlite` to validate every canonical card and exact legacy text round trip before publication.

`prepare_remote.sh` builds an isolated runtime from the current production release plus only the committed server overlay. It installs the new immutable data file without changing the active configuration. `probe_remote.sh` and `verify_http.py` check the candidate. `activate_local.sh` uses the existing private release-target transport (credentials via stdin, not arguments) to run `activate_remote.sh`: atomically switch runtime and morpheme override under deploy lock, verify, and roll back on failure. These scripts are release-specific and deliberately reject reuse against a changed active release. No Android update endpoint/public APK is modified.

Deprecated schema=1 exists only as a temporary server adapter. The application uses schema=2 only. At first public client release record an exact sunset timestamp (+90 days) and execute the RETIRE-MORPHEME-SCHEMA1 cleanup from the API design. Keeping a compatibility flag indefinitely is not the retirement plan.
