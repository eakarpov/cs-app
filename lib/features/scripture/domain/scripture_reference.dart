import 'books.dart';

String _key(String text) => text
    .toLowerCase()
    .replaceAll(RegExp(r'[.\s\u00a0\u2009]'), '')
    .replaceAll('ѳ', 'ф')
    .replaceAll('і', 'и')
    .replaceAll('ѣ', 'е')
    .replaceAll('ё', 'е');

final _aliases = <String, String>{
  for (final entry in scriptureBooks.entries)
    for (final name in entry.value.names) _key(name): entry.key,
  'матф': 'matfeya',
  'матфей': 'matfeya',
  'мт': 'matfeya',
  'марк': 'marka',
  'мар': 'marka',
  'лук': 'luki',
  'иоан': 'ioanna',
  'иоанн': 'ioanna',
  'иоанна': 'ioanna',
  'псал': 'psaltir',
  'псалом': 'psaltir',
  'притч': 'pritchi',
  'екклесиаст': 'ekklesiast',
  'эккл': 'ekklesiast',
  'исаи': 'isaii',
  'исайя': 'isaii',
  'иезек': 'iezekiilya',
  'сир': 'sirakha',
  'сирах': 'sirakha',
  'софон': 'sofonii',
  'апок': 'otkrovenie',
  'откр': 'otkrovenie',
  for (final n in [1, 2, 3, 4]) '$nцарств': '$n-tsarstv',
  for (final n in [1, 2]) ...{
    '$nфесс': '$n-fessaloniyitsam',
    '$nсол': '$n-fessaloniyitsam',
    '$nпетр': '$n-petra',
    '$nиоан': '$n-ioanna-posl',
    '$nиоанн': '$n-ioanna-posl',
    '$nпарал': '$n-paralipomenon',
  },
  '3иоан': '3-ioanna-posl',
  '3иоанн': '3-ioanna-posl',
};

int? _number(String value) {
  final numeric = int.tryParse(value);
  if (numeric != null) return numeric;
  final roman = value.toUpperCase();
  if (!RegExp(
    r'^(?=[MDCLXVI]+$)M{0,3}(CM|CD|D?C{0,3})(XC|XL|L?X{0,3})(IX|IV|V?I{0,3})$',
  ).hasMatch(roman)) {
    return null;
  }
  const numbers = {
    'I': 1,
    'V': 5,
    'X': 10,
    'L': 50,
    'C': 100,
    'D': 500,
    'M': 1000,
  };
  var result = 0, previous = 0;
  for (final c in roman.split('').reversed) {
    final n = numbers[c]!;
    result += n < previous ? -n : n;
    previous = n;
  }
  return result;
}

class ScriptureReference {
  const ScriptureReference(
    this.start,
    this.end,
    this.label,
    this.book,
    this.chapter,
    this.first,
    this.last,
  );
  final int start, end, chapter, first, last;
  final String label, book;
  Uri get uri => Uri.https('www.typikon.info', '/bible/$book/$chapter', {
    'highlight': first == last ? '$first' : '$first-$last',
  }).replace(fragment: 'v$first');
}

final _pattern = RegExp(
  r'(^|[^\p{L}\p{M}\d])((?:[1-4]\s*)?[\p{L}]+\.?)\s*:?\s*(\d{1,3}|[IVXLCDM]+)\s*[:,.]\s*(\d+)(?:\s*[-–—]\s*(\d+))?(?![\d:]|\s*[-–—]\s*\d)',
  caseSensitive: false,
  unicode: true,
);

List<ScriptureReference> scriptureReferences(String text) {
  final result = <ScriptureReference>[];
  for (final m in _pattern.allMatches(text)) {
    final book = _aliases[_key(m[2]!)];
    final chapter = _number(m[3]!);
    if (book == null || chapter == null || chapter < 1) continue;
    final first = int.tryParse(m[4]!), last = int.tryParse(m[5] ?? m[4]!);
    if (first == null || last == null) continue;
    final bounds = scriptureBooks[book]!.verses;
    if (chapter > bounds.length ||
        first < 1 ||
        last < first ||
        last > bounds[chapter - 1]) {
      continue;
    }
    final start = m.start + m[1]!.length;
    result.add(
      ScriptureReference(
        start,
        m.end,
        text.substring(start, m.end),
        book,
        chapter,
        first,
        last,
      ),
    );
  }
  return result;
}
