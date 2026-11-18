import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cs/app/app.dart';
import 'package:cs/core/personal_store.dart';
import 'package:cs/features/dictionary/data/dictionary_repository.dart';
import 'package:cs/features/dictionary/domain/models.dart';
import 'package:cs/features/dictionary/presentation/search_controller.dart';
import 'dictionary_test.dart' show MemoryPreferences;

Json wire(String key) => object(
  object(
    jsonDecode(File('qa/mobile/m1-04-wire-examples.json').readAsStringSync()),
  )[key],
);
http.Response reply(Object data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Future<void> settleRequest() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test(
    'actual server wire pins search, continuation, article and source',
    () async {
      final calls = <Uri>[];
      final repo = DictionaryRepository(
        client: MockClient((r) async {
          calls.add(r.url);
          return reply(
            wire(
              r.url.path.contains('source-entries')
                  ? 'source'
                  : r.url.path.contains('lexemes')
                  ? 'article'
                  : r.url.queryParameters.containsKey('cursor')
                  ? 'continuation'
                  : 'search',
            ),
          );
        }),
      );
      addTearDown(repo.close);
      final first = await repo.search('аа', 'cu-ru', limit: 2);
      final next = await repo.search(
        'аа',
        'cu-ru',
        limit: 2,
        cursor: first.nextCursor,
        version: first.version,
      );
      expect(next.schemaVersion, 2);
      expect(next.version, first.version);
      expect(next.items.first.id, endsWith('3'));
      final article = await repo.article(
        first.items.first.id,
        version: first.version,
      );
      final source = await repo.source(
        article.sources.first.id,
        version: first.version,
      );
      expect(article.version, first.version);
      expect(source['sourceVersion'], 'source-revision');
      expect(article.extra.first.formOrigin, 'dictionary');
      expect(article.extra.first.reviewStatus, 'unknown');
      expect(calls.every((u) => u.queryParameters['schema'] == '2'), isTrue);
      expect(
        calls
            .skip(1)
            .every((u) => u.queryParameters['version'] == first.version),
        isTrue,
      );
    },
  );
  test(
    'legacy server is explicit legacy and cannot satisfy a pinned request',
    () async {
      final repo = DictionaryRepository(
        client: MockClient(
          (_) async =>
              reply({'version': 'old', 'items': [], 'nextCursor': null}),
        ),
      );
      addTearDown(repo.close);
      expect((await repo.search('земля', 'cu-ru')).schemaVersion, 1);
      await expectLater(
        repo.search('земля', 'cu-ru', version: 'requested'),
        throwsA(
          isA<DictionaryException>().having(
            (e) => e.code,
            'code',
            'invalid_contract',
          ),
        ),
      );
    },
  );
  test(
    'mismatched versions, aliases and malformed schema=2 are not empty data',
    () async {
      for (final data in [
        {...wire('search'), 'dictionaryVersion': 'other'},
        {...wire('search'), 'items': null},
        {...wire('search'), 'schemaVersion': 3},
        {...wire('search'), 'nextCursor': 17},
      ]) {
        final repo = DictionaryRepository(
          client: MockClient((_) async => reply(data)),
        );
        await expectLater(
          repo.search('аа', 'cu-ru'),
          throwsA(isA<DictionaryException>()),
        );
        repo.close();
      }
      final article = wire('article');
      final f = object(array(article['extra']).first)..remove('formOrigin');
      article['extra'] = [f];
      final repo = DictionaryRepository(
        client: MockClient((_) async => reply(article)),
      );
      addTearDown(repo.close);
      await expectLater(
        repo.article(string(article['id'])),
        throwsA(isA<DictionaryException>()),
      );
    },
  );
  test(
    'continuation retry keeps cursor and version; 409 requires explicit restart',
    () async {
      final calls = <Uri>[];
      var failures = 1;
      var expired = false;
      final repo = DictionaryRepository(
        client: MockClient((r) async {
          calls.add(r.url);
          if (r.url.queryParameters.containsKey('cursor')) {
            if (expired) {
              return reply({
                'error': {'code': 'version_unavailable'},
              }, 409);
            }
            if (failures-- > 0) return http.Response('bad gateway', 502);
            return reply(wire('continuation'));
          }
          return reply(wire('search'));
        }),
      );
      final c = WordSearchController(repo);
      addTearDown(c.dispose);
      addTearDown(repo.close);
      c.change('аа', immediate: true);
      await settleRequest();
      await c.more();
      expect(c.items.length, 2);
      expect(c.restartRequired, isFalse);
      c.retry();
      await settleRequest();
      expect(c.items.length, 4);
      expect(calls[1], calls[2]);
      c.change('аа', immediate: true);
      await settleRequest();
      expired = true;
      await c.more();
      expect(c.restartRequired, isTrue);
      expect(c.nextCursor, isNull);
      expect(c.items.length, 2);
      c.retry();
      await settleRequest();
      expect(calls.last.queryParameters.containsKey('cursor'), isFalse);
      expect(calls.last.queryParameters.containsKey('version'), isFalse);
    },
  );
  test(
    'legacy continuation stays legacy and guards changed publications',
    () async {
      final calls = <Uri>[];
      final repo = DictionaryRepository(
        client: MockClient((r) async {
          calls.add(r.url);
          final next = r.url.queryParameters.containsKey('cursor');
          return reply({
            'version': next ? 'changed' : 'old',
            'items': [
              {'id': 'word', 'name': 'слово'},
            ],
            'nextCursor': '20',
          });
        }),
      );
      final c = WordSearchController(repo);
      addTearDown(c.dispose);
      addTearDown(repo.close);
      c.change('слово', immediate: true);
      await settleRequest();
      await c.more();
      expect(calls.last.queryParameters['schema'], '1');
      expect(c.restartRequired, isTrue);
      expect(c.items.length, 1);
    },
  );
  test(
    'unknown origin/status stays neutral and does not imply generated/verified',
    () {
      expect(
        WordForm({'value': 'а', 'formOrigin': 'future'}).originLabel,
        'Происхождение неизвестно',
      );
      expect(
        SourceCard({'mappingStatus': 'future'}).mappingLabel,
        'Статус сопоставления не указан',
      );
      expect(SearchHit({'match': 'future', 'exact': false}).indicator, isNull);
    },
  );
  testWidgets(
    'query, loaded results and scroll survive article/source/nested lookup return',
    (tester) async {
      final calls = <Uri>[];
      final repo = DictionaryRepository(
        client: MockClient((r) async {
          calls.add(r.url);
          if (r.url.path.endsWith('/search')) {
            return reply({
              ...wire('search'),
              'query': r.url.queryParameters['q'],
              'nextCursor': null,
              'items': List.generate(
                30,
                (i) => {
                  ...object(array(wire('search')['items']).first),
                  'id': (i + 1).toRadixString(16).padLeft(24, '0'),
                  'name': 'a${i + 1}',
                },
              ),
            });
          }
          if (r.url.path.contains('source-entries')) {
            return reply({
              ...wire('source'),
              'paragraphs': [
                {
                  'runs': [
                    {'text': 'text', 'kind': 'text', 'target': 'lookup:бета'},
                  ],
                },
              ],
            });
          }
          final id = r.url.pathSegments.last;
          return reply({
            ...wire('article'),
            'id': id,
            'name': 'a${int.parse(id, radix: 16)}',
          });
        }),
      );
      addTearDown(repo.close);
      final personal = PersonalStore(MemoryPreferences());
      await personal.initialized;
      await tester.pumpWidget(
        ChurchSlavonicApp(repository: repo, personal: personal),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'аа');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('a20'),
        400,
        scrollable: find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      final scroll = tester.widget<ListView>(find.byType(ListView)).controller!;
      final offset = scroll.offset;
      expect(offset, greaterThan(0));
      await tester.tap(find.text('a20'));
      await tester.pumpAndSettle();
      expect(
        calls.last.queryParameters['version'],
        wire('search')['dictionaryVersion'],
      );
      await tester.tap(find.text('Source').first);
      await tester.pumpAndSettle();
      expect(
        calls.last.queryParameters['version'],
        wire('search')['dictionaryVersion'],
      );
      await tester.tap(find.text('бета'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'бета'), findsOneWidget);
      await tester.tap(find.byTooltip('Назад'));
      await tester.pumpAndSettle();
      expect(find.text('Статья источника'), findsOneWidget);
      await tester.tap(find.byTooltip('Назад'));
      await tester.pumpAndSettle();
      expect(find.text('Словарная статья'), findsOneWidget);
      await tester.tap(find.byTooltip('Назад'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'аа'), findsOneWidget);
      expect(scroll.offset, offset);
      expect(calls.where((u) => u.path.endsWith('/search')).length, 2);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'failed search offers retry without missing-word report; empty success offers report',
    (tester) async {
      var failed = true;
      final repo = DictionaryRepository(
        client: MockClient(
          (_) async => failed
              ? http.Response('bad gateway', 502)
              : reply({...wire('search'), 'items': [], 'nextCursor': null}),
        ),
      );
      addTearDown(repo.close);
      final personal = PersonalStore(MemoryPreferences());
      await personal.initialized;
      await tester.pumpWidget(
        ChurchSlavonicApp(repository: repo, personal: personal),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'аа');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.text('Повторить'), findsOneWidget);
      expect(find.text('Сообщить о недостающем слове'), findsNothing);
      failed = false;
      await tester.tap(find.text('Повторить'));
      await tester.pumpAndSettle();
      expect(find.text('Сообщить о недостающем слове'), findsOneWidget);
      expect(find.text('Копировать запрос'), findsOneWidget);
    },
  );
}
