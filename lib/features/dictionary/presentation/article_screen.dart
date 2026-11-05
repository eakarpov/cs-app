import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/personal_store.dart';
import '../data/dictionary_repository.dart';
import '../domain/models.dart';
import '../domain/grammar_labels.dart';
import 'resource_screen.dart';
import 'report_dialog.dart';

class ArticleScreen extends StatefulWidget {
  const ArticleScreen({
    super.key,
    required this.id,
    required this.repository,
    required this.personal,
    this.lookup,
    this.matched,
    this.grammar,
  });
  final String id;
  final String? matched, grammar;
  final DictionaryRepository repository;
  final PersonalStore personal;
  final void Function(String)? lookup;
  @override
  State<ArticleScreen> createState() => _ArticleScreenState();
}

class _ArticleScreenState extends State<ArticleScreen> {
  late Future<WordArticle> future;
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    future = widget.repository.article(widget.id).then((a) {
      widget.personal.opened(SavedWord(a.id, a.name));
      return a;
    });
  }

  void openArticle(String id) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => ArticleScreen(
        id: id,
        repository: widget.repository,
        personal: widget.personal,
        lookup: lookupWord,
      ),
    ),
  );
  Future<void> lookupWord(String word) async {
    try {
      final result = await widget.repository.search(
        word.replaceFirst(RegExp(r'_\d+$'), ''),
        'cu-ru',
      );
      if (!mounted) return;
      if (result.items.length == 1) {
        openArticle(result.items.first.id);
        return;
      }
      final selected = await showModalBottomSheet<String>(
        context: context,
        builder: (context) => SafeArea(
          child: result.items.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Подходящая статья пока не найдена.'),
                )
              : ListView(
                  shrinkWrap: true,
                  children: result.items
                      .map(
                        (hit) => ListTile(
                          title: Text(
                            hit.name,
                            style: const TextStyle(fontFamily: 'Monomakh'),
                          ),
                          subtitle: Text(
                            hit.grammar.isEmpty ? hit.matchLabel : hit.grammar,
                          ),
                          onTap: () => Navigator.pop(context, hit.id),
                        ),
                      )
                      .toList(),
                ),
        ),
      );
      if (selected != null && mounted) openArticle(selected);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Widget wordForm(WordForm f) {
    final size = widget.personal.fontSize;
    final segments = f.segments;
    final shape = widget.personal.highlightEndings && segments != null
        ? Text.rich(
            TextSpan(
              children: segments
                  .map(
                    (s) => TextSpan(
                      text: string(s['text']).isEmpty && s['kind'] == 'ending'
                          ? '∅'
                          : string(s['text']),
                      style: TextStyle(
                        color: s['kind'] == 'ending'
                            ? Theme.of(context).colorScheme.primary
                            : null,
                        decoration: s['kind'] == 'ending'
                            ? TextDecoration.underline
                            : null,
                      ),
                    ),
                  )
                  .toList(),
            ),
            style: TextStyle(fontFamily: 'Monomakh', fontSize: size),
          )
        : Text(
            f.value,
            style: TextStyle(fontFamily: 'Monomakh', fontSize: size),
          );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Tooltip(
            message: f.provenance.isEmpty
                ? 'Происхождение не установлено'
                : '${f.stored ? '' : 'На основании схемы: '}${f.provenance.map((p) => p.label).toSet().join('\n')}',
            child: shape,
          ),
          Text(
            f.stored ? 'Из словаря' : 'Расчётная форма',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }

  Widget relations(List<Json> rows, bool proposed) => ExpansionTile(
    key: PageStorageKey('${widget.id}:relations:$proposed'),
    title: Text(proposed ? 'Предположительные связи' : 'Подтверждённые связи'),
    subtitle: proposed
        ? const Text('Машинное сопоставление; требует проверки')
        : null,
    children: rows
        .map(
          (r) => ListTile(
            title: Text(
              string(r['targetName']),
              style: const TextStyle(fontFamily: 'Monomakh'),
            ),
            subtitle: Text(
              '${r['type'] == 'antonym' ? 'Антоним' : 'Синоним'} · ${string(r['anchorText'])}\n${string(r['basis'])}\nСоответствующее значение: ${string(r['targetAnchorText'])}',
            ),
            trailing: r['sourceId'] is String
                ? PopupMenuButton<String>(
                    tooltip: 'Источники связи',
                    icon: const Icon(Icons.menu_book_outlined),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: string(r['sourceId']),
                        child: const Text('Значение этого слова'),
                      ),
                      if (r['targetSourceId'] is String)
                        PopupMenuItem(
                          value: string(r['targetSourceId']),
                          child: const Text('Значение связанного слова'),
                        ),
                    ],
                    onSelected: (id) => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => ResourceScreen(
                          repository: widget.repository,
                          id: id,
                          size: widget.personal.fontSize,
                          lookup: lookupWord,
                        ),
                      ),
                    ),
                  )
                : null,
            onTap: () => openArticle(string(r['targetId'])),
          ),
        )
        .toList(),
  );

  Future<void> information(WordArticle a) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .8,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Источники и пометы',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const ListTile(
              title: Text('Извод: русский синодальный'),
              subtitle: Text(
                'Другие исторические свидетельства различаются по источникам.',
              ),
            ),
            ListTile(
              title: const Text('Происхождение лексемы'),
              subtitle: Text(
                a.lexemeOrigins.isEmpty
                    ? 'Происхождение неизвестно'
                    : a.lexemeOrigins.map((p) => p.label).toSet().join('\n'),
              ),
            ),
            ListTile(
              title: const Text('Происхождение схемы'),
              subtitle: Text(
                a.schemeOrigins.isEmpty
                    ? 'Происхождение неизвестно'
                    : a.schemeOrigins.map((p) => p.label).toSet().join('\n'),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Для сведений об источнике отдельной формы нажмите и удерживайте её.',
              ),
            ),
            for (final u in a.usage)
              ListTile(
                title: Text('${string(u['axis'])}: ${string(u['value'])}'),
                subtitle: Text(string(u['evidence'])),
              ),
            for (final source in a.sources)
              ListTile(
                title: Text(source.title),
                subtitle: Text(
                  source.proposed
                      ? 'Сопоставление требует проверки'
                      : 'Сопоставлено по написанию и словарному указателю',
                ),
              ),
            TextButton.icon(
              onPressed: () =>
                  showContentReport(context, widget.repository, id: a.id),
              icon: const Icon(Icons.flag_outlined),
              label: const Text('Сообщить об ошибке'),
            ),
          ],
        ),
      ),
    ),
  );

  Widget sectionList(String key, List<Widget> children) => Builder(
    builder: (context) => CustomScrollView(
      key: PageStorageKey('${widget.id}:$key'),
      slivers: [
        SliverOverlapInjector(
          handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList.list(children: children),
        ),
      ],
    ),
  );

  Widget examples(WordArticle a) => sectionList('examples', [
    const Text('Цитаты из словарей. Сохраняется написание источника.'),
    if (a.examples.isEmpty) ...[
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'Примеры пока не выделены отдельно. Цитаты можно посмотреть в статьях источников.',
        ),
      ),
      for (final source in a.sources)
        ListTile(
          title: Text(source.title),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => openSource(source.id),
        ),
    ],
    for (final example in a.examples)
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                example.quote,
                style: TextStyle(
                  fontFamily: example.church ? 'Monomakh' : 'OldStandard',
                  fontSize: widget.personal.fontSize,
                ),
              ),
              const SizedBox(height: 12),
              Text(example.citation),
              TextButton.icon(
                onPressed: () => openSource(example.sourceId),
                icon: const Icon(Icons.menu_book_outlined),
                label: Text(example.sourceTitle),
              ),
            ],
          ),
        ),
      ),
  ]);

  void openSource(String id) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => ResourceScreen(
        repository: widget.repository,
        id: id,
        size: widget.personal.fontSize,
        lookup: lookupWord,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.personal,
    builder: (context, _) => FutureBuilder<WordArticle>(
      future: future,
      builder: (context, snapshot) {
        final a = snapshot.data;
        final personal = widget.personal;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Словарная статья'),
            actions: [
              IconButton(
                tooltip: 'Источники и пометы',
                icon: const Icon(Icons.info_outline),
                onPressed: a == null ? null : () => information(a),
              ),
            ],
          ),
          body: a == null
              ? Center(
                  child: snapshot.hasError
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(snapshot.error.toString()),
                              FilledButton(
                                onPressed: () => setState(load),
                                child: const Text('Повторить'),
                              ),
                            ],
                          ),
                        )
                      : const CircularProgressIndicator(),
                )
              : DefaultTabController(
                  length: 3,
                  child: SelectionArea(
                    child: NestedScrollView(
                      headerSliverBuilder: (context, innerBoxIsScrolled) => [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        a.name,
                                        style: TextStyle(
                                          fontFamily: 'Monomakh',
                                          fontSize: personal.fontSize + 10,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: personal.isFavorite(a.id)
                                          ? 'Убрать из избранного'
                                          : 'В избранное',
                                      onPressed: personal.ready
                                          ? () => personal.toggle(
                                              SavedWord(a.id, a.name),
                                            )
                                          : null,
                                      icon: Icon(
                                        personal.isFavorite(a.id)
                                            ? Icons.bookmark
                                            : Icons.bookmark_border,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Копировать слово',
                                      onPressed: () => Clipboard.setData(
                                        ClipboardData(text: a.name),
                                      ),
                                      icon: const Icon(Icons.copy_outlined),
                                    ),
                                  ],
                                ),
                                Text(
                                  a.properties.map(propertyLabel).join(' · '),
                                ),
                                if (widget.matched != null)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    child: Text(
                                      'Найденная форма: ${widget.matched}\n${widget.grammar ?? ''}',
                                      style: TextStyle(
                                        fontSize: personal.fontSize,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        SliverOverlapAbsorber(
                          handle:
                              NestedScrollView.sliverOverlapAbsorberHandleFor(
                                context,
                              ),
                          sliver: SliverPersistentHeader(
                            pinned: true,
                            delegate: _ArticleTabs(
                              height:
                                  MediaQuery.textScalerOf(context).scale(16) +
                                  32,
                              color: Theme.of(context).colorScheme.surface,
                            ),
                          ),
                        ),
                      ],
                      body: TabBarView(
                        children: [
                          sectionList('interpretations', [
                            if (a.sources.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Text(
                                  'Для этой статьи пока не подготовлено объяснение из источников. Формы и грамматические сведения доступны во вкладке «Формы».',
                                ),
                              ),
                            for (final source in a.sources)
                              Card(
                                child: ListTile(
                                  title: Text(source.title),
                                  subtitle: Text(
                                    '${source.proposed ? 'Предположительное сопоставление\n' : ''}${source.preview}',
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute<void>(
                                      builder: (_) => ResourceScreen(
                                        repository: widget.repository,
                                        id: source.id,
                                        size: personal.fontSize,
                                        lookup: lookupWord,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            if (a.relatedSources.isNotEmpty)
                              ExpansionTile(
                                key: PageStorageKey('${a.id}:related-sources'),
                                title: const Text(
                                  'Перекрёстные ссылки источника',
                                ),
                                subtitle: const Text(
                                  'Статьи других слов; не являются переводами этого слова',
                                ),
                                children: a.relatedSources
                                    .map(
                                      (source) => ListTile(
                                        title: Text(source.title),
                                        subtitle: Text(source.preview),
                                        onTap: () => Navigator.push(
                                          context,
                                          MaterialPageRoute<void>(
                                            builder: (_) => ResourceScreen(
                                              repository: widget.repository,
                                              id: source.id,
                                              size: personal.fontSize,
                                              lookup: lookupWord,
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            if (a.relations.any(
                              (r) => r['status'] == 'verified',
                            ))
                              relations(
                                a.relations
                                    .where((r) => r['status'] == 'verified')
                                    .toList(),
                                false,
                              ),
                            if (personal.showProposed &&
                                a.relations.any(
                                  (r) => r['status'] == 'proposed',
                                ))
                              relations(
                                a.relations
                                    .where((r) => r['status'] == 'proposed')
                                    .toList(),
                                true,
                              ),
                            if (a.relations.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Text(
                                  'Смысловые связи пока не подготовлены.',
                                ),
                              ),
                            for (final e in a.etymologies)
                              ListTile(
                                title: const Text('Этимология'),
                                subtitle: Text(
                                  'Историческое свидетельство в статье ${string(e['lemma'])}\n${string(e['evidence'])}',
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder: (_) => ResourceScreen(
                                      repository: widget.repository,
                                      id: '',
                                      protoId: (e['articleId'] as num).toInt(),
                                      expectedBodyHash:
                                          e['bodySha256'] as String?,
                                      size: personal.fontSize,
                                    ),
                                  ),
                                ),
                              ),
                          ]),
                          examples(a),
                          sectionList('forms', [
                            const Text(
                              'Подчёркивание обозначает окончание; ∅ — нулевое окончание. Неустановленные границы не выделяются.',
                            ),
                            if (a.morphologyStatus == 'unassigned')
                              const Text(
                                'Парадигма пока не определена. Показаны известные формы.',
                              ),
                            if (a.morphologyStatus == 'notApplicable')
                              const Text('Слово не изменяется.'),
                            for (final p in a.paradigms.where(
                              (p) => p.slots.isNotEmpty,
                            ))
                              ExpansionTile(
                                key: PageStorageKey(
                                  '${a.id}:paradigm:${a.paradigms.indexOf(p)}',
                                ),
                                title: Text(p.title),
                                children: p.slots
                                    .map(
                                      (slot) => Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 6,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(slot.label),
                                                ),
                                                IconButton(
                                                  tooltip:
                                                      'Грамматическая подпись',
                                                  onPressed: () => showDialog<void>(
                                                    context: context,
                                                    builder: (_) => AlertDialog(
                                                      title: const Text(
                                                        'Форма слова',
                                                      ),
                                                      content: Text(
                                                        grammaticalHelp(
                                                          slot.label,
                                                        ),
                                                      ),
                                                      actions: [
                                                        TextButton(
                                                          onPressed: () =>
                                                              Navigator.pop(
                                                                context,
                                                              ),
                                                          child: const Text(
                                                            'Понятно',
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  icon: const Icon(
                                                    Icons.info_outline,
                                                    size: 18,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            ...slot.forms.map(wordForm),
                                          ],
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            if (a.extra.isNotEmpty)
                              ExpansionTile(
                                key: PageStorageKey('${a.id}:extra'),
                                initiallyExpanded: a.paradigms.every(
                                  (p) => p.slots.isEmpty,
                                ),
                                title: const Text('Другие выписанные формы'),
                                children: a.extra
                                    .map(
                                      (f) => ListTile(
                                        title: wordForm(f),
                                        subtitle: Text(f.grammar),
                                      ),
                                    )
                                    .toList(),
                              ),
                            if (a.composition.isNotEmpty)
                              ExpansionTile(
                                key: PageStorageKey('${a.id}:composition'),
                                title: const Text('Состав написания'),
                                children: a.composition
                                    .map(
                                      (c) => ListTile(
                                        title: Text(
                                          string(c['form']),
                                          style: const TextStyle(
                                            fontFamily: 'Monomakh',
                                          ),
                                        ),
                                        subtitle: Text(
                                          '${const {'base': 'основное слово', 'enclitic': 'энклитика', 'particle': 'частица', 'other': 'компонент'}[string(c['role'])] ?? string(c['role'])}${c['lexemeId'] == null ? ' · связь требует уточнения' : ''}',
                                        ),
                                        onTap: c['lexemeId'] is String
                                            ? () => openArticle(
                                                string(c['lexemeId']),
                                              )
                                            : null,
                                      ),
                                    )
                                    .toList(),
                              ),
                          ]),
                        ],
                      ),
                    ),
                  ),
                ),
        );
      },
    ),
  );
}

class _ArticleTabs extends SliverPersistentHeaderDelegate {
  _ArticleTabs({required this.height, required this.color});
  final double height;
  final Color color;
  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => Material(
    color: color,
    child: TabBar(
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      tabs: [
        for (final label in ['Толкования', 'Примеры', 'Формы'])
          Tab(height: height - 2, text: label),
      ],
    ),
  );
  @override
  bool shouldRebuild(covariant _ArticleTabs oldDelegate) =>
      oldDelegate.height != height || oldDelegate.color != color;
}
