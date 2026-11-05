import 'package:flutter/material.dart';
import '../../../core/personal_store.dart';
import '../data/dictionary_repository.dart';
import '../domain/models.dart';
import 'search_controller.dart';
import 'article_screen.dart';
import 'report_dialog.dart';

class DictionaryScreen extends StatefulWidget {
  const DictionaryScreen({
    super.key,
    required this.repository,
    required this.personal,
  });
  final DictionaryRepository repository;
  final PersonalStore personal;
  @override
  State<DictionaryScreen> createState() => _DictionaryScreenState();
}

class _DictionaryScreenState extends State<DictionaryScreen> {
  late final WordSearchController search = WordSearchController(
    widget.repository,
  );
  final text = TextEditingController();
  int tab = 0;
  @override
  void dispose() {
    search.dispose();
    text.dispose();
    super.dispose();
  }

  void lookup(String word) {
    Navigator.of(context).popUntil((r) => r.isFirst);
    setState(() => tab = 0);
    text.text = word;
    search.change(word, mode: 'cu-ru', immediate: true);
  }

  void open(String id, {SearchHit? hit}) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => ArticleScreen(
        id: id,
        matched: hit?.matched,
        grammar: hit?.grammar,
        repository: widget.repository,
        personal: widget.personal,
        lookup: lookup,
      ),
    ),
  );
  void insert(String value) {
    final selection = text.selection;
    final start = selection.isValid ? selection.start : text.text.length,
        end = selection.isValid ? selection.end : text.text.length;
    text.value = TextEditingValue(
      text: text.text.replaceRange(start, end, value),
      selection: TextSelection.collapsed(offset: start + value.length),
    );
    search.change(text.text);
  }

  void settings() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ListenableBuilder(
        listenable: widget.personal,
        builder: (context, _) => Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Настройки'),
                DropdownButton<ThemeMode>(
                  value: widget.personal.themeMode,
                  items: const [
                    DropdownMenuItem(
                      value: ThemeMode.system,
                      child: Text('Как в системе'),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.light,
                      child: Text('Светлая тема'),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.dark,
                      child: Text('Тёмная тема'),
                    ),
                  ],
                  onChanged: (v) => widget.personal.settings(theme: v),
                ),
                Text('Размер текста: ${widget.personal.fontSize.round()}'),
                Slider(
                  value: widget.personal.fontSize,
                  min: 16,
                  max: 36,
                  divisions: 20,
                  onChanged: (v) => widget.personal.settings(size: v),
                ),
                SwitchListTile(
                  title: const Text('Выделять окончания'),
                  value: widget.personal.highlightEndings,
                  onChanged: (v) => widget.personal.settings(endings: v),
                ),
                SwitchListTile(
                  title: const Text('Показывать предположительные связи'),
                  value: widget.personal.showProposed,
                  onChanged: (v) => widget.personal.settings(proposed: v),
                ),
                TextButton(
                  onPressed: () => widget.personal.clearHistory(),
                  child: const Text('Очистить историю'),
                ),
                const Text(
                  'Приложение работает при наличии сети. Избранное, история и настройки хранятся на этом устройстве.',
                ),
                TextButton(
                  onPressed: () => showLicensePage(
                    context: context,
                    applicationName: 'ЦС Словарь',
                    applicationVersion: '0.1.0',
                  ),
                  child: const Text('Лицензии'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  Widget saved(List<SavedWord> words, String empty) => words.isEmpty
      ? Center(child: Text(empty))
      : ListView.builder(
          itemCount: words.length,
          itemBuilder: (context, i) => ListTile(
            title: Text(
              words[i].name,
              style: TextStyle(
                fontFamily: 'Monomakh',
                fontSize: widget.personal.fontSize,
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => open(words[i].id),
          ),
        );
  Widget searchView() => ListenableBuilder(
    listenable: search,
    builder: (context, _) => Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'cu-ru',
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('ЦС'),
                        Icon(Icons.arrow_forward, size: 14),
                        Text('русский'),
                      ],
                    ),
                  ),
                  ButtonSegment(
                    value: 'ru-cu',
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Русский'),
                        Icon(Icons.arrow_forward, size: 14),
                        Text('ЦС'),
                      ],
                    ),
                  ),
                ],
                selected: {search.direction},
                onSelectionChanged: (v) =>
                    search.change(text.text, mode: v.first, immediate: true),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: text,
                style: TextStyle(
                  fontFamily: search.direction == 'cu-ru' ? 'Monomakh' : null,
                  fontSize: 22,
                ),
                onChanged: search.change,
                onSubmitted: (v) => search.change(v, immediate: true),
                maxLength: 120,
                decoration: InputDecoration(
                  labelText: search.direction == 'cu-ru'
                      ? 'Слово или словоформа'
                      : 'Русское слово или выражение',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    tooltip: 'Очистить',
                    onPressed: () {
                      text.clear();
                      search.change('');
                    },
                    icon: const Icon(Icons.clear),
                  ),
                ),
              ),
              if (search.direction == 'cu-ru')
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children:
                        [
                              'ѣ',
                              'і',
                              'ѳ',
                              'ѵ',
                              'ѡ',
                              'ꙋ',
                              'ѧ',
                              'ꙗ',
                              'ѿ',
                              '҃',
                              '́',
                              '҆',
                            ]
                            .map(
                              (s) => TextButton(
                                onPressed: () => insert(s),
                                child: Text(
                                  const {
                                        '҃': 'титло',
                                        '́': 'ударение',
                                        '҆': 'звательце',
                                      }[s] ??
                                      s,
                                  style: TextStyle(
                                    fontFamily: ['҃', '́', '҆'].contains(s)
                                        ? null
                                        : 'Monomakh',
                                    fontSize: ['҃', '́', '҆'].contains(s)
                                        ? 14
                                        : 24,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                  ),
                ),
            ],
          ),
        ),
        if (search.loading) const LinearProgressIndicator(),
        if (search.error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Text(search.error!),
                TextButton(
                  onPressed: search.retry,
                  child: const Text('Повторить'),
                ),
              ],
            ),
          ),
        Expanded(
          child: search.items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          search.query.isEmpty
                              ? 'Найдите слово, его значение и формы.'
                              : search.loading
                              ? 'Ищем…'
                              : search.error != null
                              ? 'Для поиска нужен доступ к сети.'
                              : 'По этому запросу ничего не найдено.',
                        ),
                        if (search.query.isNotEmpty && !search.loading)
                          TextButton(
                            onPressed: () => showContentReport(
                              context,
                              widget.repository,
                              query: search.query,
                            ),
                            child: const Text('Сообщить о недостающем слове'),
                          ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount:
                      search.items.length + (search.nextCursor != null ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i == search.items.length) {
                      return TextButton(
                        onPressed: search.loading ? null : search.more,
                        child: const Text('Показать ещё'),
                      );
                    }
                    final hit = search.items[i];
                    return ListTile(
                      title: Text(
                        hit.name,
                        style: TextStyle(
                          fontFamily: 'Monomakh',
                          fontSize: widget.personal.fontSize,
                        ),
                      ),
                      subtitle: Text(
                        '${hit.matchLabel}\n${hit.matched}${hit.grammar.isEmpty ? '' : ' · ${hit.grammar}'}',
                      ),
                      isThreeLine: true,
                      onTap: () => open(hit.id, hit: hit),
                    );
                  },
                ),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.personal,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: Text(['Словарь', 'Избранное', 'История'][tab]),
        actions: [
          IconButton(
            tooltip: 'Настройки',
            onPressed: widget.personal.ready ? settings : null,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          if (widget.personal.error != null)
            MaterialBanner(
              content: Text(widget.personal.error!),
              actions: [
                TextButton(
                  onPressed: widget.personal.retryPersistence,
                  child: const Text('Повторить'),
                ),
              ],
            ),
          Expanded(
            child: !widget.personal.ready
                ? const Center(child: CircularProgressIndicator())
                : switch (tab) {
                    1 => saved(
                      widget.personal.favorites,
                      'В избранном пока нет слов.',
                    ),
                    2 => saved(
                      widget.personal.history,
                      'Открытые статьи появятся здесь.',
                    ),
                    _ => searchView(),
                  },
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.search), label: 'Словарь'),
          NavigationDestination(
            icon: Icon(Icons.bookmark_outline),
            label: 'Избранное',
          ),
          NavigationDestination(icon: Icon(Icons.history), label: 'История'),
        ],
      ),
    ),
  );
}
