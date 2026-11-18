import 'package:cs/app/app.dart';
import 'package:cs/core/personal_store.dart';
import 'package:cs/features/dictionary/data/dictionary_repository.dart';
import 'package:cs/features/dictionary/domain/models.dart';
import 'package:cs/features/dictionary/presentation/article_screen.dart';
import 'package:cs/features/reader/presentation/corpus_screen.dart';
import 'package:cs/features/reader/presentation/reader_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dictionary_test.dart' show MemoryPreferences;
import 'reader_mobile_test.dart' as f;
import 'dictionary_article_states_test.dart' as a;

http.Response response(String body, int status) => http.Response(
  body,
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  testWidgets(
    'catalog → reader → passport → token candidates → article preserves reader and dictionary state',
    (tester) async {
      final personal = PersonalStore(MemoryPreferences());
      await personal.initialized;
      await personal.toggle(const SavedWord('saved', 'Избранное'));
      final requests = <http.Request>[];
      final dict = DictionaryRepository(
        client: MockClient((r) async {
          requests.add(r);
          final path = r.url.path;
          if (path.endsWith('/index/capabilities')) {
            return response(
              f.envelope(f.makeSession().index, 'cs-index/1'),
              200,
            );
          }
          if (path.endsWith('/capabilities')) {
            return response(f.envelope(f.makeSession().reader), 200);
          }
          if (path.endsWith('/catalog')) {
            return response(
              f.envelope({
                'items': [f.readWire()['data']['source']],
                'catalogRevision': 'C',
                'nextCursor': null,
              }),
              200,
            );
          }
          if (path.endsWith('/resolve')) {
            return response(
              f.envelope({
                'result': 'resolved',
                'source': f.readWire()['data']['source'],
                'resolvedAddress': f.readWire()['data']['resolvedAddress'],
              }),
              200,
            );
          }
          if (path.endsWith('/read')) return f.jsonResponse(f.readWire());
          if (path.contains('/passport/')) {
            return response(
              f.envelope({
                'sourceId': f.readWire()['data']['resolvedAddress']['sourceId'],
                'passportRevision': f
                    .readWire()['data']['resolvedAddress']['passportRevision'],
                'fields': {
                  'translator': {
                    'state': 'unknown',
                    'display': 'Переводчик не установлен.',
                  },
                },
                'sources': [],
              }),
              200,
            );
          }
          if (path.endsWith('/search')) {
            return f.jsonResponse({
              'schemaVersion': 2,
              'dictionaryVersion': 'D',
              'version': 'D',
              'query': r.url.queryParameters['q'],
              'direction': 'cu-ru',
              'nextCursor': null,
              'items': [
                for (final id in ['one', 'two'])
                  {
                    'id': id,
                    'name': 'Кандидат $id',
                    'pos': 'noun',
                    'match': 'stored-form',
                    'matched': 'бл҃г',
                    'grammar': '',
                    'exact': true,
                  },
              ],
            });
          }
          if (path.contains('/lexemes/')) {
            return f.jsonResponse({
              ...a.wire('article'),
              'id': 'one',
              'name': 'Первое слово',
              'dictionaryVersion': 'D',
              'version': 'D',
            });
          }
          return response('{}', 404);
        }),
      );
      addTearDown(dict.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CorpusScreen(dictionary: dict, personal: personal),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(f.readWire()['data']['source']['title']));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderScreen), findsOneWidget);
      await tester.tap(find.byTooltip('Паспорт текста'));
      await tester.pumpAndSettle();
      expect(find.text('Переводчик не установлен.'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Выбрать слово'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('бл҃г').last);
      await tester.pumpAndSettle();
      expect(find.text('Кандидат one'), findsOneWidget);
      expect(find.text('Кандидат two'), findsOneWidget);
      final lookup = requests.last;
      expect(lookup.url.queryParameters['version'], 'D');
      expect(lookup.url.queryParameters['schema'], '2');
      await tester.tap(find.text('Кандидат one'));
      await tester.pumpAndSettle();
      expect(find.byType(ArticleScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(ReaderScreen), findsOneWidget);
      expect(find.text('Выбрать слово'), findsOneWidget);
      expect(personal.favorites.single.id, 'saved');
      expect(tester.takeException(), null);
    },
  );
  testWidgets(
    'missing corpus keeps dictionary usable, and opening text tab retains search query',
    (tester) async {
      final personal = PersonalStore(MemoryPreferences());
      await personal.initialized;
      final dict = DictionaryRepository(
        client: MockClient(
          (r) async => r.url.path.contains('/reader/')
              ? response('not found', 404)
              : f.jsonResponse({'version': 'legacy', 'items': []}),
        ),
      );
      addTearDown(dict.close);
      await tester.pumpWidget(
        ChurchSlavonicApp(repository: dict, personal: personal),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'мой запрос');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Тексты'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Словарь продолжает работать'),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Словарь'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'мой запрос'), findsOneWidget);
      expect(tester.takeException(), null);
    },
  );
}
