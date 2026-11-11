import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../domain/models.dart';
import '../domain/morphemes.dart';

class DictionaryException implements Exception {
  const DictionaryException(this.message, {this.status, this.retryAfter});
  final String message;
  final int? status, retryAfter;
  @override
  String toString() => message;
}

class DictionaryRepository {
  DictionaryRepository({http.Client? client, Uri? base, Uri? interlexBase})
    : _client = client ?? http.Client(),
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
  final http.Client _client;
  final Uri base, interlexBase;
  Future<Json> _get(Uri url) async {
    try {
      final response = await _client
          .get(url, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw DictionaryException(
          response.statusCode == 429
              ? 'Слишком много запросов. Попробуйте чуть позже.'
              : response.statusCode == 404
              ? 'Материал не найден.'
              : 'Не удалось загрузить материал. Попробуйте ещё раз.',
          status: response.statusCode,
          retryAfter: int.tryParse(response.headers['retry-after'] ?? ''),
        );
      }
      final decoded = object(jsonDecode(utf8.decode(response.bodyBytes)));
      if (decoded.isEmpty) {
        throw const DictionaryException('Сервер вернул неполный ответ.');
      }
      return decoded;
    } on DictionaryException {
      rethrow;
    } on TimeoutException {
      throw const DictionaryException(
        'Сервер не ответил вовремя. Повторите запрос.',
      );
    } on FormatException {
      throw const DictionaryException('Не удалось прочитать ответ сервера.');
    } catch (_) {
      throw const DictionaryException(
        'Нет соединения с сервером. Проверьте доступ к интернету.',
      );
    }
  }

  Future<SearchPage> search(
    String query,
    String direction, {
    String? cursor,
    int? limit,
  }) async => SearchPage(
    await _get(
      base
          .resolve('search')
          .replace(
            queryParameters: {
              'q': query,
              'direction': direction,
              'cursor': ?cursor,
              if (limit != null) 'limit': '$limit',
            },
          ),
    ),
  );
  Future<WordArticle> article(String id) async => WordArticle(
    await _get(base.resolve('lexemes/${Uri.encodeComponent(id)}')),
  );
  Future<WordMorphemes> wordMorphemes(String id) async {
    final data = await _get(
      base.resolve('lexemes/${Uri.encodeComponent(id)}/morphemes'),
    );
    if (string(data['version']).isEmpty || data['analyses'] is! List) {
      throw const DictionaryException(
        'API вернул неполный морфемный разбор. Попробуйте ещё раз.',
      );
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
    if (data['schemaVersion'] != 2 ||
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
  }) async => MorphemeWords(
    await _get(
      base
          .resolve('morphemes/${Uri.encodeComponent(id)}/words')
          .replace(
            queryParameters: {
              'version': version,
              'limit': '20',
              'cursor': ?cursor,
            },
          ),
    ),
  );
  Future<List<Json>> lexicalRelations(String id) async => array(
    (await _get(
      base
          .resolve('lexemes/${Uri.encodeComponent(id)}')
          .replace(queryParameters: {'view': 'relations'}),
    ))['relations'],
  ).map(object).toList();
  Future<Json> source(String id) =>
      _get(base.resolve('source-entries/${Uri.encodeComponent(id)}'));
  Future<Json> etymology(int id) => _get(interlexBase.resolve('proto/$id'));
  Future<void> report({
    required String reason,
    required String comment,
    String? lexemeId,
    String? query,
  }) async {
    try {
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
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 201) {
        throw DictionaryException(
          response.statusCode == 429
              ? 'Сообщений слишком много. Попробуйте позже.'
              : 'Не удалось отправить сообщение.',
        );
      }
    } on DictionaryException {
      rethrow;
    } catch (_) {
      throw const DictionaryException(
        'Нет соединения. Сообщение не отправлено.',
      );
    }
  }

  void close() => _client.close();
}
