part of 'morphemes_view.dart';

class _MorphemeDetails extends StatefulWidget {
  const _MorphemeDetails({
    required this.card,
    required this.fontSize,
    required this.openTarget,
  });
  final MorphemeCard card;
  final double fontSize;
  final ValueChanged<Json> openTarget;
  @override
  State<_MorphemeDetails> createState() => _MorphemeDetailsState();
}

class _MorphemeDetailsState extends State<_MorphemeDetails>
    with AutomaticKeepAliveClientMixin {
  String? selectedVariant;
  @override
  bool get wantKeepAlive => true;
  Widget heading(String title) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 8),
    child: Text(title, style: Theme.of(context).textTheme.titleLarge),
  );
  _Evidence evidence(Json value) =>
      _Evidence(value: value, card: widget.card, openTarget: widget.openTarget);
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final card = widget.card;
    final variants = card.variants
        .where((v) => string(v['id']).isNotEmpty)
        .toList();
    final variant =
        selectedVariant ??
        (variants.isEmpty ? '' : string(variants.first['id']));
    final models = card.composition.models
        .where((m) => array(m['allomorphIds']).contains(variant))
        .toList();
    return ListView(
      key: const PageStorageKey('morpheme-etymology'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        heading('Внутренний состав'),
        if (variants.length > 1)
          DropdownButtonFormField<String>(
            key: ValueKey(variant),
            initialValue: variant,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Вариант морфемы'),
            items: [
              for (final v in variants)
                DropdownMenuItem(
                  value: string(v['id']),
                  child: Text(
                    string(v['surface']).isEmpty ? '∅' : string(v['surface']),
                  ),
                ),
            ],
            onChanged: (v) => setState(() => selectedVariant = v),
          ),
        if (models.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Внутренний состав этого варианта пока не описан.'),
          ),
        for (final model in models)
          _CompositionView(
            key: ValueKey(model['id']),
            model: model,
            card: card,
            fontSize: widget.fontSize,
            openTarget: widget.openTarget,
          ),
        if (card.composition.notes.isNotEmpty)
          ExpansionTile(
            key: const PageStorageKey('composition-notes'),
            tilePadding: EdgeInsets.zero,
            title: const Text('Дополнительные описания состава'),
            subtitle: const Text(
              'Привязка к выбранному варианту не установлена.',
            ),
            children: [
              for (final note in card.composition.notes) evidence(note),
            ],
          ),
        heading('Происхождение'),
        if (card.etymology.chains.isEmpty && card.etymology.notes.isEmpty)
          const Text('Этимологические связи пока не описаны.'),
        for (final chain in card.etymology.chains)
          _ChainView(
            key: ValueKey(chain['id']),
            chain: chain,
            card: card,
            openTarget: widget.openTarget,
          ),
        if (card.etymology.notes.isNotEmpty) ...[
          if (card.etymology.chains.isEmpty)
            const Text(
              'Историческое описание. Последовательность этапов пока не задана.',
            ),
          for (final note in card.etymology.notes) evidence(note),
        ],
        if (card.variants.isNotEmpty)
          ExpansionTile(
            key: const PageStorageKey('morpheme-variants'),
            tilePadding: EdgeInsets.zero,
            title: Text('Варианты морфемы · ${card.variants.length}'),
            children: [
              for (final v in card.variants)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    string(v['surface']).isEmpty ? '∅' : string(v['surface']),
                    style: TextStyle(
                      fontFamily: 'Monomakh',
                      fontSize: widget.fontSize,
                    ),
                  ),
                  subtitle: Text(
                    '${analysisStatus(string(v['status']))}\n${string(v['note'])}',
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _Evidence extends StatelessWidget {
  const _Evidence({
    required this.value,
    required this.card,
    required this.openTarget,
  });
  final Json value;
  final MorphemeCard card;
  final ValueChanged<Json> openTarget;
  @override
  Widget build(BuildContext context) {
    final sources = {for (final s in card.sources) string(s['id']): s};
    final refs = array(value['evidence']).map(object).toList();
    final target = object(value['target']);
    const functions = {
      'nominal_formant': 'Именной формант',
      'historical_case_form_reflex': 'Рефлекс исторической падежной формы',
      'nominal_suffix': 'Именной суффикс',
      'adjectival_suffix': 'Суффикс прилагательного',
      'thematic_vowel': 'Тематическая гласная',
      'root_final_glide': 'Исторический конечный элемент корня',
      'historical_nasal_reflex': 'Рефлекс исторического носового',
      'internal_negation': 'Историческое отрицание',
      'internal_prefix': 'Историческая приставка',
      'internal_root': 'Исторический корень',
    };
    final function = functions[string(value['function'])];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (string(value['title']).isNotEmpty)
            Text(
              string(value['title']),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          if (function != null) Text(function),
          if (string(value['reconstruction']).isNotEmpty)
            Text(string(value['reconstruction'])),
          if (string(value['status']).isNotEmpty)
            Text(analysisStatus(string(value['status']))),
          if (string(value['text']).isNotEmpty) Text(string(value['text'])),
          if (string(value['note']).isNotEmpty) Text(string(value['note'])),
          if (refs.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              key: PageStorageKey('sources-${value['id']}'),
              title: Text('Источники · ${refs.length}'),
              children: [
                for (final e in refs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(string(sources[string(e['sourceId'])]?['title'])),
                        if (string(e['locator']).isNotEmpty)
                          Text(string(e['locator'])),
                        if (string(e['quote']).isNotEmpty)
                          Text('«${string(e['quote'])}»'),
                        if (string(e['supports']).isNotEmpty)
                          Text(string(e['supports'])),
                      ],
                    ),
                  ),
              ],
            ),
          if (target.isNotEmpty &&
              !(target['kind'] == 'morpheme' && target['id'] == card.id))
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => openTarget(target),
                child: Text(
                  target['kind'] == 'interlex'
                      ? 'Этимологическая статья'
                      : 'Связанная морфема',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CompositionView extends StatefulWidget {
  const _CompositionView({
    super.key,
    required this.model,
    required this.card,
    required this.fontSize,
    required this.openTarget,
  });
  final Json model;
  final MorphemeCard card;
  final double fontSize;
  final ValueChanged<Json> openTarget;
  @override
  State<_CompositionView> createState() => _CompositionViewState();
}

class _CompositionViewState extends State<_CompositionView>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  String? selected;
  Widget partButton(Json p, bool selectedPart) {
    final color = morphemeColor(string(p['kind']));
    final surface = p['surface'] == ''
        ? '∅'
        : string(p['surface']).isEmpty
        ? string(p['label'])
        : string(p['surface']);
    return Semantics(
      selected: selectedPart,
      label: '${string(p['label'])}. ${analysisStatus(string(p['status']))}',
      button: true,
      child: Material(
        color: color,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(
            color: selectedPart ? const Color(0xffb94e0c) : Colors.black26,
            width: selectedPart ? 3 : 1,
          ),
        ),
        child: InkWell(
          onTap: () => setState(() => selected = string(p['id'])),
          borderRadius: BorderRadius.circular(4),
          child: Container(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text(
              surface,
              style: TextStyle(
                fontFamily: 'Monomakh',
                fontSize: widget.fontSize,
                color: color.computeLuminance() > .5
                    ? Colors.black
                    : Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final model = widget.model;
    final parts = array(model['parts']).map(object).toList();
    final index = parts.indexWhere((p) => p['id'] == selected);
    final part = parts.isEmpty ? null : parts[index < 0 ? 0 : index];
    final mapping = switch (model['mappingMode']) {
      'fusion' => 'Слияние компонентов',
      'concatenative' => 'Последовательное соединение',
      _ => 'Буквенное соответствие не установлено',
    };
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            model['level'] == 'historical'
                ? 'Исторический состав'
                : 'Письменный состав',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(analysisStatus(string(model['status']))),
          Text(mapping),
          const SizedBox(height: 8),
          Card(
            key: ValueKey('composition-scheme-${model['id']}'),
            color: Colors.white,
            surfaceTintColor: Colors.transparent,
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final p in parts)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: partButton(p, p == part),
                      ),
                  ],
                ),
              ),
            ),
          ),

          if (part != null)
            _Evidence(
              value: {...part, 'title': string(part['label'])},
              card: widget.card,
              openTarget: widget.openTarget,
            ),
          if (string(model['note']).isNotEmpty ||
              array(model['evidence']).isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              key: PageStorageKey('composition-note-${model['id']}'),
              title: const Text('Пояснение состава'),
              children: [
                _Evidence(
                  value: model,
                  card: widget.card,
                  openTarget: widget.openTarget,
                ),
              ],
            ),
          if (model['level'] == 'historical')
            const Text(
              'Исторические компоненты не меняют письменный разбор слова.',
            ),
        ],
      ),
    );
  }
}

class _ChainView extends StatefulWidget {
  const _ChainView({
    super.key,
    required this.chain,
    required this.card,
    required this.openTarget,
  });
  final Json chain;
  final MorphemeCard card;
  final ValueChanged<Json> openTarget;
  @override
  State<_ChainView> createState() => _ChainViewState();
}

class _ChainViewState extends State<_ChainView>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  bool earlier = false;
  Widget node(Json node) {
    final language = object(node['language']);
    final variety = object(node['variety']);
    final period = object(node['period']);
    final main = string(node['form']).isNotEmpty
        ? string(node['form'])
        : string(node['label']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          main,
          style: const TextStyle(fontFamily: 'Monomakh', fontSize: 22),
        ),
        if (main != string(node['label'])) Text(string(node['label'])),
        Text(switch (node['formType']) {
          'reconstructed' => 'Реконструкция',
          'descriptive' => 'Описание исторического состояния',
          _ => 'Засвидетельствованная форма',
        }),
        if (string(node['meaning']).isNotEmpty) Text(string(node['meaning'])),
        Text(language.isEmpty ? 'Язык не указан' : string(language['label'])),
        if (variety.isNotEmpty) Text(string(variety['label'])),
        Text(
          period.isEmpty ? 'Датировка не установлена' : string(period['label']),
        ),
        _Evidence(
          value: node,
          card: widget.card,
          openTarget: widget.openTarget,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final history = widget.card.etymology;
    final nodes = {for (final n in history.nodes) string(n['id']): n};
    List<Json> relations;
    try {
      relations = history.orderedRelations(widget.chain);
    } on FormatException catch (e) {
      return Text(e.message.toString());
    }
    final visible = earlier
        ? relations
        : relations.length > 3
        ? relations.sublist(relations.length - 3)
        : relations;
    return ExpansionTile(
      key: PageStorageKey(widget.chain['id']),
      tilePadding: EdgeInsets.zero,
      initiallyExpanded: history.chains.length == 1,
      title: Text(string(widget.chain['title'])),
      subtitle: Text(analysisStatus(string(widget.chain['status']))),
      children: [
        _Evidence(
          value: widget.chain,
          card: widget.card,
          openTarget: widget.openTarget,
        ),
        if (relations.length > 3)
          TextButton(
            onPressed: () => setState(() => earlier = !earlier),
            child: Text(earlier ? 'Ближайшие этапы' : 'Ранее'),
          ),
        for (final r in visible)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (array(r['fromNodeIds']).length > 1)
                  Text(
                    r['type'] == 'comparison'
                        ? 'Сопоставляемые формы'
                        : 'Совместные компоненты',
                  ),
                for (final id in array(r['fromNodeIds']))
                  if (nodes[string(id)] != null) node(nodes[string(id)]!),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 16, right: 8),
                      child: Text(
                        r['type'] == 'comparison'
                            ? '↔'
                            : r['status'] == 'approved'
                            ? '│\n↓'
                            : '┊\n↓',
                        style: const TextStyle(fontSize: 20),
                      ),
                    ),
                    Expanded(
                      child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        key: PageStorageKey('relation-${r['id']}'),
                        title: Text(string(r['label'])),
                        subtitle: Text(analysisStatus(string(r['status']))),
                        children: [
                          _Evidence(
                            value: r,
                            card: widget.card,
                            openTarget: widget.openTarget,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (nodes[string(r['toNodeId'])] != null)
                  node(nodes[string(r['toNodeId'])]!),
                const Divider(),
              ],
            ),
          ),
      ],
    );
  }
}
