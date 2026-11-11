import 'package:flutter/material.dart';
import '../../../core/personal_store.dart';
import '../../../core/personal_store_banner.dart';
import '../domain/models.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.personal, required this.open});
  final PersonalStore personal;
  final ValueChanged<String> open;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: personal,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('Профиль')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PersonalStoreBanner(personal: personal),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text(
              'Избранное',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Expanded(
            child: SavedWordsView(
              words: personal.favorites,
              empty: 'В избранном пока нет слов.',
              fontSize: personal.fontSize,
              open: open,
            ),
          ),
        ],
      ),
    ),
  );
}

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key, required this.personal, required this.open});
  final PersonalStore personal;
  final ValueChanged<String> open;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: personal,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: const Text('История'),
        actions: [
          IconButton(
            tooltip: 'Очистить историю',
            onPressed: personal.ready && personal.history.isNotEmpty
                ? personal.clearHistory
                : null,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Column(
        children: [
          PersonalStoreBanner(personal: personal),
          Expanded(
            child: SavedWordsView(
              words: personal.history,
              empty: 'Открытые статьи появятся здесь.',
              fontSize: personal.fontSize,
              open: open,
            ),
          ),
        ],
      ),
    ),
  );
}

class SavedWordsView extends StatelessWidget {
  const SavedWordsView({
    super.key,
    required this.words,
    required this.empty,
    required this.fontSize,
    required this.open,
  });
  final List<SavedWord> words;
  final String empty;
  final double fontSize;
  final ValueChanged<String> open;

  @override
  Widget build(BuildContext context) => words.isEmpty
      ? Center(
          child: Padding(padding: const EdgeInsets.all(24), child: Text(empty)),
        )
      : ListView.builder(
          itemCount: words.length,
          itemBuilder: (context, i) => ListTile(
            title: Text(
              words[i].name,
              style: TextStyle(fontFamily: 'Monomakh', fontSize: fontSize),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => open(words[i].id),
          ),
        );
}
