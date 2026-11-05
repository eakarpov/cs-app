import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Edits use UTF-16 offsets, like Flutter's selection, and never detach marks
/// from a selected base letter. The caller owns the controller and search.
TextEditingValue insertCs(
  TextEditingValue current,
  String value, {
  bool mark = false,
}) {
  final selection = current.selection;
  final start = selection.isValid ? selection.start : current.text.length;
  final end = selection.isValid ? selection.end : current.text.length;
  final at = mark ? end : start;
  if (mark &&
      (at == 0 ||
          !RegExp(
            r'[А-Яа-яЁёѠ-ӿꙀ-ꚟ\u0300-\u036f\u0483-\u0489\u2de0-\u2dff]',
          ).hasMatch(current.text.substring(at - 1, at)))) {
    return current;
  }
  final next = current.text.replaceRange(at, mark ? at : end, value);
  if (next.characters.length > 120) return current;
  return TextEditingValue(
    text: next,
    selection: TextSelection.collapsed(offset: at + value.length),
  );
}

TextEditingValue eraseCs(TextEditingValue current) {
  final selection = current.selection;
  final end = selection.isValid ? selection.end : current.text.length;
  var start = selection.isValid ? selection.start : end;
  if (start == end && start > 0) {
    start -= current.text.substring(0, start).characters.last.length;
  }
  return TextEditingValue(
    text: current.text.replaceRange(start, end, ''),
    selection: TextSelection.collapsed(offset: start),
  );
}

class CsKeyboard extends StatefulWidget {
  const CsKeyboard({super.key, required this.controller});
  final TextEditingController controller;
  @override
  State<CsKeyboard> createState() => _CsKeyboardState();
}

class _CsKeyboardState extends State<CsKeyboard> {
  bool capitals = false, covering = true;
  int tab = 0;
  String? message;
  static const letters =
      'а б в г д е ж ѕ з и і к л м н о п р с т ꙋ ф х ѡ ц ч ш щ ъ ы ь ѣ ю ꙗ ѯ ѱ ѳ ѵ';
  static const variants = 'є ѻ ѿ ѧ ѹ ї й ѥ ѫ ѩ ѭ ѷ у';
  static const marks = [
    ('\u0301', 'Острое ударение'),
    ('\u0300', 'Тяжёлое ударение'),
    ('\u0311', 'Камора'),
    ('\u0486', 'Звательце'),
    ('\u0485', 'Дасия'),
    ('\u0483', 'Титло'),
    ('\u0487', 'Покрытие'),
    ('\u0486\u0301', 'Звательце и острое'),
    ('\u0486\u0300', 'Звательце и тяжёлое'),
  ];

  void insert(String value, {bool mark = false}) {
    final next = insertCs(widget.controller.value, value, mark: mark);
    setState(
      () => message = next == widget.controller.value
          ? (mark
                ? 'Поставьте курсор после буквы. Не более 120 знаков.'
                : 'Не более 120 знаков.')
          : null,
    );
    widget.controller.value = next;
  }

  Widget key(String value, {String? label, bool mark = false}) => Padding(
    padding: const EdgeInsets.all(3),
    child: OutlinedButton(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      onPressed: () => insert(value, mark: mark),
      child: Semantics(
        label: label ?? value,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${mark ? '◌' : ''}$value',
              style: const TextStyle(fontFamily: 'Monomakh', fontSize: 28),
            ),
            if (label != null)
              Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    ),
  );

  Future<void> paste() async {
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    if (mounted && clip?.text != null) insert(clip!.text!);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .9,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(child: Text('Клавиатура ЦС')),
                IconButton(
                  tooltip: 'Закрыть клавиатуру',
                  onPressed: () => Navigator.pop(context, false),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            TextField(
              controller: widget.controller,
              readOnly: true,
              showCursor: true,
              maxLines: 2,
              style: const TextStyle(fontFamily: 'Monomakh', fontSize: 26),
              decoration: const InputDecoration(
                labelText: 'Слово или словоформа',
                helperText:
                    'Для надстрочного знака поставьте курсор после буквы.',
              ),
            ),
            if (message != null)
              Text(
                message!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('Буквы')),
                  ButtonSegment(value: 1, label: Text('Знаки')),
                  ButtonSegment(value: 2, label: Text('Буквотитла')),
                ],
                selected: {tab},
                onSelectionChanged: (v) => setState(() => tab = v.first),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    if (tab == 0) ...[
                      FilterChip(
                        label: const Text('Прописные буквы'),
                        selected: capitals,
                        onSelected: (v) => setState(() => capitals = v),
                      ),
                      Wrap(
                        alignment: WrapAlignment.center,
                        children: letters
                            .split(' ')
                            .map((s) => key(capitals ? s.toUpperCase() : s))
                            .toList(),
                      ),
                      const Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('Варианты начертания и исторические буквы'),
                      ),
                      Wrap(
                        alignment: WrapAlignment.center,
                        children: [
                          ...variants
                              .split(' ')
                              .map((s) => key(capitals ? s.toUpperCase() : s)),
                          key(capitals ? 'Оу' : 'ᲂу'),
                        ],
                      ),
                    ],
                    if (tab == 1)
                      Wrap(
                        alignment: WrapAlignment.center,
                        children: marks
                            .map((m) => key(m.$1, label: m.$2, mark: true))
                            .toList(),
                      ),
                    if (tab == 2) ...[
                      FilterChip(
                        label: const Text('С покрытием'),
                        selected: covering,
                        onSelected: (v) => setState(() => covering = v),
                      ),
                      Wrap(
                        alignment: WrapAlignment.center,
                        children: [
                          for (var i = 0; i < 32; i++)
                            key(
                              '${String.fromCharCode(0x2de0 + i)}${covering ? '\u0487' : ''}',
                              label: const [
                                'б',
                                'в',
                                'г',
                                'д',
                                'ж',
                                'з',
                                'к',
                                'л',
                                'м',
                                'н',
                                'о',
                                'п',
                                'р',
                                'с',
                                'т',
                                'х',
                                'ц',
                                'ч',
                                'ш',
                                'щ',
                                'ѳ',
                                'ст',
                                'а',
                                'е',
                                'ћ',
                                'ꙋ',
                                'ѣ',
                                'ю',
                                'ꙗ',
                                'ѧ',
                                'ѫ',
                                'ѭ',
                              ][i],
                              mark: true,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Удалить символ',
                  onPressed: () => widget.controller.value = eraseCs(
                    widget.controller.value,
                  ),
                  icon: const Icon(Icons.backspace_outlined),
                ),
                TextButton(
                  onPressed: () => insert(' '),
                  child: const Text('Пробел'),
                ),
                TextButton(onPressed: paste, child: const Text('Вставить')),
                TextButton(
                  onPressed: widget.controller.clear,
                  child: const Text('Очистить'),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.search),
                  label: const Text('Найти'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
