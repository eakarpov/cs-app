import 'dart:convert';
import 'reader_packet.dart';

typedef Wire = Map<String, dynamic>;
Wire wireObject(dynamic v) {
  if (v is! Map<String, dynamic>) {
    throw const FormatException('Ожидался объект');
  }
  return v;
}

List<dynamic> wireList(dynamic v) {
  if (v is! List) throw const FormatException('Ожидался список');
  return v;
}

String wireString(dynamic v) {
  if (v is! String || v.isEmpty) {
    throw const FormatException('Ожидалась строка');
  }
  return v;
}

void requireWire(bool condition) {
  if (!condition) throw const FormatException('Несогласованный ответ корпуса');
}

Wire decodeEnvelope(String text, String contract) {
  final w = wireObject(jsonDecode(text));
  requireWire(
    w['contract'] == contract &&
        w.containsKey('data') != w.containsKey('error'),
  );
  if (w.containsKey('error')) {
    final e = wireObject(w['error']);
    requireWire(e['retryable'] is bool);
    throw ReaderApiFailure(
      wireString(e['code']),
      wireString(e['message']),
      e['retryable'],
    );
  }
  wireList(w['warnings']);
  return wireObject(w['data']);
}

class SourceAddress {
  SourceAddress(Wire data) : wire = Map.unmodifiable(data) {
    requireWire(data['version'] == 2);
    wireString(data['sourceId']);
    for (final key in ['sourceRevision', 'passportRevision']) {
      if (data.containsKey(key)) wireString(data[key]);
    }
    if (data['selector'] != null) {
      final s = wireObject(data['selector']);
      switch (s['kind']) {
        case 'occurrence':
          wireString(s['occurrenceId']);
        case 'fragment':
          wireString(s['fragmentId']);
        case 'range':
          wireString(s['startFragmentId']);
          wireString(s['endFragmentId']);
        default:
          throw const FormatException('Неизвестный селектор');
      }
    }
  }
  final Wire wire;
  String get sourceId => wire['sourceId'];
  bool get pinned =>
      wire['sourceRevision'] is String && wire['passportRevision'] is String;
  SourceAddress get whole => SourceAddress({...wire}..remove('selector'));
  Uri get url {
    final s = wire['selector'] as Wire?;
    return Uri.https('www.typikon.info', '/sources/id/$sourceId', {
      if (wire['sourceRevision'] != null) 'revision': wire['sourceRevision'],
      if (wire['passportRevision'] != null)
        'passport': wire['passportRevision'],
      if (s?['kind'] == 'occurrence') 'occurrence': s!['occurrenceId'],
      if (s?['kind'] == 'fragment') 'fragment': s!['fragmentId'],
      if (s?['kind'] == 'range') ...{
        'from': s!['startFragmentId'],
        'to': s['endFragmentId'],
      },
    });
  }
}

class CorpusSession {
  CorpusSession(this.index, this.reader) {
    requireWire(
      index['available'] == true &&
          index['publicRead'] == true &&
          reader['addressVersion'] == 2,
    );
    for (final k in [
      'pilotId',
      'indexRevision',
      'corpusRelease',
      'dictionaryVersion',
    ]) {
      wireString(index[k]);
    }
    final advertised = wireList(
      index['profiles'],
    ).map(wireObject).map((p) => wireString(p['id'])).toSet();
    profiles = wireList(reader['profileSets'])
        .map(wireObject)
        .where(
          (p) =>
              advertised.contains(p['id']) &&
              p['profiles'] is Map &&
              [
                'display-source-r1',
                'display-unicode-r1',
              ].contains(p['profiles']['display']),
        )
        .toList();
    requireWire(profiles.isNotEmpty);
    for (final p in profiles) {
      wireString(p['id']);
      wireString(p['profiles']['tokenizer']);
    }
  }
  final Wire index, reader;
  late final List<Wire> profiles;
  String get pilot => index['pilotId'];
  String get revision => index['indexRevision'];
  String get release => index['corpusRelease'];
  String get dictionary => index['dictionaryVersion'];
  String get defaultProfile =>
      (profiles
          .where((p) => p['profiles']['display'] == 'display-source-r1')
          .firstOrNull ??
      profiles.first)['id'];
}

List<(int, int)> wireRanges(
  dynamic value, {
  int? min,
  int? max,
  bool empty = false,
}) => wireList(value).map((v) {
  final r = wireList(v);
  requireWire(r.length == 2 && r[0] is int && r[1] is int);
  final a = r[0] as int, b = r[1] as int;
  requireWire(
    a >= (min ?? 0) && (empty ? b >= a : b > a) && (max == null || b <= max),
  );
  return (a, b);
}).toList();

void validUtf16(String text) {
  for (var i = 0; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    if (c >= 0xd800 && c <= 0xdbff) {
      requireWire(++i < text.length);
      final d = text.codeUnitAt(i);
      requireWire(d >= 0xdc00 && d <= 0xdfff);
    } else {
      requireWire(c < 0xdc00 || c > 0xdfff);
    }
  }
}

void utf16Boundary(String text, int offset) {
  if (offset > 0 && offset < text.length) {
    final previous = text.codeUnitAt(offset - 1),
        current = text.codeUnitAt(offset);
    requireWire(
      !(previous >= 0xd800 &&
          previous <= 0xdbff &&
          current >= 0xdc00 &&
          current <= 0xdfff),
    );
  }
}

/// Validates a projection before either rendering or applying a token highlight.
class CorpusProjection {
  CorpusProjection(this.wire, {required String profile, String? tokenizer}) {
    wireString(wire['projectionId']);
    wireString(wire['bodyId']);
    wireString(wire['bodyRevision']);
    requireWire(
      wire['profileSetId'] == profile &&
          wire['rawText'] is String &&
          wire['viewText'] is String,
    );
    validUtf16(raw);
    validUtf16(text);
    final r = wireRanges([wire['rawWindow']], empty: true).single;
    requireWire(
      raw.length == r.$2 - r.$1 &&
          wire['bodyLengthUtf16'] is int &&
          r.$2 <= wire['bodyLengthUtf16'],
    );
    final m = wireObject(wire['map']);
    requireWire(
      m['profileSetId'] == profile &&
          m['bodyId'] == wire['bodyId'] &&
          m['bodyRevision'] == wire['bodyRevision'] &&
          jsonEncode(m['rawWindow']) == jsonEncode(wire['rawWindow']) &&
          m['outputLengthUtf16'] == text.length,
    );
    wireString(m['mapId']);
    var outEnd = 0;
    for (final s in wireList(m['segments']).map(wireObject)) {
      final o = wireRanges(
        [s['outRange']],
        max: text.length,
        empty: true,
      ).single;
      requireWire(o.$1 == outEnd);
      wireRanges(s['rawRanges'], min: r.$1, max: r.$2);
      outEnd = o.$2;
    }
    requireWire(outEnd == text.length);
    final ids = <String>{};
    for (final t in tokens) {
      requireWire(
        ids.add(wireString(t['tokenId'])) &&
            (tokenizer == null || t['tokenizerProfileId'] == tokenizer),
      );
      final rawRanges = wireRanges(t['rawRanges'], min: r.$1, max: r.$2);
      requireWire(rawRanges.isNotEmpty);
      for (final range in rawRanges) {
        utf16Boundary(raw, range.$1 - r.$1);
        utf16Boundary(raw, range.$2 - r.$1);
      }
      for (final range in wireRanges(t['surfaceRanges'], max: text.length)) {
        utf16Boundary(text, range.$1);
        utf16Boundary(text, range.$2);
      }
    }
  }
  final Wire wire;
  String get text => wire['viewText'];
  String get raw => wire['rawText'];
  List<Wire> get tokens => wireList(wire['tokens']).map(wireObject).toList();
  List<(int, int)> highlights(List<String> tokenIds) => tokens
      .where((t) => tokenIds.contains(t['tokenId']))
      .expand((t) => wireRanges(t['surfaceRanges'], max: text.length))
      .toList();
}

class CorpusHit {
  CorpusHit(this.wire, String profile) {
    for (final key in [
      'hitId',
      'bodyId',
      'bodyRevision',
      'occurrenceId',
      'matchKind',
    ]) {
      wireString(wire[key]);
    }
    address = SourceAddress(wireObject(wire['address']));
    requireWire(
      address.pinned &&
          address.wire['selector']?['occurrenceId'] == wire['occurrenceId'],
    );
    wireString(wireObject(wire['source'])['title']);
    tokenIds = wireList(wire['tokenIds']).map(wireString).toList();
    requireWire(
      tokenIds.isNotEmpty && tokenIds.toSet().length == tokenIds.length,
    );
    wireRanges(wire['rawRanges']);
    if (wire['snippet'] != null) {
      snippet = CorpusProjection(wireObject(wire['snippet']), profile: profile);
      validateProjection(snippet!);
    }
    if (wire['matchKind'] == 'lexeme_verified') {
      wireString(wire['lexemeId']);
      wireObject(wire['bindingEvidence']);
    }
  }
  final Wire wire;
  late final SourceAddress address;
  late final List<String> tokenIds;
  CorpusProjection? snippet;
  String get title => wire['source']['title'];
  String get kind => wire['matchKind'];
  String get label => switch (kind) {
    'lexeme_verified' => 'Принятая связь с лексемой',
    'abbreviation_skeleton' => 'Совпадение сокращённого написания',
    'folded' => 'Совпадение нормализованного написания',
    _ => 'Совпадение: $kind',
  };
  void validateProjection(CorpusProjection p) {
    requireWire(
      p.wire['bodyId'] == wire['bodyId'] &&
          p.wire['bodyRevision'] == wire['bodyRevision'],
    );
    final matched = tokenIds
        .map((id) => p.tokens.where((t) => t['tokenId'] == id).single)
        .toList();
    requireWire(
      jsonEncode(matched.expand((t) => t['rawRanges'] as List).toList()) ==
          jsonEncode(wire['rawRanges']),
    );
  }
}

class CorpusPage {
  CorpusPage(
    this.data,
    CorpusSession session,
    String profile, {
    bool lemma = false,
  }) {
    requireWire(
      data['indexRevision'] == session.revision &&
          data['corpusRelease'] == session.release &&
          data['dictionaryVersion'] == session.dictionary &&
          data['profileSetId'] == profile &&
          data['scope'] == 'searchable-pilot-only' &&
          data['association'] ==
              (lemma ? 'accepted-only' : 'surface-match-only'),
    );
    hits = wireList(
      data['hits'],
    ).map((v) => CorpusHit(wireObject(v), profile)).toList();
    requireWire(hits.map((h) => h.wire['hitId']).toSet().length == hits.length);
    requireWire(
      hits.every(
        (h) =>
            lemma ? h.kind == 'lexeme_verified' : h.kind != 'lexeme_verified',
      ),
    );
    final page = wireObject(data['page']);
    requireWire(
      page['hasMore'] is bool &&
          page['truncated'] is bool &&
          (page['nextCursor'] == null || page['nextCursor'] is String),
    );
    final total = wireObject(page['total']);
    requireWire(['exact', 'at_least', 'unknown'].contains(total['state']));
    if (total['state'] != 'unknown') {
      requireWire(total['value'] is int && total['value'] >= hits.length);
    }
  }
  final Wire data;
  late final List<CorpusHit> hits;
  String? get cursor => data['page']['nextCursor'];
  bool get truncated => data['page']['truncated'];
  String get totalLabel {
    final t = data['page']['total'];
    return switch (t['state']) {
      'exact' => 'Найдено: ${t['value']}',
      'at_least' => 'Найдено не менее ${t['value']}',
      _ => 'Общее число не определено',
    };
  }
}
