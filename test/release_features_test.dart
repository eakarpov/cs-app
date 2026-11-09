import 'dart:async';
import 'dart:convert';
import 'package:cs/core/external_link.dart';
import 'package:cs/features/scripture/domain/scripture_reference.dart';
import 'package:cs/features/scripture/presentation/scripture_text.dart';
import 'package:cs/features/dictionary/data/dictionary_repository.dart';
import 'package:cs/features/dictionary/domain/models.dart';
import 'package:cs/features/dictionary/presentation/lexical_search_controller.dart';
import 'package:cs/features/dictionary/presentation/lexical_search_view.dart';
import 'package:cs/core/personal_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dictionary_test.dart' show MemoryPreferences;

http.Response jsonResponse(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
SearchHit hit(String id, [String name = 'слово']) =>
    SearchHit({'id': id, 'name': name, 'match': 'lemma', 'exact': true});
void main() {
  test(
    'citations preserve exact text and map portal canonical books and verse bounds',
    () {
      const input = 'Мф. 5, 3–5; Іоан. III. 16; 1 Кор 13:4; Сирах: XXI. 24.';
      final refs = scriptureReferences(input);
      expect(refs.map((r) => r.book), [
        'matfeya',
        'ioanna',
        '1-korinfyanam',
        'sirakha',
      ]);
      expect(
        refs.first.uri.toString(),
        'https://www.typikon.info/bible/matfeya/5?highlight=3-5#v3',
      );
      for (final r in refs) {
        expect(input.substring(r.start, r.end), r.label);
      }
      for (final text in [
        'Мф 99:1',
        'Мф 5:0',
        'Мф 5:99',
        'Мф 5:10-3',
        'Мф 5:1000',
        'Ин 3:1–4:2',
        'Супр 3,16',
        '2026,11',
      ]) {
        expect(scriptureReferences(text), isEmpty, reason: text);
      }
    },
  );
  test(
    'exact badges never turn explanation or an absent match flag into a certainty',
    () {
      expect(hit('a').indicator, SearchIndicator.exact);
      expect(
        SearchHit({'match': 'lemma', 'exact': false}).indicator,
        SearchIndicator.prefix,
      );
      expect(
        SearchHit({'match': 'translation', 'exact': true}).indicator,
        SearchIndicator.translation,
      );
      expect(
        SearchHit({'match': 'explanation', 'exact': true}).indicator,
        isNull,
      );
      expect(SearchHit({'match': 'lemma'}).indicator, isNull);
    },
  );
  test(
    'installed Android reader is preferred with the complete HTTPS URI; fallback is safe',
    () async {
      final uri = scriptureReferences('Ин 3:16').single.uri;
      var fallback = 0;
      Uri? received;
      expect(
        await launchExternalUri(
          uri,
          android: true,
          installed: (u) async {
            received = u;
            return true;
          },
          external: (_) async {
            fallback++;
            return true;
          },
        ),
        true,
      );
      expect(received, uri);
      expect(fallback, 0);
      expect(
        await launchExternalUri(
          uri,
          android: true,
          installed: (_) async => false,
          external: (_) async {
            fallback++;
            return true;
          },
        ),
        true,
      );
      expect(fallback, 1);
      var nativeCalls = 0;
      await launchExternalUri(
        Uri.parse('https://example.org/bible/ioanna/3'),
        android: true,
        installed: (_) async {
          nativeCalls++;
          return true;
        },
        external: (_) async => true,
      );
      expect(nativeCalls, 0);
    },
  );
  testWidgets(
    'a Scripture address split between source runs is clickable and retains its text',
    (tester) async {
      Uri? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScriptureText(
              '',
              spans: const [
                TextSpan(
                  text: 'Ин ',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                TextSpan(text: '3:16'),
              ],
              onOpen: (u) => opened = u,
            ),
          ),
        ),
      );
      final paragraph = tester.widget<SelectableText>(
        find.byType(SelectableText),
      );
      expect(paragraph.textSpan!.toPlainText(), 'Ин 3:16');
      await tester.tapAt(
        tester.getTopLeft(find.byType(SelectableText)) + const Offset(10, 8),
      );
      await tester.pump();
      expect(opened?.fragment, 'v16');
    },
  );
  test(
    'changing the selected word or class discards a stale relation response',
    () async {
      final pending = Completer<http.Response>();
      final repo = DictionaryRepository(
        client: MockClient((_) => pending.future),
      );
      final c = LexicalSearchController(repo);
      c.select(hit('a'));
      final finding = c.find();
      c.selectType('antonym');
      pending.complete(
        jsonResponse({
          'relations': [
            {
              'type': 'synonym',
              'targetId': 'b',
              'targetName': 'другое',
              'status': 'verified',
            },
          ],
        }),
      );
      await finding;
      expect(c.results, isEmpty);
      expect(c.loading, false);
      expect(c.searched, false);
      c.dispose();
      repo.close();
    },
  );
  testWidgets(
    'five suggestions, explicit selection and class search preserve meaning statuses and homonyms',
    (tester) async {
      final requests = <Uri>[];
      final repo = DictionaryRepository(
        client: MockClient((r) async {
          requests.add(r.url);
          if (r.url.path.endsWith('/search')) {
            return jsonResponse({
              'version': 'v',
              'items': List.generate(
                7,
                (i) => {
                  'id': 'id$i',
                  'name': 'слово$i',
                  'match': 'lemma',
                  'exact': true,
                },
              ),
            });
          }
          return jsonResponse({
            'id': 'id0',
            'relations': [
              {
                'type': 'synonym',
                'targetId': 'one',
                'targetName': 'мир',
                'status': 'verified',
                'anchorText': 'покой',
                'targetAnchorText': 'тишина',
              },
              {
                'type': 'synonym',
                'targetId': 'two',
                'targetName': 'мир',
                'status': 'verified',
                'anchorText': 'свет',
                'targetAnchorText': 'вселенная',
              },
              {
                'type': 'synonym',
                'targetId': 'maybe',
                'targetName': 'кандидат',
                'status': 'proposed',
                'anchorText': 'иное',
              },
              {
                'type': 'antonym',
                'targetId': 'anti',
                'targetName': 'противное',
                'status': 'verified',
              },
            ],
          });
        }),
      );
      final personal = PersonalStore(MemoryPreferences());
      await personal.initialized;
      final c = LexicalSearchController(repo);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LexicalSearchView(
              controller: c,
              personal: personal,
              open: (_) {},
            ),
          ),
        ),
      );
      await tester.enterText(find.byKey(const Key('lexical-query')), 'слово');
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      expect(c.candidates.length, 5);
      expect(requests.first.queryParameters['limit'], '5');
      await tester.tap(find.text('слово0'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Найти'));
      await tester.tap(find.text('Найти'));
      await tester.pumpAndSettle();
      expect(requests.last.queryParameters['view'], 'relations');
      expect(c.results.length, 3);
      expect(c.results.where((r) => r.name == 'мир').length, 2);
      expect(c.results.last.proposed, true);
      expect(c.results.first.evidence.first['anchorText'], isNotEmpty);
      await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Антонимы').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Найти'));
      await tester.pumpAndSettle();
      expect(c.results.single.id, 'anti');

      await tester.pumpWidget(const SizedBox());
      c.dispose();
      repo.close();
    },
  );
}
