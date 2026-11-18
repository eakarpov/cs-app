import 'package:cs/features/dictionary/domain/morphemes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('automatic provenance does not imply dictionary verification', () {
    final a = MorphemeAnalysis({
      'status': 'proposed',
      'generationOrigin': 'automatic',
      'reviewStatus': 'unreviewed',
      'completeness': 'partial',
    });
    expect(a.reviewLabel, 'Автоматический кандидат · Не проверен');
    expect(a.completeness, 'partial');
  });
  test(
    'dictionary check is independent from automatic generation and hypothesis',
    () {
      final a = MorphemeAnalysis({
        'status': 'proposed',
        'generationOrigin': 'automatic',
        'reviewStatus': 'dictionary_checked',
      });
      expect(a.reviewLabel, 'Проверено по словарям');
      expect(analysisStatus(a.status), 'Рабочая гипотеза');
    },
  );
  test('old publications without provenance remain readable', () {
    final a = MorphemeAnalysis({'status': 'proposed'});
    expect(a.reviewLabel, isEmpty);
    expect(a.parts, isEmpty);
  });
}
