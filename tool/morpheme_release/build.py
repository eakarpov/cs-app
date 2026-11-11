"""Build an immutable, separate API publication; never edits dictionary/research inputs."""
import argparse
from collections import defaultdict
import hashlib
import json
from pathlib import Path
import re
import sqlite3
import sys
import unicodedata

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tool/morpheme_schema2'))
from canonical import canonical_card
from orthography import normalize


def compact(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'))


def clean(value):
    return re.sub(r'(?:data|import|/private/tmp)/[^\s;,)]+', 'редакторский материал', value)


def key(value):
    try:
        return normalize(value)[0]
    except ValueError:
        return None


def role(m):
    return 'thematic_vowel' if m['kind'] == 'stem_suffix' and 'THEMATIC' in m['id'] else m['kind']


def project(a, form, allomorphs, morphemes, etymologies):
    parts, colors, owners, notes = [], [], [], []
    normalized, alignment = normalize(form['raw'])
    assert normalized == form['normalized'] and alignment == form['alignment']
    for seg in a['segments']:
        allo = allomorphs.get(seg.get('allomorph_id'))
        m = morphemes.get(allo['morpheme_id']) if allo else None
        parts.append({'id': f'p{seg["ordinal"]}', 'morphemeId': m['id'] if m else None,
                      'surface': seg['surface'], 'kind': role(m) if m else seg['kind'],
                      'gloss': clean(m['gloss']) if m else ''})
    for cp in range(len(normalized)):
        indices = [i for i, s in enumerate(a['segments']) if s['start_cp'] <= cp < s['end_cp']]
        assert indices, (a['id'], cp)
        own = [parts[i]['id'] for i in indices]
        kinds = [parts[i]['kind'] for i in indices]
        messages = []
        for i in indices:
            seg = a['segments'][i]
            for e in etymologies.get(seg.get('allomorph_id'), []):
                if e['mapping_mode'] != 'fusion':
                    continue
                components = [c for c in e['components'] if c.get('start_cp', -1) <= cp - seg['start_cp'] < c.get('end_cp', -1)]
                if len(components) < 2:
                    continue
                fused = []
                for c in components:
                    mid = c.get('morpheme_id')
                    if mid in morphemes:
                        fused.append(role(morphemes[mid]))
                        own.extend(p['id'] for p in parts if p['morphemeId'] == mid)
                    elif 'root' in c.get('function', ''):
                        fused.append('root')
                    elif 'stem_vowel' in c.get('function', ''):
                        fused.append(parts[i]['kind'])
                    else:
                        fused.append('derivational_suffix')
                kinds = fused
                messages.append(clean(e['reconstruction'] + '. ' + e['status'] + '. ' + e['note']))
        colors.append(list(dict.fromkeys(kinds)))
        owners.append(list(dict.fromkeys(own)))
        notes.append('\n'.join(messages))
    letters = []
    for cp, (start, end) in enumerate(alignment):
        text = form['raw'][start:end]
        assert text
        letters.append({'text': text, 'partIds': owners[cp], 'colorKinds': colors[cp], 'note': notes[cp]})
    assert ''.join(x['text'] for x in letters) == form['raw']
    return {'id': a['id'], 'form': form['raw'], 'status': a['status'],
            'note': clean(a['rationale']), 'parts': parts, 'letters': letters}


def reviewed_forms(review_path, plan_path, context_path, research_path, dictionary,
                   forms, primary, witnesses, rawdb, baseline_mapping):
    """Revalidate reviewed form addresses; do not infer any extra links."""
    assert plan_path and context_path, 'Review requires its exact plan and server context'
    review = json.loads(review_path.read_text())
    plan = json.loads(plan_path.read_text())
    context = json.loads(context_path.read_text())
    for name, path in [('research', research_path), ('plan', plan_path), ('serverContext', context_path)]:
        assert hashlib.sha256(path.read_bytes()).hexdigest() == review['inputHashes'][name], ('Changed review input', name)
    assert review['dictionaryVersion'] == dictionary['dictionaryVersion'] == context['metadata']['version']
    assert plan['baseline']['fingerprint'] == context['metadata']['baselineFingerprint']
    assert plan['sourceVersion'] == context['metadata']['sourceVersion']
    words = {w['id']: w for w in dictionary['words']}
    imported = {r['externalKey']: r for r in plan['links']}
    aa = {a['id']: a for rows in primary.values() for a in rows}
    ww = {w['id']: w for rows in witnesses.values() for w in rows}
    original_mapping = defaultdict(set)
    for wid, lid, *_ in baseline_mapping:
        original_mapping[wid].add(lid)
    seen = set()
    result = []
    for link in review['links']:
        lid, fid, aid, wid = (link[k] for k in ('researchId', 'formId', 'analysisId', 'dictionaryId'))
        assert (fid, wid) not in seen, 'Duplicate reviewed form address'
        assert not any(fid == old_fid for old_fid, _ in seen), 'Form assigned to multiple dictionary IDs'
        seen.add((fid, wid))
        assert link['kind'] in {'direct', 'variant', 'participle', 'homonyms'}
        assert forms[fid]['lexeme_id'] == lid and aa[aid]['form_id'] == fid
        witness = ww[link['witnessId']]
        assert witness['form_id'] == fid and witness['entry_id'] == link['entryId']
        assert witness['body_sha256'] == link['bodySha256']
        row = rawdb.execute('SELECT body,headers FROM entries WHERE id=?', (link['entryId'],)).fetchone()
        assert row and hashlib.sha256(row[0].encode()).hexdigest() == link['bodySha256']
        assert witness['header'] in json.loads(row[1])
        assert rawdb.execute('SELECT 1 FROM grammar WHERE sourceEntryId=? AND target=? AND properties=? AND analysis=?',
                            (link['entryId'], link['target'], link['properties'], link['sourceAnalysis'])).fetchone()
        exact = imported[link['target']]
        assert exact['method'] == 'exact' and exact['candidateIds'] == [wid]
        article = context['articles'][wid]
        assert article['originalName'] == link['dictionaryName'] == words[wid]['originalName']
        assert article['pos'] == words[wid]['pos']
        assert set(article['properties']) == set(link['properties'].split(','))
        assert original_mapping[wid] == set(link['existingResearchIds'])
        if link['kind'] == 'participle':
            assert article['pos'] == 'verb' and 'partcp' in link['sourceAnalysis'].split(',')
        if link['kind'] in {'variant', 'participle'}:
            assert original_mapping[wid], 'Must extend an existing card'
        else:
            assert not original_mapping[wid], 'Must not overwrite an existing card'
        # Homonym glosses are taken only from the exact witnessed source of this
        # dictionary ID, never from the research entry's combined homonym gloss.
        previews = [s['preview'].strip() for s in article['sources']
                    if s['mappingStatus'] == 'verified' and
                    context['sources'][s['id']]['entryId'] == link['entryId']]
        gloss = previews[0] if previews else ''
        if link['kind'] == 'homonyms':
            assert gloss, 'Homonym requires its own sense evidence'
        result.append((link, aa[aid], gloss))
    assert len({r[0]['researchId'] for r in result}) == review['safeResearchLexemes']
    assert len(result) == review['safeFormLinks']
    return result


def build(research_path, projection_path, source_path, out, review_path=None, plan_path=None, context_path=None):
    assert not out.exists(), 'Output already exists; use a new immutable filename'
    research = json.loads(research_path.read_text())
    dictionary = json.loads(projection_path.read_text())
    morphemes = {m['id']: m for m in research['morphemes']}
    allomorphs = {a['id']: a for a in research['allomorphs']}
    forms = {f['id']: f for f in research['forms']}
    lexemes = {l['id']: l for l in research['lexemes']}
    sources = {s['id']: s for s in research['sources']}
    etys = defaultdict(list)
    for e in research['morpheme_etymologies']:
        etys[e['allomorph_id']].append(e)
    primary = defaultdict(list)
    for a in research['analyses']:
        if a['is_primary'] and a['status'] != 'rejected':
            primary[forms[a['form_id']]['lexeme_id']].append(a)
    by_entry = defaultdict(list)
    for w in dictionary['words']:
        for eid in w['entryIds']:
            by_entry[eid].append(w)
    rawdb = sqlite3.connect(source_path.resolve().as_uri() + '?mode=ro', uri=True)
    witnesses = defaultdict(list)
    for w in research['witnesses']:
        witnesses[forms[w['form_id']]['lexeme_id']].append(w)
    pos = {'NOUN': 'noun', 'ADJ': 'adjective', 'VERB': 'verb', 'ADV': 'adverb',
           'PRON': 'pronoun', 'NUM': 'numeral', 'PART': 'particle'}
    linked, unresolved = {}, []
    mapping = []
    # Exact source ownership AND exact orthographic key AND POS, never fuzzy search.
    for lid, lexeme in lexemes.items():
        candidates = {}
        valid = []
        for witness in witnesses[lid]:
            row = rawdb.execute('SELECT body,headers FROM entries WHERE id=?', (witness['entry_id'],)).fetchone()
            assert row and hashlib.sha256(row[0].encode()).hexdigest() == witness['body_sha256'], witness['id']
            assert witness['header'] in json.loads(row[1]), witness['id']
            valid.append(witness)
            for word in by_entry[witness['entry_id']]:
                if word['pos'] != pos.get(lexeme['pos']):
                    continue
                if key(word['originalName']) not in {key(lexeme['lemma']), key(witness['header'])}:
                    continue
                candidates[word['id']] = word
        if len(candidates) != 1:
            unresolved.append({'researchId': lid, 'lemma': lexeme['lemma'], 'reason': 'ambiguous' if candidates else 'no_exact_verified_owner', 'candidates': sorted(candidates)})
            continue
        word = next(iter(candidates.values()))
        if word['id'] in linked:
            # Different research senses must not silently collapse to one public ID.
            unresolved.append({'researchId': lid, 'lemma': lexeme['lemma'], 'reason': 'multiple_research_senses', 'candidates': [word['id']]})
            linked[word['id']] = None
            continue
        linked[word['id']] = lid
        for w in valid:
            if w['entry_id'] in word['entryIds']:
                mapping.append((word['id'], lid, w['id'], 'verified', 'exact_source_owner+orthographic_key+pos'))
    linked = {wid: lid for wid, lid in linked.items() if lid is not None}
    mapping = [m for m in mapping if linked.get(m[0]) == m[1]]
    associations = defaultdict(list)
    for wid, lid in linked.items():
        for analysis in primary.get(lid, []):
            associations[wid].append((lid, analysis, None, None))
    reviewed = []
    if review_path:
        reviewed = reviewed_forms(review_path, plan_path, context_path, research_path,
                                  dictionary, forms, primary, witnesses, rawdb, mapping)
        old_unlinked = {r['researchId'] for r in unresolved}
        resolved = {link['researchId'] for link, _, _ in reviewed}
        assert resolved <= old_unlinked, 'Review must only extend the original unlinked queue'
        for link, analysis, gloss in reviewed:
            wid, lid = link['dictionaryId'], link['researchId']
            associations[wid].append((lid, analysis, link, gloss))
            mapping.append((wid, lid, link['witnessId'], 'verified', link['basis']))
        unresolved = [r for r in unresolved if r['researchId'] not in resolved]
    rawdb.close()
    analyses_by_word = {}
    form_mapping = []
    memberships = defaultdict(dict)
    used_forms = defaultdict(set)
    for word in dictionary['words']:
        analyses = []
        seen = set()
        # Keep the original sequence, then append explicit variants/participles.
        original = [x for x in associations[word['id']] if x[2] is None]
        original.sort(key=lambda x: (key(forms[x[1]['form_id']]['normalized']) != key(lexemes[x[0]]['lemma']), x[1]['form_id']))
        added = sorted((x for x in associations[word['id']] if x[2] is not None), key=lambda x: x[1]['form_id'])
        for lid, a, link, gloss in original + added:
            assert a['id'] not in seen, 'Duplicate analysis on a word card'
            seen.add(a['id'])
            f = forms[a['form_id']]
            projected = project(a, f, allomorphs, morphemes, etys)
            if link:
                projected.update(formId=f['id'], linkKind=link['kind'], sourceGrammar=link['sourceAnalysis'])
                if link['kind'] == 'participle':
                    projected['note'] = f"Причастная форма глагола «{word['originalName']}». " + projected['note']
                elif link['kind'] == 'variant':
                    projected['note'] = f"Вариант написания слова «{word['originalName']}». " + projected['note']
            analyses.append(projected)
            form_mapping.append((word['id'], lid, f['id'], a['id'], link['witnessId'] if link else None,
                                 link['kind'] if link else 'original'))
            for mid in {p['morphemeId'] for p in projected['parts']} - {None}:
                # Preserve the existing card's gloss when extending it with forms.
                memberships[mid].setdefault(word['id'], {'id': word['id'], 'name': word['name'],
                    'gloss': clean(gloss if link and link['kind'] == 'homonyms' else lexemes[lid]['sense'])})
                used_forms[mid].add(f['id'])
        analyses_by_word[word['id']] = analyses
    # Bind every explicit review input to this immutable publication version.
    review_bytes = b'' if not review_path else review_path.read_bytes() + plan_path.read_bytes() + context_path.read_bytes()
    version = hashlib.sha256(b'cs-morphemes-v1\0' + research_path.read_bytes() + projection_path.read_bytes() + Path(__file__).read_bytes() + (ROOT / 'tool/morpheme_schema2/canonical.py').read_bytes() + (ROOT / 'tool/morpheme_schema2/orthography.py').read_bytes() + review_bytes).hexdigest()
    cards = {}
    for mid, m in morphemes.items():
        variants = [v for v in research['allomorphs'] if v['morpheme_id'] == mid]
        structure, history = [], []
        for e in research['morpheme_etymologies']:
            if e['morpheme_id'] != mid:
                continue
            src = sources[e['source_id']]
            h = {'title': 'Слияние исторических элементов' if e['mapping_mode'] == 'fusion' else 'Происхождение морфемы',
                 'reconstruction': clean(e['reconstruction']), 'note': clean(e['note']), 'status': e['status'],
                 'sources': [{'title': clean(src['title']), 'locator': clean(e['locator'])}]}
            if e.get('related_morpheme_id'):
                h['morphemeId'] = e['related_morpheme_id']
            history.append(h)
            if e['mapping_mode'] == 'concatenative' and len(e['components']) > 1:
                for c in e['components']:
                    part = {'title': c.get('surface', '') + ' · ' + c.get('historical_element', ''),
                            'note': clean(c.get('origin_hypothesis', e['note'])), 'status': e['status']}
                    if c.get('morpheme_id') in morphemes and c['morpheme_id'] != mid:
                        part['morphemeId'] = c['morpheme_id']
                    structure.append(part)
        for r in research['allomorph_relations']:
            if r['morpheme_id'] == mid:
                history.append({'title': 'Чередование вариантов', 'reconstruction': allomorphs[r['left_id']]['surface'] + ' / ' + allomorphs[r['right_id']]['surface'],
                                'note': clean(r['note']), 'status': r['status'],
                                'sources': [{'title': clean(sources[r['source_id']]['title']), 'locator': clean(r['locator'])}]})
        cards[mid] = {'id': mid, 'version': version, 'title': ' / '.join(v['surface'] or '∅' for v in variants),
                      'kind': role(m), 'status': m['status'], 'gloss': clean(m['gloss']),
                      'statistics': {'lexemes': len(memberships[mid]), 'forms': len(used_forms[mid])},
                      'allomorphs': [{'id': v['id'], 'surface': v['surface'], 'note': clean(v['condition_note']), 'status': v['status']} for v in variants],
                      'structure': structure, 'history': history}
        cards[mid] = canonical_card(cards[mid], research)
    db = sqlite3.connect(out)
    db.executescript('''CREATE TABLE metadata(key TEXT PRIMARY KEY,value TEXT NOT NULL);
      CREATE TABLE words(id TEXT PRIMARY KEY,payload TEXT NOT NULL);
      CREATE TABLE morphemes(id TEXT PRIMARY KEY,payload TEXT NOT NULL);
      CREATE TABLE morpheme_words(morpheme_id TEXT NOT NULL,sort_key TEXT NOT NULL,lexeme_id TEXT NOT NULL,payload TEXT NOT NULL,
        PRIMARY KEY(morpheme_id,sort_key,lexeme_id),UNIQUE(morpheme_id,lexeme_id));
      CREATE TABLE dictionary_morpheme_lexeme(dictionary_id TEXT,research_lexeme_id TEXT,witness_id TEXT,status TEXT,basis TEXT,
        PRIMARY KEY(dictionary_id,research_lexeme_id,witness_id));
      CREATE INDEX mapping_dictionary ON dictionary_morpheme_lexeme(dictionary_id);
      CREATE TABLE dictionary_morpheme_form(dictionary_id TEXT NOT NULL,research_lexeme_id TEXT NOT NULL,
        form_id TEXT NOT NULL,analysis_id TEXT NOT NULL,witness_id TEXT,link_kind TEXT NOT NULL,
        PRIMARY KEY(dictionary_id,analysis_id),UNIQUE(form_id));
      CREATE INDEX form_dictionary ON dictionary_morpheme_form(dictionary_id);''')
    db.executemany('INSERT INTO words VALUES (?,?)', ((wid, compact({'version': version, 'lexemeId': wid, 'analyses': aa})) for wid, aa in analyses_by_word.items()))
    db.executemany('INSERT INTO morphemes VALUES (?,?)', ((mid, compact(c)) for mid, c in cards.items()))
    for mid, words in memberships.items():
        db.executemany('INSERT INTO morpheme_words VALUES (?,?,?,?)', ((mid, unicodedata.normalize('NFC', key(w['name']) or w['name']), wid, compact(w)) for wid, w in words.items()))
    db.executemany('INSERT INTO dictionary_morpheme_lexeme VALUES (?,?,?,?,?)', mapping)
    db.executemany('INSERT INTO dictionary_morpheme_form VALUES (?,?,?,?,?,?)', form_mapping)
    meta = {'format': 'cs-morphemes-v1', 'state': 'complete', 'version': version,
            'dictionaryVersion': dictionary['dictionaryVersion'], 'researchVersion': research['version'], 'cardSchemaVersion': '2'}
    if review_path:
        meta['reviewSha256'] = hashlib.sha256(review_path.read_bytes()).hexdigest()
    db.executemany('INSERT INTO metadata VALUES (?,?)', meta.items())
    db.commit()
    assert db.execute('PRAGMA quick_check').fetchone()[0] == 'ok'
    db.close()
    out.chmod(0o444)
    report = {'version': version, 'dictionaryVersion': dictionary['dictionaryVersion'], 'researchVersion': research['version'],
              'wordsWithAnalysis': sum(bool(a) for a in analyses_by_word.values()), 'analyses': sum(map(len, analyses_by_word.values())),
              'morphemes': len(cards), 'mappingRows': len(mapping), 'formMappingRows':len(form_mapping),
              'reviewedResearchLexemes':len({l['researchId'] for l, _, _ in reviewed}),
              'reviewedFormLinks':len(reviewed), 'unlinked': unresolved,
              'sha256': hashlib.sha256(out.read_bytes()).hexdigest(), 'quickCheck': 'ok'}
    out.with_suffix('.report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    return report

if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('--research', type=Path, default=ROOT / 'data/morphemes/reviewed-pilot.json')
    p.add_argument('--projection', type=Path, required=True)
    p.add_argument('--source', type=Path, default=ROOT / 'import/chu-rus.sqlite')
    p.add_argument('--out', type=Path, required=True)
    p.add_argument('--review', type=Path)
    p.add_argument('--plan', type=Path)
    p.add_argument('--context', type=Path)
    a = p.parse_args()
    r = build(a.research, a.projection, a.source, a.out, a.review, a.plan, a.context)
    print(compact({k: v for k, v in r.items() if k != 'unlinked'} | {'unlinked': len(r['unlinked'])}))
