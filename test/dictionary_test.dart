import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cs/app/app.dart';
import 'package:cs/core/personal_store.dart';
import 'package:cs/features/dictionary/data/dictionary_repository.dart';
import 'package:cs/features/dictionary/domain/models.dart';
import 'package:cs/features/dictionary/presentation/search_controller.dart';

http.Response response(
  String body,
  int status, {
  Map<String, String>? headers,
}) => http.Response(
  body,
  status,
  headers: {'content-type': 'application/json; charset=utf-8', ...?headers},
);

class MemoryPreferences implements PreferencesStore {
  String? value;
  bool failRead = false, failWrite = false;
  int writes = 0;
  @override
  Future<String?> read() async {
    if (failRead) throw StateError('read');
    return value;
  }

  @override
  Future<void> write(String raw) async {
    writes++;
    if (failWrite) throw StateError('write');
    value = raw;
  }
}

String page(String name) => jsonEncode({
  'version': 'v',
  'items': [
    {'id': name, 'name': name, 'match': 'lemma'},
  ],
  'nextCursor': null,
});
void main() {
  testWidgets('request timeout is readable and leaves no pending UI timer', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    final repository = DictionaryRepository(
      client: MockClient((_) => pending.future),
    );
    final assertion = expectLater(
      repository.search('слово', 'cu-ru'),
      throwsA(
        isA<DictionaryException>().having(
          (e) => e.message,
          'message',
          contains('вовремя'),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 16));
    await assertion;
    repository.close();
  });
  test(
    'offline and independent interlex failures do not poison article loading',
    () async {
      final offline = DictionaryRepository(
        client: MockClient((_) => throw http.ClientException('offline')),
      );
      await expectLater(
        offline.search('слово', 'cu-ru'),
        throwsA(
          isA<DictionaryException>().having(
            (e) => e.message,
            'message',
            contains('соединения'),
          ),
        ),
      );
      offline.close();
      final repository = DictionaryRepository(
        client: MockClient(
          (r) async => r.url.path.contains('/proto/')
              ? response('{}', 503)
              : response('{"id":"word"}', 200),
        ),
      );
      await expectLater(
        repository.etymology(20),
        throwsA(isA<DictionaryException>()),
      );
      expect((await repository.article('word')).id, 'word');
      repository.close();
    },
  );
  test(
    'network errors preserve Retry-After and do not parse error bodies as dictionary data',
    () async {
      final r = DictionaryRepository(
        client: MockClient(
          (_) async =>
              response('not json', 429, headers: {'retry-after': '12'}),
        ),
        base: Uri.parse('https://example.org/'),
      );
      await expectLater(
        r.search('а', 'cu-ru'),
        throwsA(
          isA<DictionaryException>()
              .having((e) => e.status, 'status', 429)
              .having((e) => e.retryAfter, 'retry', 12),
        ),
      );
      r.close();
    },
  );
  test('rapid searches and direction changes ignore late responses', () async {
    final first = Completer<http.Response>(),
        second = Completer<http.Response>();
    var calls = 0;
    final repository = DictionaryRepository(
      client: MockClient((_) => ++calls == 1 ? first.future : second.future),
    );
    final controller = WordSearchController(repository);
    controller.change('старое', immediate: true);
    controller.change('новое', mode: 'ru-cu', immediate: true);
    second.complete(response(page('новое'), 200));
    await Future<void>.delayed(Duration.zero);
    first.complete(response(page('старое'), 200));
    await Future<void>.delayed(Duration.zero);
    expect(controller.items.single.name, 'новое');
    expect(controller.direction, 'ru-cu');
    expect(controller.loading, false);
    controller.dispose();
    repository.close();
  });
  test('clear search cancels pending publication of results', () async {
    final result = Completer<http.Response>();
    final repository = DictionaryRepository(
      client: MockClient((_) => result.future),
    );
    final controller = WordSearchController(repository);
    controller.change('слово', immediate: true);
    controller.change('');
    result.complete(response(page('слово'), 200));
    await Future<void>.delayed(Duration.zero);
    expect(controller.items, isEmpty);
    expect(controller.loading, false);
    controller.dispose();
    repository.close();
  });
  test(
    'favorites, history limit, settings and rapid writes survive a restart',
    () async {
      final prefs = MemoryPreferences();
      final store = PersonalStore(prefs);
      await store.initialized;
      await store.toggle(const SavedWord('a', 'а҆'));
      for (var i = 0; i < 105; i++) {
        await store.opened(SavedWord('$i', 'слово $i'));
      }
      await store.opened(const SavedWord('50', 'слово 50'));
      await store.settings(
        theme: ThemeMode.dark,
        size: 32,
        endings: false,
        proposed: false,
      );
      final second = PersonalStore(prefs);
      await second.initialized;
      expect(second.favorites.single.id, 'a');
      expect(second.history.length, 100);
      expect(second.history.first.id, '50');
      expect(second.history.where((w) => w.id == '50').length, 1);
      expect(second.themeMode, ThemeMode.dark);
      expect(second.fontSize, 32);
      expect(second.highlightEndings, false);
      expect(second.showProposed, false);
      await Future.wait([
        second.toggle(const SavedWord('b', 'б')),
        second.toggle(const SavedWord('c', 'в')),
      ]);
      final third = PersonalStore(prefs);
      await third.initialized;
      expect(third.favorites.map((w) => w.id), containsAll(['a', 'b', 'c']));
    },
  );
  test('failed local read never overwrites existing personal data', () async {
    final prefs = MemoryPreferences()
      ..value = 'unread original'
      ..failRead = true;
    final store = PersonalStore(prefs);
    await store.initialized;
    await store.toggle(const SavedWord('a', 'а'));
    expect(prefs.writes, 0);
    expect(prefs.value, 'unread original');
    expect(store.error, isNotNull);
  });
  test(
    'report is sent only by explicit repository action and has no credentials',
    () async {
      var calls = 0;
      final repository = DictionaryRepository(
        client: MockClient((r) async {
          calls++;
          expect(r.method, 'POST');
          expect(r.headers.containsKey('Authorization'), false);
          expect(jsonDecode(r.body)['comment'], 'Не хватает слова');
          return response('{"accepted":true}', 201);
        }),
      );
      expect(calls, 0);
      await repository.report(
        reason: 'missing',
        comment: 'Не хватает слова',
        query: 'слово',
      );
      expect(calls, 1);
      repository.close();
    },
  );
  testWidgets(
    'search, article, source and local favorite work at large text scale',
    (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final prefs = MemoryPreferences();
      final personal = PersonalStore(prefs);
      await personal.initialized;
      final repository = DictionaryRepository(
        client: MockClient((r) async {
          if (r.url.path.endsWith('/search')) {
            return response(page('word'), 200);
          }
          if (r.url.path.contains('source-entries')) {
            return response(
              jsonEncode({
                'title': 'Словарь Свирелина',
                'paragraphs': [
                  {
                    'runs': [
                      {'text': 'Проверенное пояснение', 'kind': 'text'},
                    ],
                  },
                ],
              }),
              200,
            );
          }
          return response(
            jsonEncode({
              'id': 'word',
              'name': 'сло́во',
              'pos': 'noun',
              'properties': ['S', 'n'],
              'morphologyStatus': 'unassigned',
              'sources': [
                {
                  'id': 'source',
                  'title': 'Словарь Свирелина',
                  'preview': 'Пояснение',
                },
              ],
              'paradigms': [],
              'extra': [],
              'relations': [],
              'etymologies': [],
              'usage': [],
              'composition': [],
            }),
            200,
          );
        }),
      );
      await tester.pumpWidget(
        ChurchSlavonicApp(repository: repository, personal: personal),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'слово');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await tester.tap(find.text('word'));
      await tester.pumpAndSettle();
      expect(find.text('сло́во'), findsOneWidget);
      await tester.tap(find.byTooltip('В избранное'));
      await tester.pumpAndSettle();
      expect(personal.favorites.single.id, 'word');
      await tester.tap(find.text('Словарь Свирелина').first);
      await tester.pumpAndSettle();
      expect(
        find.text('Проверенное пояснение', findRichText: true),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Назад'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Назад'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Настройки'));
      await tester.pumpAndSettle();
      expect(find.text('Размер текста: 22'), findsOneWidget);
      expect(tester.takeException(), isNull);
      repository.close();
    },
  );
}
