// Read-only acceptance check using the application's repository and API URL.
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

  List<String> endings(WordArticle a, String kind, String slot) => [
    for (final p in a.paradigms)
      if (p.kind == kind)
        for (final s in p.slots)
          if (s.id == slot)
            for (final f in s.forms)
              for (final segment in f.segments ?? <Json>[])
                if (segment['kind'] == 'ending') string(segment['text']),
  ];
  try {
    final first = await repo.article('68399a217310e32be5d772b6');
    check(endings(first, 'verb', 'presSg2').contains('еши'), 'еши');
    check(
      endings(first, 'participle-brev', 'sgMNDat').contains('ꙋ'),
      'participle ending',
    );
    check(
      endings(first, 'participle-plen', 'sgMNDat').contains('омꙋ'),
      'passive participle ending',
    );
    final second = await repo.article('68399a217310e32be5d76e64');
    check(endings(second, 'verb', 'presSg2').contains('иши'), 'иши');
    final adjective = await repo.article('68399a217310e32be5d7654e');
    check(
      endings(adjective, 'adjective-plen', 'sgMNDat').contains('омꙋ'),
      'adjective ending',
    );
    final unconfirmed = adjective.paradigms
        .where((p) => p.kind == 'adjective-plen')
        .expand((p) => p.slots)
        .where((s) => s.id == 'sgMNomAcc')
        .expand((s) => s.forms)
        .firstWhere((f) => f.value == 'без̑печа́лный');
    check(unconfirmed.segments == null, 'unconfirmed stays null');
    for (final a in [first, second, adjective]) {
      for (final p in a.paradigms) {
        for (final s in p.slots) {
          for (final f in s.forms) {
            if (f.segments != null) {
              check(
                f.segments!.map((x) => string(x['text'])).join() == f.value,
                'exact spelling and accent',
              );
            }
          }
        }
      }
    }
    print(
      const JsonEncoder.withIndent('  ').convert({
        'api': repo.base.toString(),
        'checks': checks,
        'wordCards': 3,
        'status': 'passed',
        'checkedAt': DateTime.now().toUtc().toIso8601String(),
      }),
    );
  } finally {
    repo.close();
  }
}
