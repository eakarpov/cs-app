// Read-only acceptance using the same repository and default API as the app.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'package:cs/features/dictionary/data/dictionary_repository.dart';
import 'package:cs/features/dictionary/domain/models.dart';

Future<void> main() async {
  final repo = DictionaryRepository();
  var checks = 0;
  void check(bool value, String label) {
    if (!value) throw StateError(label);
    checks++;
  }

  try {
    final word = await repo.wordMorphemes('68399a217310e32be5d76a6c');
    final card = await repo.morpheme(
      'formative_suffix:INF',
      version: word.version,
    );
    check(card.version == word.version, 'same version');
    check(card.meaning == 'Показатель инфинитива', 'meaning label');
    check(
      card.composition.models.any(
        (m) =>
            array(
              m['parts'],
            ).map(object).map((p) => string(p['surface'])).join() ==
            'ти',
      ),
      'explicit ti model',
    );
    check(card.etymology.notes.isNotEmpty, 'historical description retained');
    check(card.sources.isNotEmpty, 'sources retained');
    final other = await repo.morpheme(
      'derivational_suffix:ост',
      version: word.version,
    );
    for (final model in other.composition.models) {
      check(array(model['allomorphIds']).isNotEmpty, 'explicit variant scope');
      check(
        array(
          model['allomorphIds'],
        ).every((id) => other.variants.any((v) => v['id'] == id)),
        'known variants',
      );
    }
    final page = await repo.morphemeWords(card.id, version: word.version);
    check(page.total == card.wordCount, 'statistics match words');
    check(page.items.isNotEmpty, 'word list available');
    print(
      const JsonEncoder.withIndent('  ').convert({
        'api': repo.base.toString(),
        'version': word.version,
        'checks': checks,
        'status': 'passed',
        'checkedAt': DateTime.now().toUtc().toIso8601String(),
      }),
    );
  } finally {
    repo.close();
  }
}
