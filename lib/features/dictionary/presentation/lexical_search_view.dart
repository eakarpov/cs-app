import 'package:flutter/material.dart';
import '../../../core/personal_store.dart';
import '../domain/models.dart';
import 'lexical_search_controller.dart';
import 'search_result_heading.dart';

class LexicalSearchView extends StatefulWidget {
  const LexicalSearchView({
    super.key,
    required this.controller,
    required this.personal,
    required this.open,
  });
  final LexicalSearchController controller;
  final PersonalStore personal;
  final void Function(String) open;
  @override
  State<LexicalSearchView> createState() => _LexicalSearchViewState();
}

class _LexicalSearchViewState extends State<LexicalSearchView> {
  late final text = TextEditingController(text: widget.controller.query);
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  Widget result(LexicalResult r) => Card(
    child: ListTile(
      title: Text(
        r.name,
        style: TextStyle(
          fontFamily: 'Monomakh',
          fontSize: widget.personal.fontSize,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in r.evidence)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                [
                  'Значение исходного слова: ${string(e['anchorText'])}',
                  if (string(e['targetAnchorText']).isNotEmpty)
                    'Значение найденного слова: ${string(e['targetAnchorText'])}',
                  if (string(e['basis']).isNotEmpty) string(e['basis']),
                ].join('\n'),
              ),
            ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => widget.open(r.id),
    ),
  );
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final verified = c.results.where((r) => !r.proposed).toList();
      final proposed = c.results.where((r) => r.proposed).toList();
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Выберите слово и лексический класс. Связи относятся к конкретным значениям.',
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('lexical-query'),
            controller: text,
            maxLength: 120,
            style: TextStyle(
              fontFamily: 'Monomakh',
              fontSize: widget.personal.fontSize,
            ),
            decoration: InputDecoration(
              labelText: 'Слово или словоформа',
              suffixIcon: IconButton(
                tooltip: 'Очистить слово',
                icon: const Icon(Icons.clear),
                onPressed: () {
                  text.clear();
                  c.change('');
                },
              ),
            ),
            onChanged: c.change,
          ),
          if (c.suggesting) const LinearProgressIndicator(),
          for (final candidate in c.candidates)
            ListTile(
              title: SearchResultHeading(
                hit: candidate,
                size: widget.personal.fontSize,
              ),
              subtitle: Text(
                [
                  candidate.pos,
                  candidate.matched,
                  candidate.grammar,
                ].where((v) => v.isNotEmpty).join(' · '),
              ),
              onTap: () {
                text.text = candidate.name;
                c.select(candidate);
                FocusManager.instance.primaryFocus?.unfocus();
              },
            ),
          if (!c.suggesting &&
              c.query.trim().isNotEmpty &&
              c.selected == null &&
              c.candidates.isEmpty &&
              c.error == null)
            const Text('Слово не найдено. Попробуйте другое написание.'),
          if (c.selected != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Выбрано: ${c.selected!.name}',
                semanticsLabel: 'Выбрано слово ${c.selected!.name}',
              ),
            ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: c.type,
            decoration: const InputDecoration(labelText: 'Лексический класс'),
            items: const [
              DropdownMenuItem(value: 'synonym', child: Text('Синонимы')),
              DropdownMenuItem(value: 'antonym', child: Text('Антонимы')),
            ],
            onChanged: (v) {
              if (v != null) c.selectType(v);
            },
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: c.selected == null || c.loading ? null : c.find,
            icon: const Icon(Icons.search),
            label: const Text('Найти'),
          ),
          if (c.loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (c.error != null) ...[
            Text(c.error!),
            TextButton(
              onPressed: () {
                if (c.selected == null) {
                  c.change(text.text);
                } else {
                  c.find();
                }
              },
              child: const Text('Повторить'),
            ),
          ],
          if (c.searched) ...[
            const SizedBox(height: 20),
            Text(
              '${c.type == 'synonym' ? 'Синонимы' : 'Антонимы'}: ${c.selected!.name}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (verified.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Подтверждённых связей этого класса пока нет.'),
              ),
            for (final r in verified) result(r),
            if (proposed.isNotEmpty && widget.personal.showProposed)
              ExpansionTile(
                title: Text('Предположительные связи (${proposed.length})'),
                subtitle: const Text(
                  'Нуждаются в проверке; совпадение перевода само по себе не доказывает связь.',
                ),
                children: proposed.map(result).toList(),
              ),
            if (proposed.isNotEmpty && !widget.personal.showProposed)
              const Text('Предположительные связи скрыты в настройках.'),
          ],
        ],
      );
    },
  );
}
