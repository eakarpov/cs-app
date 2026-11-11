import 'lexical_search_controller.dart';
import 'lexical_search_view.dart';
import 'package:flutter/material.dart';
import '../../../core/personal_store.dart';
import '../../../core/personal_store_banner.dart';
import '../data/dictionary_repository.dart';
import '../domain/models.dart';
import 'search_controller.dart';
import 'article_screen.dart';
import 'report_dialog.dart';
import 'search_result_heading.dart';
import 'project_pages.dart';
import 'cs_keyboard.dart';
import 'settings_screen.dart';
import 'personal_screens.dart';
import '../../encyclopedia/presentation/encyclopedia_screen.dart';

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
  late final lexical = LexicalSearchController(widget.repository);
  final text = TextEditingController();
  int tab = 0;
  @override
  void dispose() {
    search.dispose();
    lexical.dispose();
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

  Future<void> keyboard() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final before = text.text;
    final submit = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CsKeyboard(controller: text),
    );
    if (mounted && (submit == true || text.text != before)) {
      search.change(text.text, immediate: true);
    }
  }

  void settings() => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => SettingsScreen(personal: widget.personal),
    ),
  );

  void profile() => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) =>
          ProfileScreen(personal: widget.personal, open: (id) => open(id)),
    ),
  );

  void history() => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) =>
          HistoryScreen(personal: widget.personal, open: (id) => open(id)),
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
                direction:
                    MediaQuery.sizeOf(context).width < 600 &&
                        MediaQuery.textScalerOf(context).scale(14) > 18
                    ? Axis.vertical
                    : Axis.horizontal,
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
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (search.direction == 'cu-ru')
                        IconButton(
                          tooltip: 'Клавиатура ЦС',
                          onPressed: keyboard,
                          icon: const Icon(Icons.keyboard_alt_outlined),
                        ),
                      IconButton(
                        tooltip: 'Очистить',
                        onPressed: () {
                          text.clear();
                          search.change('');
                        },
                        icon: const Icon(Icons.clear),
                      ),
                    ],
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
                      title: SearchResultHeading(
                        hit: hit,
                        size: widget.personal.fontSize,
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
        title: Text(
          const ['Словарь', 'Связи', 'Энциклопедия'][tab],
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (tab == 0)
            IconButton(
              tooltip: 'История',
              onPressed: widget.personal.ready ? history : null,
              icon: const Icon(Icons.history),
            ),
          IconButton(
            tooltip: 'Профиль',
            onPressed: widget.personal.ready ? profile : null,
            icon: const Icon(Icons.person_outline),
          ),
          IconButton(
            tooltip: 'Настройки',
            onPressed: widget.personal.ready ? settings : null,
            icon: const Icon(Icons.settings_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: 'Меню проекта',
            onSelected: (value) => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => value == 'about'
                    ? const ProjectAboutScreen()
                    : const UsefulResourcesScreen(),
              ),
            ),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'about', child: Text('О проекте')),
              PopupMenuItem(
                value: 'resources',
                child: Text('Полезные ресурсы'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          PersonalStoreBanner(personal: widget.personal),
          Expanded(
            child: !widget.personal.ready
                ? const Center(child: CircularProgressIndicator())
                : switch (tab) {
                    1 => LexicalSearchView(
                      controller: lexical,
                      personal: widget.personal,
                      open: (id) => open(id),
                    ),
                    2 => EncyclopediaHome(textSize: widget.personal.fontSize),
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
          NavigationDestination(icon: Icon(Icons.hub_outlined), label: 'Связи'),
          NavigationDestination(
            icon: Icon(Icons.auto_stories_outlined),
            label: 'Энциклопедия',
          ),
        ],
      ),
    ),
  );
}
