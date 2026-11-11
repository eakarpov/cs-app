import 'models.dart';
import 'grammar_labels.dart';

bool hasTitlo(String value) => RegExp('[\u0483\u0487]').hasMatch(value);
bool hasRaisedLetters(String value) =>
    RegExp('[\u2de0-\u2dff\ua674-\ua67d]').hasMatch(value);

List<WordForm> uniqueForms(Iterable<WordForm> forms) {
  final seen = <String>{};
  return forms.where((f) => seen.add(f.value)).toList();
}

List<WordForm> readableForms(Iterable<WordForm> forms) =>
    uniqueForms(forms.where((f) => !hasTitlo(f.value)));

/// Chooses a display representative, without asserting a new dictionary norm.
/// Exact API order is preserved among ordinary spellings of the same status.
WordForm? primaryForm(Iterable<WordForm> forms) {
  final plain = readableForms(forms).where((f) => !hasRaisedLetters(f.value));
  if (plain.isEmpty) return null;
  return plain.first;
}

String conciseProperties(WordArticle article) {
  const inherent = {
    'SPRO',
    'NUM',
    'NUMR',
    'APRO',
    'ANUM',
    'S',
    'A',
    'V',
    'm',
    'f',
    'n',
    'anim',
    'inan',
    'persn',
    'topn',
    'poss',
    'ADV',
    'CONJ',
    'PART',
    'PR',
    'INTJ',
    'ADVPRO',
    'plur',
    'pf',
    'ipf',
    'tran',
    'intr',
    'med',
  };
  return article.properties
      .where(inherent.contains)
      .map(propertyLabel)
      .toSet()
      .join(' · ');
}

String conciseGrammar(String value) => value
    .split(' / ')
    .map(
      (reading) => reading
          .split(' · ')
          .map((v) => v.trim())
          .where((v) => v.isNotEmpty)
          .toSet()
          .join(' · '),
    )
    .where((v) => v.isNotEmpty)
    .toSet()
    .join(' / ');

class WordHeading {
  WordHeading(WordArticle article) {
    final initial = <WordForm>[
      for (final p in article.paradigms)
        for (final slot in p.slots)
          if (const {'sgNom', 'sgMNomAcc', 'sgMNom', 'inf'}.contains(slot.id) ||
              (article.properties.contains('plur') && slot.id == 'plNom'))
            ...slot.forms,
      for (final f in article.extra)
        if ((RegExp(r'\bsg\b').hasMatch(f.grammar) &&
                RegExp(r'\bnom\b').hasMatch(f.grammar)) ||
            (f.grammar.contains('единственное число') &&
                f.grammar.contains('именительный')))
          f,
    ];
    name = hasTitlo(article.name)
        ? primaryForm(initial)?.value ?? article.name
        : article.name;
    titloVariants = {
      if (hasTitlo(article.name) && article.name != name) article.name,
      for (final f in initial)
        if (hasTitlo(f.value) && f.value != name) f.value,
    }.toList();
  }
  late final String name;
  late final List<String> titloVariants;
}

class FormGrid {
  FormGrid(this.title, this.rowHeading, this.rows, this.columns, this.cells);
  final String title, rowHeading;
  final List<String> rows, columns;
  final Map<String, List<WordForm>> cells;
  List<WordForm> forms(int row, int column) => cells['$row:$column'] ?? [];
}

/// Slot IDs are the server contract. Labels are not parsed to infer grammar.
List<FormGrid> formGrids(Paradigm paradigm) {
  const numbers = ['sg', 'pl', 'du'];
  const numberLabels = ['Ед. ч.', 'Мн. ч.', 'Дв. ч.'];
  const cases = ['Nom', 'Gen', 'Dat', 'Acc', 'Ins', 'Loc', 'Voc'];
  const caseLabels = [
    'Именительный',
    'Родительный',
    'Дательный',
    'Винительный',
    'Творительный',
    'Местный',
    'Звательный',
  ];
  final result = <FormGrid>[];
  final verb = RegExp(r'^(pres|imperf|aor|imp)(Sg|Pl|Du)([123]+)$');
  for (final tense in const {
    'pres': 'Настоящее время',
    'imp': 'Повелительное наклонение',
    'imperf': 'Имперфект',
    'aor': 'Аорист',
  }.entries) {
    final cells = <String, List<WordForm>>{};
    for (final slot in paradigm.slots) {
      final m = verb.firstMatch(slot.id);
      if (m == null || m[1] != tense.key) continue;
      final col = numbers.indexOf(m[2]!.toLowerCase());
      for (final person in m[3]!.split('')) {
        cells
            .putIfAbsent('${int.parse(person) - 1}:$col', () => [])
            .addAll(slot.forms);
      }
    }
    if (cells.isNotEmpty) {
      result.add(
        FormGrid(
          tense.value,
          'Лицо',
          ['1-е лицо', '2-е лицо', '3-е лицо'],
          numberLabels,
          cells,
        ),
      );
    }
  }
  final nominal = RegExp(r'^(sg|pl|du)([MFN]*)(Nom|Gen|Dat|Acc|Ins|Loc|Voc)');
  final slots = paradigm.slots.where((s) => nominal.hasMatch(s.id)).toList();
  final gendered = slots.any((s) => nominal.firstMatch(s.id)![2]!.isNotEmpty);
  for (final gender in gendered ? ['M', 'F', 'N'] : ['']) {
    final cells = <String, List<WordForm>>{};
    for (var col = 0; col < numbers.length; col++) {
      for (var row = 0; row < cases.length; row++) {
        final matches = <FormSlot>[];
        for (final slot in slots) {
          if (slot.id == 'plMAccFNomAcc') {
            if (col == 1 &&
                ((gender == 'M' && cases[row] == 'Acc') ||
                    (gender == 'F' && ['Nom', 'Acc'].contains(cases[row])))) {
              matches.add(slot);
            }
            continue;
          }
          final m = nominal.firstMatch(slot.id)!;
          if (m[1] != numbers[col] || !slot.id.contains(cases[row])) continue;
          if (m[2]!.isNotEmpty && !m[2]!.contains(gender)) continue;
          matches.add(slot);
        }
        if (matches.isEmpty) continue;
        // A dedicated slot (e.g. sgMAcc) overrides a syncretic slot.
        final exact = matches
            .where((s) => s.id == '${numbers[col]}$gender${cases[row]}')
            .toList();
        cells['$row:$col'] = [
          for (final s in exact.isNotEmpty ? exact : matches) ...s.forms,
        ];
      }
    }
    if (cells.isNotEmpty) {
      result.add(
        FormGrid(
          const {
                'M': 'Мужской род',
                'F': 'Женский род',
                'N': 'Средний род',
              }[gender] ??
              paradigm.title,
          'Падеж',
          caseLabels,
          numberLabels,
          cells,
        ),
      );
    }
  }
  return result;
}
