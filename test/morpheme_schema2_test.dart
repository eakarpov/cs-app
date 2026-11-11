import 'dart:convert';
import 'dart:io';
import 'package:cs/features/dictionary/domain/morphemes.dart';
import 'package:cs/features/dictionary/presentation/morphemes_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'morphemes_test.dart' as fixtures;

Map<String, dynamic> example() =>
    jsonDecode(
          File(
            'docs/morphemes/contracts/morpheme-inf.example.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;
void main() {
  test(
    'orders explicit dependencies, preserves shared inputs and comparison',
    () {
      final c = example();
      final e = c['etymology'] as Map<String, dynamic>;
      final r = (e['relations'] as List).first as Map<String, dynamic>;
      final a = {
        ...r,
        'id': 'a',
        'fromNodeIds': ['old'],
        'toNodeId': 'middle',
      };
      final b = {
        ...r,
        'id': 'b',
        'fromNodeIds': ['middle', 'other'],
        'toNodeId': 'new',
      };
      e['relations'] = [b, a];
      final model = MorphemeCard(c);
      final ordered = model.etymology.orderedRelations({
        'relationIds': ['b', 'a'],
      });
      expect(ordered.map((r) => r['id']), ['a', 'b']);
      expect(ordered.last['fromNodeIds'], ['middle', 'other']);
      e['relations'] = [
        {
          ...a,
          'fromNodeIds': ['new'],
        },
        b,
      ];
      expect(
        () => MorphemeCard(c).etymology.orderedRelations({
          'relationIds': ['b', 'a'],
        }),
        throwsFormatException,
      );
    },
  );
  testWidgets(
    'composition keeps one component per rectangle in white card and history reveals evidence',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = example();
      c['version'] = 'v1';
      final repo = fixtures.repository((r) async {
        if (r.url.path.endsWith('/words')) {
          return fixtures.response({
            'version': 'v1',
            'total': 0,
            'items': [],
            'nextCursor': null,
          });
        }
        expect(r.url.queryParameters['schema'], '2');
        return fixtures.response(c);
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: MorphemeScreen(
            id: c['id'],
            version: 'v1',
            repository: repo,
            openWord: (_) {},
            fontSize: 22,
            initialTab: 1,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scheme = find.byKey(
        const ValueKey('composition-scheme-ETYM-INF-NOMINAL'),
      );
      expect(scheme, findsOneWidget);
      expect(tester.widget<Card>(scheme).color, Colors.white);
      expect(
        find.descendant(of: scheme, matching: find.text('т')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: scheme, matching: find.text('и')),
        findsOneWidget,
      );
      for (
        var i = 0;
        i < 8 &&
            find
                .descendant(of: scheme, matching: find.text('и'))
                .hitTestable()
                .evaluate()
                .isEmpty;
        i++
      ) {
        await tester.drag(find.byType(NestedScrollView), const Offset(0, -120));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.descendant(of: scheme, matching: find.text('и')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Вокализм всей исторической формы.'),
        findsOneWidget,
      );
      for (
        var i = 0;
        i < 12 &&
            find
                .text('Дательный ед. ч. → инфинитив')
                .hitTestable()
                .evaluate()
                .isEmpty;
        i++
      ) {
        await tester.drag(find.byType(NestedScrollView), const Offset(0, -260));
        await tester.pumpAndSettle();
      }
      expect(
        find.text('Дательный ед. ч. → инфинитив').hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.text('Дательный ед. ч. → инфинитив'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Точный праиндоевропейский вокализм'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      repo.close();
    },
  );
  testWidgets('unstructured history is text, never synthesized into a chain', (
    tester,
  ) async {
    final c = fixtures.card();
    c['etymology'] = {
      'state': 'partial',
      'nodes': [],
      'relations': [],
      'chains': [],
      'notes': [
        {
          'id': 'n',
          'title': 'Старое описание',
          'text': 'Точная форма дꙋ́ша',
          'status': 'disputed',
          'evidence': [],
          'target': null,
        },
      ],
    };
    final repo = fixtures.repository(
      (r) async => fixtures.response(
        r.url.path.endsWith('/words')
            ? {'version': 'v1', 'total': 0, 'items': [], 'nextCursor': null}
            : c,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MorphemeScreen(
          id: 'root:KAJ',
          version: 'v1',
          repository: repo,
          openWord: (_) {},
          fontSize: 22,
          initialTab: 1,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Историческое описание. Последовательность этапов пока не задана.',
      ),
      findsOneWidget,
    );
    expect(find.text('Точная форма дꙋ́ша'), findsOneWidget);
    expect(find.text('Спорный разбор'), findsOneWidget);
    expect(find.text('┊\n↓'), findsNothing);
    repo.close();
  });
}
