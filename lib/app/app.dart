import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../core/personal_store.dart';
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
      title: 'Церковнославянский словарь',
      debugShowCheckedModeBanner: false,
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
      home: DictionaryScreen(repository: repository, personal: personal),
    ),
  );
}
