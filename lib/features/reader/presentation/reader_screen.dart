import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/external_link.dart';
import '../../../core/personal_store.dart';
import '../../dictionary/data/dictionary_repository.dart';
import '../../dictionary/domain/models.dart';
import '../../dictionary/presentation/article_screen.dart';
import '../data/reader_repository.dart';
import '../domain/corpus.dart';
import '../domain/reader_packet.dart';
import 'corpus_widgets.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.repository,
    required this.dictionary,
    required this.personal,
    required this.session,
    required this.profile,
    this.address,
    this.url,
    this.hit,
  });
  final ReaderRepository repository;
  final DictionaryRepository dictionary;
  final PersonalStore personal;
  final CorpusSession session;
  final String profile;
  final SourceAddress? address;
  final String? url;
  final CorpusHit? hit;
  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  SourceAddress? address;
  ReaderReadPacket? packet;
  Wire? resolved;
  Object? error;
  VoidCallback? retryLoad;
  bool busy = false, contextOnly = false;
  String? cursor, pageCursor;
  final previousCursors = <String?>[];
  bool useHit = true;
  late String profile = widget.profile;
  late CorpusSession session = widget.session;
  final scroll = ScrollController();
  int generation = 0;
  Wire get profileWire =>
      session.profiles.singleWhere((p) => p['id'] == profile);
  @override
  void initState() {
    super.initState();
    address = widget.address;
    load(resolve: true);
  }

  @override
  void dispose() {
    generation++;
    scroll.dispose();
    super.dispose();
  }

  Future<void> load({
    bool resolve = false,
    bool next = false,
    bool previous = false,
    bool current = false,
    bool whole = false,
  }) async {
    retryLoad = () => load(
      resolve: resolve,
      next: next,
      previous: previous,
      current: current,
      whole: whole,
    );
    final request = ++generation;
    setState(() {
      busy = true;
      error = null;
      packet = null;
    });
    try {
      if (current) {
        session = await widget.repository.session();
        profile = session.defaultProfile;
        address = SourceAddress({
          'version': 2,
          'sourceId': address?.sourceId ?? widget.address?.sourceId,
        });
        cursor = null;
        pageCursor = null;
        previousCursors.clear();
        contextOnly = false;
        useHit = false;
      }
      if (resolve || current) {
        resolved = await widget.repository.resolve(
          address: address ?? widget.address,
          url: address == null && widget.address == null ? widget.url : null,
        );
        if (!mounted || request != generation) return;
        if (resolved!['result'] == 'container') {
          setState(() => busy = false);
          return;
        }
        address = SourceAddress(wireObject(resolved!['resolvedAddress']));
        contextOnly = !current && widget.hit?.snippet != null;
      }
      if (whole) {
        address = address!.whole;
        contextOnly = false;
        cursor = null;
        pageCursor = null;
        previousCursors.clear();
        useHit = false;
      }
      final requestedCursor = next
          ? cursor
          : previous
          ? previousCursors.last
          : pageCursor;
      final window = contextOnly
          ? {
              'bodyId': widget.hit!.wire['bodyId'],
              'rawRange': widget.hit!.snippet!.wire['rawWindow'],
            }
          : null;
      final nextPacket = await widget.repository.read(
        address!,
        profileWire,
        cursor: requestedCursor,
        window: window,
      );
      if (!mounted || request != generation) return;
      if (useHit &&
          widget.hit != null &&
          nextPacket.projections.any(
            (p) => p['bodyId'] == widget.hit!.wire['bodyId'],
          )) {
        final p = CorpusProjection(
          wireObject(
            nextPacket.projections.firstWhere(
              (p) => p['bodyId'] == widget.hit!.wire['bodyId'],
            ),
          ),
          profile: profile,
        );
        widget.hit!.validateProjection(p);
      }
      setState(() {
        if (next) previousCursors.add(pageCursor);
        if (previous) previousCursors.removeLast();
        pageCursor = requestedCursor;
        packet = nextPacket;
        cursor = nextPacket.data['page']['nextCursor'];
        busy = false;
      });
      if (scroll.hasClients) scroll.jumpTo(0);
    } catch (e) {
      if (mounted && request == generation) {
        setState(() {
          error = e is CorpusFailure
              ? e
              : const CorpusFailure(
                  'Текст и адрес не согласованы. Откройте текущую версию отдельно.',
                );
          busy = false;
        });
      }
    }
  }

  Future<void> passport() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PassportScreen(repository: widget.repository, address: address!),
      ),
    );
  }

  Future<void> lookup(CorpusProjection p, Wire token) async {
    final key = token['lookupKey'];
    if (key is! Map || key['value'] is! String || key['value'].isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Разбор недоступен'),
          content: Text(
            'Для этого слова пока нет распознанного написания для поиска. Исходная графика сохранена.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Закрыть'),
            ),
          ],
        ),
      );
      return;
    }
    // Reuse schema=2 search with exact D. Legacy reader lookup cannot pin D.
    // The supplied server key is never normalized or expanded on the device.
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => TokenLookupScreen(
          dictionary: widget.dictionary,
          personal: widget.personal,
          keyValue: key['value'],
          dictionaryVersion: session.dictionary,
        ),
      ),
    );
  }

  void selectToken(CorpusProjection p) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(c).height * .7,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Выберите слово для поиска в словаре'),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final t in p.tokens.where(
                    (t) => [
                      'word',
                      'numberCandidate',
                      'unresolved',
                    ].contains(t['type']),
                  ))
                    ListTile(
                      title: Text(
                        wireRanges(
                          t['surfaceRanges'],
                        ).map((r) => p.text.substring(r.$1, r.$2)).join(),
                        style: TextStyle(
                          fontFamily: 'Monomakh',
                          fontSize: widget.personal.fontSize,
                        ),
                      ),
                      subtitle: t['blockedReason'] == null
                          ? null
                          : const Text('Нераспознанная графика'),
                      onTap: () {
                        Navigator.pop(c);
                        lookup(p, t);
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.personal,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: Text(
          resolved?['source']?['title'] ?? 'Чтение',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (address?.pinned == true)
            IconButton(
              tooltip: 'Паспорт текста',
              icon: const Icon(Icons.info_outline),
              onPressed: passport,
            ),
          if (address != null)
            PopupMenuButton<String>(
              tooltip: 'Адрес текста',
              onSelected: (v) {
                if (v == 'copy') {
                  Clipboard.setData(
                    ClipboardData(text: address!.url.toString()),
                  );
                } else {
                  openExternalLink(context, address!.url.toString());
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'copy',
                  child: Text('Копировать постоянную ссылку'),
                ),
                PopupMenuItem(
                  value: 'portal',
                  child: Text('Открыть на портале'),
                ),
              ],
            ),
        ],
      ),
      body: busy
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? Center(
              child: CorpusErrorView(
                error: error!,
                retry: retryLoad ?? () => load(resolve: address == null),
                current:
                    address != null && error is CorpusFailure &&
                        (error as CorpusFailure).restartRequired
                    ? () => load(current: true)
                    : null,
              ),
            )
          : resolved?['result'] == 'container'
          ? Center(
              child: TextButton(
                onPressed: () =>
                    openExternalLink(context, resolved!['canonicalUrl']),
                child: const Text('Открыть книгу на портале'),
              ),
            )
          : packet == null
          ? const SizedBox.shrink()
          : SelectionArea(
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    contextOnly
                        ? 'Контекст найденного места'
                        : 'Текст пилота. Для загрузки требуется сеть.',
                  ),
                  if (resolved?['source']?['sourceRights']?['status'] ==
                      'unresolved')
                    const Text(
                      'Условия использования текста не установлены; публичное чтение не означает свободную лицензию.',
                    ),
                  for (final unit in (packet!.data['units'] as List))
                    Text(
                      [
                        if (unit['placement']?['ode'] != null)
                          'Песнь ${unit['placement']['ode']}',
                        if (unit['placement']?['unit'] != null)
                          '${unit['placement']['unit']}',
                      ].join(' · '),
                    ),
                  DropdownButtonFormField<String>(
                    initialValue: profile,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Вид текста'),
                    items: session.profiles
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
                    onChanged: (v) {
                      if (v != null && v != profile) {
                        setState(() {
                          profile = v;
                          cursor = null;
                          pageCursor = null;
                          previousCursors.clear();
                        });
                        load();
                      }
                    },
                  ),
                  if (contextOnly)
                    TextButton(
                      onPressed: () => load(whole: true),
                      child: const Text('Читать текст целиком'),
                    ),
                  for (final raw in packet!.projections) ...[
                    Builder(
                      builder: (context) {
                        final p = CorpusProjection(
                          wireObject(raw),
                          profile: profile,
                        );
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ProjectionText(
                              projection: p,
                              highlight: contextOnly
                                  ? widget.hit!.tokenIds
                                  : const [],
                              size: widget.personal.fontSize,
                              onToken: (t) => lookup(p, t),
                            ),
                            TextButton.icon(
                              onPressed: () => selectToken(p),
                              icon: const Icon(Icons.search),
                              label: const Text('Выбрать слово'),
                            ),
                            ExpansionTile(
                              title: const Text('Исходный текст и диагностика'),
                              children: [
                                Text(
                                  p.raw,
                                  style: TextStyle(
                                    fontFamily: 'Monomakh',
                                    fontFamilyFallback: const ['Shafarik'],
                                    fontSize: widget.personal.fontSize,
                                  ),
                                ),
                                if (p.tokens.any(
                                  (t) => t['blockedReason'] != null,
                                ))
                                  const Text(
                                    'Есть нераспознанные или недоступные для поиска токены. Они не удалены из исходного текста.',
                                  ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (previousCursors.isNotEmpty)
                    TextButton(
                      onPressed: () => load(previous: true),
                      child: const Text('Предыдущий фрагмент'),
                    ),
                  if (cursor != null)
                    FilledButton(
                      onPressed: () => load(next: true),
                      child: const Text('Следующий фрагмент'),
                    ),
                  if (cursor == null && !contextOnly)
                    const Text('Конец выбранного текста.'),
                ],
              ),
            ),
    ),
  );
}

class TokenLookupScreen extends StatefulWidget {
  const TokenLookupScreen({
    super.key,
    required this.dictionary,
    required this.personal,
    required this.keyValue,
    required this.dictionaryVersion,
  });
  final DictionaryRepository dictionary;
  final PersonalStore personal;
  final String keyValue, dictionaryVersion;
  @override
  State<TokenLookupScreen> createState() => _TokenLookupScreenState();
}

class _TokenLookupScreenState extends State<TokenLookupScreen> {
  late Future<SearchPage> future;
  void load() {
    future = widget.dictionary.search(
      widget.keyValue,
      'cu-ru',
      version: widget.dictionaryVersion,
      limit: 20,
    );
    future.ignore();
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Слово из текста')),
    body: FutureBuilder<SearchPage>(
      future: future,
      builder: (context, s) {
        if (s.hasError) {
          return Center(
            child: CorpusErrorView(
              error: s.error!,
              retry: () => setState(load),
            ),
          );
        }
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        // Prefix hits are not analysis candidates for the selected complete token.
        final hits = s.data!.items.where((h) => h.exact).toList();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              widget.keyValue,
              style: TextStyle(
                fontFamily: 'Monomakh',
                fontSize: widget.personal.fontSize,
              ),
            ),
            const Text(
              'Кандидаты словарного поиска. Это не подтверждённый разбор токена: выберите подходящую статью.',
            ),
            if (hits.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Для этой формы подходящих статей не найдено.'),
              ),
            for (final h in hits)
              ListTile(
                title: Text(
                  h.name,
                  style: TextStyle(
                    fontFamily: 'Monomakh',
                    fontSize: widget.personal.fontSize,
                  ),
                ),
                subtitle: Text('${h.pos} · ${h.matchLabel}\n${h.grammar}'),
                onTap: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ArticleScreen(
                      id: h.id,
                      repository: widget.dictionary,
                      personal: widget.personal,
                      dictionaryVersion: widget.dictionaryVersion,
                      matched: h.matched,
                      match: h.match,
                      grammar: h.grammar,
                    ),
                  ),
                ),
              ),
            if (s.data!.nextCursor != null)
              const Text(
                'Показана первая страница кандидатов; для уточнения используйте словарь.',
              ),
          ],
        );
      },
    ),
  );
}

class PassportScreen extends StatefulWidget {
  const PassportScreen({
    super.key,
    required this.repository,
    required this.address,
  });
  final ReaderRepository repository;
  final SourceAddress address;
  @override
  State<PassportScreen> createState() => _PassportScreenState();
}

class _PassportScreenState extends State<PassportScreen> {
  late Future<Wire> future;
  void load() {
    future = widget.repository.passport(widget.address);
    future.ignore();
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  static const labels = {
    'authorship': 'Авторство',
    'translator': 'Переводчик',
    'createdAt': 'Создание',
    'translatedAt': 'Перевод',
    'originalPartOf': 'Родной канон',
  };
  static const states = {
    'unknown': 'Не установлено',
    'candidate': 'Предположение',
    'disputed': 'Спорно',
    'accepted': 'Принято',
    'known': 'Установлено',
  };
  String describe(dynamic value) {
    if (value == null) return 'Не установлено';
    if (value is String || value is num || value is bool) return '$value';
    if (value is List) return value.map(describe).join('; ');
    final v = value as Map;
    if (v['label'] != null) return '${v['label']}';
    if (v['value'] != null) return describe(v['value']);
    return v.entries
        .where(
          (e) => ![
            'id',
            'ref',
            'revision',
            'subjectId',
            'sourceRef',
            'assertionIds',
            'questionIds',
          ].contains(e.key),
        )
        .map((e) => describe(e.value))
        .join(' · ');
  }

  Widget record(dynamic value) {
    final v = value as Map;
    final parts = <String>[];
    if (v['predicate'] != null) {
      parts.add(
        const {
              'authoredBy': 'Авторство',
              'recordCreatedAt': 'Дата записи в базе',
              'storedAt': 'Хранение текста',
              'usedIn': 'Использование',
              'originalPartOf': 'Родной канон',
              'reportedField': 'Сведения каталога',
            }[v['predicate']] ??
            '${v['predicate']}',
      );
    }
    for (final key in [
      'value',
      'rawValue',
      'reason',
      'explanation',
      'rationale',
    ]) {
      if (v[key] != null) parts.add(describe(v[key]));
    }
    if (v['reviewStatus'] != null) {
      parts.add(
        'Проверка: ${const {'unreviewed': 'не проверено', 'accepted': 'принято', 'rejected': 'отклонено'}[v['reviewStatus']] ?? v['reviewStatus']}',
      );
    }
    if (v['locator'] != null) parts.add('Место в источнике: ${v['locator']}');
    if (v['recordedAt'] != null) {
      parts.add('Сведения зафиксированы: ${v['recordedAt']}');
    }
    if (v['url'] != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(parts.join('\n')),
          TextButton(
            onPressed: () => openExternalLink(context, '${v['url']}'),
            child: const Text('Открыть источник'),
          ),
        ],
      );
    }
    if (v['snapshot'] != null && parts.isEmpty) {
      parts.add(
        'Цифровой источник портала; подробные сведения доступны по постоянной ссылке.',
      );
    }
    if (v['evidenceLinks'] is List) {
      parts.addAll(
        (v['evidenceLinks'] as List).map((e) => '${e['explanation'] ?? ''}'),
      );
    }
    return SelectableText(parts.isEmpty ? describe(v) : parts.join('\n'));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Паспорт текста')),
    body: FutureBuilder<Wire>(
      future: future,
      builder: (context, s) {
        if (s.hasError) {
          return Center(
            child: CorpusErrorView(
              error: s.error!,
              retry: () => setState(load),
            ),
          );
        }
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final data = s.data!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Неизвестные сведения и альтернативные атрибуции сохранены. Техническая дата записи не является датой создания произведения.',
            ),
            for (final entry in wireObject(data['fields']).entries)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        labels[entry.key] ?? entry.key,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        states[entry.value['state']] ??
                            '${entry.value['state']}',
                      ),
                      Text('${entry.value['display'] ?? ''}'),
                    ],
                  ),
                ),
              ),
            for (final key in [
              'assertions',
              'sources',
              'observations',
              'questions',
              'cases',
              'reviewEvents',
            ])
              ExpansionTile(
                title: Text(
                  const {
                    'assertions': 'Утверждения и основания',
                    'sources': 'Источники',
                    'observations': 'Наблюдения',
                    'questions': 'Неизвестные сведения',
                    'cases': 'Альтернативы',
                    'reviewEvents': 'Редакторские решения',
                  }[key]!,
                ),
                children: [
                  for (final item in (data[key] as List? ?? []))
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: record(item),
                    ),
                ],
              ),
            TextButton(
              onPressed: () =>
                  openExternalLink(context, widget.address.url.toString()),
              child: const Text('Открыть паспорт на портале'),
            ),
          ],
        );
      },
    ),
  );
}
