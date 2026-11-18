import 'dart:convert';

typedef Json = Map<String, Object?>;
Json object(Object? v) => v is Map ? v.cast<String, Object?>() : {};
List<Object?> array(Object? v) => v is List ? v.cast<Object?>() : [];
String string(Object? v, [String fallback = '']) => v is String ? v : fallback;

enum SearchIndicator { translation, prefix, exact }

class SearchHit {
  SearchHit(Json j)
    : id = string(j['id']),
      name = string(j['name']),
      pos = string(j['pos']),
      match = string(j['match']),
      exact = j['exact'] == true,
      hasExact = j['exact'] is bool,
      matched = string(j['matched']),
      grammar = string(j['grammar']);
  final String id, name, pos, match, matched, grammar;
  final bool exact, hasExact;
  SearchIndicator? get indicator {
    if (!{
          'lemma',
          'stored-form',
          'source-variant',
          'generated-form',
          'translation',
        }.contains(match) ||
        !hasExact) {
      return null;
    }
    if (!exact) return SearchIndicator.prefix;
    return match == 'translation'
        ? SearchIndicator.translation
        : const {
            'lemma',
            'stored-form',
            'source-variant',
            'generated-form',
          }.contains(match)
        ? SearchIndicator.exact
        : null;
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
    return !hasExact || exact || match == 'explanation'
        ? label
        : '$label · по началу слова';
  }
}

class SearchPage {
  SearchPage(Json j)
    : version = string(j['dictionaryVersion'], string(j['version'])),
      schemaVersion = j['schemaVersion'] == 2 ? 2 : 1,
      items = array(j['items']).map((v) => SearchHit(object(v))).toList(),
      nextCursor = j['nextCursor'] as String?;
  final String version;
  final int schemaVersion;
  final List<SearchHit> items;
  final String? nextCursor;
}

class SourceCard {
  SourceCard(Json j)
    : id = string(j['id']),
      title = string(j['title']),
      preview = string(j['preview']),
      mappingStatus = string(j['mappingStatus'], 'unknown'),
      sourceVersion = string(j['sourceVersion']),
      proposed = j['mappingStatus'] == 'proposed';
  final String id, title, preview, mappingStatus, sourceVersion;
  @Deprecated('Use mappingStatus; false does not prove verification.')
  final bool proposed;
  String get mappingLabel => switch (mappingStatus) {
    'verified' => 'Проверенное сопоставление',
    'proposed' => 'Сопоставление требует проверки',
    'disputed' => 'Спорное сопоставление',
    _ => 'Статус сопоставления не указан',
  };
}

class DataOrigin {
  DataOrigin(Json j)
    : title = string(j['title'], 'Происхождение неизвестно'),
      sourceId = string(j['sourceId']),
      targetId = string(j['targetId']),
      carrierVersionId = string(j['carrierVersionId']),
      reportedSourceId = string(j['reportedSourceId']),
      origin = string(j['origin']),
      attribution = string(j['attribution']);
  final String title, origin, attribution;
  final String sourceId, targetId, carrierVersionId, reportedSourceId;
  String get label => origin == 'unknown' || attribution == 'unknown'
      ? 'Происхождение неизвестно'
      : origin == 'reported-corpus'
      ? 'Свидетельство, указанное в словаре: $title'
      : title;
}

class WordForm {
  WordForm(Json j)
    : value = string(j['value']),
      formOrigin = string(
        j['formOrigin'],
        j['origin'] == 'stored'
            ? 'dictionary'
            : j['origin'] == 'generated'
            ? 'generated'
            : 'unknown',
      ),
      stored = j['origin'] == 'stored',
      reviewStatus = string(j['reviewStatus'], 'unknown'),
      evidence = array(j['evidence']).map(object).toList(),
      grammar = string(j['grammar']),
      provenance = array(
        j['provenance'],
      ).map((v) => DataOrigin(object(v))).toList(),
      segments = j['segments'] is List
          ? array(j['segments']).map(object).toList()
          : null;
  final String value, grammar, formOrigin;
  final String reviewStatus;
  final List<Json> evidence;
  String get originLabel => switch (formOrigin) {
    'dictionary' => 'Из словаря',
    'generated' => 'Расчётная форма',
    'attested' => 'Засвидетельствовано в тексте',
    _ => 'Происхождение неизвестно',
  };
  String get reviewLabel => switch (reviewStatus) {
    'verified' => 'Проверено',
    'proposed' => 'Требует проверки',
    'disputed' => 'Спорные сведения',
    _ => 'Проверка не зафиксирована',
  };
  // Local selection key within a publication, not a new public form identifier.
  String get selectionKey => jsonEncode([
    value,
    grammar,
    formOrigin,
    reviewStatus,
    provenance
        .map(
          (p) => [
            p.sourceId,
            p.targetId,
            p.carrierVersionId,
            p.reportedSourceId,
            p.origin,
            p.attribution,
            p.title,
          ],
        )
        .toList(),
    evidence,
    segments,
  ]);
  final List<DataOrigin> provenance;
  @Deprecated('Use formOrigin; false does not imply generated.')
  final bool stored;
  final List<Json>? segments;
}

class FormSlot {
  FormSlot(Json j)
    : id = string(j['id']),
      label = string(j['label']),
      forms = array(j['forms']).map((f) => WordForm(object(f))).toList();
  final String id, label;
  final List<WordForm> forms;
}

class Paradigm {
  Paradigm(Json j)
    : kind = string(j['kind']),
      title = string(j['title']),
      slots = array(j['slots']).map((s) => FormSlot(object(s))).toList();
  final String kind, title;
  final List<FormSlot> slots;
}

class DictionaryExample {
  DictionaryExample(Json j)
    : id = string(j['id']),
      quote = string(j['quote']),
      citation = string(j['citation']),
      sourceId = string(j['sourceId']),
      sourceTitle = string(j['sourceTitle']),
      sourceVersion = string(j['sourceVersion']),
      anchorId = string(j['anchorId']),
      church = j['script'] == 'church';
  final String id,
      quote,
      citation,
      sourceId,
      sourceTitle,
      sourceVersion,
      anchorId;
  final bool church;
}

class WordArticle {
  WordArticle(Json j)
    : id = string(j['id']),
      version = string(j['dictionaryVersion'], string(j['version'])),
      schemaVersion = j['schemaVersion'] == 2 ? 2 : 1,
      name = string(j['name']),
      pos = string(j['pos']),
      morphologyStatus = string(j['morphologyStatus']),
      izvod = string(j['izvod']),
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
      examples = array(
        j['examples'],
      ).map((v) => DictionaryExample(object(v))).toList(),
      composition = array(j['composition']).map(object).toList();
  final String id, name, pos, morphologyStatus, version, izvod;
  List<WordForm> get allForms => [
    ...extra,
    for (final p in paradigms)
      for (final s in p.slots) ...s.forms,
  ];
  bool get hasForms => allForms.any((f) => f.value.isNotEmpty);
  final int schemaVersion;
  final List<DataOrigin> lexemeOrigins, schemeOrigins;
  final List<String> properties;
  final List<SourceCard> sources, relatedSources;
  final List<Paradigm> paradigms;
  final List<WordForm> extra;
  final List<DictionaryExample> examples;
  final List<Json> relations, etymologies, usage, composition;
}

class SavedWord {
  const SavedWord(this.id, this.name);
  factory SavedWord.fromJson(Json j) =>
      SavedWord(string(j['id']), string(j['name']));
  final String id, name;
  Json toJson() => {'id': id, 'name': name};
}
