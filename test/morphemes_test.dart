import 'dart:convert';
import 'package:cs/features/dictionary/data/dictionary_repository.dart';
import 'package:cs/features/dictionary/domain/morphemes.dart';
import 'package:cs/features/dictionary/presentation/morphemes_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> analysis({String form = 'каяти'}) => {
  'id': 'a',
  'form': form,
  'status': 'proposed',
  'note': '',
  'parts': [
    {
      'id': 'p0',
      'morphemeId': 'root:KAJ',
      'surface': 'каj',
      'kind': 'root',
      'gloss': 'каяться',
    },
    {
      'id': 'p1',
      'morphemeId': 'theme:A',
      'surface': 'я',
      'kind': 'thematic_vowel',
      'gloss': '',
    },
    {
      'id': 'p2',
      'morphemeId': 'suffix:INF',
      'surface': 'ти',
      'kind': 'formative_suffix',
      'gloss': 'инфинитив',
    },
    {
      'id': 'p3',
      'morphemeId': 'ending:ZERO',
      'surface': '',
      'kind': 'inflection',
      'gloss': '',
    },
  ],
  'letters': [
    {
      'text': 'к',
      'partIds': ['p0'],
      'colorKinds': ['root'],
      'note': '',
    },
    {
      'text': 'а',
      'partIds': ['p0'],
      'colorKinds': ['root'],
      'note': '',
    },
    {
      'text': 'я',
      'partIds': ['p0', 'p1'],
      'colorKinds': ['root', 'thematic_vowel'],
      'note': 'Совместное отображение j + а; рабочая гипотеза',
    },
    {
      'text': 'т',
      'partIds': ['p2'],
      'colorKinds': ['formative_suffix'],
      'note': '',
    },
    {
      'text': 'и',
      'partIds': ['p2'],
      'colorKinds': ['formative_suffix'],
      'note': '',
    },
  ],
};
Map<String, dynamic> card() => {
  'version': 'v1',
  'id': 'root:KAJ',
  'title': 'каj',
  'kind': 'root',
  'status': 'proposed',
  'gloss': 'каяться',
  'statistics': {'lexemes': 21, 'forms': 24},
  'allomorphs': [
    {'surface': 'ка', 'status': 'proposed', 'note': ''},
  ],
  'schemaVersion': 2,
  'composition': {'state': 'undescribed', 'models': [], 'notes': []},
  'etymology': {
    'state': 'undescribed',
    'nodes': [],
    'relations': [],
    'chains': [],
    'notes': [],
  },
  'sources': [],
};
http.Response response(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
DictionaryRepository repository(
  Future<http.Response> Function(http.Request) handler,
) => DictionaryRepository(
  base: Uri.parse('https://example.test/api/v2/cs/'),
  client: MockClient(handler),
);
Widget wordView(DictionaryRepository repo) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: WordMorphemesView(
        id: 'dictionary-id',
        repository: repo,
        openWord: (_) {},
        fontSize: 22,
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'one block per morpheme stays on one scrollable row in dark theme',
    (tester) async {
      final data = analysis();
      (data['parts'] as List).first['surface'] = 'предлиннейший';
      final a = MorphemeAnalysis(data);
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 260,
                  child: MorphemeScheme(
                    analysis: a,
                    onSelect: (id) => selected = id,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scheme = find.byType(MorphemeScheme);
      final card = tester.widget<Card>(
        find.byKey(const ValueKey('morpheme-scheme-card')),
      );
      expect(card.color, Colors.white);
      expect(card.surfaceTintColor, Colors.transparent);
      final blocks = [
        for (final part in a.parts)
          find.byKey(ValueKey('morpheme-part-${part.id}')),
      ];
      expect(
        find.descendant(of: scheme, matching: find.byType(InkWell)),
        findsNWidgets(a.parts.length),
      );
      final tops = blocks.map((block) => tester.getTopLeft(block).dy).toSet();
      expect(tops, hasLength(1));
      expect(tester.getSize(blocks.first).width, greaterThan(48));
      final scrollable = find.descendant(
        of: scheme,
        matching: find.byType(Scrollable),
      );
      final state = tester.state<ScrollableState>(scrollable);
      expect(state.position.axis, Axis.horizontal);
      expect(state.position.maxScrollExtent, greaterThan(0));
      expect(find.text('∅'), findsOneWidget);
      await tester.drag(scheme, const Offset(-1000, 0));
      await tester.pumpAndSettle();
      await tester.tap(blocks.last);
      expect(selected, 'p3');
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'API uses dictionary IDs, opaque cursors and pinned publication',
    () async {
      final requests = <Uri>[];
      final repo = repository((r) async {
        requests.add(r.url);
        if (r.url.path.endsWith('/words')) {
          return response({
            'version': 'v1',
            'items': [],
            'total': 0,
            'nextCursor': null,
          });
        }
        if (r.url.path.endsWith('/morphemes')) {
          return response({'version': 'v1', 'analyses': []});
        }
        return response(card());
      });
      await repo.wordMorphemes('dict/id');
      await repo.morpheme('root:KAJ', version: 'v1');
      await repo.morphemeWords('root:KAJ', version: 'v1', cursor: 'a+/=&');
      expect(requests[0].pathSegments, contains('dict/id'));
      expect(requests[1].queryParameters, {'version': 'v1', 'schema': '2'});
      expect(requests[2].queryParameters, {
        'version': 'v1',
        'limit': '20',
        'cursor': 'a+/=&',
      });
      repo.close();
    },
  );

  testWidgets(
    'no assigned analysis stays empty without guessing or extra requests',
    (tester) async {
      final paths = <String>[];
      final repo = repository((r) async {
        paths.add(r.url.path);
        return response({'version': 'v1', 'analyses': []});
      });
      await tester.pumpWidget(wordView(repo));
      await tester.pumpAndSettle();
      expect(
        find.text('Морфемный разбор этого слова пока не задан.'),
        findsOneWidget,
      );
      expect(find.byType(MorphemeScheme), findsNothing);
      expect(paths, ['/api/v2/cs/lexemes/dictionary-id/morphemes']);
      repo.close();
    },
  );

  testWidgets(
    'incomplete API response is not treated as an unassigned analysis',
    (tester) async {
      final repo = repository((r) async => response({'version': 'v1'}));
      await tester.pumpWidget(wordView(repo));
      await tester.pumpAndSettle();
      expect(
        find.text('Морфемный разбор этого слова пока не задан.'),
        findsNothing,
      );
      expect(
        find.text('API вернул неполный морфемный разбор. Попробуйте ещё раз.'),
        findsOneWidget,
      );
      repo.close();
    },
  );

  testWidgets(
    'unavailable API differs from unassigned analysis and can retry',
    (tester) async {
      var count = 0;
      final repo = repository((r) async {
        count++;
        return count == 1
            ? response({'error': {}}, 404)
            : response({'version': 'v1', 'analyses': []});
      });
      await tester.pumpWidget(wordView(repo));
      await tester.pumpAndSettle();
      expect(
        find.text('Морфемные данные пока недоступны через API.'),
        findsOneWidget,
      );
      expect(
        find.text('Морфемный разбор этого слова пока не задан.'),
        findsNothing,
      );
      await tester.tap(find.text('Повторить'));
      await tester.pumpAndSettle();
      expect(
        find.text('Морфемный разбор этого слова пока не задан.'),
        findsOneWidget,
      );
      expect(count, 2);
      repo.close();
    },
  );

  testWidgets('shared letter selects its morpheme block and root opens card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = repository((r) async {
      if (r.url.path.endsWith('/words')) {
        return response({
          'version': 'v1',
          'total': 21,
          'items': [],
          'nextCursor': null,
        });
      }
      if (r.url.path.endsWith('/morphemes')) {
        return response({
          'version': 'v1',
          'analyses': [analysis()],
        });
      }
      return response(card());
    });
    await tester.pumpWidget(wordView(repo));
    await tester.pumpAndSettle();
    expect(find.text('я'), findsOneWidget);
    expect(find.text('∅ — окончание'), findsOneWidget);
    await tester.tap(find.text('я'));
    await tester.pumpAndSettle();
    final theme = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'я — тематическая гласная'),
    );
    expect(theme.selected, isTrue);
    await tester.tap(find.text('каj — корень'));
    await tester.pumpAndSettle();
    expect(find.text('Слов: 21'), findsOneWidget);
    expect(find.text('Форм: 24'), findsOneWidget);
    expect(find.text('каяться'), findsOneWidget);
    expect(tester.takeException(), isNull);
    repo.close();
  });

  testWidgets(
    'word pages replace items, preserve previous cursor and open dictionary ID',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final cursorRequests = <String?>[];
      String? opened;
      final repo = repository((r) async {
        if (!r.url.path.endsWith('/words')) return response(card());
        final cursor = r.url.queryParameters['cursor'];
        cursorRequests.add(cursor);
        return response({
          'version': 'v1',
          'total': 21,
          'items': [
            {
              'id': cursor == null ? 'dict-first' : 'dict-last',
              'name': cursor == null ? 'Первое' : 'Последнее',
              'gloss': '',
            },
          ],
          'nextCursor': cursor == null ? 'opaque-cursor' : null,
        });
      });
      await tester.pumpWidget(
        MaterialApp(
          home: MorphemeScreen(
            id: 'root:KAJ',
            version: 'v1',
            repository: repo,
            openWord: (id) => opened = id,
            fontSize: 22,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Далее'));
      await tester.tap(find.text('Далее'));
      await tester.pumpAndSettle();
      expect(find.text('Последнее'), findsOneWidget);
      expect(find.text('Первое'), findsNothing);
      expect(find.text('Страница 2'), findsOneWidget);
      await tester.tap(find.text('Состав и этимология'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Слова'));
      await tester.pumpAndSettle();
      expect(find.text('Страница 2'), findsOneWidget);
      await tester.tap(find.text('Последнее'));
      expect(opened, 'dict-last');
      await tester.tap(find.text('Назад'));
      await tester.pumpAndSettle();
      expect(find.text('Первое'), findsOneWidget);
      expect(cursorRequests, [null, 'opaque-cursor', null]);
      repo.close();
    },
  );

  testWidgets('changed publication cannot mix word statistics and list', (
    tester,
  ) async {
    final repo = repository(
      (r) async => r.url.path.endsWith('/words')
          ? response({
              'version': 'v2',
              'total': 99,
              'items': [
                {'name': 'Wrong version'},
              ],
            })
          : response(card()),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MorphemeScreen(
          id: 'root:KAJ',
          version: 'v1',
          repository: repo,
          openWord: (_) {},
          fontSize: 22,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Версия базы изменилась. Откройте вкладку «Морфемы» заново.'),
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const PageStorageKey('morpheme-words')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Wrong version'), findsNothing);
    repo.close();
  });

  testWidgets(
    'long morpheme preserves accents at large text scale without overflow',
    (tester) async {
      final data = analysis();
      (data['parts'] as List).first['surface'] = 'а́' * 50;
      data['letters'] = List.generate(
        50,
        (_) => {
          'text': 'а́',
          'partIds': ['p0'],
          'colorKinds': ['root'],
          'note': '',
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 600),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(
              body: SizedBox(
                width: 320,
                child: SingleChildScrollView(
                  child: MorphemeScheme(analysis: MorphemeAnalysis(data)),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('а́'), findsNWidgets(50));
    },
  );
}
