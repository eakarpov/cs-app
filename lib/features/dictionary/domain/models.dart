typedef Json = Map<String, Object?>;
Json object(Object? v) => v is Map ? v.cast<String, Object?>() : {};
List<Object?> array(Object? v) => v is List ? v.cast<Object?>() : [];
String string(Object? v, [String fallback = '']) => v is String ? v : fallback;

enum SearchIndicator { translation, prefix }

class SearchHit {
  SearchHit(Json j)
    : id = string(j['id']),
      name = string(j['name']),
      pos = string(j['pos']),
      match = string(j['match']),
      exact = j['exact'] != false,
      matched = string(j['matched']),
      grammar = string(j['grammar']);
  final String id, name, pos, match, matched, grammar;
  final bool exact;
  SearchIndicator? get indicator {
    if (match == 'explanation') return null;
    if (!exact) return SearchIndicator.prefix;
    return match == 'translation' ? SearchIndicator.translation : null;
  }

  String get matchLabel {
    final label =
        const {
          'lemma': 'Словарная форма',
          'stored-form': 'Словоформа из словаря',
          'source-variant': 'Вариант написания из источника',
          'generated-form': 'Расчётная форма',
          'translation': 'Совпадение с переводом',
          'explanation': 'Упоминание в объяснении',
        }[match] ??
        'Соответствие';
    return exact || match == 'explanation' ? label : '$label · по началу слова';
  }
}

class SearchPage {
  SearchPage(Json j)
    : version = string(j['version']),
      items = array(j['items']).map((v) => SearchHit(object(v))).toList(),
      nextCursor = j['nextCursor'] as String?;
  final String version;
  final List<SearchHit> items;
  final String? nextCursor;
}

class SourceCard {
  SourceCard(Json j)
    : id = string(j['id']),
      title = string(j['title']),
      preview = string(j['preview']),
      proposed = j['mappingStatus'] == 'proposed';
  final String id, title, preview;
  final bool proposed;
}

class DataOrigin {
  DataOrigin(Json j)
    : title = string(j['title'], 'Происхождение неизвестно'),
      origin = string(j['origin']),
      attribution = string(j['attribution']);
  final String title, origin, attribution;
  String get label => origin == 'unknown' || attribution == 'unknown'
      ? 'Происхождение неизвестно'
      : origin == 'reported-corpus'
      ? 'Свидетельство, указанное в словаре: $title'
      : title;
}

class WordForm {
  WordForm(Json j)
    : value = string(j['value']),
      stored = j['origin'] == 'stored',
      grammar = string(j['grammar']),
      provenance = array(
        j['provenance'],
      ).map((v) => DataOrigin(object(v))).toList(),
      segments = j['segments'] is List
          ? array(j['segments']).map(object).toList()
          : null;
  final String value, grammar;
  final List<DataOrigin> provenance;
  final bool stored;
  final List<Json>? segments;
}

class FormSlot {
  FormSlot(Json j)
    : label = string(j['label']),
      forms = array(j['forms']).map((f) => WordForm(object(f))).toList();
  final String label;
  final List<WordForm> forms;
}

class Paradigm {
  Paradigm(Json j)
    : title = string(j['title']),
      slots = array(j['slots']).map((s) => FormSlot(object(s))).toList();
  final String title;
  final List<FormSlot> slots;
}

class WordArticle {
  WordArticle(Json j)
    : id = string(j['id']),
      name = string(j['name']),
      pos = string(j['pos']),
      morphologyStatus = string(j['morphologyStatus']),
      lexemeOrigins = array(
        object(j['provenance'])['lexeme'],
      ).map((v) => DataOrigin(object(v))).toList(),
      schemeOrigins = array(
        object(j['provenance'])['scheme'],
      ).map((v) => DataOrigin(object(v))).toList(),
      properties = array(j['properties']).map(string).toList(),
      sources = array(j['sources']).map((v) => SourceCard(object(v))).toList(),
      relatedSources = array(
        j['relatedSources'],
      ).map((v) => SourceCard(object(v))).toList(),
      paradigms = array(
        j['paradigms'],
      ).map((v) => Paradigm(object(v))).toList(),
      extra = array(j['extra']).map((v) => WordForm(object(v))).toList(),
      relations = array(j['relations']).map(object).toList(),
      etymologies = array(j['etymologies']).map(object).toList(),
      usage = array(j['usage']).map(object).toList(),
      composition = array(j['composition']).map(object).toList();
  final String id, name, pos, morphologyStatus;
  final List<DataOrigin> lexemeOrigins, schemeOrigins;
  final List<String> properties;
  final List<SourceCard> sources, relatedSources;
  final List<Paradigm> paradigms;
  final List<WordForm> extra;
  final List<Json> relations, etymologies, usage, composition;
}

class SavedWord {
  const SavedWord(this.id, this.name);
  factory SavedWord.fromJson(Json j) =>
      SavedWord(string(j['id']), string(j['name']));
  final String id, name;
  Json toJson() => {'id': id, 'name': name};
}
