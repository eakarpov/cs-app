import 'models.dart';

String morphemeKind(String kind) =>
    const {
      'prefix': 'приставка',
      'root': 'корень',
      'interfix': 'соединительная гласная',
      'derivational_suffix': 'суффикс',
      'formative_suffix': 'формообразующий суффикс',
      'stem_suffix': 'расширитель основы',
      'thematic_vowel': 'тематическая гласная',
      'inflection': 'окончание',
      'postfix': 'постфикс',
      'orthography': 'орфографический элемент',
      'unresolved': 'неопределённая часть',
    }[kind] ??
    kind;

String analysisStatus(String status) =>
    const {
      'approved': 'Проверено',
      'proposed': 'Рабочая гипотеза',
      'disputed': 'Спорный разбор',
      'partial': 'Частичный разбор',
    }[status] ??
    'Статус не указан';

class MorphemePart {
  MorphemePart(Json j)
    : id = string(j['id']),
      surface = string(j['surface']),
      kind = string(j['kind']),
      gloss = string(j['gloss']),
      morphemeId = j['morphemeId'] as String?;
  final String id, surface, kind, gloss;
  final String? morphemeId;
  bool get navigable =>
      morphemeId != null &&
      const {
        'root',
        'prefix',
        'derivational_suffix',
        'formative_suffix',
        'stem_suffix',
        'postfix',
      }.contains(kind);
}

/// One displayed grapheme, with explicit server-resolved ownership. Historical
/// fusion can have more than one owner without duplicating the written letter.
class MorphemeLetter {
  MorphemeLetter(Json j)
    : text = string(j['text']),
      partIds = array(j['partIds']).map(string).toList(),
      colorKinds = array(j['colorKinds']).map(string).toList(),
      note = string(j['note']);
  final String text, note;
  final List<String> partIds, colorKinds;
}

class MorphemeAnalysis {
  MorphemeAnalysis(Json j)
    : id = string(j['id']),
      form = string(j['form']),
      status = string(j['status']),
      note = string(j['note']),
      parts = array(j['parts']).map((v) => MorphemePart(object(v))).toList(),
      letters = array(
        j['letters'],
      ).map((v) => MorphemeLetter(object(v))).toList();
  final String id, form, status, note;
  final List<MorphemePart> parts;
  final List<MorphemeLetter> letters;
}

class WordMorphemes {
  WordMorphemes(Json j)
    : version = string(j['version']),
      analyses = array(
        j['analyses'],
      ).map((v) => MorphemeAnalysis(object(v))).toList();
  final String version;
  final List<MorphemeAnalysis> analyses;
}

class MorphemeCard {
  MorphemeCard(Json j)
    : id = string(j['id']),
      title = string(j['title']),
      kind = string(j['kind']),
      gloss = string(j['gloss']),
      status = string(j['status']),
      version = string(j['version']),
      wordCount = (object(j['statistics'])['lexemes'] as num?)?.toInt() ?? 0,
      formCount = (object(j['statistics'])['forms'] as num?)?.toInt() ?? 0,
      variants = array(j['allomorphs']).map(object).toList(),
      composition = MorphemeComposition(object(j['composition'])),
      etymology = MorphemeEtymology(object(j['etymology'])),
      sources = array(j['sources']).map(object).toList();
  final String id, title, kind, gloss, status, version;
  final int wordCount, formCount;
  final List<Json> variants, sources;
  final MorphemeComposition composition;
  final MorphemeEtymology etymology;
  String get meaning => gloss == 'INF' ? 'Показатель инфинитива' : gloss;
}

class MorphemeWords {
  MorphemeWords(Json j)
    : version = string(j['version']),
      total = (j['total'] as num?)?.toInt() ?? 0,
      items = array(j['items']).map(object).toList(),
      nextCursor = j['nextCursor'] as String?;
  final String version;
  final int total;
  final List<Json> items;
  final String? nextCursor;
}

class MorphemeComposition {
  MorphemeComposition(Json j)
    : models = array(j['models']).map(object).toList(),
      notes = array(j['notes']).map(object).toList();
  final List<Json> models, notes;
}

class MorphemeEtymology {
  MorphemeEtymology(Json j)
    : nodes = array(j['nodes']).map(object).toList(),
      relations = array(j['relations']).map(object).toList(),
      chains = array(j['chains']).map(object).toList(),
      notes = array(j['notes']).map(object).toList();
  final List<Json> nodes, relations, chains, notes;

  /// A display order follows explicit dependencies, never array order or dates.
  /// Each relation keeps its complete input set, so a branch is not a sequence.
  List<Json> orderedRelations(Json chain) {
    final byId = {for (final r in relations) string(r['id']): r};
    final pending = array(chain['relationIds']).map((id) {
      final r = byId[string(id)];
      if (r == null) throw const FormatException('Не найдена связь цепочки.');
      return r;
    }).toList();
    final result = <Json>[];
    while (pending.isNotEmpty) {
      final available = pending
          .where(
            (r) =>
                r['type'] == 'comparison' ||
                !pending.any(
                  (other) =>
                      other['type'] != 'comparison' &&
                      array(r['fromNodeIds']).contains(other['toNodeId']),
                ),
          )
          .toList();
      if (available.isEmpty) {
        throw const FormatException('Цикл в исторической цепочке.');
      }
      available.sort((a, b) => string(a['id']).compareTo(string(b['id'])));
      for (final r in available) {
        result.add(r);
        pending.remove(r);
      }
    }
    return result;
  }
}
