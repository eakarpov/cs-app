import 'package:cs/features/dictionary/domain/models.dart';
import 'package:cs/features/dictionary/domain/form_presentation.dart';
import 'package:cs/features/dictionary/presentation/forms_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> form(String value) => {'value': value, 'origin': 'stored'};
Map<String, dynamic> slot(String id, List<String> values) => {
  'id': id,
  'label': id,
  'forms': values.map(form).toList(),
};
WordArticle article() => WordArticle({
  'id': 'god',
  'name': 'бо́гъ',
  'pos': 'noun',
  'properties': ['S', 'm', 'S', 'sg', 'plen', 'm'],
  'paradigms': [
    {
      'kind': 'noun',
      'title': 'Склонение',
      'slots': [
        slot('sgNom', ['бг҃ъ', 'бо́гъ', 'бо́гъ', 'боⷢъ', 'бо́г']),
        slot('sgGen', ['бг҃а', 'бо́га']),
        slot('duNomAcc', ['бо́га']),
      ],
    },
  ],
});

void main() {
  test('header uses inherent properties once and only lemma titlo forms', () {
    final a = article();
    expect(conciseProperties(a), 'существительное · мужской род');
    expect(WordHeading(a).name, 'бо́гъ');
    expect(WordHeading(a).titloVariants, ['бг҃ъ']);
    expect(
      conciseGrammar(
        'полная форма · полная форма · единственное число / полная форма · единственное число',
      ),
      'полная форма · единственное число',
    );
  });
  test('titled headword expands only from an explicit initial slot', () {
    final a = WordArticle({
      'name': 'бг҃ъ',
      'paradigms': [
        {
          'slots': [
            slot('sgNom', ['бг҃ъ', 'бо́гъ']),
            slot('sgGen', ['бо́га']),
          ],
        },
      ],
    });
    expect(WordHeading(a).name, 'бо́гъ');
    expect(WordHeading(a).titloVariants, ['бг҃ъ']);
    expect(WordHeading(WordArticle({'name': 'бг҃ъ'})).name, 'бг҃ъ');
  });
  test(
    'titlo and raised letters are not base cell values; exact duplicates vanish',
    () {
      final forms = article().paradigms.single.slots.first.forms;
      expect(primaryForm(forms)?.value, 'бо́гъ');
      expect(readableForms(forms).map((f) => f.value), [
        'бо́гъ',
        'боⷢъ',
        'бо́г',
      ]);
      expect(
        primaryForm([WordForm(form('бг҃ъ')), WordForm(form('боⷢъ'))]),
        isNull,
      );
    },
  );
  test(
    'noun syncretism populates both cases without inventing other cells',
    () {
      final grid = formGrids(article().paradigms.single).single;
      expect(grid.forms(0, 2).single.value, 'бо́га');
      expect(grid.forms(3, 2).single.value, 'бо́га');
      expect(grid.forms(1, 2), isEmpty);
    },
  );
  test(
    'dedicated adjective slots override general slots and preserve the mixed plural slot',
    () {
      final grids = formGrids(
        Paradigm({
          'title': 'Полные формы',
          'slots': [
            slot('sgMNomAcc', ['до́брый']),
            slot('sgMAcc', ['до́браго']),
            slot('plMAccFNomAcc', ['до́брыя']),
          ],
        }),
      );
      expect(grids.first.forms(0, 0).single.value, 'до́брый');
      expect(grids.first.forms(3, 0).single.value, 'до́браго');
      expect(grids[1].forms(0, 1).single.value, 'до́брыя');
      expect(grids[1].forms(3, 1).single.value, 'до́брыя');
    },
  );
  test('verbs split by tense and combined persons map to separate cells', () {
    final grids = formGrids(
      Paradigm({
        'slots': [
          slot('presSg1', ['несꙋ̀']),
          slot('aorSg23', ['несѐ']),
        ],
      }),
    );
    expect(grids.map((g) => g.title), ['Настоящее время', 'Аорист']);
    expect(grids.last.forms(1, 0).single.value, 'несѐ');
    expect(grids.last.forms(2, 0).single.value, 'несѐ');
    expect(grids.last.forms(0, 0), isEmpty);
  });
  testWidgets(
    'default is a table; other spellings are opt-in and titlo never enters declension',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: WordFormsView(
                article: article(),
                formBuilder: (f) => Text(f.value),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DataTable), findsOneWidget);
      expect(find.text('бо́гъ'), findsOneWidget);
      expect(find.text('бг҃ъ'), findsNothing);
      expect(find.text('боⷢъ'), findsNothing);
      await tester.tap(find.text('Иные написания (2)'));
      await tester.pumpAndSettle();
      expect(find.text('боⷢъ'), findsOneWidget);
      expect(find.text('бо́г'), findsOneWidget);
      expect(find.text('бг҃ъ'), findsNothing);
      await tester.tap(find.text('Закрыть'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Подробно'));
      await tester.pumpAndSettle();
      expect(find.byType(DataTable), findsNothing);
      await tester.tap(find.text('Склонение'));
      await tester.pumpAndSettle();
      expect(find.text('sgNom'), findsOneWidget);
      expect(find.text('бг҃ъ'), findsNothing);
      expect(find.text('бг҃а'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
