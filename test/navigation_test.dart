import 'dart:convert';
import 'dart:io';
import 'package:cs/app/app.dart';
import 'package:cs/core/personal_store.dart';
import 'package:cs/features/dictionary/data/dictionary_repository.dart';
import 'package:cs/features/dictionary/domain/models.dart';
import 'package:cs/features/dictionary/presentation/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dictionary_test.dart' show MemoryPreferences;

Finder destination(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

void main() {
  // Ahem replaces Cyrillic glyphs with wide boxes; use the Android UI font to
  // check whether the complete navigation labels fit on phone screens.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final flutterRoot = Platform.environment['FLUTTER_ROOT']!;
    final loader = FontLoader('Roboto')
      ..addFont(
        File(
          '$flutterRoot/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
        ).readAsBytes().then(ByteData.sublistView),
      );
    await loader.load();
  });
  testWidgets('profile and dictionary history preserve search and saved data', (
    tester,
  ) async {
    final personal = PersonalStore(MemoryPreferences());
    await personal.initialized;
    await personal.toggle(const SavedWord('favorite', 'Любимое слово'));
    await personal.opened(const SavedWord('recent', 'Недавнее слово'));
    final requests = <Uri>[];
    final repository = DictionaryRepository(
      client: MockClient((request) async {
        requests.add(request.url);
        final search = request.url.path.endsWith('/search');
        return http.Response(
          jsonEncode(
            search
                ? {'version': 'v', 'items': []}
                : {'id': 'favorite', 'name': 'Любимое слово'},
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    addTearDown(repository.close);
    await tester.pumpWidget(
      ChurchSlavonicApp(repository: repository, personal: personal),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).title,
      'Лексикон ЦС',
    );
    expect(
      tester
          .widgetList<NavigationDestination>(find.byType(NavigationDestination))
          .map((d) => d.label),
      ['Словарь', 'Связи', 'Энциклопедия'],
    );
    await tester.enterText(find.byType(TextField), 'сохранённый запрос');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('История'));
    await tester.pumpAndSettle();
    expect(find.text('Недавнее слово'), findsOneWidget);
    expect(find.text('Любимое слово'), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(find.byTooltip('Очистить историю'));
    await tester.pumpAndSettle();
    expect(find.text('Открытые статьи появятся здесь.'), findsOneWidget);
    expect(personal.favorites.single.id, 'favorite');
    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Профиль'));
    await tester.pumpAndSettle();
    expect(find.text('Избранное'), findsOneWidget);
    expect(find.text('Любимое слово'), findsOneWidget);
    await tester.tap(find.text('Любимое слово'));
    await tester.pumpAndSettle();
    expect(requests.last.path, endsWith('/lexemes/favorite'));
    await tester.tap(find.byTooltip('Убрать из избранного'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();
    expect(find.text('В избранном пока нет слов.'), findsOneWidget);
    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(TextField, 'сохранённый запрос'),
      findsOneWidget,
    );
    expect(requests.length, 2);

    for (final label in ['Связи', 'Энциклопедия']) {
      await tester.tap(destination(label));
      await tester.pumpAndSettle();
      expect(find.byTooltip('История'), findsNothing);
      expect(find.byTooltip('Профиль'), findsOneWidget);
      expect(find.byTooltip('Настройки'), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'settings is a full page and changes persist without switching sections',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final prefs = MemoryPreferences();
      final personal = PersonalStore(prefs);
      await personal.initialized;
      final repository = DictionaryRepository(
        client: MockClient((_) async => throw StateError('No network needed')),
      );
      addTearDown(repository.close);
      await tester.pumpWidget(
        ChurchSlavonicApp(repository: repository, personal: personal),
      );
      await tester.pumpAndSettle();
      await tester.tap(destination('Энциклопедия'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Настройки'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
      await tester.tap(find.byType(DropdownButton<ThemeMode>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Тёмная тема').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(Slider));
      await tester.drag(find.byType(Slider), const Offset(50, 0));
      await tester.pumpAndSettle();
      expect(personal.fontSize, greaterThan(22));
      await tester.ensureVisible(find.text('Выделять окончания'));
      await tester.tap(find.text('Выделять окончания'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.text('Показывать предположительные связи'),
      );
      await tester.tap(find.text('Показывать предположительные связи'));
      await tester.pumpAndSettle();
      final reloaded = PersonalStore(prefs);
      await reloaded.initialized;
      expect(reloaded.themeMode, ThemeMode.dark);
      expect(reloaded.fontSize, personal.fontSize);
      expect(reloaded.highlightEndings, false);
      expect(reloaded.showProposed, false);
      await tester.tap(find.byTooltip('Назад'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        2,
      );
      expect(find.byTooltip('История'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [320.0, 390.0]) {
    testWidgets('three navigation labels fit one line at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final personal = PersonalStore(MemoryPreferences());
      await personal.initialized;
      final repository = DictionaryRepository();
      addTearDown(repository.close);
      await tester.pumpWidget(
        ChurchSlavonicApp(repository: repository, personal: personal),
      );
      await tester.pumpAndSettle();
      final paragraph = tester.renderObject<RenderParagraph>(
        destination('Энциклопедия'),
      );
      expect(
        paragraph.getBoxesForSelection(
          const TextSelection(baseOffset: 0, extentOffset: 12),
        ),
        hasLength(1),
      );
      await tester.tap(destination('Энциклопедия'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
