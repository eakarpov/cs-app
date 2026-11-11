"""Written-form normalization used by the publication exporter, preserving alignment."""
import unicodedata as ud

def normalize(raw):
    groups = []
    for i, ch in enumerate(raw):
        if ud.category(ch).startswith('M') and groups:
            groups[-1][1] += ch
            groups[-1][3] = i + 1
        else:
            groups.append([ch, '', i, i + 1])
    result, alignment = '', []
    mapping = {'ꙋ': 'у', 'ѹ': 'у', 'ѧ': 'я', 'ꙗ': 'я', 'ѡ': 'о', 'ѻ': 'о', 'ї': 'і'}
    for base, marks, start, end in groups:
        if '\u0483' in marks or any('\u2de0' <= c <= '\u2dff' for c in marks):
            raise ValueError('Abbreviations need an editorial expansion')
        base = base.lower()
        # Preserve й, including its decomposed encoding и + breve.
        if base == 'й' or (base == 'и' and '\u0306' in marks):
            base = 'й'
        else:
            base = mapping.get(base, base)
            base = ''.join(c for c in ud.normalize('NFD', base) if not ud.combining(c))
        result += base
        alignment.extend([[start, end]] * len(base))
    return result, alignment
