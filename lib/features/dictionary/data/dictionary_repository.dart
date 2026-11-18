import 'dart:async';
import '../../reader/data/reader_repository.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../domain/models.dart';
import '../domain/morphemes.dart';

class DictionaryException implements Exception {
  const DictionaryException(
    this.message, {
    this.status,
    this.retryAfter,
    this.code,
    this.retryAt,
  });
  final String message;
  final String? code;
  final int? status, retryAfter;
  final DateTime? retryAt;
  @override
  String toString() => message;
}

class DictionaryRepository {
  DictionaryRepository({
    http.Client? client,
    Uri? base,
    Uri? interlexBase,
    DateTime Function()? now,
    this.requestTimeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client(),
       _now = now ?? DateTime.now,
       base =
           base ??
           Uri.parse(
             const String.fromEnvironment(
               'CS_API_BASE_URL',
               defaultValue: 'https://www.typikon.info/api/v2/cs/',
             ),
           ),
       interlexBase =
           interlexBase ??
           Uri.parse(
             const String.fromEnvironment(
               'CS_INTERLEX_BASE_URL',
               defaultValue: 'https://interslavic-lexicon.com/api/public/cs/',
             ),
           );
  late final ReaderRepository reader = ReaderRepository(
    client: _client,
    base:
        Uri.parse(
          const String.fromEnvironment('CS_READER_BASE_URL', defaultValue: ''),
        ).toString().isNotEmpty
        ? Uri.parse(const String.fromEnvironment('CS_READER_BASE_URL'))
        : base.resolve('/api/v2/study/reader/v1/'),
  );
  final http.Client _client;
  final Uri base, interlexBase;
  final DateTime Function() _now;
  final Duration requestTimeout;
  // Bodies are session-only and always revalidated; this is not an offline store.
  final _bodies = <Uri, ({String body, String etag})>{};
  final _backoff = <String, DictionaryException>{};
  static const _maxBodyBytes = 512 * 1024;
  static const _maxCacheBytes = 4 * 1024 * 1024;

  void _checkBackoff(Uri url) {
    final e = _backoff[url.origin];
    if (e?.retryAt != null && e!.retryAt!.isAfter(_now())) throw e;
    _backoff.remove(url.origin);
  }

  DictionaryException _httpError(http.Response response, Uri url) {
    String? code;
    try {
      code = string(
        object(
          object(jsonDecode(utf8.decode(response.bodyBytes)))['error'],
        )['code'],
      );
    } catch (_) {}
    DateTime? retryAt;
    final value = response.headers['retry-after']?.trim();
    if (value != null) {
      try {
        final seconds = RegExp(r'^\d+$').hasMatch(value)
            ? int.tryParse(value)
            : null;
        retryAt = seconds != null
            ? _now().add(Duration(seconds: seconds))
            : parseHttpDate(value);
        if (!retryAt.isAfter(_now())) retryAt = null;
      } catch (_) {
        retryAt = null;
      }
    }
    final e = DictionaryException(
      response.statusCode == 429
          ? 'Слишком много запросов. Попробуйте чуть позже.'
          : response.statusCode == 409
          ? 'Версия словаря недоступна. Откройте текущую версию.'
          : response.statusCode == 404
          ? 'Материал не найден.'
          : response.statusCode >= 500
          ? 'Сервис временно недоступен. Попробуйте ещё раз.'
          : 'Не удалось загрузить материал. Попробуйте ещё раз.',
      status: response.statusCode,
      code: code,
      retryAt: retryAt,
      retryAfter: retryAt == null
          ? null
          : (retryAt.difference(_now()).inMilliseconds / 1000).ceil(),
    );
    if (response.statusCode == 429 && retryAt != null) _backoff[url.origin] = e;
    return e;
  }

  Future<Json> _get(Uri url) async {
    try {
      _checkBackoff(url);
      final cached = _bodies[url];
      var response = await _client
          .get(
            url,
            headers: {
              'Accept': 'application/json',
              if (cached != null) 'If-None-Match': cached.etag,
            },
          )
          .timeout(requestTimeout);
      if (response.statusCode == 304 && cached == null) {
        // A 304 without a body cannot be interpreted as an empty resource.
        response = await _client
            .get(url, headers: {'Accept': 'application/json'})
            .timeout(requestTimeout);
      }
      final reused = response.statusCode == 304 ? cached : null;
      if (response.statusCode != 200 && reused == null) {
        throw _httpError(response, url);
      }
      final body = reused?.body ?? utf8.decode(response.bodyBytes);
      final value = jsonDecode(body);
      if (value is! Map<String, dynamic> || value.isEmpty) {
        throw const DictionaryException(
          'Сервер вернул неполный ответ.',
          code: 'invalid_contract',
        );
      }
      final noStore = (response.headers['cache-control'] ?? '')
          .toLowerCase()
          .split(',')
          .any((v) => v.trim() == 'no-store');
      final etag = response.headers['etag'] ?? reused?.etag;
      _bodies.remove(url);
      if (!noStore &&
          etag != null &&
          etag.isNotEmpty &&
          utf8.encode(body).length <= _maxBodyBytes) {
        _bodies[url] = (body: body, etag: etag);
        while (_bodies.length > 32 ||
            _bodies.values.fold<int>(
                  0,
                  (n, v) => n + utf8.encode(v.body).length,
                ) >
                _maxCacheBytes) {
          _bodies.remove(_bodies.keys.first);
        }
      }
      return value;
    } on DictionaryException {
      rethrow;
    } on TimeoutException {
      throw const DictionaryException(
        'Сервер не ответил вовремя. Повторите запрос.',
        code: 'timeout',
      );
    } on FormatException {
      throw const DictionaryException(
        'Не удалось прочитать ответ сервера.',
        code: 'invalid_contract',
      );
    } catch (_) {
      throw const DictionaryException(
        'Нет соединения с сервером. Проверьте доступ к интернету.',
        code: 'network',
      );
    }
  }

  Future<SearchPage> search(
    String query,
    String direction, {
    String? cursor,
    int? limit,
    String? version,
    int schema = 2,
  }) async {
    final data = await _dictionaryGet(
      base
          .resolve('search')
          .replace(
            queryParameters: {
              'q': query,
              'direction': direction,
              'schema': '$schema',
              'version': ?version,
              'cursor': ?cursor,
              if (limit != null) 'limit': '$limit',
            },
          ),
      schema: schema,
      version: version,
    );
    if (data['schemaVersion'] == 2) {
      if (data['query'] != query.trim() ||
          data['direction'] != direction ||
          data['items'] is! List ||
          data['nextCursor'] != null && data['nextCursor'] is! String) {
        throw _invalidContract;
      }
      for (final value in array(data['items'])) {
        final hit = object(value);
        if ([
              'id',
              'name',
              'pos',
              'match',
              'matched',
              'grammar',
            ].any((k) => hit[k] is! String) ||
            string(hit['id']).isEmpty ||
            hit['exact'] is! bool) {
          throw _invalidContract;
        }
      }
    }
    return SearchPage(data);
  }

  static const _invalidContract = DictionaryException(
    'Сервер вернул несовместимый ответ словаря.',
    code: 'invalid_contract',
  );
  Future<Json> _dictionaryGet(
    Uri uri, {
    required int schema,
    String? version,
  }) async {
    final data = await _get(uri);
    if (schema == 2 && data['schemaVersion'] != 2) {
      // A pre-profile server may ignore schema/version. Only unpinned latest can use legacy.
      if (data['schemaVersion'] != null ||
          version != null ||
          uri.queryParameters['cursor'] != null) {
        throw _invalidContract;
      }
      return data;
    }
    if (schema == 2) {
      final actual = string(data['dictionaryVersion']);
      if (actual.isEmpty ||
          version != null && actual != version ||
          (uri.path.contains('/source-entries/')
              ? data['publicationVersion'] != actual ||
                    data['sourceVersion'] is! String ||
                    data['sourceVersion'] != data['version']
              : data['version'] != actual)) {
        throw _invalidContract;
      }
    }
    return data;
  }

  Future<WordArticle> article(
    String id, {
    String? version,
    int schema = 2,
  }) async {
    final data = await _dictionaryGet(
      base
          .resolve('lexemes/${Uri.encodeComponent(id)}')
          .replace(queryParameters: {'schema': '$schema', 'version': ?version}),
      schema: schema,
      version: version,
    );
    if (data['schemaVersion'] == 2) {
      if (data['id'] != id ||
          ['name', 'pos'].any((k) => data[k] is! String) ||
          [
            'sources',
            'relatedSources',
            'examples',
            'paradigms',
            'extra',
            'relations',
            'etymologies',
            'usage',
            'composition',
            'properties',
          ].any((k) => data[k] is! List)) {
        throw _invalidContract;
      }
      final forms = <Object?>[...array(data['extra'])];
      for (final p in array(data['paradigms'])) {
        if (p is! Map || p['slots'] is! List) {
          throw _invalidContract;
        }
        for (final slot in array(p['slots'])) {
          if (slot is! Map || slot['forms'] is! List) {
            throw _invalidContract;
          }
          forms.addAll(array(slot['forms']));
        }
      }
      for (final value in forms) {
        final f = object(value);
        if ([
              'value',
              'grammar',
              'formOrigin',
              'reviewStatus',
            ].any((k) => f[k] is! String) ||
            f['provenance'] is! List ||
            f['evidence'] is! List ||
            f['segments'] != null && f['segments'] is! List) {
          throw _invalidContract;
        }
      }
    }
    return WordArticle(data);
  }

  Future<WordMorphemes> wordMorphemes(
    String id, {
    String? dictionaryVersion,
  }) async {
    final data = await _get(
      base
          .resolve('lexemes/${Uri.encodeComponent(id)}/morphemes')
          .replace(queryParameters: {'dictionaryVersion': ?dictionaryVersion}),
    );
    if (string(data['version']).isEmpty || data['analyses'] is! List) {
      throw const DictionaryException(
        'API вернул неполный морфемный разбор. Попробуйте ещё раз.',
      );
    }
    if (dictionaryVersion != null &&
        data['dictionaryVersion'] != dictionaryVersion) {
      throw _invalidContract;
    }
    return WordMorphemes(data);
  }

  Future<MorphemeCard> morpheme(String id, {required String version}) async {
    final data = await _get(
      base
          .resolve('morphemes/${Uri.encodeComponent(id)}')
          .replace(queryParameters: {'version': version, 'schema': '2'}),
    );
    final composition = object(data['composition']);
    final etymology = object(data['etymology']);
    if (data['id'] != id ||
        data['version'] != version ||
        data['schemaVersion'] != 2 ||
        data['composition'] is! Map ||
        data['etymology'] is! Map ||
        data['sources'] is! List ||
        ['models', 'notes'].any((key) => composition[key] is! List) ||
        [
          'nodes',
          'relations',
          'chains',
          'notes',
        ].any((key) => etymology[key] is! List)) {
      throw const DictionaryException(
        'API вернул неполную карточку морфемы. Откройте морфему заново.',
      );
    }
    return MorphemeCard(data);
  }

  Future<MorphemeWords> morphemeWords(
    String id, {
    required String version,
    String? cursor,
  }) async {
    final data = await _get(
      base
          .resolve('morphemes/${Uri.encodeComponent(id)}/words')
          .replace(
            queryParameters: {
              'version': version,
              'limit': '20',
              'cursor': ?cursor,
            },
          ),
    );
    if (data['version'] != version) {
      throw const DictionaryException(
        'Версия базы изменилась. Откройте вкладку «Морфемы» заново.',
        status: 409,
        code: 'version_unavailable',
      );
    }
    if (data['items'] is! List ||
        data['total'] is! num ||
        data['nextCursor'] != null && data['nextCursor'] is! String) {
      throw _invalidContract;
    }
    return MorphemeWords(data);
  }

  Future<List<Json>> lexicalRelations(String id) async => array(
    (await _get(
      base
          .resolve('lexemes/${Uri.encodeComponent(id)}')
          .replace(queryParameters: {'view': 'relations'}),
    ))['relations'],
  ).map(object).toList();
  Future<Json> source(
    String id, {
    String? version,
    int schema = 2,
    String? sourceVersion,
  }) async {
    final data = await _dictionaryGet(
      base
          .resolve('source-entries/${Uri.encodeComponent(id)}')
          .replace(
            queryParameters: {
              'schema': '$schema',
              'version': ?version,
              'sourceVersion': ?sourceVersion,
            },
          ),
      schema: schema,
      version: version,
    );
    if (data['schemaVersion'] == 2 &&
        (data['id'] != id ||
            data['text'] is! String ||
            [
              'paragraphs',
              'anchors',
              'examples',
            ].any((k) => data[k] is! List))) {
      throw _invalidContract;
    }
    if (sourceVersion != null &&
        (data['sourceVersion'] ?? data['version']) != sourceVersion) {
      throw _invalidContract;
    }
    return data;
  }

  Future<Json> etymology(int id) => _get(interlexBase.resolve('proto/$id'));
  Future<void> report({
    required String reason,
    required String comment,
    String? lexemeId,
    String? query,
  }) async {
    try {
      _checkBackoff(base.resolve('reports'));
      final response = await _client
          .post(
            base.resolve('reports'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'reason': reason,
              'comment': comment,
              'lexemeId': ?lexemeId,
              'query': ?query,
            }),
          )
          .timeout(requestTimeout);
      if (response.statusCode != 201) {
        throw _httpError(response, base.resolve('reports'));
      }
    } on DictionaryException {
      rethrow;
    } catch (_) {
      throw const DictionaryException(
        'Нет соединения. Сообщение не отправлено.',
      );
    }
  }

  void close() {
    reader.close();
    _bodies.clear();
    _backoff.clear();
    _client.close();
  }
}
