import 'package:flutter/material.dart';
import '../data/dictionary_repository.dart';

Future<void> showContentReport(
  BuildContext context,
  DictionaryRepository repository, {
  String? id,
  String? query,
}) async {
  await showDialog<void>(
    context: context,
    builder: (context) =>
        _ReportDialog(repository: repository, id: id, query: query),
  );
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog({required this.repository, this.id, this.query});
  final DictionaryRepository repository;
  final String? id, query;
  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final comment = TextEditingController();
  String reason = 'inaccurate';
  String? error;
  bool sending = false;
  @override
  void initState() {
    super.initState();
    if (widget.id == null) reason = 'missing';
  }

  @override
  void dispose() {
    comment.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (comment.text.trim().length < 3) {
      setState(() => error = 'Добавьте короткое пояснение.');
      return;
    }
    setState(() {
      sending = true;
      error = null;
    });
    try {
      await widget.repository.report(
        reason: reason,
        comment: comment.text.trim(),
        lexemeId: widget.id,
        query: widget.query,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          sending = false;
          error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Сообщить об ошибке'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.query != null) Text('Запрос: ${widget.query}'),
          DropdownButtonFormField<String>(
            initialValue: reason,
            items:
                const {
                      'missing': 'Не хватает слова',
                      'inaccurate': 'Неточное объяснение',
                      'morphology': 'Ошибка в формах',
                      'source': 'Ошибка источника',
                      'other': 'Другое',
                    }.entries
                    .map(
                      (e) =>
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                    )
                    .toList(),
            onChanged: sending ? null : (v) => setState(() => reason = v!),
          ),
          TextField(
            controller: comment,
            maxLength: 2000,
            minLines: 3,
            maxLines: 6,
            enabled: !sending,
            decoration: const InputDecoration(
              labelText: 'Что нужно исправить?',
            ),
          ),
          const Text(
            'Сообщение отправится редактору только после нажатия «Отправить».',
          ),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: sending ? null : () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(
        onPressed: sending ? null : submit,
        child: Text(sending ? 'Отправляем…' : 'Отправить'),
      ),
    ],
  );
}
