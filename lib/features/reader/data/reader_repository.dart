import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../domain/corpus.dart';
import '../domain/reader_packet.dart';

class CorpusFailure implements Exception {
  const CorpusFailure(
    this.message, {
    this.code = 'invalid_contract',
    this.status,
    this.retryAt,
  });
  final String message, code;
  final int? status;
  final DateTime? retryAt;
  bool get restartRequired =>
      status == 409 || status == 410 || code == 'invalid_contract';
  @override
  String toString() => message;
}

/// Anonymous reader transport. No permanent body cache and no automatic retries.
class ReaderRepository {
  ReaderRepository({
    http.Client? client,
    Uri? base,
    DateTime Function()? now,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       base =
           base ??
           Uri.parse(
             const String.fromEnvironment(
               'CS_READER_BASE_URL',
               defaultValue: 'https://www.typikon.info/api/v2/study/reader/v1/',
             ),
           ),
       _now = now ?? DateTime.now;
  final http.Client _client;
  final bool _ownsClient;
  final Uri base;
  final Duration timeout;
  final DateTime Function() _now;
  final _cache = <Uri, ({String body, String etag})>{};
  CorpusFailure? _backoff;

  Future<String> _request(String path, {Wire? query, Wire? body}) async {
    final uri = base
        .resolve(path)
        .replace(queryParameters: query?.map((k, v) => MapEntry(k, '$v')));
    if (_backoff?.retryAt?.isAfter(_now()) == true) throw _backoff!;
    final cached = body == null ? _cache[uri] : null;
    try {
      Future<http.Response> send(bool conditional) => body == null
          ? _client
                .get(
                  uri,
                  headers: {
                    'Accept': 'application/json',
                    if (conditional && cached != null)
                      'If-None-Match': cached.etag,
                  },
                )
                .timeout(timeout)
          : _client
                .post(
                  uri,
                  headers: {
                    'Accept': 'application/json',
                    'Content-Type': 'application/json',
                  },
                  body: jsonEncode({'contract': 'cs-reader/1', ...body}),
                )
                .timeout(timeout);
      var response = await send(true);
      if (response.statusCode == 304 && cached == null) {
        response = await send(false);
      }
      if (response.statusCode == 304 && cached != null) return cached.body;
      if (response.statusCode != 200) {
        _cache.remove(
          uri,
        ); // No stale fallback after visibility/version errors.
        String code = 'http_${response.statusCode}';
        try {
          code = wireString(
            wireObject(
              wireObject(jsonDecode(utf8.decode(response.bodyBytes)))['error'],
            )['code'],
          );
        } catch (_) {}
        DateTime? retryAt;
        final retry = response.headers['retry-after'];
        if (retry != null) {
          try {
            retryAt = RegExp(r'^\d+$').hasMatch(retry)
                ? _now().add(Duration(seconds: int.parse(retry)))
                : parseHttpDate(retry);
          } catch (_) {}
        }
        final error = CorpusFailure(
          switch (response.statusCode) {
            404 =>
              'Корпусный материал пока недоступен. Словарь продолжает работать.',
            409 =>
              'Версии данных изменились или несовместимы. Начните заново с текущей версией.',
            410 =>
              'Сохранённая ревизия или место недоступны. Можно отдельно открыть текущую версию.',
            422 =>
              'Запрос или профиль не поддержан. Проверьте написание и выбранный вид текста.',
            429 => 'Лимит запросов исчерпан. Повторите позже.',
            413 =>
              'Текст слишком велик для одного ответа. Откройте отдельный фрагмент.',
            _ => 'Не удалось загрузить корпус. Повторите запрос.',
          },
          status: response.statusCode,
          code: code,
          retryAt: retryAt,
        );
        if (response.statusCode == 429) _backoff = error;
        throw error;
      }
      final text = utf8.decode(response.bodyBytes);
      final noStore = (response.headers['cache-control'] ?? '').contains(
        'no-store',
      );
      // Only conditional, bounded metadata bodies are retained for the session.
      final metadata =
          path == 'capabilities' ||
          path == 'index/capabilities' ||
          path == 'catalog' ||
          path.startsWith('passport/');
      _cache.remove(uri);
      final etag = response.headers['etag'];
      if (metadata &&
          !noStore &&
          etag != null &&
          response.bodyBytes.length <= 512 * 1024) {
        _cache[uri] = (body: text, etag: etag);
        while (_cache.length > 8) {
          _cache.remove(_cache.keys.first);
        }
      }
      return text;
    } on CorpusFailure {
      rethrow;
    } on TimeoutException {
      throw const CorpusFailure(
        'Сервер не ответил вовремя. Повторите запрос.',
        code: 'timeout',
      );
    } on FormatException {
      throw const CorpusFailure('Не удалось прочитать ответ корпуса.');
    } catch (_) {
      throw const CorpusFailure(
        'Для корпуса требуется сеть. Проверьте соединение и повторите.',
        code: 'network',
      );
    }
  }

  Future<T> _decode<T>(
    Future<String> response,
    T Function(String) parse,
  ) async {
    final text = await response;
    try {
      return parse(text);
    } on ReaderApiFailure catch (e) {
      throw CorpusFailure(e.message, code: e.code);
    } catch (_) {
      throw const CorpusFailure(
        'Сервер вернул несогласованные данные корпуса.',
      );
    }
  }

  Future<Wire> get(
    String path, {
    Wire? query,
    String contract = 'cs-reader/1',
  }) =>
      _decode(_request(path, query: query), (s) => decodeEnvelope(s, contract));
  Future<Wire> post(String path, Wire body) => _decode(
    _request(path, body: body),
    (s) => decodeEnvelope(s, 'cs-reader/1'),
  );

  Future<CorpusSession> session() async {
    final index = await get('index/capabilities', contract: 'cs-index/1');
    if (index['available'] != true || index['publicRead'] != true) {
      throw const CorpusFailure(
        'Корпусный пилот пока не опубликован. Словарь доступен.',
        code: 'not_published',
      );
    }
    final reader = await get('capabilities');
    try {
      return CorpusSession(index, reader);
    } catch (_) {
      throw const CorpusFailure('Совместимый профиль корпуса недоступен.');
    }
  }

  Future<Wire> catalog(CorpusSession session, {String? cursor}) async {
    final data = await get(
      'catalog',
      query: {
        'pilotId': session.pilot,
        'limit': 20,
        'catalogRevision': session.release,
        'cursor': ?cursor,
      },
    );
    try {
      requireWire(
        data['catalogRevision'] == session.release &&
            (data['nextCursor'] == null || data['nextCursor'] is String),
      );
      for (final source in wireList(data['items']).map(wireObject)) {
        wireString(source['sourceId']);
        wireString(source['title']);
      }
    } catch (_) {
      throw const CorpusFailure(
        'Каталог изменился. Откройте текущую версию.',
        status: 409,
        code: 'catalog_changed',
      );
    }
    return data;
  }

  Future<CorpusPage> search(
    CorpusSession session,
    String profile, {
    required String query,
    String mode = 'word',
    String? cursor,
  }) => _decode(
    _request(
      'index/search',
      query: {
        'pilotId': session.pilot,
        'indexRevision': session.revision,
        'profileSetId': profile,
        'q': query,
        'mode': mode,
        'limit': 20,
        'cursor': ?cursor,
      },
    ),
    (s) => CorpusPage(decodeEnvelope(s, 'cs-index/1'), session, profile),
  );
  Future<CorpusPage> occurrences(
    CorpusSession session,
    String profile,
    String id,
    String dictionary, {
    String? cursor,
  }) async {
    if (dictionary != session.dictionary) {
      throw const CorpusFailure(
        'У этой версии статьи нет совместимой публикации индекса. Откройте текущую статью отдельно.',
        status: 409,
        code: 'dictionary_version_mismatch',
      );
    }
    return _decode(
      _request(
        'index/occurrences',
        query: {
          'pilotId': session.pilot,
          'indexRevision': session.revision,
          'profileSetId': profile,
          'lexemeId': id,
          'dictionaryVersion': dictionary,
          'limit': 20,
          'cursor': ?cursor,
        },
      ),
      (s) {
        final page = CorpusPage(
          decodeEnvelope(s, 'cs-index/1'),
          session,
          profile,
          lemma: true,
        );
        requireWire(page.hits.every((h) => h.wire['lexemeId'] == id));
        return page;
      },
    );
  }

  Future<Wire> resolve({SourceAddress? address, String? url}) async {
    final data = await post('resolve', {
      if (address != null) 'address': address.wire,
      'url': ?url,
    });
    try {
      if (data['result'] == 'container') return data;
      final resolved = SourceAddress(wireObject(data['resolvedAddress']));
      requireWire(data['result'] == 'resolved' && resolved.pinned);
      if (address != null) {
        for (final key in address.wire.keys) {
          requireWire(
            jsonEncode(resolved.wire[key]) == jsonEncode(address.wire[key]),
          );
        }
      }
    } catch (_) {
      throw const CorpusFailure('Адрес не соответствует запрошенному тексту.');
    }
    return data;
  }

  Future<ReaderReadPacket> read(
    SourceAddress address,
    Wire profile, {
    String? cursor,
    Wire? window,
    int limit = 1,
  }) => _decode(
    _request(
      'read',
      body: {
        'address': address.wire,
        'profileSetId': profile['id'],
        'limit': limit,
        'cursor': ?cursor,
        'window': ?window,
      },
    ),
    (text) {
      final packet = ReaderReadPacket.decode(text);
      requireWire(jsonEncode(packet.data['profileSet']) == jsonEncode(profile));
      for (final key in address.wire.keys) {
        requireWire(
          jsonEncode(packet.address[key]) == jsonEncode(address.wire[key]),
        );
      }
      for (final p in packet.projections) {
        CorpusProjection(
          wireObject(p),
          profile: profile['id'],
          tokenizer: profile['profiles']['tokenizer'],
        );
      }
      return packet;
    },
  );
  Future<Wire> passport(SourceAddress address) async {
    final data = await get(
      'passport/${Uri.encodeComponent(address.sourceId)}',
      query: {
        if (address.wire['passportRevision'] != null)
          'revision': address.wire['passportRevision'],
      },
    );
    try {
      requireWire(
        data['sourceId'] == address.sourceId &&
            data['passportRevision'] == address.wire['passportRevision'],
      );
      wireObject(data['fields']);
    } catch (_) {
      throw const CorpusFailure('Паспорт относится к другой ревизии.');
    }
    return data;
  }

  void close() {
    _cache.clear();
    if (_ownsClient) _client.close();
  }
}
