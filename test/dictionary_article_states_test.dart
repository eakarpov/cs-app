import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:cs/core/personal_store.dart';
import 'package:cs/features/dictionary/data/dictionary_repository.dart';
import 'package:cs/features/dictionary/domain/models.dart';
import 'package:cs/features/dictionary/domain/form_presentation.dart';
import 'package:cs/features/dictionary/presentation/article_screen.dart';
import 'package:cs/features/dictionary/presentation/resource_screen.dart';
import 'package:cs/features/dictionary/presentation/morphemes_view.dart';
import 'dictionary_test.dart' show MemoryPreferences;
import 'morphemes_test.dart' as fixtures;

Json wire(String key) => object(
  object(
    jsonDecode(File('qa/mobile/m1-04-wire-examples.json').readAsStringSync()),
  )[key],
);
Json form(String value, {String origin = 'dictionary'}) => {
  'value': value,
  'grammar': 'инфинитив',
  'formOrigin': origin,
  'reviewStatus': 'proposed',
  'segments': null,
  'provenance': [
    {
      'sourceId': 'bibliography:only',
      'title': 'Словарь',
      'origin': 'reported-corpus',
      'attribution': 'unknown',
    },
  ],
  'evidence': [
    {
      'kind': 'source-entry',
      'sourceId': wire('source')['id'],
      'sourceVersion': 'source-revision',
      'title': 'Источник формы',
    },
  ],
};
Json article() => {
  ...wire('article'),
  'name': 'каяти',
  'extra': [],
  'paradigms': [
    {
      'kind': 'verb',
      'title': 'Спряжение',
      'slots': [
        {
          'id': 'inf',
          'label': 'Инфинитив',
          'forms': [form('каяти'), form('ка́яти', origin: 'attested')],
        },
      ],
    },
  ],
};
Future<PersonalStore> personal() async {
  final p = PersonalStore(MemoryPreferences());
  await p.initialized;
  return p;
}

Future<void> tab(WidgetTester t, String label) async {
  await t.ensureVisible(find.text(label).first);
  await t.tap(find.text(label).first);
  await t.pumpAndSettle();
}

void main() {
  test(
    'identical writing keeps separate provenance/grammar; true duplicates collapse',
    () {
      final a = WordForm(form('каяти')),
          b = WordForm(form('каяти', origin: 'generated'));
      expect(uniqueForms([a, a, b]).length, 2);
      expect(a.selectionKey, isNot(b.selectionKey));
    },
  );
  test(
    'source revision from card or citation must match the opened source',
    () async {
      final repo = DictionaryRepository(
        client: MockClient((_) async => fixtures.response(wire('source'))),
      );
      addTearDown(repo.close);
      await expectLater(
        repo.source(
          string(wire('source')['id']),
          version: string(wire('source')['dictionaryVersion']),
          sourceVersion: 'changed',
        ),
        throwsA(isA<DictionaryException>()),
      );
    },
  );
  for (final id in [
    '68399a217310e32be5d79676',
    '68399a217310e32be5d79f44',
    '68399a217310e32be5d79c10',
  ]) {
    testWidgets('missing source is a content gap, not a network error: $id', (
      t,
    ) async {
      final repo = DictionaryRepository(
        client: MockClient(
          (_) async => fixtures.response({
            ...wire('article'),
            'id': id,
            'sources': [],
            'izvod': '',
          }),
        ),
      );
      addTearDown(repo.close);
      await t.pumpWidget(
        MaterialApp(
          home: ArticleScreen(
            id: id,
            repository: repo,
            personal: await personal(),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(
        find.text(
          'Для этой статьи пока не подготовлено объяснение из источников.',
        ),
        findsOneWidget,
      );
      expect(find.text('Повторить'), findsNothing);
      expect(find.text('Открыть формы'), findsOneWidget);
      await t.tap(find.byTooltip('Источники и пометы'));
      await t.pumpAndSettle();
      expect(find.text('Извод не указан'), findsOneWidget);
      expect(find.text('Извод: русский синодальный'), findsNothing);
    });
  }
  testWidgets(
    'selected spelling and form/source sheet survive routes and tab changes',
    (t) async {
      t.view.physicalSize = const Size(430, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final calls = <Uri>[];
      final repo = DictionaryRepository(
        client: MockClient((r) async {
          calls.add(r.url);
          return fixtures.response(
            r.url.path.contains('source-entries') ? wire('source') : article(),
          );
        }),
      );
      addTearDown(repo.close);
      await t.pumpWidget(
        MaterialApp(
          home: ArticleScreen(
            id: string(article()['id']),
            repository: repo,
            personal: await personal(),
          ),
        ),
      );
      await t.pumpAndSettle();
      await tab(t, 'Формы');
      await t.tap(find.text('Иные написания (1)'));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Сведения о форме: ка́яти'));
      await t.pumpAndSettle();
      expect(find.text('Засвидетельствовано в тексте'), findsOneWidget);
      expect(find.text('Требует проверки'), findsOneWidget);
      await t.tap(find.text('Источник формы'));
      await t.pumpAndSettle();
      expect(find.text('Источник для: ка́яти'), findsOneWidget);
      expect(
        calls.last.queryParameters['version'],
        wire('article')['dictionaryVersion'],
      );
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.text('Засвидетельствовано в тексте'), findsOneWidget);
      Navigator.of(t.element(find.text('Требует проверки'))).pop();
      await t.pumpAndSettle();
      expect(find.text('Иные написания'), findsOneWidget);
      await t.tap(find.text('Закрыть'));
      await t.pumpAndSettle();
      expect(find.text('Выбрана форма: ка́яти'), findsOneWidget);
      await t.tap(find.text('Подробно'));
      await t.pumpAndSettle();
      await tab(t, 'Толкования');
      await tab(t, 'Примеры');
      await tab(t, 'Формы');
      expect(find.text('Выбрана форма: ка́яти'), findsOneWidget);
      expect(
        t
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Подробно'))
            .selected,
        isTrue,
      );
      expect(calls.where((u) => u.path.contains('/lexemes/')).length, 1);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'analysis ID, selected morpheme and scroll survive tabs and child card',
    (t) async {
      t.view.physicalSize = const Size(430, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final calls = <Uri>[];
      final repo = DictionaryRepository(
        client: MockClient((r) async {
          calls.add(r.url);
          if (r.url.path.endsWith('/morphemes')) {
            return fixtures.response({
              'version': 'M',
              'dictionaryVersion': wire('article')['dictionaryVersion'],
              'analyses': [
                {...fixtures.analysis(), 'id': 'first'},
                {...fixtures.analysis(form: 'ка́яти'), 'id': 'second'},
              ],
            });
          }
          if (r.url.path.endsWith('/words')) {
            return fixtures.response({
              'version': 'M',
              'items': [],
              'nextCursor': null,
            });
          }
          if (r.url.path.contains('/morphemes/')) {
            return fixtures.response({...fixtures.card(), 'version': 'M'});
          }
          return fixtures.response(article());
        }),
      );
      addTearDown(repo.close);
      await t.pumpWidget(
        MaterialApp(
          home: ArticleScreen(
            id: string(article()['id']),
            repository: repo,
            personal: await personal(),
          ),
        ),
      );
      await t.pumpAndSettle();
      await tab(t, 'Морфемы');
      await t.tap(find.byType(DropdownButtonFormField<int>));
      await t.pumpAndSettle();
      await t.tap(find.text('ка́яти · Рабочая гипотеза').last);
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('каj — корень'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView).last,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await t.pumpAndSettle();
      final scroll = t
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(CustomScrollView).last,
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      final offset = scroll.pixels;
      await t.tap(find.text('каj — корень'));
      await t.pumpAndSettle();
      expect(find.byType(MorphemeScreen), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      expect(scroll.pixels, offset);
      expect(
        t
            .widget<ListTile>(
              find.ancestor(
                of: find.text('каj — корень'),
                matching: find.byType(ListTile),
              ),
            )
            .selected,
        isTrue,
      );
      await tab(t, 'Толкования');
      await tab(t, 'Примеры');
      await tab(t, 'Морфемы');
      expect(find.text('ка́яти · Рабочая гипотеза'), findsOneWidget);
      expect(calls.where((u) => u.path.endsWith('/morphemes')).length, 1);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('empty forms/examples and local morpheme failure stay distinct', (
    t,
  ) async {
    final repo = DictionaryRepository(
      client: MockClient(
        (r) async => r.url.path.endsWith('/morphemes')
            ? fixtures.response({
                'error': {'code': 'unavailable'},
              }, 503)
            : fixtures.response({
                ...wire('article'),
                'sources': [],
                'paradigms': [],
                'extra': [],
                'examples': [],
              }),
      ),
    );
    addTearDown(repo.close);
    await t.pumpWidget(
      MaterialApp(
        home: ArticleScreen(
          id: string(wire('article')['id']),
          repository: repo,
          personal: await personal(),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Открыть формы'), findsNothing);
    await tab(t, 'Формы');
    expect(find.text('Формы пока не подготовлены.'), findsOneWidget);
    await tab(t, 'Примеры');
    expect(find.text('Примеры пока не выделены отдельно.'), findsOneWidget);
    await tab(t, 'Морфемы');
    expect(
      find.text('Морфемный разбор этого слова пока не задан.'),
      findsNothing,
    );
    expect(find.text('Повторить'), findsOneWidget);
    await tab(t, 'Толкования');
    expect(
      find.text(
        'Для этой статьи пока не подготовлено объяснение из источников.',
      ),
      findsOneWidget,
    );
  });
  testWidgets(
    'hidden proposed relations and unknown status do not imply no data',
    (t) async {
      final p = await personal();
      await p.settings(proposed: false);
      final repo = DictionaryRepository(
        client: MockClient(
          (_) async => fixtures.response({
            ...wire('article'),
            'relations': [
              {'status': 'proposed'},
              {'status': 'future'},
            ],
          }),
        ),
      );
      addTearDown(repo.close);
      await t.pumpWidget(
        MaterialApp(
          home: ArticleScreen(
            id: string(wire('article')['id']),
            repository: repo,
            personal: p,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(
        find.text('Предположительные связи скрыты настройкой.'),
        findsOneWidget,
      );
      expect(find.text('Смысловые связи пока не подготовлены.'), findsNothing);
    },
  );
  testWidgets(
    'empty source preserves mapping context and offers a source report',
    (t) async {
      final repo = DictionaryRepository(
        client: MockClient(
          (_) async => fixtures.response({
            ...wire('source'),
            'paragraphs': [],
            'text': '',
          }),
        ),
      );
      addTearDown(repo.close);
      await t.pumpWidget(
        MaterialApp(
          home: ResourceScreen(
            repository: repo,
            id: string(wire('source')['id']),
            size: 22,
            wordName: 'каяти',
            mappingLabel: 'Сопоставление требует проверки',
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Источник для: каяти'), findsOneWidget);
      expect(find.text('Сопоставление требует проверки'), findsOneWidget);
      expect(find.text('Текст статьи пока недоступен.'), findsOneWidget);
      await t.tap(find.text('Сообщить об источнике'));
      await t.pumpAndSettle();
      expect(find.text('Ошибка источника'), findsOneWidget);
      await t.tap(find.text('Отмена'));
      await t.pumpAndSettle();
    },
  );
  testWidgets(
    'source retry keeps revisions and reading position survives nested navigation',
    (t) async {
      var fail = true;
      final calls = <Uri>[];
      final source = wire('source');
      final repo = DictionaryRepository(
        client: MockClient((r) async {
          calls.add(r.url);
          if (fail) {
            return fixtures.response({
              'error': {'code': 'not_found'},
            }, 404);
          }
          return fixtures.response({
            ...source,
            'paragraphs': List.generate(
              30,
              (i) => {
                'runs': [
                  {
                    'text': 'Строка $i. Длинный текст источника.',
                    'kind': 'text',
                    if (i == 29) 'target': 'lookup:иная',
                  },
                ],
              },
            ),
          });
        }),
      );
      addTearDown(repo.close);
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ResourceScreen(
              repository: repo,
              id: string(source['id']),
              size: 22,
              dictionaryVersion: string(source['dictionaryVersion']),
              expectedSourceVersion: 'source-revision',
              lookup: (word) => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => Scaffold(appBar: AppBar(title: Text(word))),
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Статья источника недоступна.'), findsOneWidget);
      expect(find.text('Текст статьи пока недоступен.'), findsNothing);
      fail = false;
      await t.tap(find.text('Повторить'));
      await t.pumpAndSettle();
      expect(calls[0], calls[1]);
      for (
        var i = 0;
        i < 30 && find.text('иная').hitTestable().evaluate().isEmpty;
        i++
      ) {
        await t.dragFrom(const Offset(8, 300), const Offset(0, -400));
        await t.pumpAndSettle();
      }
      expect(find.text('иная').hitTestable(), findsOneWidget);
      final position = t
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(ListView),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      final offset = position.pixels;
      expect(offset, greaterThan(0));
      await t.tap(find.text('иная'));
      await t.pumpAndSettle();
      await t.pageBack();
      await t.pumpAndSettle();
      expect(position.pixels, offset);
      expect(calls.length, 2);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('form details fit a narrow dark screen with large text', (
    t,
  ) async {
    t.view.physicalSize = const Size(320, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    t.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    final a = {
      ...article(),
      'paradigms': [],
      'extra': [form('ка́яти')],
    };
    final repo = DictionaryRepository(
      client: MockClient((_) async => fixtures.response(a)),
    );
    addTearDown(repo.close);
    await t.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: ArticleScreen(
          id: string(a['id']),
          repository: repo,
          personal: await personal(),
        ),
      ),
    );
    await t.pumpAndSettle();
    await tab(t, 'Формы');
    final action = find.byTooltip('Сведения о форме: ка́яти');
    for (var i = 0; i < 15 && action.hitTestable().evaluate().isEmpty; i++) {
      await t.drag(find.byType(CustomScrollView).last, const Offset(0, -220));
      await t.pumpAndSettle();
    }
    expect(action.hitTestable(), findsOneWidget);
    await t.tap(action);
    await t.pumpAndSettle();
    expect(find.text('Проверка формы и привязки'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
