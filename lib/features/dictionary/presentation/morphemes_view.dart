import 'package:flutter/material.dart';
import '../data/dictionary_repository.dart';
import '../domain/models.dart';
import '../domain/morphemes.dart';
import 'resource_screen.dart';

Color morphemeColor(String kind) => switch (kind) {
  'prefix' => const Color(0xffb94e0c),
  'root' => const Color(0xff171717),
  'interfix' => const Color(0xff505050),
  'derivational_suffix' ||
  'formative_suffix' ||
  'postfix' => const Color(0xff2459b5),
  'stem_suffix' || 'thematic_vowel' => const Color(0xff247341),
  'inflection' => const Color(0xffe1e3e5),
  _ => const Color(0xffeeeeee),
};

class MorphemeScheme extends StatelessWidget {
  const MorphemeScheme({
    super.key,
    required this.analysis,
    this.selected,
    this.onSelect,
  });
  final MorphemeAnalysis analysis;
  final String? selected;
  final ValueChanged<String>? onSelect;

  @override
  Widget build(BuildContext context) => Card(
    key: const ValueKey('morpheme-scheme-card'),
    color: Colors.white,
    surfaceTintColor: Colors.transparent,
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var i = 0; i < analysis.parts.length; i++)
              Padding(
                padding: EdgeInsets.only(
                  right: i + 1 < analysis.parts.length ? 8 : 0,
                ),
                child: _part(context, analysis.parts[i]),
              ),
          ],
        ),
      ),
    ),
  );

  Widget _part(BuildContext context, MorphemePart part) {
    final color = morphemeColor(part.kind);
    final foreground = color.computeLuminance() > .5
        ? Colors.black
        : Colors.white;
    final surface = part.surface.isEmpty ? '∅' : part.surface;
    final sharedLetters = analysis.letters.where(
      (letter) => letter.partIds.contains(part.id) && letter.partIds.length > 1,
    );
    final label =
        '$surface — ${morphemeKind(part.kind)}${sharedLetters.isEmpty ? '' : '. Общие буквы: ${sharedLetters.map((l) => l.text).join(', ')}'}';
    final isSelected = selected == part.id;
    return Semantics(
      label: label,
      button: onSelect != null,
      selected: isSelected,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: Material(
          key: ValueKey('morpheme-part-${part.id}'),
          color: color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: BorderSide(
              color: isSelected ? const Color(0xffb94e0c) : Colors.black26,
              width: isSelected ? 3 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onSelect == null ? null : () => onSelect!(part.id),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final grapheme in surface.characters)
                      Builder(
                        builder: (context) {
                          final shared = sharedLetters.where(
                            (letter) => letter.text == grapheme,
                          );
                          final colors = shared.isEmpty
                              ? [color]
                              : shared.first.colorKinds
                                    .map(morphemeColor)
                                    .toList();
                          final striped = colors.length > 1;
                          return CustomPaint(
                            painter: _LetterFill(
                              colors.isEmpty ? [color] : colors,
                            ),
                            child: Text(
                              grapheme,
                              style: TextStyle(
                                fontFamily: 'Monomakh',
                                fontSize: 22,
                                color: striped ? Colors.white : foreground,
                                shadows: striped
                                    ? const [
                                        Shadow(
                                          color: Colors.black,
                                          blurRadius: 4,
                                        ),
                                      ]
                                    : null,
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LetterFill extends CustomPainter {
  _LetterFill(this.colors);
  final List<Color> colors;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = colors.first);
    if (colors.length == 1) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (double x = -size.height; x < size.width + size.height; x += 7) {
      final index = ((x + size.height) / 7).round() % colors.length;
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        Paint()
          ..color = colors[index]
          ..strokeWidth = 7,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LetterFill oldDelegate) =>
      oldDelegate.colors.length != colors.length ||
      List.generate(
        colors.length,
        (i) => colors[i] != oldDelegate.colors[i],
      ).any((v) => v);
}

class WordMorphemesView extends StatefulWidget {
  const WordMorphemesView({
    super.key,
    required this.id,
    required this.repository,
    required this.openWord,
    required this.fontSize,
  });
  final String id;
  final DictionaryRepository repository;
  final ValueChanged<String> openWord;
  final double fontSize;
  @override
  State<WordMorphemesView> createState() => _WordMorphemesViewState();
}

class _WordMorphemesViewState extends State<WordMorphemesView> {
  late Future<WordMorphemes> future = widget.repository.wordMorphemes(
    widget.id,
  );
  int analysisIndex = 0;
  String? selected;

  @override
  Widget build(BuildContext context) => FutureBuilder<WordMorphemes>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _LoadError(
          error: snapshot.error!,
          retry: () => setState(() {
            future = widget.repository.wordMorphemes(widget.id);
          }),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final data = snapshot.data!;
      if (data.analyses.isEmpty) {
        return const Text('Морфемный разбор этого слова пока не задан.');
      }
      final a = data.analyses[analysisIndex];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (data.analyses.length > 1)
            DropdownButtonFormField<int>(
              initialValue: analysisIndex,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Вариант разбора'),
              items: [
                for (var i = 0; i < data.analyses.length; i++)
                  DropdownMenuItem(
                    value: i,
                    child: Text(
                      '${data.analyses[i].form} · ${analysisStatus(data.analyses[i].status)}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) => setState(() {
                analysisIndex = value!;
                selected = null;
              }),
            ),
          const SizedBox(height: 12),
          Text(
            analysisStatus(a.status),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 12),
          MorphemeScheme(
            analysis: a,
            selected: selected,
            onSelect: (id) => setState(() => selected = id),
          ),
          const SizedBox(height: 12),
          const Text(
            'Один прямоугольник — одна морфема. Штриховка — общая буква соседних морфем. Нажмите на морфему, чтобы выделить её в списке. ∅ — нулевая морфема.',
          ),
          if (a.note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(a.note),
            ),
          const SizedBox(height: 24),
          Text('Морфемы', style: Theme.of(context).textTheme.titleLarge),
          for (final part in a.parts)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              selected: part.id == selected,
              leading: Container(
                width: 12,
                height: 32,
                color: morphemeColor(part.kind),
              ),
              title: Text(
                '${part.surface.isEmpty ? '∅' : part.surface} — ${morphemeKind(part.kind)}',
              ),
              subtitle: part.gloss.isEmpty ? null : Text(part.gloss),
              trailing: part.navigable ? const Icon(Icons.chevron_right) : null,
              onTap: part.navigable
                  ? () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => MorphemeScreen(
                          id: part.morphemeId!,
                          version: data.version,
                          repository: widget.repository,
                          openWord: widget.openWord,
                          fontSize: widget.fontSize,
                        ),
                      ),
                    )
                  : () => setState(() => selected = part.id),
            ),
        ],
      );
    },
  );
}

class MorphemeScreen extends StatefulWidget {
  const MorphemeScreen({
    super.key,
    required this.id,
    required this.version,
    required this.repository,
    required this.openWord,
    required this.fontSize,
  });
  final String id, version;
  final DictionaryRepository repository;
  final ValueChanged<String> openWord;
  final double fontSize;
  @override
  State<MorphemeScreen> createState() => _MorphemeScreenState();
}

class _MorphemeScreenState extends State<MorphemeScreen> {
  late Future<MorphemeCard> future = widget.repository.morpheme(
    widget.id,
    version: widget.version,
  );
  late Future<MorphemeWords> words = loadWords(null);
  final cursors = <String?>[null];
  int page = 0;

  Future<MorphemeWords> loadWords(String? cursor) async {
    final data = await widget.repository.morphemeWords(
      widget.id,
      version: widget.version,
      cursor: cursor,
    );
    if (data.version != widget.version) {
      throw const DictionaryException(
        'Версия базы изменилась. Откройте вкладку «Морфемы» заново.',
        status: 409,
      );
    }
    return data;
  }

  void go(int target, String? cursor) => setState(() {
    if (target == cursors.length) cursors.add(cursor);
    page = target;
    words = loadWords(cursors[page]);
  });

  Widget heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleLarge),
  );

  void openRelated(String id) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => MorphemeScreen(
        id: id,
        version: widget.version,
        repository: widget.repository,
        openWord: widget.openWord,
        fontSize: widget.fontSize,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Морфема')),
    body: FutureBuilder<MorphemeCard>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _LoadError(
            error: snapshot.error!,
            retry: () => setState(() {
              future = widget.repository.morpheme(
                widget.id,
                version: widget.version,
              );
            }),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final m = snapshot.data!;
        if (m.version != widget.version) {
          return const Center(
            child: Text(
              'Версия базы изменилась. Откройте вкладку «Морфемы» заново.',
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              m.title,
              style: TextStyle(
                fontFamily: 'Monomakh',
                fontSize: widget.fontSize + 10,
              ),
            ),
            Text('${morphemeKind(m.kind)} · ${analysisStatus(m.status)}'),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                Chip(label: Text('Слов: ${m.wordCount}')),
                Chip(label: Text('Форм: ${m.formCount}')),
                Chip(label: Text('Вариантов: ${m.variants.length}')),
              ],
            ),
            const Text(
              'Статистика по текущей версии базы; каждое слово учитывается один раз.',
            ),
            heading('Семантика'),
            Text(m.gloss.isEmpty ? 'Значение пока не описано.' : m.gloss),
            heading('Варианты морфемы'),
            for (final v in m.variants)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  string(v['surface']).isEmpty ? '∅' : string(v['surface']),
                ),
                subtitle: Text(
                  '${analysisStatus(string(v['status']))}\n${string(v['note'])}',
                ),
              ),
            heading('Внутренняя структура'),
            if (m.structure.isEmpty)
              const Text('Внутренняя структура пока не описана.'),
            for (final s in m.structure)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(string(s['title'])),
                subtitle: Text(
                  '${string(s['note'])}\n${analysisStatus(string(s['status']))}',
                ),
                trailing: s['morphemeId'] is String
                    ? const Icon(Icons.chevron_right)
                    : null,
                onTap: s['morphemeId'] is String
                    ? () => openRelated(string(s['morphemeId']))
                    : null,
              ),
            heading('Исторические связи'),
            if (m.history.isEmpty)
              const Text('Исторические связи пока не описаны.'),
            for (final h in m.history)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        string(h['title']),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(analysisStatus(string(h['status']))),
                      if (string(h['reconstruction']).isNotEmpty)
                        Text(string(h['reconstruction'])),
                      Text(string(h['note'])),
                      for (final source in array(h['sources']).map(object))
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '${string(source['title'])} · ${string(source['locator'])}',
                          ),
                        ),
                      if (h['morphemeId'] is String)
                        TextButton(
                          onPressed: () => openRelated(string(h['morphemeId'])),
                          child: const Text('Связанная морфема'),
                        ),
                      if (h['protoId'] is num)
                        TextButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => ResourceScreen(
                                repository: widget.repository,
                                id: '',
                                protoId: (h['protoId'] as num).toInt(),
                                expectedBodyHash: h['bodySha256'] as String?,
                                size: widget.fontSize,
                              ),
                            ),
                          ),
                          child: const Text('Этимологическая статья'),
                        ),
                    ],
                  ),
                ),
              ),
            heading('Связанные слова'),
            FutureBuilder<MorphemeWords>(
              future: words,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _LoadError(
                    error: snapshot.error!,
                    retry: () =>
                        setState(() => words = loadWords(cursors[page])),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final result = snapshot.data!;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Всего слов: ${result.total}'),
                    if (result.items.isEmpty)
                      const Text('Связанные слова пока не подготовлены.'),
                    for (final w in result.items)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          string(w['name']),
                          style: const TextStyle(fontFamily: 'Monomakh'),
                        ),
                        subtitle: Text(string(w['gloss'])),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => widget.openWord(string(w['id'])),
                      ),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: page > 0 ? () => go(page - 1, null) : null,
                          child: const Text('Назад'),
                        ),
                        Text('Страница ${page + 1}'),
                        TextButton(
                          onPressed: result.nextCursor != null
                              ? () => go(page + 1, result.nextCursor)
                              : null,
                          child: const Text('Далее'),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
        );
      },
    ),
  );
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.error, required this.retry});
  final Object error;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          error is DictionaryException &&
                  (error as DictionaryException).status == 404
              ? 'Морфемные данные пока недоступны через API.'
              : error.toString(),
        ),
        TextButton(onPressed: retry, child: const Text('Повторить')),
      ],
    ),
  );
}
