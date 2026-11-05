import 'package:flutter/material.dart';

import '../features/dictionary/presentation/dictionary_screen.dart';

class ChurchSlavonicApp extends StatelessWidget {
  const ChurchSlavonicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Церковнославянский словарь',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
      ),
      home: const DictionaryScreen(),
    );
  }
}
