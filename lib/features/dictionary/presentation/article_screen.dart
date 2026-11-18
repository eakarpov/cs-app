import '../../scripture/presentation/scripture_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/personal_store.dart';
import '../data/dictionary_repository.dart';
import '../domain/models.dart';
import '../domain/form_presentation.dart';
import 'forms_view.dart';
import '../../reader/presentation/corpus_screen.dart';
import 'resource_screen.dart';
import 'retry_button.dart';
import 'report_dialog.dart';
import 'morphemes_view.dart';
import 'dictionary_screen.dart';
import 'form_information.dart';

class ArticleScreen extends StatefulWidget {
  const ArticleScreen({
    super.key,
    required this.id,
    required this.repository,
    required this.personal,
    this.lookup,
    this.matched,
    this.grammar,
    this.match,
    this.dictionaryVersion,
    this.dictionarySchema = 2,
  });
  final String id;
  final String? matched, grammar;
  final String? match, dictionaryVersion;
  final int dictionarySchema;
  final DictionaryRepository repository;
  final PersonalStore personal;
  final void Function(String)? lookup;
  @override
  State<ArticleScreen> createState() => _ArticleScreenState();
}

class _ArticleScreenState extends State<ArticleScreen> {
  late Future<WordArticle> future;
  String? pinnedVersion;
  int profile = 2;
  WordArticle? loadedArticle;
  WordForm? selectedForm;
  bool useLookupContext = true;
  String get scopeKey =>
      '${widget.id}:${loadedArticle?.version ?? pinnedVersion ?? 'latest'}';

  @override
  void initState() {
    super.initState();
    pinnedVersion = widget.dictionaryVersion;
    profile = widget.dictionarySchema;
    load();
  }

  void load() {
    future = widget.repository
        .article(widget.id, version: pinnedVersion, schema: profile)
        .then((a) {
          if (loadedArticle?.version != a.version) selectedForm = null;
          loadedArticle = a;
          final matches = uniqueForms(
            a.allForms.where(
              (f) =>
                  useLookupContext &&
                  !{'translation', 'explanation'}.contains(widget.match) &&
                  f.value == widget.matched,
            ),
          );
          if (selectedForm == null && matches.length == 1) {
            selectedForm = matches.single;
          }
          profile = a.schemaVersion;
          pinnedVersion = profile == 2 ? a.version : null;
          widget.personal.opened(SavedWord(a.id, a.name));
          return a;
        });
    // Retry can fail before FutureBuilder subscribes on the next frame.
    // Mark the error handled without changing the future seen by the view.
    future.ignore();
  }

  void openArticle(String id) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => ArticleScreen(
        id: id,
        dictionaryVersion: pinnedVersion,
        dictionarySchema: profile,
        repository: widget.repository,
        personal: widget.personal,
        lookup: lookupWord,
      ),
    ),
  );
  Future<void> lookupWord(String word) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => DictionaryScreen(
          repository: widget.repository,
          personal: widget.personal,
          initialQuery: word.replaceFirst(RegExp(r'_\d+$'), ''),
          nestedLookup: true,
        ),
      ),
    );
  }

  void showFormDetails(WordForm f) {
    setState(() => selectedForm = f);
    showFormInformation(
      context,
      f,
      fontSize: widget.personal.fontSize,
      openSource: (id, revision) => openSource(
        id,
        sourceVersion: revision,
        wordName: f.value,
        mappingLabel: 'Свидетельство формы',
      ),
    );
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
    final selected = selectedForm?.selectionKey == f.selectionKey;

    return Semantics(
      selected: selected,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        decoration: BoxDecoration(
          border: selected
              ? Border.all(color: Theme.of(context).colorScheme.primary)
              : null,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onLongPress: () => showFormDetails(f),
              child: shape,
            ),
            Tooltip(
              message: 'Сведения о форме: ${f.value}',
              child: TextButton.icon(
                onPressed: () => showFormDetails(f),
                icon: const Icon(Icons.info_outline, size: 18),
                label: const Text('Сведения о форме'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget relations(List<Json> rows, bool proposed) => ExpansionTile(
    key: PageStorageKey('$scopeKey:relations:$proposed'),
    title: Text(proposed ? 'Предположительные связи' : 'Подтверждённые связи'),
    subtitle: proposed
        ? const Text('Связь требует проверки; основание указано ниже')
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
                    onSelected: (id) => openSource(
                      id,
                      wordName: id == r['targetSourceId']
                          ? string(r['targetName'])
                          : loadedArticle?.name,
                      mappingLabel: 'Основание смысловой связи',
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
            ListTile(
              title: Text(
                a.izvod.isEmpty
                    ? 'Извод не указан'
                    : 'Извод: ${a.izvod == 'russian-synodal' ? 'русский синодальный' : a.izvod}',
              ),
              subtitle: const Text(
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
                'Используйте действие «Сведения о форме» рядом с нужным написанием.',
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
                subtitle: Text(source.mappingLabel),
                onTap: () => openSource(source.id),
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

  Widget sectionList(String key, List<Widget> children) => _KeepArticleSection(
    key: ValueKey('$scopeKey:$key'),
    child: Builder(
      builder: (context) => CustomScrollView(
        key: PageStorageKey('$scopeKey:$key'),
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
    ),
  );

  Widget examples(WordArticle a) => sectionList('examples', [
    const Text('Цитаты из словарей. Сохраняется написание источника.'),
    if (a.examples.isEmpty) ...[
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          a.sources.isEmpty
              ? 'Примеры пока не выделены отдельно.'
              : 'Примеры пока не выделены отдельно. Цитаты можно посмотреть в статьях источников.',
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
              ScriptureText(
                example.quote,
                style: TextStyle(
                  fontFamily: example.church ? 'Monomakh' : 'OldStandard',
                  fontSize: widget.personal.fontSize,
                ),
              ),
              const SizedBox(height: 12),
              ScriptureText(example.citation),
              TextButton.icon(
                onPressed: () => openSource(
                  example.sourceId,
                  sourceVersion: example.sourceVersion.isEmpty
                      ? null
                      : example.sourceVersion,
                ),
                icon: const Icon(Icons.menu_book_outlined),
                label: Text(example.sourceTitle),
              ),
            ],
          ),
        ),
      ),
  ]);

  void openSource(
    String id, {
    String? sourceVersion,
    String? mappingLabel,
    String? wordName,
  }) {
    final matches = [
      ...?loadedArticle?.sources,
      ...?loadedArticle?.relatedSources,
    ].where((s) => s.id == id).toList();
    final source = matches.length == 1 ? matches.single : null;
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ResourceScreen(
          dictionaryVersion: pinnedVersion,
          dictionarySchema: profile,
          repository: widget.repository,
          id: id,
          size: widget.personal.fontSize,
          lookup: lookupWord,
          wordName: wordName ?? loadedArticle?.name,
          mappingLabel: mappingLabel ?? source?.mappingLabel,
          expectedSourceVersion:
              sourceVersion ??
              (source?.sourceVersion.isNotEmpty == true
                  ? source!.sourceVersion
                  : null),
        ),
      ),
    );
  }

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
                              Text(
                                snapshot.error is DictionaryException &&
                                        (snapshot.error as DictionaryException)
                                                .status ==
                                            404
                                    ? 'Статья недоступна по сохранённому адресу.'
                                    : snapshot.error.toString(),
                              ),
                              RetryButton(
                                error: snapshot.error,
                                onRetry: () => setState(load),
                              ),
                              if (snapshot.error is DictionaryException &&
                                  (snapshot.error as DictionaryException)
                                          .status ==
                                      409)
                                TextButton(
                                  onPressed: () => setState(() {
                                    useLookupContext = false;
                                    pinnedVersion = null;
                                    profile = 2;
                                    load();
                                  }),
                                  child: const Text('Открыть текущую версию'),
                                ),
                            ],
                          ),
                        )
                      : const CircularProgressIndicator(),
                )
              : DefaultTabController(
                  key: ValueKey(scopeKey),
                  length: 4,
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
                                        WordHeading(a).name,
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
                                      onPressed: personal.canEdit
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
                                        ClipboardData(
                                          text: WordHeading(a).name,
                                        ),
                                      ),
                                      icon: const Icon(Icons.copy_outlined),
                                    ),
                                  ],
                                ),
                                if (WordHeading(a).titloVariants.isNotEmpty)
                                  Text(
                                    WordHeading(a).titloVariants.first,
                                    key: const ValueKey('headword-titlo'),
                                    style: TextStyle(
                                      fontFamily: 'Monomakh',
                                      fontSize: personal.fontSize,
                                    ),
                                  ),
                                OutlinedButton.icon(
                                  onPressed: a.schemaVersion == 2
                                      ? () => Navigator.push<void>(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => CorpusScreen(
                                              dictionary: widget.repository,
                                              personal: personal,
                                              lexemeId: a.id,
                                              dictionaryVersion: a.version,
                                              word:
                                                  selectedForm?.value ?? a.name,
                                            ),
                                          ),
                                        )
                                      : null,
                                  icon: const Icon(Icons.find_in_page_outlined),
                                  label: const Text('Употребления'),
                                ),
                                if (conciseProperties(a).isNotEmpty)
                                  Text(conciseProperties(a)),
                                if (useLookupContext &&
                                    widget.matched != null &&
                                    widget.matched != a.name)
                                  ExpansionTile(
                                    tilePadding: EdgeInsets.zero,
                                    title: Text(
                                      '${widget.match == 'translation' || widget.match == 'explanation' ? 'Найдено по' : 'Найденная форма'}: ${widget.matched}',
                                      style: TextStyle(
                                        fontFamily: 'Monomakh',
                                        fontSize: personal.fontSize,
                                      ),
                                    ),
                                    children: [
                                      if (widget.grammar?.isNotEmpty ?? false)
                                        Text(conciseGrammar(widget.grammar!)),
                                    ],
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
                                  'Для этой статьи пока не подготовлено объяснение из источников.',
                                ),
                              ),
                            if (a.sources.isEmpty && a.hasForms)
                              Builder(
                                builder: (context) => TextButton(
                                  onPressed: () => DefaultTabController.of(
                                    context,
                                  ).animateTo(2),
                                  child: const Text('Открыть формы'),
                                ),
                              ),
                            for (final source in a.sources)
                              Card(
                                child: ListTile(
                                  title: Text(source.title),
                                  subtitle: ScriptureText(
                                    '${source.mappingLabel}\n${source.preview}',
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => openSource(
                                    source.id,
                                    mappingLabel: source.mappingLabel,
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
                                        subtitle: ScriptureText(source.preview),
                                        onTap: () => openSource(
                                          source.id,
                                          mappingLabel:
                                              'Перекрёстная ссылка; не является толкованием этого слова. ${source.mappingLabel}',
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
                            if (!personal.showProposed &&
                                a.relations.any(
                                  (r) => r['status'] == 'proposed',
                                ))
                              const Text(
                                'Предположительные связи скрыты настройкой.',
                              ),
                            if (a.relations.any(
                              (r) => !{
                                'verified',
                                'proposed',
                              }.contains(r['status']),
                            ))
                              const Text(
                                'Есть связи с неустановленным или спорным статусом; подтверждение не задано.',
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
                                      dictionaryVersion: pinnedVersion,
                                      dictionarySchema: profile,
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
                            if (selectedForm != null)
                              TextButton(
                                onPressed: () => showFormDetails(selectedForm!),
                                child: Text(
                                  'Выбрана форма: ${selectedForm!.value}',
                                ),
                              ),
                            WordFormsView(
                              key: ValueKey('$scopeKey:forms'),
                              article: a,
                              formBuilder: wordForm,
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
                          sectionList('morphemes', [
                            WordMorphemesView(
                              initialForm: selectedForm?.value,
                              dictionaryVersion: pinnedVersion,
                              id: a.id,
                              repository: widget.repository,
                              openWord: openArticle,
                              fontSize: personal.fontSize,
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
        for (final label in ['Толкования', 'Примеры', 'Формы', 'Морфемы'])
          Tab(height: height - 2, text: label),
      ],
    ),
  );
  @override
  bool shouldRebuild(covariant _ArticleTabs oldDelegate) =>
      oldDelegate.height != height || oldDelegate.color != color;
}

class _KeepArticleSection extends StatefulWidget {
  const _KeepArticleSection({super.key, required this.child});
  final Widget child;
  @override
  State<_KeepArticleSection> createState() => _KeepArticleSectionState();
}

class _KeepArticleSectionState extends State<_KeepArticleSection>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
