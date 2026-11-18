import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cs/core/personal_store.dart';
import 'package:cs/features/dictionary/data/dictionary_repository.dart';
import 'package:cs/features/dictionary/domain/models.dart';
import 'package:cs/features/dictionary/presentation/article_screen.dart';
import 'package:cs/features/dictionary/presentation/resource_screen.dart';
import 'package:cs/features/dictionary/presentation/retry_button.dart';
import 'package:cs/features/dictionary/presentation/search_controller.dart';
import 'dictionary_test.dart' show MemoryPreferences;
import 'dictionary_article_states_test.dart' show wire;

http.Response json(Object j, {Map<String, String> headers = const {}}) =>
    http.Response(
      jsonEncode(j),
      200,
      headers: {'content-type': 'application/json; charset=utf-8', ...headers},
    );
void main() {
  test(
    'old preferences survive loading, renamed articles, version changes and restart',
    () async {
      final prefs = MemoryPreferences()
        ..value = jsonEncode({
          'version': 1,
          'favorites': [
            {'id': 'saved', 'name': 'старое имя'},
          ],
          'history': [
            {'id': 'saved', 'name': 'старое имя'},
          ],
          'theme': 'dark',
          'fontSize': 30,
          'showProposed': false,
          'highlightEndings': false,
        });
      final store = PersonalStore(prefs);
      await store.initialized;
      expect(store.canEdit, true);
      expect(store.themeMode, ThemeMode.dark);
      expect(store.fontSize, 30);
      expect(store.showProposed, false);
      expect(store.highlightEndings, false);
      await store.opened(const SavedWord('saved', 'новое имя'));
      final restart = PersonalStore(prefs);
      await restart.initialized;
      expect(restart.favorites.single.id, 'saved');
      expect(restart.favorites.single.name, 'новое имя');
      expect(restart.history.single.id, 'saved');
      expect(restart.themeMode, ThemeMode.dark);
    },
  );
  test(
    'malformed or newer preferences are never replaced by empty defaults',
    () async {
      for (final raw in [
        '[]',
        'null',
        '{"version":2}',
        '{"favorites":{}}',
        '{"favorites":[{"id":"x"}]}',
        '{"fontSize":"22"}',
        '{"showProposed":"false"}',
        'broken',
      ]) {
        final prefs = MemoryPreferences()..value = raw;
        final store = PersonalStore(prefs);
        await store.initialized;
        expect(store.canEdit, false, reason: raw);
        await store.toggle(const SavedWord('x', 'слово'));
        await store.clearHistory();
        await store.settings(size: 28);
        await store.retryPersistence();
        expect(prefs.value, raw);
        expect(prefs.writes, 0);
        expect(store.favorites, isEmpty);
      }
    },
  );
  test(
    'failed read can recover without writing defaults; failed write retries newest snapshot',
    () async {
      final prefs = MemoryPreferences()
        ..failRead = true
        ..value = '{"favorites":[{"id":"keep","name":"слово"}]}';
      final store = PersonalStore(prefs);
      await store.initialized;
      await store.toggle(const SavedWord('discard', 'нет'));
      prefs.failRead = false;
      await store.retryPersistence();
      expect(store.favorites.single.id, 'keep');
      expect(prefs.writes, 0);
      prefs.failWrite = true;
      await store.settings(size: 32);
      expect(store.error, isNotNull);
      prefs.failWrite = false;
      await store.retryPersistence();
      final restart = PersonalStore(prefs);
      await restart.initialized;
      expect(restart.fontSize, 32);
      expect(restart.favorites.single.id, 'keep');
      expect(store.error, isNull);
    },
  );
  for (final header in ['7', 'Sat, 14 Nov 2026 12:00:07 GMT']) {
    test(
      '429 $header blocks requests until deadline without automatic resend',
      () async {
        var now = DateTime.utc(2026, 11, 14, 12);
        var calls = 0;
        final repo = DictionaryRepository(
          now: () => now,
          client: MockClient((_) async {
            calls++;
            return calls == 1
                ? http.Response(
                    '<html>limit</html>',
                    429,
                    headers: {'retry-after': header},
                  )
                : json({'lemma': 'ok'});
          }),
        );
        addTearDown(repo.close);
        await expectLater(
          repo.etymology(1),
          throwsA(
            isA<DictionaryException>()
                .having((e) => e.status, 'status', 429)
                .having((e) => e.retryAfter, 'delay', 7),
          ),
        );
        await expectLater(
          repo.etymology(1),
          throwsA(isA<DictionaryException>()),
        );
        expect(calls, 1);
        now = now.add(const Duration(seconds: 8));
        expect(calls, 1);
        expect((await repo.etymology(1))['lemma'], 'ok');
        expect(calls, 2);
      },
    );
  }
  test(
    'invalid Retry-After permits manual repeat and independent host remains available',
    () async {
      var calls = 0;
      final repo = DictionaryRepository(
        client: MockClient((r) async {
          calls++;
          return calls == 1
              ? http.Response('', 429, headers: {'retry-after': 'invalid'})
              : json({'version': 'v', 'items': [], 'nextCursor': null});
        }),
      );
      addTearDown(repo.close);
      await expectLater(
        repo.search('а', 'cu-ru'),
        throwsA(
          isA<DictionaryException>().having(
            (e) => e.retryAt,
            'deadline',
            isNull,
          ),
        ),
      );
      await repo.search('а', 'cu-ru');
      expect(calls, 2);
    },
  );
  test(
    'ETag revalidates only its exact URL and returns independent decoded bodies',
    () async {
      final requests = <http.Request>[];
      final repo = DictionaryRepository(
        client: MockClient((r) async {
          requests.add(r);
          return r.headers.containsKey('if-none-match')
              ? http.Response('', 304)
              : json({'lemma': 'original'}, headers: {'etag': '"v1"'});
        }),
      );
      addTearDown(repo.close);
      final first = await repo.etymology(1);
      first['lemma'] = 'mutated';
      expect((await repo.etymology(1))['lemma'], 'original');
      await repo.etymology(2);
      expect(requests[0].headers['if-none-match'], isNull);
      expect(requests[1].headers['if-none-match'], '"v1"');
      expect(requests[2].headers['if-none-match'], isNull);
    },
  );
  test('304 without a cached body retries unconditionally once', () async {
    var calls = 0;
    final repo = DictionaryRepository(
      client: MockClient((r) async {
        expect(r.headers['if-none-match'], isNull);
        return ++calls == 1 ? http.Response('', 304) : json({'lemma': 'body'});
      }),
    );
    addTearDown(repo.close);
    expect((await repo.etymology(1))['lemma'], 'body');
    expect(calls, 2);
  });
  test(
    'no-store and session eviction prevent conditional requests with missing bodies',
    () async {
      final requests = <http.Request>[];
      final repo = DictionaryRepository(
        client: MockClient((r) async {
          requests.add(r);
          return json(
            {'lemma': 'body'},
            headers: {
              'etag': '"v1"',
              if (r.url.path.endsWith('/0')) 'cache-control': 'no-store',
            },
          );
        }),
      );
      addTearDown(repo.close);
      await repo.etymology(0);
      await repo.etymology(0);
      expect(requests.last.headers['if-none-match'], isNull);
      for (var i = 1; i <= 33; i++) {
        await repo.etymology(i);
      }
      await repo.etymology(1);
      expect(requests.last.headers['if-none-match'], isNull);
    },
  );
  test(
    'pinned version is still validated after 304; cached versions never mix',
    () async {
      final data = wire('article');
      final d = data['dictionaryVersion'] as String;
      final requests = <http.Request>[];
      final repo = DictionaryRepository(
        client: MockClient((r) async {
          requests.add(r);
          return r.headers.containsKey('if-none-match')
              ? http.Response('', 304)
              : json(data, headers: {'etag': '"a"'});
        }),
      );
      addTearDown(repo.close);
      await repo.article(data['id'] as String, version: d);
      await repo.article(data['id'] as String, version: d);
      await expectLater(
        repo.article(data['id'] as String, version: 'other'),
        throwsA(
          isA<DictionaryException>().having(
            (e) => e.code,
            'code',
            'invalid_contract',
          ),
        ),
      );
      expect(requests.last.headers['if-none-match'], isNull);
    },
  );
  test(
    'HTML 502, timeout and network exceptions are distinct from empty success',
    () async {
      for (final kind in ['502', 'timeout', 'network']) {
        final repo = DictionaryRepository(
          requestTimeout: const Duration(milliseconds: 1),
          client: MockClient((_) async {
            if (kind == '502') {
              return http.Response('<html>bad gateway</html>', 502);
            }
            if (kind == 'network') throw http.ClientException('offline');
            await Future<void>.delayed(const Duration(milliseconds: 20));
            return json({'lemma': 'late'});
          }),
        );
        await expectLater(
          repo.etymology(1),
          throwsA(
            isA<DictionaryException>().having(
              (e) => kind == '502' ? e.status : e.code,
              'error',
              kind == '502' ? 502 : kind,
            ),
          ),
        );
        repo.close();
      }
    },
  );
  test(
    'failed continuation retries same cursor and version without losing first page',
    () async {
      final urls = <Uri>[];
      final repo = DictionaryRepository(
        client: MockClient((r) async {
          urls.add(r.url);
          if (urls.length == 2) return http.Response('', 502);
          return json({
            'schemaVersion': 2,
            'dictionaryVersion': 'D',
            'version': 'D',
            'query': 'а',
            'direction': 'cu-ru',
            'items': urls.length == 1
                ? [
                    {
                      'id': 'a',
                      'name': 'а',
                      'pos': 'noun',
                      'match': 'lemma',
                      'matched': 'а',
                      'grammar': '',
                      'exact': true,
                    },
                  ]
                : [],
            'nextCursor': urls.length == 1 ? 'cursor' : null,
          });
        }),
      );
      addTearDown(repo.close);
      final controller = WordSearchController(repo);
      addTearDown(controller.dispose);
      controller.change('а', immediate: true);
      await Future<void>.delayed(Duration.zero);
      await controller.more();
      expect(controller.items.single.id, 'a');
      expect(controller.error, isNotNull);
      controller.retry();
      await Future<void>.delayed(Duration.zero);
      expect(urls[1], urls[2]);
      expect(controller.error, isNull);
      expect(controller.items.single.id, 'a');
    },
  );
  testWidgets('404 retains favorite and history; retry follows same ID', (
    t,
  ) async {
    final prefs = MemoryPreferences();
    final personal = PersonalStore(prefs);
    await personal.initialized;
    await personal.toggle(const SavedWord('gone', 'сохранённое'));
    await personal.opened(const SavedWord('gone', 'сохранённое'));
    var calls = 0;
    final repo = DictionaryRepository(
      client: MockClient((r) async {
        calls++;
        expect(r.url.path.endsWith('/gone'), true);
        return http.Response('', 404);
      }),
    );
    addTearDown(repo.close);
    await t.pumpWidget(
      MaterialApp(
        home: ArticleScreen(id: 'gone', repository: repo, personal: personal),
      ),
    );
    await t.pumpAndSettle();
    expect(
      find.text('Статья недоступна по сохранённому адресу.'),
      findsOneWidget,
    );
    await t.tap(find.text('Повторить'));
    await t.pumpAndSettle();
    expect(calls, 2);
    expect(personal.favorites.single.id, 'gone');
    expect(personal.history.single.id, 'gone');
  });
  testWidgets(
    'etymology failure retries its own resource and returns to unchanged parent',
    (t) async {
      var calls = 0;
      final repo = DictionaryRepository(
        client: MockClient((r) async {
          expect(r.url.host, 'interslavic-lexicon.com');
          return ++calls == 1
              ? http.Response('', 503)
              : json({
                  'lemma': 'корень',
                  'body': 'текст',
                  'bodySha256': 'hash',
                });
        }),
      );
      addTearDown(repo.close);
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  c,
                  MaterialPageRoute<void>(
                    builder: (_) => ResourceScreen(
                      repository: repo,
                      id: '',
                      protoId: 1,
                      size: 22,
                    ),
                  ),
                ),
                child: const Text('Толкование сохраняется'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Толкование сохраняется'));
      await t.pumpAndSettle();
      expect(find.textContaining('Сервис временно'), findsOneWidget);
      await t.tap(find.text('Повторить'));
      await t.pumpAndSettle();
      expect(find.text('корень'), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.text('Толкование сохраняется'), findsOneWidget);
      expect(calls, 2);
    },
  );
  testWidgets('rate limit button waits and never sends a retry itself', (
    t,
  ) async {
    var calls = 0;
    final e = DictionaryException(
      'limit',
      status: 429,
      retryAt: DateTime.now().add(const Duration(seconds: 30)),
    );
    await t.pumpWidget(
      MaterialApp(
        home: RetryButton(error: e, onRetry: () => calls++),
      ),
    );
    expect(t.widget<TextButton>(find.byType(TextButton)).onPressed, isNull);
    await t.pump(const Duration(seconds: 1));
    expect(calls, 0);
    await t.pumpWidget(
      MaterialApp(
        home: RetryButton(
          error: const DictionaryException('expired'),
          onRetry: () => calls++,
        ),
      ),
    );
    await t.tap(find.text('Повторить'));
    expect(calls, 1);
  });
}
