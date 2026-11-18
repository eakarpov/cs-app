import 'package:flutter/material.dart';
import '../../../core/personal_store.dart';
import '../../dictionary/data/dictionary_repository.dart';
import '../../dictionary/presentation/article_screen.dart';
import '../data/reader_repository.dart';
import '../domain/corpus.dart';
import 'corpus_controller.dart';
import 'corpus_widgets.dart';
import 'reader_screen.dart';

class CorpusScreen extends StatefulWidget {
  const CorpusScreen({
    super.key,
    required this.dictionary,
    required this.personal,
    this.lexemeId,
    this.dictionaryVersion,
    this.word,
    this.initialQuery,
  });
  final DictionaryRepository dictionary;
  final PersonalStore personal;
  final String? lexemeId, dictionaryVersion, word, initialQuery;
  @override
  State<CorpusScreen> createState() => _CorpusScreenState();
}

class _CorpusScreenState extends State<CorpusScreen>
    with AutomaticKeepAliveClientMixin {
  late final repository = widget.dictionary.reader;
  late final controller = CorpusController(
    repository,
    lexemeId: widget.lexemeId,
    dictionaryVersion: widget.dictionaryVersion,
  );
  late final text = TextEditingController(text: widget.initialQuery ?? '');
  final urlText = TextEditingController();
  CorpusSession? session;
  final sources = <Wire>[];
  String? catalogCursor;
  Object? catalogError;
  bool catalogBusy = false, searching = false;
  int catalogGeneration = 0;
  final scroll = ScrollController();
  bool get lemma => widget.lexemeId != null;
  @override
  bool get wantKeepAlive => true;
  @override
  void initState() {
    super.initState();
    widget.personal.addListener(personalChanged);
    if (lemma || widget.initialQuery != null) {
      searching = true;
      controller.start(query: text.text);
    } else {
      loadCatalog();
    }
  }

  void personalChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.personal.removeListener(personalChanged);
    catalogGeneration++;
    controller.dispose();
    text.dispose();
    urlText.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> loadCatalog({bool more = false}) async {
    if (catalogBusy) return;
    final generation = ++catalogGeneration;
    setState(() {
      catalogBusy = true;
      catalogError = null;
      if (!more) sources.clear();
    });
    try {
      final nextSession = more ? session! : await repository.session();
      final page = await repository.catalog(
        nextSession,
        cursor: more ? catalogCursor : null,
      );
      if (!mounted || generation != catalogGeneration) return;
      setState(() {
        session = nextSession;
        sources.addAll(wireList(page['items']).map(wireObject));
        catalogCursor = page['nextCursor'];
      });
    } catch (e) {
      if (mounted && generation == catalogGeneration) {
        setState(() {
          catalogError = e;
          sources.clear();
        });
      }
    } finally {
      if (mounted && generation == catalogGeneration) {
        setState(() => catalogBusy = false);
      }
    }
  }

  void open({SourceAddress? address, String? url, CorpusHit? hit}) {
    final s = searching ? controller.session : session;
    if (s == null) return;
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ReaderScreen(
          repository: repository,
          dictionary: widget.dictionary,
          personal: widget.personal,
          session: s,
          profile: searching ? controller.profile! : s.defaultProfile,
          address: address,
          url: url,
          hit: hit,
        ),
      ),
    );
  }

  void submit() {
    setState(() => searching = true);
    if (scroll.hasClients) scroll.jumpTo(0);
    controller.start(query: text.text);
  }

  Widget results() => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Column(
      children: [
        if (controller.session != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DropdownButtonFormField<String>(
              initialValue: controller.profile,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Вид текста'),
              items: controller.session!.profiles
                  .map(
                    (p) => DropdownMenuItem(
                      value: p['id'] as String,
                      child: Text(
                        p['profiles']['display'] == 'display-source-r1'
                            ? 'Исходная графика'
                            : 'Нормализованный Unicode',
                      ),
                    ),
                  )
                  .toList(),
              onChanged: controller.busy
                  ? null
                  : (v) {
                      if (v != null) controller.start(profile: v);
                    },
            ),
          ),
        Expanded(
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Поиск ограничен пятью материалами пилота. Ссылочный ирмос учитывается по месту, без удвоения.',
              ),
              if (lemma)
                const Text(
                  'Показаны только принятые связи с лексемой. Проверено лишь небольшое число мест; это не полный список употреблений.',
                ),
              if (controller.page != null) Text(controller.page!.totalLabel),
              for (final hit in controller.hits)
                Card(
                  child: InkWell(
                    onTap: () => open(address: hit.address, hit: hit),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            hit.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(hit.label),
                          if (hit.snippet != null)
                            ProjectionText(
                              projection: hit.snippet!,
                              highlight: hit.tokenIds,
                              size: widget.personal.fontSize,
                            )
                          else
                            const Text(
                              'Контекст не помещается в выдачу. Откройте текст.',
                            ),
                          if ((hit.wire['navigationAliases'] as List? ?? [])
                              .isNotEmpty)
                            const Text(
                              'Это место доступно также через другой материал пилота.',
                            ),
                          if (hit.wire['bindingEvidence'] != null)
                            ExpansionTile(
                              title: const Text('Основание связи'),
                              children: [
                                Text(
                                  'Проверяющий: ${hit.wire['bindingEvidence']['reviewer']}',
                                ),
                                Text(
                                  '${hit.wire['bindingEvidence']['rationale']}',
                                ),
                              ],
                            ),
                          TextButton(
                            onPressed: () =>
                                open(address: hit.address, hit: hit),
                            child: const Text('Открыть место'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (!controller.busy &&
                  controller.error == null &&
                  controller.page != null &&
                  controller.hits.isEmpty)
                Text(
                  lemma
                      ? 'В этом пилоте пока нет принятых связей с этой лексемой. Это не означает, что слово не встречается в текстах.'
                      : 'В доступной поиску части пилота совпадений не найдено.',
                ),
              if (lemma && !controller.busy)
                OutlinedButton(
                  onPressed: widget.word == null
                      ? null
                      : () => Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CorpusScreen(
                              dictionary: widget.dictionary,
                              personal: widget.personal,
                              initialQuery: widget.word,
                            ),
                          ),
                        ),
                  child: const Text('Искать по написанию отдельно'),
                ),
              if (controller.busy)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  ),
                ),
              if (controller.error != null)
                CorpusErrorView(
                  error: controller.error!,
                  retry: controller.restartRequired || controller.page == null
                      ? () => controller.start()
                      : controller.more,
                  current: controller.restartRequired
                      ? () {
                          if (lemma &&
                              controller.error is CorpusFailure &&
                              (controller.error as CorpusFailure).code ==
                                  'dictionary_version_mismatch') {
                            Navigator.push<void>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ArticleScreen(
                                  id: widget.lexemeId!,
                                  repository: widget.dictionary,
                                  personal: widget.personal,
                                ),
                              ),
                            );
                          } else {
                            controller.start();
                          }
                        }
                      : null,
                ),
              if (!controller.busy && controller.page?.cursor != null)
                FilledButton(
                  onPressed: controller.more,
                  child: const Text('Ещё употребления'),
                ),
              if (controller.page?.truncated == true)
                const Text('Достигнут предел выдачи. Уточните запрос.'),
            ],
          ),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final body = Column(
      children: [
        if (!lemma)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  controller: text,
                  maxLength: 200,
                  decoration: InputDecoration(
                    labelText: 'Слово или фраза в пилоте',
                    suffixIcon: IconButton(
                      tooltip: 'Найти в текстах',
                      onPressed: submit,
                      icon: const Icon(Icons.search),
                    ),
                  ),
                  onSubmitted: (_) => submit(),
                ),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: controller.mode,
                        items: const [
                          DropdownMenuItem(
                            value: 'word',
                            child: Text('Одно слово'),
                          ),
                          DropdownMenuItem(
                            value: 'phrase',
                            child: Text('Фраза (2–12 слов)'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => controller.mode = v);
                            if (searching) submit();
                          }
                        },
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => searching = false),
                      child: const Text('Каталог'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        Expanded(
          child: searching
              ? results()
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text(
                      'Пилот: канон, акафист Николаю, глава Маргарита, ссылочный ирмос и тропарь. Для чтения требуется сеть.',
                    ),
                    for (final source in sources)
                      ListTile(
                        title: Text(source['title']),
                        subtitle: Text(
                          source['sourceRights']?['status'] == 'unresolved'
                              ? 'Условия использования не установлены'
                              : 'Условия использования — в паспорте',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => open(
                          address: SourceAddress({
                            'version': 2,
                            'sourceId': source['sourceId'],
                          }),
                        ),
                      ),
                    if (catalogBusy)
                      const Center(child: CircularProgressIndicator()),
                    if (catalogError != null)
                      CorpusErrorView(error: catalogError!, retry: loadCatalog),
                    if (catalogCursor != null && !catalogBusy)
                      TextButton(
                        onPressed: () => loadCatalog(more: true),
                        child: const Text('Ещё тексты'),
                      ),
                    const Divider(),
                    TextField(
                      controller: urlText,
                      decoration: const InputDecoration(
                        labelText: 'Постоянная или старая ссылка портала',
                      ),
                      keyboardType: TextInputType.url,
                    ),
                    TextButton(
                      onPressed: session == null
                          ? null
                          : () => open(url: urlText.text.trim()),
                      child: const Text('Открыть ссылку в приложении'),
                    ),
                  ],
                ),
        ),
      ],
    );
    return lemma || widget.initialQuery != null
        ? Scaffold(
            appBar: AppBar(
              title: Text(
                lemma
                    ? 'Употребления: ${widget.word ?? ''}'
                    : 'Поиск по написанию',
              ),
            ),
            body: body,
          )
        : body;
  }
}
