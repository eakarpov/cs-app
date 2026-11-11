import 'dart:convert';
import 'dart:io';
import 'package:cs/features/dictionary/data/dictionary_repository.dart';
import 'package:http/http.dart' as http;

Future<void> main(List<String> args) async {
  final base = Uri.parse(
    args.isEmpty ? 'https://www.typikon.info/api/v2/cs/' : args.first,
  );
  final repository = DictionaryRepository(base: base);
  var passed = 0;
  void check(bool value, String label) {
    if (!value) throw StateError(label);
    passed++;
  }

  try {
    final god = await repository.wordMorphemes('68399a217310e32be5d76a6c');
    check(god.analyses.isNotEmpty, 'Assigned богъ analysis');
    check(
      god.analyses.first.letters.map((l) => l.text).join() ==
          god.analyses.first.form,
      'Exact grapheme reconstruction',
    );
    final help = await repository.wordMorphemes('68399a217310e32be5d7b2ec');
    check(help.version == god.version, 'Same publication');
    check(
      help.analyses.first.letters.any(
        (l) =>
            l.text == 'щ' &&
            l.colorKinds.toSet().containsAll(['root', 'derivational_suffix']),
      ),
      'Fusion щ',
    );
    final repent = await repository.wordMorphemes('68399a217310e32be5d78d3a');
    check(
      repent.analyses.first.letters.any(
        (l) => l.colorKinds.toSet().containsAll(['root', 'thematic_vowel']),
      ),
      'Shared root and thematic vowel',
    );
    final good = await repository.wordMorphemes('68399a217310e32be5d77b6f');
    check(good.analyses.isNotEmpty, 'Assigned добрый analysis');
    final root = god.analyses.first.parts.firstWhere((p) => p.kind == 'root');
    final card = await repository.morpheme(
      root.morphemeId!,
      version: god.version,
    );
    check(
      card.wordCount > 0 && card.variants.isNotEmpty,
      'Card and statistics',
    );
    final ids = <String>{};
    String? cursor;
    var pages = 0;
    do {
      final page = await repository.morphemeWords(
        card.id,
        version: god.version,
        cursor: cursor,
      );
      check(
        page.total == card.wordCount && page.version == card.version,
        'List statistics and version',
      );
      for (final word in page.items) {
        check(ids.add(word['id'] as String), 'No duplicate words');
      }
      cursor = page.nextCursor;
      pages++;
      check(pages < 100, 'Finite cursor sequence');
    } while (cursor != null);
    check(ids.length == card.wordCount, 'All linked words returned');
    check(
      ids.contains('68399a217310e32be5d76a6c'),
      'Dictionary ID survives round trip',
    );
    // At least one known dictionary entry absent from this curated research
    // publication must return an explicit empty analysis, never a guessed one.
    final unknown = await repository.wordMorphemes('03ee6a4e9f26a3208ca52399');
    check(unknown.analyses.isEmpty, 'Unassigned word stays empty');
    final url = base
        .resolve('morphemes/${Uri.encodeComponent(card.id)}')
        .replace(queryParameters: {'version': god.version});
    final response = await http.get(url);
    check(
      response.statusCode == 200 &&
          response.headers['access-control-allow-origin'] == '*',
      'Public CORS',
    );
    final conditional = await http.get(
      url,
      headers: {'If-None-Match': response.headers['etag']!},
    );
    check(conditional.statusCode == 304, 'ETag conditional request');
    final stale = await http.get(
      url.replace(queryParameters: {'version': '0' * 64}),
    );
    check(stale.statusCode == 409, 'Expired version');
    final badLimit = await http.get(
      base
          .resolve('morphemes/${Uri.encodeComponent(card.id)}/words')
          .replace(queryParameters: {'version': god.version, 'limit': '101'}),
    );
    check(badLimit.statusCode == 400, 'Invalid limit');
    final missing = await http.get(
      base.resolve('lexemes/${'0' * 24}/morphemes'),
    );
    check(missing.statusCode == 404, 'Unknown ID');
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        'api': base.toString(),
        'version': god.version,
        'passed': passed,
        'rootWords': ids.length,
        'pages': pages,
        'unassignedProbe': unknown.analyses.length,
        'checkedAt': DateTime.now().toUtc().toIso8601String(),
      }),
    );
  } finally {
    repository.close();
  }
}
