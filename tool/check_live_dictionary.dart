// Read-only smoke test of the same repository and default URLs used by the APK.
import 'dart:convert';
import 'dart:io';
import 'package:cs/features/dictionary/data/dictionary_repository.dart';
import 'package:cs/features/dictionary/domain/models.dart';

Future<void> main() async {
  final repository = DictionaryRepository();
  final checks = <String>[];
  void check(String name, bool value) {
    if (!value) throw StateError(name);
    checks.add(name);
  }

  try {
    final forms = await repository.search('земли', 'cu-ru');
    check(
      'attested form search',
      forms.items.any((h) => h.match == 'stored-form'),
    );
    final article = await repository.article(forms.items.first.id);
    check('real paradigms', article.paradigms.isNotEmpty);
    check('source-backed examples', article.examples.isNotEmpty);
    final example = article.examples.first;
    check(
      'example belongs to article source',
      article.sources.any((s) => s.id == example.sourceId),
    );
    final exampleSource = await repository.source(example.sourceId);
    check(
      'example source identity',
      array(exampleSource['examples'])
          .map(object)
          .any((e) => e['id'] == example.id && e['quote'] == example.quote),
    );
    check('example has citation', example.citation.isNotEmpty);

    check('versioned data', forms.version.isNotEmpty);
    for (final p in article.paradigms) {
      for (final slot in p.slots) {
        for (final form in slot.forms) {
          if (form.segments != null) {
            check(
              'segments reconstruct ${form.value}',
              form.segments!.map((s) => string(s['text'])).join() == form.value,
            );
          }
        }
      }
    }
    final source = await repository.source(article.sources.first.id);
    check('source content', array(source['paragraphs']).isNotEmpty);
    check(
      'short words',
      (await repository.search('а', 'cu-ru')).items.isNotEmpty,
    );
    check('titlo', (await repository.search('бг҃ъ', 'cu-ru')).items.isNotEmpty);
    final reverse = await repository.search('отец', 'ru-cu');
    check(
      'explicit reverse equivalents',
      reverse.items.any((h) => h.match == 'translation'),
    );
    final compound = await repository.search('явитимися', 'cu-ru');
    check('compound found', compound.items.isNotEmpty);
    final composed = await repository.article(compound.items.first.id);
    check(
      'enclitic kept separate',
      composed.composition.any((c) => c['role'] == 'enclitic'),
    );
    for (final c in composed.composition) {
      if (c['lexemeId'] is String) {
        await repository.article(string(c['lexemeId']));
      }
    }
    final linked = await repository.article('68399a217310e32be5d79326');
    final relation = linked.relations.firstWhere(
      (r) => r['status'] == 'verified',
    );
    await repository.article(string(relation['targetId']));
    await repository.source(string(relation['sourceId']));
    check('verified semantic link and source', true);
    final etymologyOwner = await repository.article('68399a217310e32be5d7e170');
    final etymology = etymologyOwner.etymologies.firstWhere(
      (e) => e['articleId'] == 20,
    );
    final proto = await repository.etymology(20);
    check(
      'public interlex and reviewed revision',
      string(proto['body']).isNotEmpty &&
          proto['bodySha256'] == etymology['bodySha256'],
    );
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        'api': repository.base.toString(),
        'interlex': repository.interlexBase.toString(),
        'version': forms.version,
        'passed': checks.length,
        'checks': checks,
      }),
    );
  } finally {
    repository.close();
  }
}
