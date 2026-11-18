import 'dart:convert';

Map<String, dynamic> _object(dynamic value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Reader: expected an object');
  }
  return value;
}

List<dynamic> _list(dynamic value) {
  if (value is! List) throw const FormatException('Reader: expected an array');
  return value;
}

void _require(bool condition, String message) {
  if (!condition) throw FormatException('Reader: $message');
}

/// The server's error code is extensible; preserve unfamiliar codes verbatim.
class ReaderApiFailure implements Exception {
  ReaderApiFailure(this.code, this.message, this.retryable);
  final String code;
  final String message;
  final bool retryable;
  @override
  String toString() => '$code: $message';
}

/// Contract boundary only. No repository, navigation or existing reader is switched.
/// Retaining the wire object preserves opaque metadata and future optional fields.
class ReaderEnvelope {
  ReaderEnvelope._(this.wire, this.data);
  final Map<String, dynamic> wire;
  final Map<String, dynamic> data;

  factory ReaderEnvelope.decode(String text) {
    final wire = _object(jsonDecode(text));
    _require(wire['contract'] == 'cs-reader/1', 'unsupported contract');
    _require(
      wire.containsKey('data') != wire.containsKey('error'),
      'exactly one of data/error is required',
    );
    if (wire.containsKey('error')) {
      final error = _object(wire['error']);
      _require(
        error['code'] is String &&
            error['message'] is String &&
            error['retryable'] is bool,
        'invalid error',
      );
      throw ReaderApiFailure(
        error['code'] as String,
        error['message'] as String,
        error['retryable'] as bool,
      );
    }
    _list(wire['warnings']);
    return ReaderEnvelope._(wire, _object(wire['data']));
  }
}

/// Guards the offsets used by a future Flutter reader before applying highlights.
class ReaderReadPacket {
  ReaderReadPacket._(this.envelope);
  final ReaderEnvelope envelope;
  Map<String, dynamic> get data => envelope.data;
  Map<String, dynamic> get address => _object(data['resolvedAddress']);
  List<dynamic> get projections => _list(data['projections']);

  factory ReaderReadPacket.decode(String text) {
    final envelope = ReaderEnvelope.decode(text);
    final data = envelope.data;
    final source = _object(data['source']);
    final snapshot = _object(data['snapshot']);
    final address = _object(data['resolvedAddress']);
    final descriptor = _object(data['sourceDescriptor']);
    final profile = _object(data['profileSet']);
    final profiles = _object(profile['profiles']);
    _require(address['version'] == 2, 'unsupported address');
    for (final item in [snapshot, address, descriptor]) {
      _require(
        item['sourceId'] == source['sourceId'],
        'mixed source identities',
      );
    }
    _require(
      snapshot['sourceRevision'] == address['sourceRevision'] &&
          snapshot['passportRevision'] == address['passportRevision'],
      'mixed revisions',
    );
    final projections = <String, Map<String, dynamic>>{};
    for (final raw in _list(data['projections'])) {
      final p = _object(raw);
      final window = _range(p['rawWindow']);
      final rawText = p['rawText'];
      final viewText = p['viewText'];
      _require(rawText is String && viewText is String, 'missing text');
      // Dart String offsets, like JavaScript String offsets, count UTF-16 units.
      _require(
        (rawText as String).length == window.$2 - window.$1 &&
            p['bodyLengthUtf16'] is int &&
            window.$2 <= p['bodyLengthUtf16'],
        'invalid UTF-16 window',
      );
      final map = _object(p['map']);
      _require(
        p['profileSetId'] == profile['id'] &&
            map['profileSetId'] == profile['id'] &&
            map['bodyId'] == p['bodyId'] &&
            map['bodyRevision'] == p['bodyRevision'] &&
            map['outputProfileId'] == profiles['display'] &&
            _range(map['rawWindow']) == window &&
            map['outputLengthUtf16'] == (viewText as String).length,
        'map belongs to another body or profile',
      );
      for (final rawToken in _list(p['tokens'])) {
        final token = _object(rawToken);
        _require(
          token['tokenizerProfileId'] == profiles['tokenizer'],
          'unsupported tokenizer',
        );
        for (final r in _list(token['rawRanges'])) {
          final range = _range(r);
          _require(
            range.$1 >= window.$1 && range.$2 <= window.$2,
            'absolute raw range is outside the window',
          );
        }
        for (final r in _list(token['surfaceRanges'])) {
          final range = _range(r);
          _require(
            range.$2 <= viewText.length,
            'local view range is outside the displayed text',
          );
        }
      }
      final id = p['projectionId'];
      _require(
        id is String && !projections.containsKey(id),
        'repeated projection',
      );
      projections[id as String] = p;
    }
    final units = _list(descriptor['units']).map(_object).toList();
    for (final raw in _list(data['units'])) {
      final unit = _object(raw);
      final declared = units.where(
        (u) => u['occurrenceId'] == unit['occurrenceId'],
      );
      _require(declared.length == 1, 'foreign occurrence');
      final body = _object(unit['bodyRef']);
      _require(
        declared.single['bodyId'] == body['bodyId'] &&
            declared.single['bodyRevision'] == body['bodyRevision'],
        'foreign body',
      );
      for (final id in _list(unit['projectionIds'])) {
        final p = projections[id];
        _require(
          p != null &&
              p['bodyId'] == body['bodyId'] &&
              p['bodyRevision'] == body['bodyRevision'],
          'foreign projection',
        );
      }
    }
    return ReaderReadPacket._(envelope);
  }

  static (int, int) _range(dynamic value) {
    final r = _list(value);
    _require(
      r.length == 2 && r[0] is int && r[1] is int && r[0] >= 0 && r[1] > r[0],
      'invalid range',
    );
    return (r[0] as int, r[1] as int);
  }
}
