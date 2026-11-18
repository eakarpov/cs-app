import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../domain/models.dart';
import '../domain/form_presentation.dart';

bool _canOpenSource(Json evidence) =>
    evidence['kind'] == 'source-entry' &&
    RegExp(r'^[a-f0-9]{64}$').hasMatch(string(evidence['sourceId']));

Future<void> showFormInformation(
  BuildContext context,
  WordForm form, {
  required double fontSize,
  required void Function(String, String?) openSource,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .8,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Сведения о форме',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          SelectableText(
            form.value,
            style: TextStyle(fontFamily: 'Monomakh', fontSize: fontSize + 4),
          ),
          if (form.grammar.isNotEmpty) Text(conciseGrammar(form.grammar)),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Происхождение'),
            subtitle: Text(form.originLabel),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Проверка формы и привязки'),
            subtitle: Text(form.reviewLabel),
          ),
          if (form.formOrigin == 'generated')
            const Text(
              'Расчёт по схеме не подтверждает употребление формы в тексте.',
            ),
          Text(
            'Источниковые сведения',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (form.provenance.isEmpty) const Text('Источник не установлен.'),
          for (final p in form.provenance)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(p.label),
              subtitle: Text(
                [
                  if (p.attribution.isNotEmpty && p.attribution != 'unknown')
                    'Атрибуция: ${p.attribution}',
                  if (p.carrierVersionId.isNotEmpty)
                    'Версия носителя: ${p.carrierVersionId}',
                  if (p.reportedSourceId.isNotEmpty)
                    'Указанный в словаре источник: ${p.reportedSourceId}',
                ].join('\n'),
              ),
            ),
          for (final evidence in form.evidence)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                string(
                  evidence['title'],
                  string(evidence['kind'], 'Основание'),
                ),
              ),
              subtitle: SelectableText(
                [
                  if (string(evidence['sourceId']).isNotEmpty)
                    'Источник: ${evidence['sourceId']}',
                  if (string(evidence['sourceVersion']).isNotEmpty)
                    'Ревизия: ${evidence['sourceVersion']}',
                  if (string(evidence['targetId']).isNotEmpty)
                    'Основание схемы: ${evidence['targetId']}',
                  if (evidence['target'] != null)
                    'Адрес текста: ${evidence['target']}',
                ].join('\n'),
              ),
              trailing: _canOpenSource(evidence)
                  ? const Icon(Icons.chevron_right)
                  : null,
              onTap: _canOpenSource(evidence)
                  ? () => openSource(
                      string(evidence['sourceId']),
                      string(evidence['sourceVersion']).isEmpty
                          ? null
                          : string(evidence['sourceVersion']),
                    )
                  : null,
            ),
          if (form.evidence.isEmpty)
            const Text('Точное место свидетельства не указано.'),
          TextButton.icon(
            onPressed: () => Clipboard.setData(ClipboardData(text: form.value)),
            icon: const Icon(Icons.copy_outlined),
            label: const Text('Копировать форму'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    ),
  ),
);
