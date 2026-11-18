import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cs/features/reader/data/reader_repository.dart';
import 'package:cs/features/reader/domain/corpus.dart';
import 'package:cs/features/reader/domain/reader_link.dart';
import 'package:cs/features/reader/presentation/corpus_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final fixture = jsonDecode(
  File('docs/pilot/reader-api-examples.json').readAsStringSync(),
);
Wire readWire() => wireObject(
  jsonDecode(
    jsonEncode(
      (fixture['examples'] as List).firstWhere(
        (e) => e['responseSchema'] == 'ReadResponse',
      )['response'],
    ),
  ),
);
Wire projection() => wireObject(readWire()['data']['projections'].single);
const profileId = 'cs-pilot-source-r1';
Wire profile() => wireObject(readWire()['data']['profileSet']);
CorpusSession makeSession([String version = 'I']) => CorpusSession(
  {
    'available': true,
    'publicRead': true,
    'pilotId': 'pilot',
    'indexRevision': version,
    'corpusRelease': 'C',
    'dictionaryVersion': 'D',
    'profiles': [
      {'id': profileId},
    ],
  },
  {
    'addressVersion': 2,
    'profileSets': [profile()],
  },
);
Wire hit() {
  final r = readWire()['data'];
  final p = projection();
  return wireObject(
    jsonDecode(
      jsonEncode({
        'hitId': 'h',
        'address': {
          ...r['resolvedAddress'],
          'selector': {
            'kind': 'occurrence',
            'occurrenceId': r['units'][0]['occurrenceId'],
          },
        },
        'source': r['source'],
        'bodyId': p['bodyId'],
        'bodyRevision': p['bodyRevision'],
        'occurrenceId': r['units'][0]['occurrenceId'],
        'tokenIds': [p['tokens'][0]['tokenId']],
        'rawRanges': p['tokens'][0]['rawRanges'],
        'matchKind': 'folded',
        'snippet': p,
        'navigationAliases': [],
      }),
    ),
  );
}

Wire page({String? cursor, List<Wire>? hits}) => {
  'indexRevision': 'I',
  'corpusRelease': 'C',
  'dictionaryVersion': 'D',
  'profileSetId': profileId,
  'scope': 'searchable-pilot-only',
  'association': 'surface-match-only',
  'hits': hits ?? [hit()],
  'page': {
    'nextCursor': cursor,
    'hasMore': cursor != null,
    'truncated': false,
    'total': {'state': 'exact', 'value': 2},
  },
};
String envelope(dynamic data, [String contract = 'cs-reader/1']) =>
    jsonEncode({'contract': contract, 'data': data, 'warnings': []});
http.Response jsonResponse(Object body, {Map<String, String>? headers}) =>
    http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json; charset=utf-8', ...?headers},
    );

class DeferredRepository extends ReaderRepository {
  final requests = <String, Completer<CorpusPage>>{};
  @override
  Future<CorpusSession> session() async => makeSession();
  @override
  Future<CorpusPage> search(
    CorpusSession session,
    String profile, {
    required String query,
    String mode = 'word',
    String? cursor,
  }) => (requests[query] = Completer<CorpusPage>()).future;
}

class PagedRepository extends ReaderRepository {
  PagedRepository(http.Client client) : super(client: client);
  @override
  Future<CorpusSession> session() async => makeSession();
}

void main() {
  test(
    'index DTO enforces I/C/D/P, association and exact body token identity',
    () {
      final s = makeSession();
      final p = CorpusPage(page(), s, profileId);
      expect(p.hits.single.snippet!.highlights(p.hits.single.tokenIds), [
        (0, 4),
      ]);
      for (final key in [
        'indexRevision',
        'corpusRelease',
        'dictionaryVersion',
        'profileSetId',
        'association',
      ]) {
        expect(
          () => CorpusPage({...page(), key: 'wrong'}, s, profileId),
          throwsFormatException,
          reason: key,
        );
      }
      final bad = hit();
      bad['rawRanges'] = [
        [0, 4],
      ];
      expect(() => CorpusHit(bad, profileId), throwsFormatException);
      final foreign = hit();
      foreign['bodyRevision'] = 'other';
      expect(() => CorpusHit(foreign, profileId), throwsFormatException);
    },
  );
  test(
    'PUA surrogate and titlo offsets are UTF16 and map changes are rejected',
    () {
      final p = projection();
      p['rawText'] = '\u{f0023}а';
      p['rawWindow'] = [47, 50];
      p['bodyLengthUtf16'] = 50;
      p['viewText'] = 'и҆а';
      p['map']['rawWindow'] = [47, 50];
      p['map']['outputLengthUtf16'] = 3;
      p['map']['segments'] = [
        {
          'rawRanges': [
            [47, 50],
          ],
          'outRange': [0, 3],
          'operation': 'replace',
        },
      ];
      p['tokens'][0]['rawRanges'] = [
        [47, 50],
      ];
      p['tokens'][0]['surfaceRanges'] = [
        [0, 3],
      ];
      expect(CorpusProjection(p, profile: profileId).raw.length, 3);
      p['map']['bodyRevision'] = 'wrong';
      expect(
        () => CorpusProjection(p, profile: profileId),
        throwsFormatException,
      );
    },
  );
  test(
    '304 revalidates exact URI and never supplies cached metadata after 404',
    () async {
      var calls = 0;
      final requests = <http.Request>[];
      final repo = ReaderRepository(
        client: MockClient((request) async {
          requests.add(request);
          calls++;
          if (calls == 1) {
            return http.Response(
              envelope({'ok': true}),
              200,
              headers: {'etag': 'tag', 'cache-control': 'no-cache'},
            );
          }
          if (calls == 2) return http.Response('', 304);
          return http.Response('closed', 404);
        }),
      );
      addTearDown(repo.close);
      expect((await repo.get('catalog'))['ok'], true);
      expect((await repo.get('catalog'))['ok'], true);
      expect(requests[1].headers['if-none-match'], 'tag');
      await expectLater(
        repo.get('catalog'),
        throwsA(isA<CorpusFailure>().having((e) => e.status, 'status', 404)),
      );
      expect(
        requests.every(
          (r) =>
              !r.headers.containsKey('authorization') &&
              !r.headers.containsKey('cookie') &&
              !r.headers.containsKey('x-api-key'),
        ),
        true,
      );
    },
  );
  test('orphan 304 retries once, no-store search never reuses ETag', () async {
    var calls = 0;
    final repo = ReaderRepository(
      client: MockClient((request) async {
        calls++;
        expect(request.headers.containsKey('if-none-match'), false);
        return calls == 1
            ? http.Response('', 304)
            : http.Response(
                envelope({'ok': true}, 'cs-index/1'),
                200,
                headers: {'etag': 'tag', 'cache-control': 'no-store'},
              );
      }),
    );
    addTearDown(repo.close);
    await repo.get('index/search', contract: 'cs-index/1');
    await repo.get('index/search', contract: 'cs-index/1');
    expect(calls, 3);
  });
  test(
    'Retry-After prevents early requests, no automatic retry or stale fallback',
    () async {
      var now = DateTime.utc(2026, 11, 18), calls = 0;
      final repo = ReaderRepository(
        now: () => now,
        client: MockClient((_) async {
          calls++;
          return http.Response(
            envelope({'ignored': true}),
            429,
            headers: {'retry-after': '20'},
          );
        }),
      );
      addTearDown(repo.close);
      await expectLater(
        repo.get('catalog'),
        throwsA(
          isA<CorpusFailure>().having(
            (e) => e.retryAt,
            'deadline',
            now.add(const Duration(seconds: 20)),
          ),
        ),
      );
      await expectLater(
        repo.get('capabilities'),
        throwsA(isA<CorpusFailure>()),
      );
      expect(calls, 1);
      now = now.add(const Duration(seconds: 21));
      await expectLater(
        repo.get('capabilities'),
        throwsA(isA<CorpusFailure>()),
      );
      expect(calls, 2);
    },
  );
  test(
    'timeout, bad envelope, unpublished namespace remain separate failures',
    () async {
      final timeoutRepo = ReaderRepository(
        timeout: const Duration(milliseconds: 1),
        client: MockClient((_) => Completer<http.Response>().future),
      );
      await expectLater(
        timeoutRepo.get('capabilities'),
        throwsA(isA<CorpusFailure>().having((e) => e.code, 'code', 'timeout')),
      );
      final repo = ReaderRepository(
        client: MockClient(
          (_) async => http.Response('{"contract":"future","data":{}}', 200),
        ),
      );
      await expectLater(
        repo.session(),
        throwsA(
          isA<CorpusFailure>().having(
            (e) => e.code,
            'code',
            'invalid_contract',
          ),
        ),
      );
      final unpublished = ReaderRepository(
        client: MockClient(
          (_) async =>
              http.Response(envelope({'available': false}, 'cs-index/1'), 200),
        ),
      );
      await expectLater(
        unpublished.session(),
        throwsA(
          isA<CorpusFailure>().having((e) => e.code, 'code', 'not_published'),
        ),
      );
      timeoutRepo.close();
      repo.close();
      unpublished.close();
    },
  );
  test(
    'catalog C mismatch and pinned read mismatch never silently use latest',
    () async {
      final repo = ReaderRepository(
        client: MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response(
              envelope({
                'catalogRevision': 'new',
                'items': [],
                'nextCursor': null,
              }),
              200,
            );
          }
          final response = readWire();
          response['data']['resolvedAddress']['sourceRevision'] = 'changed';
          return jsonResponse(response);
        }),
      );
      addTearDown(repo.close);
      await expectLater(
        repo.catalog(makeSession()),
        throwsA(isA<CorpusFailure>().having((e) => e.status, 'status', 409)),
      );
      await expectLater(
        repo.read(
          SourceAddress(wireObject(readWire()['data']['resolvedAddress'])),
          profile(),
        ),
        throwsA(isA<CorpusFailure>()),
      );
      await expectLater(
        repo.occurrences(makeSession(), profileId, 'lexeme', 'other-D'),
        throwsA(
          isA<CorpusFailure>().having(
            (e) => e.code,
            'code',
            'dictionary_version_mismatch',
          ),
        ),
      );
    },
  );
  test(
    'late response and disposed controller do not replace current results',
    () async {
      final repo = DeferredRepository();
      final controller = CorpusController(repo);
      final first = controller.start(query: 'old');
      await Future<void>.delayed(Duration.zero);
      final second = controller.start(query: 'new');
      await Future<void>.delayed(Duration.zero);
      repo.requests['new']!.complete(
        CorpusPage(page(hits: []), makeSession(), profileId),
      );
      await second;
      repo.requests['old']!.complete(
        CorpusPage(page(), makeSession(), profileId),
      );
      await first;
      expect(controller.query, 'new');
      expect(controller.hits, isEmpty);
      final third = controller.start(query: 'closed');
      await Future<void>.delayed(Duration.zero);
      controller.dispose();
      repo.requests['closed']!.complete(
        CorpusPage(page(), makeSession(), profileId),
      );
      await third;
      repo.close();
    },
  );
  test('409 continuation clears old snippets; restart is explicit', () async {
    var calls = 0;
    final repo = PagedRepository(
      MockClient((r) async {
        calls++;
        expect(r.url.queryParameters['indexRevision'], 'I');
        if (calls == 2) {
          expect(r.url.queryParameters['cursor'], 'next');
          return http.Response(
            '{"contract":"cs-index/1","error":{"code":"visibility_changed","message":"changed","retryable":false}}',
            409,
          );
        }
        expect(r.url.queryParameters.containsKey('cursor'), false);
        return http.Response(
          envelope(
            page(
              cursor: calls == 1 ? 'next' : null,
              hits: calls == 1 ? [hit()] : [],
            ),
            'cs-index/1',
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final controller = CorpusController(repo);
    await controller.start(query: 'word');
    expect(controller.hits, hasLength(1));
    await controller.more();
    expect(controller.hits, isEmpty);
    expect(controller.restartRequired, true);
    expect(calls, 2);
    await controller.start();
    expect(controller.hits, isEmpty);
    expect(controller.error, null);
    controller.dispose();
    repo.close();
  });
  test(
    'incoming and shared addresses retain revisions, selectors and reject foreign hosts',
    () {
      final address = SourceAddress(wireObject(hit()['address']));
      final url = readerLink(address.url.toString());
      expect(url!.queryParameters['revision'], address.wire['sourceRevision']);
      expect(
        url.queryParameters['occurrence'],
        address.wire['selector']['occurrenceId'],
      );
      expect(
        readerLink(
          'cslexicon://reader?url=${Uri.encodeComponent(url.toString())}',
        ),
        url,
      );
      expect(readerLink('${url.path}?${url.query}'), url);
      for (final bad in [
        'https://evil.test/sources/x',
        'https://typikon.info@evil.test/sources/x',
        'https://www.typikon.info/api/v2/private',
        'javascript:alert(1)',
      ]) {
        expect(readerLink(bad), null);
      }
    },
  );
}
