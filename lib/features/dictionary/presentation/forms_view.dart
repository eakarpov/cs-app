import 'package:flutter/material.dart';
import '../domain/models.dart';
import '../domain/form_presentation.dart';
import '../domain/grammar_labels.dart';

class WordFormsView extends StatefulWidget {
  const WordFormsView({
    super.key,
    required this.article,
    required this.formBuilder,
  });
  final WordArticle article;
  final Widget Function(WordForm) formBuilder;
  @override
  State<WordFormsView> createState() => _WordFormsViewState();
}

class _WordFormsViewState extends State<WordFormsView> {
  bool detailed = false;

  void showSpellings(
    String label,
    List<WordForm> forms, {
    String title = 'Иные написания',
  }) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label),
              const SizedBox(height: 12),
              const Text(
                'Дополнительные написания и сведения. Происхождение указано у каждой формы. Порядок показа не устанавливает языковую норму.',
              ),
              for (final form in forms) widget.formBuilder(form),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Закрыть'),
        ),
      ],
    ),
  );

  Widget cell(String label, Iterable<WordForm> forms) {
    final readable = readableForms(forms);
    final primary = primaryForm(readable);
    final alternatives = readable
        .where((f) => f.selectionKey != primary?.selectionKey)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (primary != null) widget.formBuilder(primary) else const Text('—'),
        if (alternatives.isNotEmpty)
          TextButton(
            onPressed: () => showSpellings(
              label,
              alternatives,
              title: alternatives.any((f) => f.value == primary?.value)
                  ? 'Другие варианты формы'
                  : 'Иные написания',
            ),
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            child: Text(
              '${alternatives.any((f) => f.value == primary?.value) ? 'Другие варианты' : 'Иные написания'} (${alternatives.length})',
            ),
          ),
      ],
    );
  }

  Widget grid(FormGrid grid, {bool showTitle = true}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (showTitle)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            grid.title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      SingleChildScrollView(
        key: PageStorageKey(
          'forms:${widget.article.id}:${widget.article.version}:${grid.title}',
        ),
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 20,
          horizontalMargin: 8,
          dataRowMinHeight: 56,
          dataRowMaxHeight: double.infinity,
          columns: [
            DataColumn(label: Text(grid.rowHeading)),
            for (final column in grid.columns) DataColumn(label: Text(column)),
          ],
          rows: [
            for (var row = 0; row < grid.rows.length; row++)
              DataRow(
                cells: [
                  DataCell(Text(grid.rows[row])),
                  for (var col = 0; col < grid.columns.length; col++)
                    DataCell(
                      cell(
                        '${grid.title} · ${grid.rows[row]} · ${grid.columns[col]}',
                        grid.forms(row, col),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final article = widget.article;
    final defaultParadigm = article.paradigms.isEmpty
        ? null
        : article.paradigms.firstWhere(
            (p) => p.kind == 'adjective-plen',
            orElse: () => article.paradigms.first,
          );
    final displayedValues = {
      for (final p in article.paradigms)
        for (final s in p.slots)
          for (final f in s.forms) f.selectionKey,
    };
    final extra = readableForms(
      article.extra,
    ).where((f) => !displayedValues.contains(f.selectionKey)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!article.hasForms)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Формы пока не подготовлены.'),
          ),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Таблица'),
              selected: !detailed,
              onSelected: (_) => setState(() => detailed = false),
            ),
            ChoiceChip(
              label: const Text('Подробно'),
              selected: detailed,
              onSelected: (_) => setState(() => detailed = true),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Подчёркивание — окончание; ∅ — нулевое окончание. — означает отсутствие данных для ячейки. Дополнительные написания раскрываются отдельно.',
        ),
        if (!detailed && article.paradigms.isNotEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Таблицу можно прокрутить по горизонтали.'),
          ),
        if (article.morphologyStatus == 'unassigned')
          Text(
            article.hasForms
                ? 'Парадигма пока не определена. Показаны известные формы.'
                : 'Парадигма пока не определена.',
          ),
        if (article.morphologyStatus == 'notApplicable')
          const Text('Слово не изменяется.'),
        for (final p in article.paradigms.where((p) => p.slots.isNotEmpty))
          if (detailed)
            ExpansionTile(
              key: PageStorageKey(
                '${article.id}:detail:${article.paradigms.indexOf(p)}',
              ),
              title: Text(p.title),
              children: [
                for (final slot in p.slots)
                  if (readableForms(slot.forms).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text(slot.label)),
                              IconButton(
                                tooltip: 'Грамматическая подпись',
                                onPressed: () => showDialog<void>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Форма слова'),
                                    content: Text(grammaticalHelp(slot.label)),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('Понятно'),
                                      ),
                                    ],
                                  ),
                                ),
                                icon: const Icon(Icons.info_outline, size: 18),
                              ),
                            ],
                          ),
                          cell(slot.label, slot.forms),
                        ],
                      ),
                    ),
              ],
            )
          else
            ExpansionTile(
              key: PageStorageKey(
                '${article.id}:table:${article.paradigms.indexOf(p)}',
              ),
              title: Text(p.title),
              initiallyExpanded: p == defaultParadigm,
              children: [
                for (final table in formGrids(p))
                  grid(table, showTitle: table.title != p.title),
                // Unmapped IDs stay visible as supplied; no guessed table axes.
                for (final slot in p.slots)
                  if (!RegExp(
                    r'^(sg|pl|du)([MFN]*)(Nom|Gen|Dat|Acc|Ins|Loc|Voc)|^(pres|imperf|aor|imp)(Sg|Pl|Du)([123]+)$',
                  ).hasMatch(slot.id))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(slot.label),
                          cell(slot.label, slot.forms),
                        ],
                      ),
                    ),
              ],
            ),
        if (extra.isNotEmpty)
          ExpansionTile(
            key: PageStorageKey('${article.id}:extra:$detailed'),
            initiallyExpanded: article.paradigms.every((p) => p.slots.isEmpty),
            title: Text(
              extra.every((f) => f.formOrigin == 'dictionary')
                  ? 'Другие выписанные формы'
                  : 'Дополнительные формы',
            ),
            children: [
              for (final f in extra)
                ListTile(
                  title: cell(f.grammar, [f]),
                  subtitle: f.grammar.isEmpty
                      ? null
                      : Text(conciseGrammar(f.grammar)),
                ),
            ],
          ),
      ],
    );
  }
}
