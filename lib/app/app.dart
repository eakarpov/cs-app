import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../core/personal_store.dart';
import '../features/reader/domain/reader_link.dart';
import '../features/reader/presentation/reader_link_screen.dart';
import '../features/dictionary/data/dictionary_repository.dart';
import '../features/dictionary/presentation/dictionary_screen.dart';

class ChurchSlavonicApp extends StatelessWidget {
  const ChurchSlavonicApp({
    super.key,
    required this.repository,
    required this.personal,
  });
  final DictionaryRepository repository;
  final PersonalStore personal;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: personal,
    builder: (context, _) => MaterialApp(
      title: 'Лексикон ЦС',
      debugShowCheckedModeBanner: false,
      builder: const bool.fromEnvironment('CS_PREVIEW')
          ? (context, child) => Banner(
              message: 'ПРОВЕРКА',
              location: BannerLocation.topEnd,
              child: child!,
            )
          : null,
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      themeMode: personal.themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
      ),
      onGenerateRoute: (settings) {
        final url = readerLink(settings.name);
        if (url == null) return null;
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => ReaderLinkScreen(
            url: url,
            dictionary: repository,
            personal: personal,
          ),
        );
      },
      home: DictionaryScreen(
        repository: repository,
        personal: personal,
        initialQuery: const bool.fromEnvironment('CS_PREVIEW')
            ? const String.fromEnvironment(
                'CS_PREVIEW_QUERY',
                defaultValue: 'презвитер',
              )
            : null,
      ),
    ),
  );
}
